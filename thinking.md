# Hospitality AI Scenario Response

## Question A — The Immediate Response

**AI Reply at 3am:**

> I’m very sorry you’re facing this issue, especially with guests arriving in a few hours. I’ve already escalated the hot water problem to our on-call maintenance team as a highest-priority issue, and immediate action is being taken.
>
> I will personally update you within the next 15 minutes. Once the issue is resolved, we will also review appropriate compensation for the inconvenience caused tonight.

### Why this wording?

This response first acknowledges the guest’s frustration and creates confidence that action has already started. It avoids debating the refund emotionally at 3am while showing ownership, urgency, and accountability. The update timeline also helps reduce guest anxiety.

---

## Question B — The System Design

Beyond replying to the guest, the platform should automatically trigger a **P1 (critical) incident workflow**.

### System Actions:
- Create an incident ticket tagged:
  - `Villa B1`
  - `Hot Water Failure`
  - `Guest Escalation`
  - `Refund Risk`
- Notify:
  - On-call maintenance engineer
  - Guest relations manager
  - Operations dashboard
- Start a response timer and log all actions with timestamps.
- Pull previous maintenance history for Villa B1.
- Generate a troubleshooting checklist for the technician.

### Escalation Logic:
- If no human acknowledges within 15 minutes:
  - Escalate to backup technician and operations lead.
- If no response within 30 minutes:
  - Automatically authorize compensation or service credit.
  - Offer alternate arrangements if available.
  - Alert senior management.
  - Mark Villa B1 as a “maintenance risk” property internally.

This creates accountability, faster recovery, and better operational visibility.

---

## Question C — The Learning

Three hot water complaints in two months indicate a recurring operational failure, not a one-time incident.

The system should:
- Detect repeated complaint patterns automatically.
- Flag Villa B1 for preventive maintenance inspection.
- Increase maintenance priority score for that property.
- Track appliance reliability and vendor performance.

### Prevention System I Would Build

I would build a **predictive maintenance system** using:
- Complaint frequency analysis
- Boiler health monitoring
- Water pressure and temperature sensors
- Automated maintenance scheduling before guest check-ins

From a management perspective, the goal is not only to resolve complaints quickly, but to protect guest trust, reduce operational risk, and prevent repeat failures before they affect future guests.