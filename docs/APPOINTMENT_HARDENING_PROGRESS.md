# Appointment Hardening Progress

Current phase: Phase 16 — Final Audit Before Production
Last completed phase: Phase 15 — Staging Deployment
Last commit: `7dc3eba` — record appointment reminder regression check

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
* Phase 12 — PASS
* Phase 13 — PASS
* Phase 14 — PASS
* Phase 15 — PASS

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
* Functions unit coverage and Firestore emulator Rules coverage pass. Callable
  concurrency and end-to-end role scenarios remain non-production validation work.
* Expired requests are terminal for lifecycle, notification resolution, and
  automatic/manual appointment history handling.
* Phase 13 ran against `mindmate-staging` using two app-user, two active
  counselor, and one admin test accounts. Direct appointment and availability
  attacks were denied; normal booking, confirmation, cancellation, reschedule,
  proposal conflict, same-slot concurrency, terminal archive, notification,
  history, and audit assertions passed. The original `on_leave` availability
  configuration was restored after the run.
* The Phase 13 staging deployment contains the hardened appointment Functions
  and Firestore Rules. Admin/student app deployment remains Phase 15 work.
* Reminders remain eligible while a reschedule proposal is unresolved because
  the original appointment time is still authoritative until acceptance.
* Phase 15 deployed only to `mindmate-staging`: hardened Functions and Rules,
  the reminder scheduler revision, and Firebase Hosting at
  `https://mindmate-staging.web.app`. The staging admin web build returned
  HTTP 200 and a staging-flavored Android debug APK was built. The Phase 13
  authenticated multi-role E2E evidence remains the verification for booking,
  privacy, lifecycle, concurrency, availability, notification, history, and
  audit behavior; the original `on_leave` availability was restored.
* App Check is intentionally bypassed only by the staging client configuration;
  no production App Check or authorization setting was changed. The reminder
  scheduler was deployed after its focused regression test passed. The exact
  committed release-candidate revision for the hardening work is `7dc3eba`.
