# Appointment two-way agreement implementation plan

> Execute inline using executing-plans and TDD; one independent final review.

Goal: real student/PACC agreement and optional-reason cancellation while retaining the current reservation.
Architecture: extend existing proposal fields with a monotonic proposalRevision, preserve scheduledAt/status for the currently reserved schedule, and use one transactional callable for propose/accept/cancel. Existing scheduleRevision changes only on acceptance/cancellation; current confirmed reminders stay valid until then. Presentation explicitly distinguishes a pending proposal from the reserved schedule.
Tech stack: existing Flutter Provider/Firebase callable, TypeScript/Admin Firestore transactions. No dependencies.
Spec: docs/superpowers/specs/2026-11-14-appointment-two-way-agreement-design.md (approved by user).
Global constraints: preserve prior work and UI; optional cancellation reason; no second reservation; no deployment/push/merge or production access. Keep implementation uncommitted for review.
Review focus: stale/cross-account responses; accept/cancel races; legacy records with missing reservation/revision; privacy of optional reasons; reminders for current schedule during negotiation.

### Task 1: transactional agreement backend
Files: new functions/src/appointment_agreement.ts and appointment_agreement.test.ts; index.ts adapters/queue/notification guards; existing callable tests.
Interfaces: action propose/accept/cancel, appointmentId, requestId, expectedScheduledAt, expectedScheduleRevision, expectedProposalRevision, optional scheduledAt/reason. trusted staff authorization reused.
- [x] RED emulator tests for reservation retention, other-side-only acceptance, stale counterproposal, optional cancellation, conflicts/retry/ownership and reminders.
- [x] GREEN handler and compatibility guards. Durable history/notification intent in transaction. Existing staff immediate reschedule routes through proposals; cannot silently confirm current schedule with a pending proposal.
- [x] Functions build + focused emulator regression. Expected exit0 and all tests passing.

### Task 2: client contract and state
Files: appointment_model.dart, appointment_repository.dart, appointment_provider.dart; provider/repository/model tests.
Interfaces: proposalRevision, hasPendingScheduleChange, proposedBy/time; agreement action carrying both revisions and stable requestId.
- [x] RED then GREEN serialization and actions, stale-account/busy protections, optional reason. Expected focused test exit0.

### Task 3: student and PACC UI
Files: appointment_details_sheet.dart, appointment_list_view.dart, appointment_presentation.dart, admin_portal.dart, admin_portal_repository.dart, notification presentation and tests.
- [x] RED then GREEN student current/proposed summary, Accept/Suggest controls, pending recipient labels, immediate confirmation dialog cancellation optional reason, retained input on failure; staff accept/counter controls preserve original reservation and show proposal revision.
- [x] Existing editing now creates proposals, keeps current approved time; result wording truthful. Native time selection and prior layout preserved. Expected student/staff widget tests exit0.

### Task 4: end-to-end regression and independent review
- [x] Full focused Flutter appointment/admin/calendar/notification tests, Functions build and demo Firestore agreement/lifecycle/privacy/Rules suites; targeted analysis; diff check. Expected exit0.
- [x] One fresh reviewer of entire new diff; important fixes RED/GREEN and full affected regression. Record limitations and all rulings in ledger. No hosted claims.

### Verified checkpoint — November 14, 2026

- Flutter focused appointment/provider/repository/admin/calendar/notification/model suites: 139/139 passed, exit 0.
- Functions TypeScript build: exit 0. Expanded demo Firestore suite covering agreement, booking/capacity, editing, Gate 2, staff review, privacy/Rules, lifecycle, reminders and scheduling: 52/52 passed, exit 0.
- Targeted Dart analysis: No issues, exit 0. `git diff --check`: exit 0.
- Independent review: six Important findings fixed with failing regressions first; portal routing compatibility also covered. No deferred minors.
- Exact modified-file inventory, commands, RED/GREEN evidence and rulings: `.superpowers/sdd/2026-11-14-appointment-two-way-agreement/progress.md` (local ignored ledger).
- Current reserved schedule retains its actual lifecycle and reminder identity; separate revisioned proposal state records negotiation. Replacement slots are checked again on acceptance and are not reserved twice.
- Legacy proposals without verified revision/reservation provenance display a verification instruction rather than claiming a held slot or allowing unsupported acceptance. No bulk migration.
- All implementation changes remain uncommitted on `feat/appointment-two-way-agreement`; unrelated dirty files preserved. No push, merge, deployment or device installation. Local handler/emulator tests do not establish hosted callable transport, notification delivery or physical-device end-to-end acceptance. New Functions and client must be released together before manual staging acceptance.
