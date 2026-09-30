# PACC Schedule V2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement task-by-task. Steps use checkbox syntax for tracking.

**Goal:** Deliver a V2 PACC schedule that governs appointments, office status, and administration through one server-authoritative resolver.

**Architecture:** V2 parsing and resolution live in `functions/src/appointment_availability.ts`, with V1 normalization only at the read boundary. Existing appointment transactions invoke the resolver. Flutter gains a lossless V2/V1-compatible model and callable-backed editor; client status views use its Asia/Manila resolver.

**Tech Stack:** Firebase Functions/Firestore transactions, TypeScript/Node test runner, Flutter/Dart, Firebase callable functions, Firestore rules.

**Spec:** `docs/superpowers/specs/2026-09-26-paacc-schedule-v2-design.md`

## Global Constraints

- The supplied Schedule Evolution Markdown is the product contract.
- Use `Asia/Manila` for every backend and Flutter scheduling decision.
- Preserve V1 reads and never auto-migrate live V1 documents.
- Keep direct client writes to `pacc_availability` denied.
- Only Admin and Counselor may mutate; Staff remains read-only.
- Do not silently cancel or mutate existing appointments during a schedule change.
- Validate effective schedule inside transactions for create, confirmation, proposal, and proposal acceptance.
- Use test-first RED-GREEN cycles; no production change precedes its failing test.

## Review Focus

- Test Manila weekday/date boundaries, including UTC dates that differ locally (Task 1).
- Test V1 documents with server metadata and malformed V2 documents (Task 1).
- Test closed/custom override contradictions (Task 1).
- Test concurrent valid saves with one stale expected revision (Task 3).
- Test Staff read-only UI plus callable mutation denial (Tasks 4 and 6).

---

### Task 1: Complete V2 domain contract and effective resolver

**Files:**
- Modify: `functions/src/appointment_availability.ts`
- Modify: `functions/src/appointment_availability.test.ts`
- Modify: `lib/models/pacc_availability_model.dart`
- Create: `test/models/pacc_availability_model_test.dart`

**Interfaces:**
- Produces `PaccDaySchedule`, `PaccDateOverride`, `ResolvedPaccSchedule`, `resolvePaccSchedule(scheduledMillis, availability)`, and V2-only write validation with V1 read normalization.
- Consumes `APPOINTMENT_TIME_ZONE`.

- [ ] Write failing TypeScript/Dart tests for seven-day V2 round-tripping, V1 normalization, closed-day normalization, override precedence, malformed values, and Manila boundaries.
- [ ] Run: `npm.cmd test -- --test-name-pattern="V2|override|V1"` in `functions`; `flutter test test/models/pacc_availability_model_test.dart`. Expected: RED because V2 support is incomplete.
- [ ] Implement strict V2 payload validation (allowed fields, complete weekdays, times, overrides, notice/reason bounds), V1 normalizer, and canonical resolver with closure reason.
- [ ] Upgrade the Flutter model to deserialize V1/V2, serialize V2 only, and expose a pure effective-status method.
- [ ] Run: `npm.cmd test` in `functions`; `flutter test test/models/pacc_availability_model_test.dart`. Expected: GREEN.
- [ ] Commit: `feat: add PACC schedule V2 resolver`.

### Task 2: Apply resolver to slots and appointment lifecycle

**Files:**
- Modify: `functions/src/index.ts`
- Modify: `functions/src/appointment_callable.test.ts`
- Modify: `functions/src/appointment_review_callable.test.ts`
- Modify: `functions/src/appointment_scheduling.test.ts`

**Interfaces:**
- Consumes resolver and validator from Task 1.
- Produces V2-aware `getAvailableAppointmentSlots`, `createAppointmentRequest`, `reviewAppointment`, and `respondToAppointment` transaction behavior.

- [ ] Write failing callable tests for closed, appointments-disabled, counselor-unavailable, override, occupied, and timezone-boundary slots; cover confirmation and both reschedule acceptance paths.
- [ ] Run: `npm.cmd test -- --test-name-pattern="availability|proposal|confirmation|slot"` in `functions`. Expected: RED where V2 states are accepted/exposed.
- [ ] Replace global availability checks with resolver calls inside existing transactions while preserving booking policies, locks, follow-ups, and slot contention.
- [ ] Run: `npm.cmd test` in `functions`. Expected: GREEN.
- [ ] Commit: `feat: enforce V2 schedule in appointments`.

### Task 3: Add conflict preview, revision protection, and auditable saves

**Files:**
- Modify: `functions/src/appointment_availability.ts`
- Modify: `functions/src/index.ts`
- Modify: `functions/src/appointment_availability.test.ts`
- Create: `functions/src/appointment_availability_callable.test.ts`

**Interfaces:**
- Produces `previewPaccScheduleConflicts(candidate, appointments)` and save input `{availability, expectedRevision, confirmConflicts}` with result `{ok, revision, conflicts}`.

- [ ] Write failing tests for requested/confirmed/proposed conflict discovery, historical exclusion, stale revisions, unacknowledged conflicts, revision increment, and bounded audit summary.
- [ ] Run: `npm.cmd test -- --test-name-pattern="schedule conflict|revision|availability save"` in `functions`. Expected: RED.
- [ ] Implement pure conflict preview and harden `savePaccAvailability` to validate, compare revision, preview before write, atomically write V2/revision, and audit the change.
- [ ] Run: `npm.cmd test` in `functions`. Expected: GREEN.
- [ ] Commit: `feat: protect PACC schedule updates`.

### Task 4: Preserve and prove schedule access boundaries

**Files:**
- Modify: `functions/src/appointment_availability_rules.test.ts`
- Modify: `functions/src/appointment_availability_callable.test.ts`
- Modify: `firestore.rules` only if evidence shows a required gap

**Interfaces:**
- Consumes save protocol from Task 3 and callable-only rule boundary.
- Produces role/rules proof for Admin, Counselor, Staff, Student, and unauthenticated clients.

- [ ] Write failing tests for Admin/Counselor save success; Staff/Student/unauthenticated callable denial; authenticated read; and denied direct writes.
- [ ] Run: `npm.cmd test -- --test-name-pattern="availability.*role|permission|rules"` in `functions`. Expected: RED for uncovered behavior.
- [ ] Make the smallest callable authorization/rules adjustment that preserves callable-only writes.
- [ ] Run: `npm.cmd test` in `functions`. Expected: GREEN.
- [ ] Commit: `test: cover PACC schedule access boundaries`.

### Task 5: Upgrade Flutter repository and callable protocol

**Files:**
- Modify: `lib/repositories/admin_portal_repository.dart`
- Modify: `lib/repositories/pacc_availability_repository.dart`
- Create: `test/repositories/pacc_availability_repository_test.dart`

**Interfaces:**
- Consumes Flutter V2 model and callable save result.
- Produces `savePaccAvailability(availability, {confirmConflicts})` and a typed save/conflict response.

- [ ] Write failing tests for V2/V1 reads, V2-only save payload, revision forwarding, conflict preview, and error propagation.
- [ ] Run: `flutter test test/repositories/pacc_availability_repository_test.dart`. Expected: RED.
- [ ] Implement typed request/result mapping without direct Firestore writes or relaxed role checks.
- [ ] Run: `flutter test test/models/pacc_availability_model_test.dart test/repositories/pacc_availability_repository_test.dart`. Expected: GREEN.
- [ ] Commit: `feat: add V2 PACC schedule repository support`.

### Task 6: Replace global editor with weekly and special-date management

**Files:**
- Modify: `lib/features/admin/screens/admin_portal.dart`
- Create: `test/features/admin/pacc_schedule_editor_test.dart`

**Interfaces:**
- Consumes V2 model and repository contract.
- Produces seven-day editing, bulk apply, date overrides, conflict confirmation, and unsaved-change protection.

- [ ] Write failing widgets tests for seven isolated weekday rows, closed state, selected-only bulk update, time validation, add/edit/remove override, Staff read-only, Admin/Counselor save, conflict warning, discard warning, and semantic labels.
- [ ] Run: `flutter test test/features/admin/pacc_schedule_editor_test.dart`. Expected: RED because the page is global/blackout-date based.
- [ ] Replace only `_PaccAvailabilityPage` and directly supporting private widgets with a draft-based editor. Use labels with icon/status, scroll-safe dialogs, and a visible narrow-layout Save control.
- [ ] Run: `flutter test test/features/admin/pacc_schedule_editor_test.dart`. Expected: GREEN.
- [ ] Commit: `feat: redesign PACC weekly schedule editor`.

### Task 7: Use effective V2 status in student and operations views

**Files:**
- Modify: `lib/features/home/screens/home_screen.dart`
- Modify: `lib/features/admin/screens/staff_operations_dashboard.dart`
- Modify: `lib/features/admin/screens/counselor_operations_dashboard.dart` only if it shows schedule state
- Create or modify focused Home/dashboard widget tests

**Interfaces:**
- Consumes pure Flutter resolver/status API.
- Produces consistent office, appointment, and walk-in status wording.

- [ ] Write failing widget tests for open, closed, appointment-disabled, override closure, counselor absence, and non-color-only status labels.
- [ ] Run: `flutter test test/features/home test/features/admin`. Expected: RED where V1 `isOpenAt` disagrees with V2.
- [ ] Replace legacy global status reconstruction with V2 effective status, without unrelated dashboard changes.
- [ ] Run: `flutter test test/features/home test/features/admin`. Expected: GREEN.
- [ ] Commit: `feat: show effective PACC schedule status`.

### Task 8: Full regression and explicit migration boundary

**Files:**
- Modify: `docs/superpowers/specs/2026-09-26-paacc-schedule-v2-design.md` only to add verified rollout limits
- Create: `docs/superpowers/verification/2026-09-26-paacc-schedule-v2.md`

- [ ] Add any missing integration test from the Definition of Done checklist: lifecycle, cancellation, reschedule, follow-up, contention, role, audit, and notification contracts.
- [ ] Run: `npm.cmd test` in `functions`. Expected: full functions suite GREEN.
- [ ] Run: `flutter analyze` then `flutter test` in repo root. Expected: clean analyzer and green suite, or exact pre-existing failures recorded.
- [ ] Run: `git diff --check main...HEAD`. Expected: no whitespace errors.
- [ ] Record that deployment, authenticated staging validation, and intentional V1 migration are separate follow-up operations.
- [ ] Commit: `docs: record PACC schedule V2 verification`.

## Plan self-review

- Coverage: Tasks 1-7 implement the source plan’s domain, resolver, integration, conflicts, permissions, Flutter model/repository/editor, student preview/status, accessibility, and narrow-layout behavior. Task 8 enforces the migration and full-regression boundary.
- Interfaces: Task 1 produces all core types; Tasks 2-4 consume backend contracts; Tasks 5-7 consume stable Flutter/callable contracts in order.
- Testing: every task specifies RED, implementation, GREEN, and a narrow commit. Review Focus cases belong to Tasks 1, 3, 4, and 6.
- Scope: no unrelated lifecycle, Firestore policy, navigation, or dashboard refactoring is authorized.
