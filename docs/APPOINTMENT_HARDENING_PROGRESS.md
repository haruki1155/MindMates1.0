# Appointment Hardening Progress

Current phase: Phase 4 — Restrict Sensitive Appointment Reads
Last completed phase: Phase 3 — Secure Availability Publishing
Last commit: aa46ef4

## Completed

* Phase 0 — PASS
* Phase 1 — PASS
* Phase 2 — PASS
* Phase 3 — PASS

## Current blockers

* None

## Known pre-existing failures

* Flutter focused tests require the missing declared ML asset `assets/ml/paacc_intent_model_v4.tflite`.
* Existing Rules tests require Firebase emulators.

## Decisions

* Availability publishing is limited to existing clinical roles: counselor and admin.
