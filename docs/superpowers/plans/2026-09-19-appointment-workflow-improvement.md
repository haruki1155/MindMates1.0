# Appointment Workflow Improvement Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Correct the admin appointment lifecycle so confirmed appointments stay date-organized in Upcoming, become actionable only in Today, and move explicitly to Completed with durable counts and linked follow-up support.

**Architecture:** Keep Firestore as the source of truth and retain `reviewAppointment` for staff decisions. Add a pure Dart queue classifier for consistent UI/count behavior, enforce transitions in Cloud Functions, and add a transactional follow-up callable that creates a linked requested appointment plus history and notification records. Treat archive state as independent from lifecycle state.

**Tech Stack:** Flutter/Dart, Flutter widget tests, Firebase Callable Functions, TypeScript, Firestore transactions/rules/indexes, existing notification and appointment-slot infrastructure.

**Spec:** `docs/superpowers/specs/2026-09-19-appointment-workflow-design.md`

## Global Constraints

- Preserve the existing appointment, history, notification, and appointment-slot collections.
- Do not perform a destructive data migration; normalize legacy statuses at read time.
- Appointment lifecycle writes remain callable-only and server-validated.
- Do not expose new client-side authorization as a substitute for backend authorization.
- Archived appointments remain included in Completed and historical metrics.
- Upcoming confirmed appointments have no completion/outcome action before their scheduled date.
- Do not add a new dependency or replace the current state-management/repository architecture.
- Do not implement, deploy, or migrate production resources as part of plan preparation.

## Review Focus

- A confirmed appointment scheduled three days ahead must remain in Upcoming and be grouped by its scheduled date.
- A confirmed appointment must enter Today only on its scheduled local calendar date.
- Completed counts must not decrease when a completed appointment is archived.
- Follow-up creation must preserve the original appointment and create one linked request transactionally.
- Unsupported cancellation and restore actions must not remain reachable through UI or callable contracts.

---

### Task 1: Add canonical appointment queue classification

**Files:**
- Create: `lib/features/admin/domain/appointment_workflow.dart`
- Modify: `lib/models/appointment_model.dart`
- Create: `test/features/admin/appointment_workflow_test.dart`
- Modify: `test/models/appointment_model_test.dart`

**Interfaces:**
- Consumes: `AppointmentModel.status`, `scheduledAt`, `archivedAt`, and an injected `DateTime now`.
- Produces: `AppointmentQueue classifyAppointment(AppointmentModel appointment, DateTime now)` and `bool canTakeOutcomeAction(AppointmentModel appointment, DateTime now)`.

- [ ] **Step 1: Write failing classification tests**

  Cover requested, legacy pending/upcoming, reschedule proposal, confirmed today, confirmed future, completed, not-attended, archived, and a confirmed appointment whose time is later today. Assert that future confirmed records are Upcoming and not actionable.

- [ ] **Step 2: Run the focused test**

  Run: `flutter test test/features/admin/appointment_workflow_test.dart`

  Expected: FAIL because the classifier does not exist.

- [ ] **Step 3: Implement the pure classifier**

  Use local calendar dates for Today/Upcoming boundaries. Treat `archivedAt` as a separate archive filter, not as a lifecycle queue. Preserve legacy status normalization through `AppointmentStatus.parse`.

- [ ] **Step 4: Add model support for new fields**

  Add optional `parentAppointmentId`, `appointmentType`, `createdFrom`, `followUpReason`, `followUpMessage`, and `followUpRequestedAt` to `AppointmentModel`, including JSON parsing and `copyWith` support.

- [ ] **Step 5: Run tests and analyzer**

  Run: `flutter test test/features/admin/appointment_workflow_test.dart test/models/appointment_model_test.dart`

  Expected: PASS.

- [ ] **Step 6: Commit**

  Run: `git add lib/features/admin/domain/appointment_workflow.dart lib/models/appointment_model.dart test/features/admin/appointment_workflow_test.dart test/models/appointment_model_test.dart; git commit -m "feat: define appointment queue classification"`

### Task 2: Correct backend lifecycle transitions

**Files:**
- Modify: `functions/src/index.ts:1602-1935`
- Modify: `lib/repositories/admin_portal_repository.dart:943-965`
- Modify: `firestore.rules:496-560` if new fields require allowlist updates
- Create/modify: `functions/src/appointment_workflow.test.ts`

**Interfaces:**
- Consumes: Existing `reviewAppointment` callable payload.
- Produces: Server-validated actions `confirmed`, `reschedule_proposed`, `completed`, `not_attended`, and `declined`; rejects new cancellation transitions.

- [ ] **Step 1: Add failing Functions tests for transitions**

  Assert confirmed-from-requested succeeds, completed-from-confirmed succeeds only when due, completed-from-requested fails, not-attended-from-confirmed succeeds only when due, and cancelled is rejected for new calls.

- [ ] **Step 2: Run the Functions test**

  Run from `functions`: `npm test -- appointment_workflow.test.ts`

  Expected: FAIL for the new transition contract.

- [ ] **Step 3: Update the callable transition matrix**

  Change the allowed action list and per-status matrix. Use canonical status normalization for old records. Add a server-side date check based on the stored `scheduledAt` Timestamp. Keep administrator override behavior explicit and limited to the existing privileged staff role if the current authorization helpers support it.

- [ ] **Step 4: Update notification and audit labels**

  Add a distinct notification/audit mapping for `not_attended`; remove new cancellation creation. Keep legacy records readable.

- [ ] **Step 5: Run Functions tests and build**

  Run from `functions`: `npm test -- appointment_workflow.test.ts` and `npm run build`.

  Expected: PASS and TypeScript compilation succeeds.

- [ ] **Step 6: Commit**

  Run: `git add functions/src/index.ts functions/src/appointment_workflow.test.ts lib/repositories/admin_portal_repository.dart firestore.rules; git commit -m "fix: enforce appointment lifecycle transitions"`

### Task 3: Add transactional follow-up appointment creation

**Files:**
- Modify: `functions/src/index.ts` near appointment callables
- Modify: `lib/repositories/admin_portal_repository.dart`
- Modify: `lib/models/appointment_model.dart` if Task 1 did not include fields
- Create: `functions/src/follow_up_appointment.test.ts`
- Create/modify: `test/repositories/admin_portal_repository_contract_test.dart`

**Interfaces:**
- Consumes: `createFollowUpAppointment({sourceAppointmentId, scheduledAt, scheduledTime, reason, message})`.
- Produces: `{ok: true, appointmentId: string}` and a new requested appointment linked by `parentAppointmentId`.

- [ ] **Step 1: Write failing transaction tests**

  Assert that a completed source creates one requested follow-up, copies user/contact/department data, sets `appointmentType: follow_up`, writes a history event, creates a user notification, and leaves the source status unchanged. Assert that a requested or future confirmed source is rejected.

- [ ] **Step 2: Run the focused Functions test**

  Run from `functions`: `npm test -- follow_up_appointment.test.ts`

  Expected: FAIL because the callable is not present.

- [ ] **Step 3: Implement the callable transaction**

  Re-read the source appointment inside the transaction, authorize the staff actor, validate terminal source state and future schedule, reserve the new slot, create the follow-up appointment, create history/audit/notification records, and return the new ID. Use an idempotency check on the source and requested follow-up metadata.

- [ ] **Step 4: Add the repository method**

  Add `createFollowUpAppointment` to `AdminPortalRepository`, passing epoch milliseconds and trimmed message/reason values to the callable.

- [ ] **Step 5: Run tests and build**

  Run from `functions`: `npm test -- follow_up_appointment.test.ts` and `npm run build`.

  Run: `flutter test test/repositories/admin_portal_repository_contract_test.dart`.

  Expected: PASS.

- [ ] **Step 6: Commit**

  Run: `git add functions/src/index.ts functions/src/follow_up_appointment.test.ts lib/repositories/admin_portal_repository.dart lib/models/appointment_model.dart test/repositories/admin_portal_repository_contract_test.dart; git commit -m "feat: create linked follow-up appointments"`

### Task 4: Fix archive behavior and stable Completed metrics

**Files:**
- Modify: `functions/src/index.ts:1821-1905`
- Modify: `lib/repositories/admin_portal_repository.dart:1029-1042`
- Modify: `lib/features/admin/screens/admin_portal.dart:1808-2260`
- Create/modify: `test/features/admin/appointment_archive_count_test.dart`

**Interfaces:**
- Consumes: terminal appointments and the existing archive callable.
- Produces: one-way archive-to-history behavior with no restore operation and counts derived from the complete stream.

- [ ] **Step 1: Write failing archive/count tests**

  Assert that archiving a completed appointment does not change the Completed count, active queue excludes it, history includes it, and attempting restore is rejected.

- [ ] **Step 2: Remove automatic terminal archiving**

  Delete or disable the `archiveTerminalAppointment` trigger behavior so completion does not silently remove the record from the active Completed queue.

- [ ] **Step 3: Make archive one-way**

  Change `archiveAppointments` to accept only `archived: true`, reject `archived: false`, and remove restore audit/action paths. Keep terminal-status validation and counselor ownership validation.

- [ ] **Step 4: Update repository and UI contracts**

  Replace the boolean archive API with `archiveAppointments(List<String> appointmentIds)` or enforce true-only semantics. Remove restore labels, restore dialogs, restore bulk buttons, and restore menu actions.

- [ ] **Step 5: Run focused tests**

  Run: `flutter test test/features/admin/appointment_archive_count_test.dart test/repositories/admin_portal_repository_contract_test.dart`.

  Run from `functions`: `npm test -- appointment_workflow.test.ts`.

  Expected: PASS.

- [ ] **Step 6: Commit**

  Run: `git add functions/src/index.ts lib/repositories/admin_portal_repository.dart lib/features/admin/screens/admin_portal.dart test/features/admin/appointment_archive_count_test.dart; git commit -m "fix: preserve completed counts after archiving"`

### Task 5: Refactor the admin queue UI around date-driven queues

**Files:**
- Modify: `lib/features/admin/screens/admin_portal.dart:1797-3100`
- Modify: `lib/features/admin/domain/appointment_workflow.dart`
- Create/modify: `test/features/admin/appointment_portal_queue_test.dart`

**Interfaces:**
- Consumes: `AppointmentQueue`, `classifyAppointment`, and `canTakeOutcomeAction`.
- Produces: summary cards, filters, grouped Upcoming list, and contextual actions that all use the same classification.

- [ ] **Step 1: Write failing widget tests**

  Render appointments spanning requested, today, three-days-ahead confirmed, completed, and archived states. Assert Today selects Today, the future confirmed record appears under an Upcoming date heading, and outcome buttons are absent from Upcoming but present in Today.

- [ ] **Step 2: Replace duplicated filter predicates**

  Classify each record once per stream snapshot, derive counts and visible items from the classification, and use an injected `now` helper in tests.

- [ ] **Step 3: Implement date-grouped Upcoming sections**

  Sort by `scheduledAt` ascending and render a date heading for each distinct local date. Keep Today sorted by time. Show the confirmed date/time prominently in every row.

- [ ] **Step 4: Implement contextual actions**

  Requested and reschedule rows show review actions. Upcoming rows show View only. Today rows show Record completed and Record missed appointment. Completed rows show View and Follow up. Archived rows show View only.

- [ ] **Step 5: Remove confusing controls and wording**

  Remove Cancel Appointment, Restore, generic Clear filters, and “Mark no-show.” Replace with the approved terminology and inline Department reset behavior.

- [ ] **Step 6: Add per-row processing indicators**

  Track processing by appointment ID, disable only the active action, show a spinner in the button, prevent duplicate submissions, and display success/failure feedback after the callable result.

- [ ] **Step 7: Run widget tests and analyzer**

  Run: `flutter test test/features/admin/appointment_portal_queue_test.dart test/features/admin/appointment_archive_count_test.dart`

  Run: `flutter analyze lib/features/admin/screens/admin_portal.dart lib/features/admin/domain/appointment_workflow.dart lib/models/appointment_model.dart lib/repositories/admin_portal_repository.dart`

  Expected: PASS and no analyzer issues.

- [ ] **Step 8: Commit**

  Run: `git add lib/features/admin/screens/admin_portal.dart lib/features/admin/domain/appointment_workflow.dart test/features/admin/appointment_portal_queue_test.dart; git commit -m "feat: organize admin appointments by scheduled date"`

### Task 6: Improve reschedule and follow-up dialogs

**Files:**
- Modify: `lib/features/admin/screens/admin_portal.dart` appointment dialog section
- Modify: `lib/repositories/admin_portal_repository.dart`
- Create/modify: `test/features/admin/appointment_dialog_test.dart`

**Interfaces:**
- Consumes: repository review/follow-up methods and appointment queue context.
- Produces: user-centered reschedule and follow-up forms with validation and reliable submission state.

- [ ] **Step 1: Write failing dialog tests**

  Assert that reschedule shows current/proposed schedule, requires a future date and time, disables submission while processing, and displays validation errors. Assert that Follow up displays reason/message/date/time fields and invokes the repository method.

- [ ] **Step 2: Implement reschedule presentation**

  Separate current schedule from proposed schedule, use clear labels, use a date picker constrained to future dates, and show the selected date/time before submission.

- [ ] **Step 3: Implement Follow up presentation**

  Add the new action for completed/not-attended rows, collect required follow-up details, submit through `createFollowUpAppointment`, and show the resulting request confirmation.

- [ ] **Step 4: Run focused tests**

  Run: `flutter test test/features/admin/appointment_dialog_test.dart`.

  Expected: PASS.

- [ ] **Step 5: Commit**

  Run: `git add lib/features/admin/screens/admin_portal.dart lib/repositories/admin_portal_repository.dart test/features/admin/appointment_dialog_test.dart; git commit -m "feat: improve reschedule and follow-up actions"`

### Task 7: Validate reminders, rules, and full affected surface

**Files:**
- Modify: `functions/src/index.ts` reminder logic only if required by new status names
- Modify: `firestore.rules` and `firestore.indexes.json` only when tests identify a required contract change
- Modify: affected tests and docs

**Interfaces:**
- Consumes: final lifecycle/status contract and follow-up fields.
- Produces: verified reminder behavior, rule compatibility, and release evidence.

- [ ] **Step 1: Add reminder tests**

  Assert one 24-hour and one-hour reminder per confirmed appointment, no reminders after completion/not-attended, and reminder reset after accepted reschedule.

- [ ] **Step 2: Run focused Flutter validation**

  Run: `flutter test test/features/admin test/models/appointment_model_test.dart test/providers/appointment_provider_test.dart test/features/home/home_appointment_calendar_test.dart`.

- [ ] **Step 3: Run targeted analyzer**

  Run: `flutter analyze lib/features/admin lib/models/appointment_model.dart lib/repositories/admin_portal_repository.dart`.

- [ ] **Step 4: Run Functions validation**

  Run from `functions`: `npm test` and `npm run build`.

- [ ] **Step 5: Review the final diff**

  Run: `git diff --check` and `git status --short`.

  Confirm no unrelated files, generated secrets, deployment files, or restore/cancel code paths were added.

- [ ] **Step 6: Commit validation evidence**

  Run: `git add docs/superpowers/specs/2026-09-19-appointment-workflow-design.md docs/superpowers/plans/2026-09-19-appointment-workflow-improvement.md; git commit -m "docs: plan appointment workflow improvements"`

## Execution handoff

This plan is complete and intentionally stops before product implementation. Implementation should use either `superpowers:executing-plans` for native execution in this workspace or `superpowers:subagent-driven-development` for task-by-task independent implementation and review. Production deployment, Functions deployment, and Firestore rule deployment require a separate explicit request after the local validation gates pass.
