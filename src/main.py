from dotenv import load_dotenv

load_dotenv()

import os
import uuid
from typing import Literal, Optional

import anthropic
from fastapi import FastAPI
from fastapi.responses import JSONResponse
from pydantic import BaseModel

ANTHROPIC_API_KEY = os.getenv("ANTHROPIC_API_KEY")
if ANTHROPIC_API_KEY is None or ANTHROPIC_API_KEY == "":
    raise ValueError(
        "ANTHROPIC_API_KEY environment variable is not set. Copy .env.example to .env and add your key."
    )

client = anthropic.Anthropic(api_key=ANTHROPIC_API_KEY)

app = FastAPI(title="Nistula Guest Message Handler", version="1.0.0")

SYSTEM_PROMPT = (
    "You are a professional guest communication assistant for Nistula, a luxury villa rental company in Goa, India.\n\n"
    "Property context:\n"
    "- Property: Villa B1, Assagao, North Goa\n"
    "- Bedrooms: 3 | Max guests: 6 | Private pool: Yes\n"
    "- Check-in: 2pm | Check-out: 11am\n"
    "- Base rate: INR 18,000 per night (up to 4 guests)\n"
    "- Extra guest: INR 2,000 per night per person\n"
    "- WiFi password: Nistula@2024\n"
    "- Caretaker: Available 8am to 10pm\n"
    "- Chef on call: Yes, pre-booking required\n"
    "- Availability April 20-24: Available\n"
    "- Cancellation: Free up to 7 days before check-in\n\n"
    "Your job is to draft a warm, professional reply to the guest message. Be concise (3-5 sentences max). "
    "Address the guest by name. Answer their specific question directly using the property context. End with a friendly closing."
)


class InboundMessage(BaseModel):
    source: Literal["whatsapp", "booking_com", "airbnb", "instagram", "direct"]
    guest_name: str
    message: str
    timestamp: str
    booking_ref: Optional[str] = None
    property_id: Optional[str] = None


def classify_query(message_text: str) -> str:
    text = message_text.lower()
    availability_keywords = ["available", "availability", "dates", "free", "book"]
    pricing_keywords = ["rate", "price", "cost", "charge", "how much", "pricing", "per night"]
    checkin_keywords = ["check in", "check-in", "wifi", "wi-fi", "password", "arrive", "arrival", "key", "directions"]
    special_keywords = ["early check", "late check", "airport", "transfer", "chef", "extra bed", "cot", "special"]
    complaint_keywords = [
        "not working",
        "broken",
        "dirty",
        "unhappy",
        "complain",
        "problem",
        "issue",
        "ac",
        "air conditioning",
        "not happy",
    ]
    if any(kw in text for kw in availability_keywords):
        return "pre_sales_availability"
    if any(kw in text for kw in pricing_keywords):
        return "pre_sales_pricing"
    if any(kw in text for kw in checkin_keywords):
        return "post_sales_checkin"
    if any(kw in text for kw in special_keywords):
        return "special_request"
    if any(kw in text for kw in complaint_keywords):
        return "complaint"
    return "general_enquiry"


def compute_confidence(query_type: str, message_text: str) -> float:
    base_scores = {
        "pre_sales_availability": 0.90,
        "pre_sales_pricing": 0.88,
        "post_sales_checkin": 0.92,
        "special_request": 0.80,
        "complaint": 0.60,
        "general_enquiry": 0.75,
    }
    score = base_scores.get(query_type, 0.70)
    if len(message_text) > 200:
        score -= 0.05
    if len(message_text) < 20:
        score -= 0.10
    if query_type == "complaint":
        score -= 0.05
    return round(max(0.0, min(1.0, score)), 3)


def determine_action(confidence_score: float, query_type: str) -> str:
    if query_type == "complaint" or confidence_score < 0.60:
        return "escalate"
    if confidence_score > 0.85:
        return "auto_send"
    return "agent_review"


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}


@app.post("/webhook/message")
def handle_message(inbound_message: InboundMessage):
    unified_message = {
        "message_id": str(uuid.uuid4()),
        "source": inbound_message.source,
        "guest_name": inbound_message.guest_name,
        "message_text": inbound_message.message,
        "timestamp": inbound_message.timestamp,
        "booking_ref": inbound_message.booking_ref,
        "property_id": inbound_message.property_id,
        "query_type": classify_query(inbound_message.message),
    }

    user_message = (
        f"Guest name: {unified_message['guest_name']}\n"
        f"Query type: {unified_message['query_type']}\n"
        f"Message: {unified_message['message_text']}\n\n"
        "Draft a reply to this guest message."
    )

    try:
        response = client.messages.create(
            model="claude-sonnet-4-20250514",
            max_tokens=1024,
            system=SYSTEM_PROMPT,
            messages=[{"role": "user", "content": user_message}],
        )
        drafted_reply = response.content[0].text
    except anthropic.APIConnectionError as e:
        return JSONResponse(status_code=502, content={"error": "AI service unavailable", "detail": str(e)})
    except anthropic.APIStatusError as e:
        return JSONResponse(status_code=502, content={"error": "AI service error", "detail": str(e)})

    confidence_score = compute_confidence(unified_message["query_type"], unified_message["message_text"])
    action = determine_action(confidence_score, unified_message["query_type"])

    return {
        "message_id": unified_message["message_id"],
        "query_type": unified_message["query_type"],
        "drafted_reply": drafted_reply,
        "confidence_score": confidence_score,
        "action": action,
    }


if __name__ == "__main__":
    import uvicorn

    uvicorn.run("src.main:app", host="0.0.0.0", port=8000, reload=True)
