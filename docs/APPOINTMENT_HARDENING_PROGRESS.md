# Appointment Hardening Progress

Current phase: Phase 7 — Booking Policy and Abuse Controls
Last completed phase: Phase 6 — Align Student and Admin Actions
Last commit: pending Phase 6 commit

## Completed

* Phase 0 — PASS
* Phase 1 — PASS
* Phase 2 — PASS
* Phase 3 — PASS
* Phase 4 — PASS
* Phase 5 — PASS
* Phase 6 — PASS

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
