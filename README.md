# Nistula Technical Assessment

FastAPI backend for handling guest messages for Nistula, a luxury villa rental company in Goa. The service normalizes inbound channel messages, classifies the query, asks Claude to draft a guest-facing reply, computes a confidence score, and returns the recommended routing action.

## Setup Instructions

1. Clone and enter the project:

   ```bash
   git clone https://github.com/your-username/nistula-technical-assessment.git
   cd nistula-technical-assessment
   ```

2. Create and activate a virtual environment:

   ```bash
   python -m venv venv
   source venv/bin/activate
   ```

   Windows:

   ```powershell
   python -m venv venv
   .\venv\Scripts\activate
   ```

3. Install dependencies:

   ```bash
   pip install -r requirements.txt
   ```

4. Configure the Anthropic API key:

   ```bash
   cp .env.example .env
   ```

   Windows:

   ```powershell
   Copy-Item .env.example .env
   ```

   Edit `.env` and replace `your_anthropic_api_key_here` with a real Anthropic API key. The `.env` file is ignored by Git and must not be committed.

5. Run the server:

   ```bash
   uvicorn src.main:app --reload --host 0.0.0.0 --port 8000
   ```

6. Open Swagger docs:

   ```text
   http://localhost:8000/docs
   ```

## API Endpoints

### GET `/health`

Returns a simple health check response.

```bash
curl http://localhost:8000/health
```

Expected response:

```json
{"status":"ok"}
```

### POST `/webhook/message`

Accepts an inbound guest message from WhatsApp, Booking.com, Airbnb, Instagram, or a direct channel. The endpoint returns a Claude-drafted reply, a confidence score, and the recommended action.

Request body:

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

Response shape:

```json
{
  "message_id": "8e235cd8-1f60-46bb-91f5-6f3a191d0f89",
  "query_type": "pre_sales_availability",
  "drafted_reply": "Hi Rahul Sharma, yes, Villa B1 is available from April 20 to 24. For 2 adults, the base rate is INR 18,000 per night. Warm regards, Nistula",
  "confidence_score": 0.9,
  "action": "auto_send"
}
```

## Example Requests

### Availability Query

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

Expected classification and routing:

```json
{
  "query_type": "pre_sales_availability",
  "confidence_score": 0.9,
  "action": "auto_send"
}
```

### Check-In Query

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

Expected classification and routing:

```json
{
  "query_type": "post_sales_checkin",
  "confidence_score": 0.92,
  "action": "auto_send"
}
```

### Complaint Query

```bash
curl -X POST http://localhost:8000/webhook/message \
-H "Content-Type: application/json" \
-d '{
"source": "direct",
"guest_name": "Arjun Kapoor",
"message": "The AC in the master bedroom is not working and it is very hot. I am not happy at all.",
"timestamp": "2026-05-07T14:15:00Z",
"booking_ref": "NIS-2024-0210",
"property_id": "villa-b1"
}'
```

Expected classification and routing:

```json
{
  "query_type": "complaint",
  "confidence_score": 0.55,
  "action": "escalate"
}
```

## Classification Logic

The service classifies each message by checking keyword groups in this order:

1. availability keywords
2. pricing keywords
3. check-in keywords
4. special request keywords
5. complaint keywords
6. general enquiry fallback

First match wins. This keeps mixed messages deterministic. For example, a message asking whether the villa is available and mentioning the rate is classified as `pre_sales_availability` because availability is checked first.

## Confidence Scoring Logic

Base scores by query type:

| Query type | Base score |
| --- | ---: |
| `pre_sales_availability` | 0.90 |
| `pre_sales_pricing` | 0.88 |
| `post_sales_checkin` | 0.92 |
| `special_request` | 0.80 |
| `complaint` | 0.60 |
| `general_enquiry` | 0.75 |

Modifiers:

| Condition | Adjustment |
| --- | ---: |
| Message longer than 200 characters | -0.05 |
| Message shorter than 20 characters | -0.10 |
| Complaint query type | -0.05 |

The final score is rounded to three decimals and clamped between `0.0` and `1.0`.

## Action Logic

| Condition | Action | Meaning |
| --- | --- | --- |
| `query_type` is `complaint` or score is below `0.60` | `escalate` | Route to supervisor or senior staff |
| score is above `0.85` | `auto_send` | AI reply is safe to send automatically |
| all other cases | `agent_review` | Human review required before sending |

Complaints always escalate because complaint handling may involve service recovery, empathy, accountability, or compensation decisions that should not be made by AI alone.

## PostgreSQL Schema

The database schema in `schema.sql` defines five tables:

| Table | Purpose |
| --- | --- |
| `guests` | Canonical guest profiles across all channels |
| `reservations` | Booking records linked to guests and properties |
| `conversations` | Message threads by guest, channel, and optional reservation |
| `messages` | Inbound and outbound messages, including AI classification, drafted reply, confidence score, and action |
| `agents` | Internal staff accounts used for review, sending, and escalation ownership |

Important design choices:

- `booking_ref` is unique in `reservations` so inbound messages can be matched to bookings.
- `messages.ai_confidence_score`, `messages.ai_query_type`, `messages.ai_drafted_reply`, and `messages.ai_action` are stored directly on `messages` because each inbound message receives one AI processing pass.
- `messages.agent_id` is added as a foreign key after the `agents` table is created, satisfying the dependency order.
- Indexes on `messages(conversation_id, timestamp)`, `messages(source_channel)`, and actionable AI messages support agent dashboard queries.

Run the schema with PostgreSQL:

```bash
psql -U postgres -d nistula_test -f schema.sql
```

Docker example:

```bash
docker run --name nistula-pg -e POSTGRES_PASSWORD=postgres -e POSTGRES_DB=nistula_test -p 5432:5432 -d postgres:16-alpine
docker cp schema.sql nistula-pg:/schema.sql
docker exec nistula-pg psql -U postgres -d nistula_test -v ON_ERROR_STOP=1 -f /schema.sql
docker rm -f nistula-pg
```

## Project Structure

```text
nistula-technical-assessment/
|-- .env.example       Example environment file with only the placeholder API key.
|-- .gitignore         Keeps local secrets, virtual environments, and Python cache files out of Git.
|-- README.md          Setup, API, scoring, action, and database documentation.
|-- requirements.txt   Python dependencies.
|-- schema.sql         PostgreSQL schema for the guest messaging workflow.
|-- thinking.md        Assessment design reasoning and final submission notes.
`-- src/
    `-- main.py        FastAPI app with webhook, Claude integration, classification, confidence, and routing logic.
```
