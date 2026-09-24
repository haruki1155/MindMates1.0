# Appointment Capacity Decision

## Current model: Model A — one shared PACC session per start slot

MindMate currently reserves `appointment_slots/pacc_{scheduledAtMillis}`. This
is the intended capacity model: one counselor-led PACC counseling session at a
given start timestamp. It does not represent independent parallel counselor or
room appointments.

PACC may conduct a counselor-led group or seminar-style session for clients
with similar concerns. Those clients are participants in one future session
capacity capability, not separate parallel appointment resources. Automatic
grouping and multiple independent appointments in one slot are out of scope.

## Explicit non-decision

No counselor/room resource model exists in the repository. Do not introduce
resource-specific slot keys or parallel capacity without an explicit future
requirement and trusted resource assignment data.

## Confirmed duration/overlap integrity gap

The current record stores only `scheduledAt`; it has no authoritative duration
or end time. Slot identity therefore protects identical starts only. For
example, a 10:00 appointment and an 11:00 appointment use different locks,
even if the real 10:00 counseling session continues until 12:00.

This remediation preserves compatibility and does not infer a session duration.
The required follow-up is a dedicated duration-aware scheduling phase: PACC
must approve a canonical duration/end-time policy, then Functions must
transactionally reject interval overlaps before slot reservation and before a
reschedule move. Group-session capacity must be designed separately from that
change.
