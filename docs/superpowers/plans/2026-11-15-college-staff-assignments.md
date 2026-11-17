# College Staff Assignment Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:executing-plans. Steps use checkbox syntax.

**Goal:** Super-admin assigns PACC staff/counselors to existing colleges from User Management, enforced server-side.
**Architecture:** Pure validator + super-admin callable writing `users.assignedCollegeIds` with revision and audit; rules keep the field client-immutable; Flutter model, repository and a User Management dialog.
**Tech Stack:** TypeScript Functions v2, Firestore rules, Flutter/Dart, node:test, rules-unit-testing, flutter_test.
**Spec:** `docs/superpowers/specs/2026-11-15-college-staff-assignments-design.md`

## Global Constraints
- No new dependencies; no new collection; `users.collegeId` untouched.
- Callable name `setStaffCollegeAssignments`; audit action `STAFF_COLLEGE_ASSIGNMENTS_UPDATED`.
- Error codes: `role-mismatch`, `unknown-college`, `inactive-college`, `inactive-staff`, `stale-revision`, `too-many`, `invalid-id`.
- Max 20 colleges; IDs `^[A-Za-z0-9_-]{1,128}$`; reason 3–500 chars.

## Review Focus
1. A college archived after assignment must stay removable and must not block saving other changes. (Task 1)
2. Two admins saving the same staff concurrently: second gets `failed-precondition`, nothing overwritten. (Task 2)
3. A counselor whose record is later suspended: assignments can be cleared, not extended. (Task 1, Task 2)
4. Legacy staff without the new fields display "Unassigned" and revision 0. (Task 3)
5. Profile self-update must still succeed after the field exists (allow-list unaffected). (Task 2 rules test)

### Task 1: Pure validator — `functions/src/college_assignments.ts` (+ `.test.ts`)
`planCollegeAssignmentChange(input: {target: Record<string, unknown> | null; requested: unknown; colleges: Map<string, {active: boolean}>; expectedRevision: unknown}) => {changed: boolean; next: string[]; added: string[]; removed: string[]; before: string[]; revision: number}`; throws `CollegeAssignmentError(code)`. Unit tests per error code and the archive/suspension removal cases.

### Task 2: Callable + audit + rules tests
`setStaffCollegeAssignments` in `functions/src/college_assignments_callable.ts`, exported from `index.ts`; audit action registered. Emulator tests `college_assignments_callable.test.ts` (Auth+Firestore) and `college_assignments_rules.test.ts`.

### Task 3: Flutter model + repository
`UserModel.assignedCollegeIds`, `collegeAssignmentRevision`; `AdminPortalRepository.setStaffCollegeAssignments({userId, collegeIds, expectedRevision, reason})`. Tests in `test/models/user_model_college_assignment_test.dart`.

### Task 4: User Management dialog
`lib/features/admin/widgets/college_assignment_dialog.dart`; staff menu item `College assignments` (super-admin); detail line `Assigned colleges`. Widget tests `test/features/admin/college_assignment_dialog_test.dart`.

### Task 5: Verification and PR preparation
Functions build + unit + emulator suites (new + PR #46 suites), `flutter analyze`, admin/models/repositories regression, `git diff --check`, PR body.
