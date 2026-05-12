# Nistula Technical Assessment

FastAPI backend for handling guest messages for Nistula, a luxury villa rental company in Goa. The service normalizes inbound channel messages, classifies the query, asks Claude AI to draft a guest-facing reply, computes a confidence score, and returns the recommended routing action.

---

## Swagger API Documentation

FastAPI automatically generates interactive OpenAPI/Swagger documentation for testing and validating API endpoints.

---

### API Overview

Shows the available endpoints and request payload structure.

<img width="1365" height="593" alt="image" src="https://github.com/user-attachments/assets/1e52fda7-1a22-42b6-a5cb-8339da2c2a9b" />

---

### Successful Webhook Response

Demonstrates successful AI-powered message classification, confidence scoring, and drafted response generation.

<img width="1365" height="601" alt="image" src="https://github.com/user-attachments/assets/ae340b33-d6ab-4b24-8292-63f60c078d7c" />

---

### Validation & Response Schema

Displays FastAPI/Pydantic validation models and structured API response schemas.

<img width="1365" height="596" alt="image" src="https://github.com/user-attachments/assets/ffeada5b-a271-440b-a415-6b4792f6c000" />

---

# Supported Guest Channels

The backend normalizes inbound guest messages from multiple hospitality channels into a unified internal schema:

* WhatsApp
* Airbnb
* Booking.com
* Instagram
* Direct website/contact form

This allows downstream AI processing and agent workflows to remain channel-independent.

---

# System Flow

The following flowchart explains the complete lifecycle of guest message processing, AI classification, confidence scoring, and routing logic used in the backend system.

<img width="1024" height="1536" alt="image" src="https://github.com/user-attachments/assets/4176aeb3-fbcc-4128-a9f9-91e5c53fdf2a" />

---
# Tech Stack

* FastAPI
* Python 3.11
* Anthropic Claude API
* PostgreSQL
* Uvicorn
* Pydantic

---

# Setup Instructions

## 1. Clone Repository

```bash
git clone https://github.com/gagandeepsingh76/nistula-technical-assessment.git
cd nistula-technical-assessment
```

---

## 2. Create Virtual Environment

### macOS / Linux

```bash
python -m venv venv
source venv/bin/activate
```

### Windows

```powershell
python -m venv venv
.\venv\Scripts\activate
```

---

## 3. Install Dependencies

```bash
pip install -r requirements.txt
```

---

## 4. Configure Environment Variables

Create `.env` from `.env.example`.

### macOS / Linux

```bash
cp .env.example .env
```

### Windows

```powershell
Copy-Item .env.example .env
```

Add your Anthropic API key inside `.env`:

```env
ANTHROPIC_API_KEY=your_real_anthropic_api_key
```

Important:

* `.env` must never be committed to GitHub.
* `.env.example` only contains placeholder values.

---

## 5. Run Server

```bash
uvicorn src.main:app --reload --host 0.0.0.0 --port 8000
```

---

## 6. Open Swagger Docs

```text
http://localhost:8000/docs
```

---

# API Endpoints

---

## GET `/health`

Health check endpoint.

### Example

```bash
curl http://localhost:8000/health
```

### Response

```json
{
  "status": "ok"
}
```

---

## POST `/webhook/message`

Handles inbound guest communication from supported channels.

The endpoint:

* normalizes inbound messages
* classifies query type
* generates Claude AI reply
* computes confidence score
* decides routing action

---

# Request Example

```json
{
  "source": "whatsapp",
  "guest_name": "Rahul Sharma",
  "message": "Is the villa available from April 20 to 24? We are 2 adults.",
  "timestamp": "2026-05-05T10:30:00Z",
  "booking_ref": "NIS-2024-0891",
  "property_id": "villa-b1"
}
```

---

# Response Example

```json
{
  "message_id": "371688e9-02b2-40b6-8d3c-3b58361253f5",
  "query_type": "pre_sales_availability",
  "drafted_reply": "Dear Rahul, thank you for your inquiry about Villa B1 in Assagao...",
  "confidence_score": 0.9,
  "action": "auto_send"
}
```

---

# Example Requests

---

## 1. Availability Query

```bash
curl -X POST http://localhost:8000/webhook/message \
-H "Content-Type: application/json" \
-d '{
"source": "whatsapp",
"guest_name": "Rahul Sharma",
"message": "Is the villa available from April 20 to 24? We are 2 adults.",
"timestamp": "2026-05-05T10:30:00Z",
"booking_ref": "NIS-2024-0891",
"property_id": "villa-b1"
}'
```

### Expected Classification

```json
{
  "query_type": "pre_sales_availability",
  "confidence_score": 0.9,
  "action": "auto_send"
}
```

---

## 2. Check-In Query

```bash
curl -X POST http://localhost:8000/webhook/message \
-H "Content-Type: application/json" \
-d '{
"source": "airbnb",
"guest_name": "Priya Menon",
"message": "Hi, what time can we check in and what is the WiFi password?",
"timestamp": "2026-05-06T08:00:00Z",
"booking_ref": "NIS-2024-0045",
"property_id": "villa-b1"
}'
```

### Expected Classification

```json
{
  "query_type": "post_sales_checkin",
  "confidence_score": 0.92,
  "action": "auto_send"
}
```

---

## 3. Complaint Query

```bash
curl -X POST http://localhost:8000/webhook/message \
-H "Content-Type: application/json" \
-d '{
"source": "direct",
"guest_name": "Arjun Kapoor",
"message": "The AC in the master bedroom is not working and it is very hot.",
"timestamp": "2026-05-07T14:15:00Z",
"booking_ref": "NIS-2024-0210",
"property_id": "villa-b1"
}'
```

### Expected Classification

```json
{
  "query_type": "complaint",
  "confidence_score": 0.55,
  "action": "escalate"
}
```

---

# Classification Logic

Messages are classified using deterministic keyword-based routing.

Priority order:

1. availability keywords
2. pricing keywords
3. check-in keywords
4. special request keywords
5. complaint keywords
6. general enquiry fallback

First-match-wins logic ensures deterministic routing.

Example:
A message asking about both availability and pricing is classified as `pre_sales_availability` because availability has higher routing priority.

---

# Confidence Scoring Logic

## Base Scores

| Query Type             | Base Score |
| ---------------------- | ---------: |
| pre_sales_availability |       0.90 |
| pre_sales_pricing      |       0.88 |
| post_sales_checkin     |       0.92 |
| special_request        |       0.80 |
| complaint              |       0.60 |
| general_enquiry        |       0.75 |

---

## Modifiers

| Condition           | Adjustment |
| ------------------- | ---------: |
| Message > 200 chars |      -0.05 |
| Message < 20 chars  |      -0.10 |
| Complaint query     |      -0.05 |

Final score is:

* rounded to 3 decimals
* clamped between `0.0` and `1.0`

---

# Action Logic

| Condition                 | Action       | Meaning                    |
| ------------------------- | ------------ | -------------------------- |
| Complaint OR score < 0.60 | escalate     | Human escalation required  |
| Score > 0.85              | auto_send    | AI reply safe to auto-send |
| Otherwise                 | agent_review | Human review required      |

Complaints always escalate because hospitality complaints may require:

* empathy
* compensation
* operational intervention
* supervisor approval

---

# PostgreSQL Schema

The schema in `schema.sql` defines 5 tables:

| Table         | Purpose                         |
| ------------- | ------------------------------- |
| guests        | Guest profiles                  |
| reservations  | Booking records                 |
| conversations | Guest communication threads     |
| messages      | Inbound/outbound guest messages |
| agents        | Internal support agents         |

---

# Important Schema Design Decisions

* `booking_ref` is unique for reservation matching.
* AI fields are stored directly on `messages` because each message receives exactly one AI processing pass.
* Indexes optimize:

  * conversation lookup
  * dashboard filtering
  * escalation workflows
  * chronological retrieval

---

# Run PostgreSQL Schema

```bash
psql -U postgres -d nistula_test -f schema.sql
```

---

# Docker Example

```bash
docker run --name nistula-pg -e POSTGRES_PASSWORD=postgres -e POSTGRES_DB=nistula_test -p 5432:5432 -d postgres:16-alpine

docker cp schema.sql nistula-pg:/schema.sql

docker exec nistula-pg psql -U postgres -d nistula_test -v ON_ERROR_STOP=1 -f /schema.sql

docker rm -f nistula-pg
```

---

## Project Structure

```text
nistula-technical-assessment/

├── README.md                # setup instructions and confidence scoring logic explained
├── requirements.txt         # Python dependencies
├── schema.sql               # Part 2 SQL with comments
├── thinking.md              # Part 3 written answers
│
└── src/
    └── main.py              # Part 1 webhook backend code
```
---

# Security Notes

* Real API keys are never committed.
* `.env` is not included in the repository.
* `.env.example` contains placeholder values only.
---

# Final Verification Status

Verified successfully:

* FastAPI backend
* Swagger/OpenAPI docs
* `/health` endpoint
* `/webhook/message` endpoint
* Claude AI integration
* Confidence scoring
* Action routing
* PostgreSQL schema execution
* Docker compatibility
* GitHub-safe repository cleanup

---
