CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- One canonical guest record regardless of which channel they contact from.
-- phone and email are UNIQUE but nullable: guests contacting via Instagram DM may not share contact details.
-- updated_at must be kept current by application logic or a trigger.
CREATE TABLE guests (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    full_name VARCHAR(255) NOT NULL,
    email VARCHAR(255) UNIQUE,
    phone VARCHAR(50) UNIQUE,
    nationality VARCHAR(100),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- A reservation belongs to one guest and one property.
-- booking_ref is UNIQUE so we can look up a reservation from any inbound message.
-- status uses CHECK to enforce a valid state machine.
-- check_out > check_in is enforced by a CHECK constraint.
CREATE TABLE reservations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    booking_ref VARCHAR(100) UNIQUE NOT NULL,
    guest_id UUID NOT NULL REFERENCES guests(id) ON DELETE RESTRICT,
    property_id VARCHAR(100) NOT NULL,
    source VARCHAR(50) NOT NULL CHECK (source IN ('whatsapp', 'booking_com', 'airbnb', 'instagram', 'direct')),
    check_in DATE NOT NULL,
    check_out DATE NOT NULL,
    num_guests INTEGER NOT NULL CHECK (num_guests >= 1 AND num_guests <= 20),
    total_amount_inr NUMERIC(12, 2),
    status VARCHAR(50) NOT NULL DEFAULT 'enquiry' CHECK (status IN ('enquiry', 'confirmed', 'checked_in', 'checked_out', 'cancelled')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_checkout_after_checkin CHECK (check_out > check_in)
);

-- A conversation is a thread of messages between a guest and Nistula on one channel.
-- reservation_id is nullable: not every conversation is tied to a confirmed booking.
-- is_open = TRUE means the conversation needs attention; FALSE means resolved.
-- closed_at must be >= opened_at enforced by CHECK.
CREATE TABLE conversations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    guest_id UUID NOT NULL REFERENCES guests(id) ON DELETE RESTRICT,
    reservation_id UUID REFERENCES reservations(id) ON DELETE SET NULL,
    channel VARCHAR(50) NOT NULL CHECK (channel IN ('whatsapp', 'booking_com', 'airbnb', 'instagram', 'direct')),
    is_open BOOLEAN NOT NULL DEFAULT TRUE,
    opened_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    closed_at TIMESTAMPTZ,
    CONSTRAINT chk_closed_after_opened CHECK (closed_at IS NULL OR closed_at >= opened_at)
);

-- All messages from all channels in one table.
-- direction = 'inbound' means guest sent it; 'outbound' means Nistula sent it.
-- AI fields are NULL for outbound messages and for inbound messages not yet processed.
-- draft_status tracks the lifecycle: none -> ai_drafted -> agent_edited -> sent.
-- agent_id is NULL when AI auto-sent without human review.
CREATE TABLE messages (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    conversation_id UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
    direction VARCHAR(10) NOT NULL CHECK (direction IN ('inbound', 'outbound')),
    source_channel VARCHAR(50) NOT NULL CHECK (source_channel IN ('whatsapp', 'booking_com', 'airbnb', 'instagram', 'direct')),
    guest_name VARCHAR(255),
    message_text TEXT NOT NULL,
    timestamp TIMESTAMPTZ NOT NULL,
    booking_ref VARCHAR(100),
    property_id VARCHAR(100),
    ai_query_type VARCHAR(50) CHECK (ai_query_type IN ('pre_sales_availability', 'pre_sales_pricing', 'post_sales_checkin', 'special_request', 'complaint', 'general_enquiry')),
    ai_confidence_score NUMERIC(4, 3) CHECK (ai_confidence_score >= 0 AND ai_confidence_score <= 1),
    ai_drafted_reply TEXT,
    ai_action VARCHAR(20) CHECK (ai_action IN ('auto_send', 'agent_review', 'escalate')),
    draft_status VARCHAR(20) NOT NULL DEFAULT 'none' CHECK (draft_status IN ('none', 'ai_drafted', 'agent_edited', 'sent')),
    agent_id UUID,
    sent_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_messages_conversation_timestamp ON messages(conversation_id, timestamp);
CREATE INDEX idx_messages_source_channel ON messages(source_channel);
CREATE INDEX idx_messages_ai_action ON messages(ai_action) WHERE ai_action IN ('agent_review', 'escalate');

-- Internal Nistula staff who review or send replies.
-- role = supervisor can override escalated complaints.
-- is_active = FALSE for deactivated accounts (never hard delete agents).
CREATE TABLE agents (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    full_name VARCHAR(255) NOT NULL,
    email VARCHAR(255) UNIQUE NOT NULL,
    role VARCHAR(50) NOT NULL DEFAULT 'agent' CHECK (role IN ('agent', 'supervisor', 'admin')),
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE messages ADD CONSTRAINT fk_messages_agent FOREIGN KEY (agent_id) REFERENCES agents(id) ON DELETE SET NULL;

-- ============================================================
-- HARDEST DESIGN DECISION
-- ============================================================
-- The hardest decision was whether to store AI fields (confidence score,
-- query type, drafted reply, action) directly on the messages table or in
-- a separate ai_processing_log table.
-- I chose to store them on messages because:
-- 1. Every inbound message gets exactly one AI processing pass - there is
--    no many-to-one relationship requiring a separate table.
-- 2. Joining a separate table on every agent dashboard query adds latency
--    and complexity with no benefit at this scale.
-- 3. NULL columns on outbound messages are acceptable - a partial row is
--    preferable to a mandatory join on every read.
-- If Nistula later needs to re-run messages through a new AI model and
-- compare results side by side, a separate ai_processing_log table would
-- be warranted. For now, simplicity and query performance win.
-- ============================================================
