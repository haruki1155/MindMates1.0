# Student Appointment Schedule Edit Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans. Steps use checkbox syntax.

**Goal:** Let students change the time of their existing upcoming appointment and return it to awaiting confirmation.

**Architecture:** A trusted callable validates owner, current state, schedule, locks and booking policy; it atomically moves the slot, resets approval, records history and updates notification state. Flutter reuses slot availability and appointment streams. Existing security rules remain authoritative.

**Tech Stack:** Flutter, Provider, Firebase Functions, Firestore transactions and existing test infrastructure.

**Spec:** `docs/superpowers/specs/2026-11-12-student-appointment-schedule-edit-design.md`.

## Global Constraints
- No production deployment, migration, live appointment edits, APK install or push.
- Preserve the unrelated `pubspec.lock` change and existing appointment identity, owner, concern and contact details.
- Firestore client mutations remain denied. Keep user active lock, audit history and protected staff workflows.

## Review Focus
- Concurrent student/staff edits and stale retries cannot reverse later changes or release another slot.
- Missing, foreign or legacy locks fail safely with the original appointment unchanged.
- Same-time no-op never revokes confirmation or sends a notification.
- Old reminder state cannot suppress or send reminders for the wrong schedule.
- Student receives an actionable conflict or network error without losing selection.

### Task 1: Trusted transactional reschedule
**Files:** `functions/src/index.ts`, existing appointment tests under `functions/src/`; `firestore.rules` only if proven necessary.

- [ ] Write failing transaction tests for authenticated owner, allowed statuses, no-op, stale expected schedule, invalid/occupied new slot, old lock mismatch, same-user retries, competing bookings and staff review race. Assert old record and lock remain intact on failure.
- [ ] Implement callable `rescheduleStudentAppointment` with `{appointmentId, expectedScheduledAt, scheduledAt, requestId}`. Validate all input and ownership; use existing timestamp, availability and policy validators. Transactionally verify old slot ownership and active user lock, acquire new slot, release old slot, write requested status and server-derived labels, clear stale active approval/proposal and reminder fields, preserve all other fields, record history and idempotency. Preserve a prior request result only when its payload matches; stale requests never reapply.
- [ ] Update queue and portal notification handling for student schedule changes with an idempotent event identity and no concern text. Verify reminders against status, schedule and cleared markers. Test actual transaction and Rules against isolated emulators; do not infer hosted behavior.
- [ ] Run focused Functions build, transaction, notifications, reminders and Rules tests; require passing output.

### Task 2: Student date/time edit flow
**Files:** `lib/repositories/appointment_repository.dart`, `lib/providers/appointment_provider.dart`, `lib/features/counseling/widgets/appointment_details_sheet.dart`, `lib/features/counseling/screens/pacc_counseling_screen.dart`, related Home/appointment views and tests.

- [ ] Write failing tests for owner-visible edit action on requested/confirmed future appointments, hidden for terminal/archived/past/PACC-proposed appointments; edit from all existing details entry points, current schedule, available times, unchanged selection, pending feedback, conflict/retry and account change.
- [ ] Add repository/provider methods and reuse the existing date/slot controls for a dedicated edit flow. Send expected original timestamp and stable per-attempt request ID; preserve selection on failure. Explain awaiting confirmation, and ensure successful stream refresh and status display across Home and counseling screens. Do not log private content.
- [ ] Run focused widget/provider/repository tests and Flutter analysis. Verify narrow screen, keyboard and large text.

### Task 3: Integrated validation and review
- [ ] Cover student edit → pending queue → staff confirmation, retry/concurrency and reminders in emulator tests; test unchanged schedule and cross-account denial. Record complete command results and boundaries.
- [ ] Run appropriate Functions, Rules and staging Flutter regressions and diff checks. Independently review the whole change for authorization, transaction atomicity, idempotency and notifications. Fix important findings and revalidate.
- [ ] Report local implementation and exact validation; deployment, hosted data, device install, push and live acceptance remain separate approvals.
