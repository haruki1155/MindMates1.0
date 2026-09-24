# Appointment Hardening Progress

Current phase: Phase 12 — Focused Security and Lifecycle Tests
Last completed phase: Phase 11G — Follow-Up Appointment Linking
Last commit: pending Phase 11G commit

## Completed

* Phase 0 — PASS
* Phase 1 — PASS
* Phase 2 — PASS
* Phase 3 — PASS
* Phase 4 — PASS
* Phase 5 — PASS
* Phase 6 — PASS
* Phase 7 — PASS
* Phase 8 — PASS
* Phase 9 — PASS
* Phase 10 — PASS
* Phase 11A — PASS
* Phase 11B — PASS
* Phase 11C — PASS
* Phase 11D — PASS
* Phase 11E — PASS
* Phase 11F — PASS
* Phase 11G — PASS

## Current blockers

* None

## Known pre-existing failures

* Flutter focused tests require the missing declared ML asset `assets/ml/paacc_intent_model_v4.tflite`.
* Existing Rules tests require Firebase emulators.

## Decisions

* Availability publishing is limited to existing clinical roles: counselor and admin.
* Portal staff read only the server-generated `appointment_queue` projection;
  appointment records and terminal history remain owner/assigned-counselor/admin only.
* The server lifecycle matrix is the authority for student and staff transitions.
* Student UI does not offer counter-proposals from a staff proposal; the server
  supports acceptance or cancellation in that state.
* Booking policy values remain disabled until PACC publishes positive values in
  `appointment_policy/current`; enforcement is always server-side.
* Reschedule proposals are tentative; accepted moves revalidate availability
  and atomically claim the new slot before releasing the original slot.
* Model A is intentional: one shared PACC session per start timestamp. The
  repository has no duration/end-time authority, so overlapping 1–2 hour
  sessions with different starts remain a documented future integrity gap.
* Student booking time choices are fetched from the trusted slot callable;
  display availability remains non-reserving and booking repeats validation.
* Appointment intake and staff-response field bounds are enforced in Functions.
* Appointment identity snapshots prefer trusted profile values; intentionally
  editable contact and preference values remain server-validated intake data.
* Optional `blackoutDates` extend the existing PACC availability document and
  are enforced by the shared availability validator.
* Stale request expiry is disabled until `staleRequestExpiryHours` is published;
  enabled expiry uses the explicit terminal `expired` status and releases slots.
* Cancellation cutoff and reason requirements are server policies; requiring a
  reason is disabled unless explicitly published.
* Portal appointment notifications resolve for no-show and other terminal states.
* Follow-up bookings may link only to the requesting user's terminal appointment.
