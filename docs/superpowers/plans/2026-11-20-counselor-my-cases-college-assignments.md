# Counselor My Cases and College Assignments Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restore the Counselor My Cases and dashboard caseload using authorized college assignments, and add role-appropriate College Assignments pages for Counselor and Super Admin.

**Architecture:** Reuse the repository's existing Firestore live college-scope query for My Cases instead of filtering on unwritten `assignedStaffId`. Build two small read-only/overview widgets over existing repository streams; Admin mutations continue exclusively through the existing authorized assignment/transfer dialogs. Integrate both with one role-gated Admin Portal destination.

**Tech Stack:** Flutter/Dart, Cloud Firestore streams and rules, Firebase Functions (existing assignment callables only), flutter_test, Node.js 22 / Firebase Auth and Firestore emulators.

**Spec:** `docs/superpowers/specs/2026-11-20-counselor-my-cases-college-assignments-design.md`

## Global Constraints

- Base implementation on the latest `origin/main`, not an old backup-downloads or PR73 worktree.
- Use Option A: cases belong to the counselor's *currently assigned colleges*, not an individual assignment field.
- Do not change which appointment statuses count as a case in this feature. Current My Cases includes completed and terminal statuses; improve misleading `active` wording but do not add status filtering.
- Every counselor appointment query remains restricted to `studentVerificationStatus == 'verified'` and `collegeId` in the signed-in counselor's `assignedCollegeIds`.
- For no assignment, revoked assignment, suspended/unapproved counselor, unverified student, or an unrelated college: fail closed, never fetch organization-wide care data.
- Reuse `watchAppointments`' existing query pattern and `showCollegeAssignmentDialog` / `showCollegeCounselorTransferDialog`; do not create new collections, rules, callables, indexes or dependencies unless a failing test demonstrates necessity and the owner approves the expansion.
- Counselor assignment page must not query the entire `users` collection. Super Admin overview may call `watchUsers()` only after an explicit `isSuperAdmin` gate.
- Preserve case history, follow-ups, appointments, clinical notes, remarks, academic structure, assessment, student activation, announcements, Backup Data, and managed backup.
- Use synthetic users, appointments and college assignments only. Never inspect real student data.
- Make one focused local commit **after** verification. Do not push, merge, deploy, or stage unrelated worktree changes.

## Review Focus

1. **Live revocation:** Reassigning/removing a counselor's college while their page is open must stop the prior listener and clear the previous cases. Test in Task 1.
2. **Missing projections:** An appointment with no `studentVerificationStatus == 'verified'` must not leak into My Cases; do not bypass existing rules. Test query shape in Task 1 and rule behavior in Task 6.
3. **Unassigned counselor:** An empty `assignedCollegeIds` must not cause a global query; show useful wording. Test in Tasks 1 and 3.
4. **Legacy conflicting owners:** Admin overview must visibly flag multiple counselors assigned to the same college and use the existing authorized transfer flow to resolve it. Test in Task 4.
5. **Unknown/inactive college:** A saved assignment to a removed or archived catalog entry must not silently disappear or be shown as an active assignment. Test in Task 3.

---

## File Map

| File | Responsibility |
|---|---|
| `lib/repositories/admin_portal_repository.dart` | Fix the `watchMyAssignedAppointments()` predicate without changing verified-college protection. |
| `test/repositories/admin_portal_appointment_scope_test.dart` | Regression for cases lacking `assignedStaffId`, revocation and unauthorized/empty scope. |
| `functions/src/appointment_privacy_rules.test.ts` | Synthetic emulator evidence that verified-college appointment queries work without `assignedStaffId`, while cross-college queries are denied; rules themselves are untouched. |
| `lib/features/admin/screens/counselor_workflow_page.dart` | Truthful My Cases empty copy and deterministic latest-per-student selection. |
| `test/features/admin/counselor_my_cases_test.dart` | Widget regression for one case per student, follow-ups and empty wording. |
| `lib/features/admin/screens/counselor_assigned_colleges_page.dart` (new) | Signed-in counselor's read-only assignment summary. |
| `test/features/admin/counselor_assigned_colleges_page_test.dart` (new) | Own-profile-only streams, names, errors, empty and archived/unknown states. |
| `lib/features/admin/screens/admin_college_assignments_page.dart` (new) | Super Admin college-to-counselor overview using existing transfer dialog. |
| `test/features/admin/admin_college_assignments_page_test.dart` (new) | Ownership grouping, unassigned/conflict cases, authorization and actions. |
| `lib/features/admin/screens/admin_portal.dart` | One new role-gated nav destination and appropriate page dispatch. |
| `test/features/admin/college_assignments_navigation_test.dart` (new) | Counselor/Admin visibility and all other roles' denial. |

## Task 1: Confirm and fix My Cases query at the source

**Files:**
- Modify: `test/repositories/admin_portal_appointment_scope_test.dart`
- Modify: `lib/repositories/admin_portal_repository.dart`

**Interfaces:**
- Consumes: `AdminPortalRepository._watchCollegeScopedAppointments({Map<String,Object?> extraWhereEquals, required bool errorWhenUnauthorized})`.
- Produces: unchanged public signature `Stream<List<AppointmentModel>> watchMyAssignedAppointments()` with eligible college-based cases.

- [ ] **Step 1: Inspect current branch and reproduce the faulty predicate.** In the repository root, check `git status --short --branch`, read the spec, find `watchMyAssignedAppointments`, `_watchCollegeScopedAppointments`, Firestore `match /appointments` list rules, and the existing repository scope test. Verify the query currently includes `assignedStaffId` and the backend does not populate that field.
- [ ] **Step 2: Write a failing regression test.** Rename/update `'counselor watchMyAssignedAppointments includes verified + assignedCollegeIds filters'` to assert `whereEquals == {'studentVerificationStatus': 'verified'}` and `whereIn == {'collegeId': ['cas','cite']}` for active counselor `counselor-1`. Supply a synthetic appointment without `assignedStaffId` and verify it appears. **The fake Firestore service ignores predicates, so the captured `whereEquals` / `whereIn` assertions are the actual red-green proof**, not the emitted appointment alone. Keep a separate test proving portal staff, non-super-admin staff and signed-out callers cannot query.
- [ ] **Step 3: Run red test.** `flutter test --no-pub --dart-define=APP_ENV=staging test/repositories/admin_portal_appointment_scope_test.dart`. Expected: the new predicate assertion FAILS against current code.
- [ ] **Step 4: Make the minimal production fix.** Preserve the counselor-only guard in `watchMyAssignedAppointments()`. Call `_watchCollegeScopedAppointments(errorWhenUnauthorized: false)` without passing `extraWhereEquals: {'assignedStaffId': userId}`. Preserve the existing verified-college constraints and active approved counselor status checks.
- [ ] **Step 5: Run green test.** Repeat the targeted repository test; expected: PASS.
- [ ] **Step 6: Add live-scope revocation/error coverage.** Start with `assignedCollegeIds: ['cite']`, emit a matching synthetic appointment, then change the profile to `['cas']` while the new `cas` query has not emitted; assert the old `cite` case is cleared immediately. Test changing to `[]` also emits `[]` with no global query, and suspension clears the result. Verify query failures are surfaced rather than interpreted as empty. If the new-college switch test fails, change `_watchCollegeScopedAppointments` to clear prior results after cancelling old listeners and before subscribing to new scope chunks, without changing the Firestore query predicates.
- [ ] **Step 7: Re-run target.** Expected: all repository scope tests PASS.
- [ ] **Step 8: Add backend access proof without changing rules.** In `functions/src/appointment_privacy_rules.test.ts`, test a synthetic verified CITE appointment with no `assignedStaffId`: the active CITE counselor's `studentVerificationStatus == verified` plus `collegeId in ['cite']` query can list it; a CAS-only counselor cannot list CITE data. Keep the existing negative tests for unscoped and `assignedStaffId`-only queries. Run the updated suite in Task 6.

## Task 2: Keep My Cases and follow-up UI honest and stable

**Files:**
- Modify: `lib/features/admin/screens/counselor_workflow_page.dart`
- Create: `test/features/admin/counselor_my_cases_test.dart`
- Existing regression: `test/features/admin/counselor_dashboard_partial_data_test.dart`, `test/features/admin/student_case_history_entry_points_test.dart`

**Interfaces:**
- Consumes: `repository.watchMyAssignedAppointments()` from Task 1.
- Produces: unchanged `CounselorWorkflowPage` constructor, case-history and follow-up entry points.

- [ ] **Step 1: Write failing widget tests.** With synthetic appointments for one student at two different dates presented out of order, assert one case card displays the newer appointment; a second student produces a second card. Assert a follow-up with `followUpRecommended == true` and `followUpStatus == 'offered'` appears in follow-ups, while a non-follow-up does not. Assert empty My Cases uses clear wording rather than saying completed/historical data is necessarily active.
- [ ] **Step 2: Run red.** `flutter test --no-pub --dart-define=APP_ENV=staging test/features/admin/counselor_my_cases_test.dart`; expected: at least one new latest-selection/empty-copy assertion FAILS.
- [ ] **Step 3: Implement only the UI corrections.** Select newest appointment per `userId` before de-duplicating, and replace misleading `No active cases` / `No counseling cases are currently assigned to you` with accurate college-based wording. Keep Case history, View student information, Open appointment, and follow-up behavior unchanged. Do not fetch extra records.
- [ ] **Step 4: Run green and adjacent tests.** Run the new test plus `counselor_dashboard_partial_data_test.dart` and `student_case_history_entry_points_test.dart`; expected: PASS.

## Task 3: Add read-only Counselor → My Assigned Colleges

**Files:**
- Create: `lib/features/admin/screens/counselor_assigned_colleges_page.dart`
- Create: `test/features/admin/counselor_assigned_colleges_page_test.dart`

**Interfaces:**
- New widget: `CounselorAssignedCollegesPage({super.key, required AdminPortalRepository repository})`.
- Consumes: `repository.currentAccessRole`, `repository.currentUserId`, `repository.watchOwnProfile(uid)`, and `repository.watchColleges()`.
- Produces: read-only display of `assignedCollegeIds` resolved to `College.name`; no writes.

- [ ] **Step 1: Write failing widget tests.** Mock a counselor profile with two assigned college IDs and a two-college catalog; assert both college names appear. Assert an empty list says `No colleges assigned yet` with direction to contact the administrator. Assert unknown ID is labeled as unavailable/unknown, and a catalog entry with `active == false` is visibly marked inactive/archived. Emit a changed own profile and confirm the page updates.
- [ ] **Step 2: Write authorization and error tests.** For a non-counselor role or absent UID, assert no protected profile/catalog query is attempted and a safe unavailable message is shown. For a stream error, assert a visible retry/error state; ensure no `watchUsers()` is invoked from this screen.
- [ ] **Step 3: Run red.** `flutter test --no-pub --dart-define=APP_ENV=staging test/features/admin/counselor_assigned_colleges_page_test.dart`; expected: FAIL until the widget exists.
- [ ] **Step 4: Build the page.** Use repository streams and existing Admin theme/widgets. Do not infer `assignedCollegeIds` from `users/{uid}.collegeId` (home college). No edits or assignment buttons for counselors.
- [ ] **Step 5: Run green.** Repeat the targeted widget test; expected: PASS.

## Task 4: Add Super Admin → College Assignments overview

**Files:**
- Create: `lib/features/admin/screens/admin_college_assignments_page.dart`
- Create: `test/features/admin/admin_college_assignments_page_test.dart`
- Reuse unchanged: `lib/features/admin/widgets/college_assignment_dialog.dart`

**Interfaces:**
- New widget: `AdminCollegeAssignmentsPage({super.key, required AdminPortalRepository repository})`.
- Consumes only for Super Admin: `repository.watchColleges()`, `repository.watchUsers()`, `repository.isSuperAdmin`; `UserModel.assignedCollegeIds` and `UserModel.accessRole`.
- Delegates mutation exclusively to `showCollegeCounselorTransferDialog(context, repository: ..., college: ..., currentOwners: ..., eligibleCounselors: ...)`. Existing `showCollegeAssignmentDialog` remains an optional per-counselor editor.

- [ ] **Step 1: Write failing widget tests.** With synthetic data, assert one owner shows its counselor name; no owner shows `Unassigned`; two owners for one college show a visible `Assignment conflict` warning and both names; archived colleges and inactive/suspended counselor owners are visibly labeled. Assert a non-Super-Admin sees no roster data and cannot call `watchUsers()`.
- [ ] **Step 2: Assert existing mutation boundary.** For a Super Admin, verify `Manage`/ `Assign` opens or invokes the existing transfer dialog using owners and `isEligibleCounselorAccount` eligible counselors. Never mutate user docs directly. Include an error state for failed `watchUsers()` or `watchColleges()`.
- [ ] **Step 3: Run red.** `flutter test --no-pub --dart-define=APP_ENV=staging test/features/admin/admin_college_assignments_page_test.dart`; expected: FAIL until the widget exists.
- [ ] **Step 4: Implement overview.** Build `collegeId -> List<UserModel>` from counselor users' `assignedCollegeIds`; retain explicit conflict display. Keep UI responsive, use established Admin visual style, and reuse dialogs. Super Admin guard runs before starting `watchUsers()`.
- [ ] **Step 5: Run green.** Repeat target test; expected: PASS.

## Task 5: Register the shared navigation destination

**Files:**
- Modify: `lib/features/admin/screens/admin_portal.dart`
- Create: `test/features/admin/college_assignments_navigation_test.dart`

**Interfaces:**
- Add enum value `AdminPortalPage.collegeAssignments`, label `College Assignments`, and appropriate distinct icon.
- `_allowed(AdminPortalPage.collegeAssignments)` returns true only for `accessRole == AccessRole.counselor || isSuperAdmin`.
- Page dispatch: Super Admin -> `AdminCollegeAssignmentsPage`; counselor -> `CounselorAssignedCollegesPage`.

- [ ] **Step 1: Write failing navigation tests.** Counselor sees one menu entry, labeled `College Assignments`, leading to heading `My Assigned Colleges`; Super Admin sees one entry leading to Admin overview. `portalStaff`, app user, and non-Super-Admin administrators do not receive the page.
- [ ] **Step 2: Run red.** `flutter test --no-pub --dart-define=APP_ENV=staging test/features/admin/college_assignments_navigation_test.dart`; expected: FAIL before registration.
- [ ] **Step 3: Add the single route.** Update the enum's exhaustive label/icon switches, the existing People navigation section, `_allowed`, and the page-building switch. Do not duplicate the menu in two sections or change unrelated role routing.
- [ ] **Step 4: Run green.** Repeat navigation test and the Counselor/Admin page tests; expected: PASS.

## Task 6: Security regression, final verification and focused local commit

**Files:** All Task 1–5 changes only. Do not modify Cloud Functions, rules or unrelated features to make tests green.

- [ ] **Step 1: Static scope review.** Compare against `origin/main`. Verify only the listed files changed and that `firestore.rules`, `functions/src/college_assignments_callable.ts`, `functions/src/appointment_approval_service.ts`, `functions/src/backup_export.ts` and student activation paths remain untouched.
- [ ] **Step 2: Run targeted Flutter tests.**

  ```powershell
  flutter test --no-pub --dart-define=APP_ENV=staging test/repositories/admin_portal_appointment_scope_test.dart test/features/admin/counselor_my_cases_test.dart test/features/admin/counselor_assigned_colleges_page_test.dart test/features/admin/admin_college_assignments_page_test.dart test/features/admin/college_assignments_navigation_test.dart test/features/admin/counselor_dashboard_partial_data_test.dart test/features/admin/student_case_history_entry_points_test.dart test/features/admin/college_assignment_dialog_test.dart test/features/admin/user_management_page_test.dart
  ```

  Expected: 0 failures. If any named existing test changed path on latest `main`, locate the exact current file; never silently skip.

- [ ] **Step 3: Run analyzer.** `dart analyze` over all modified Dart files and their tests (or `flutter analyze` for the full project). Expected: 0 new issues; report any pre-existing baseline separately.
- [ ] **Step 4: Run Functions build.** `npm run build --prefix functions` on Node 22 with development dependencies installed. Expected: exit 0.
- [ ] **Step 5: Run existing emulator security/assignment suites.** Execute from the repo root:

  ```powershell
  firebase emulators:exec --config firebase.mood-v2.emulators.json --only auth,firestore "node --test --test-concurrency=1 functions/lib/college_assignments.test.js functions/lib/college_assignments_callable.test.js functions/lib/college_assignments_rules.test.js functions/lib/appointment_privacy_rules.test.js functions/lib/student_case_history_callable.test.js"
  ```

  Expected: 0 failures; unauthorized counselor/off-college behavior remains denied. If emulator ports are occupied, choose an existing project-specific isolated config rather than altering shared/production configuration.
- [ ] **Step 6: Build Flutter Web staging.** `flutter build web --no-pub --dart-define=APP_ENV=staging`. Expected: `Built build/web` or platform-equivalent output and exit 0.
- [ ] **Step 7: Inspect diff.** Run `git diff --check`, `git diff --stat`, `git status --short`; verify no unapproved backend/rules/dependency changes and no personal or staging credentials tracked.
- [ ] **Step 8: One local commit, only if all required checks passed.** Stage each explicitly approved file (and the spec/plan), then `git diff --cached --stat` and `git diff --cached --check`. Commit with `fix(counselor): restore college-scoped cases and add assignment views`. Do not use `git add -A`.
- [ ] **Step 9: Final report.** State branch, full commit SHA, exact changed files, test counts, build results, retained backend authorization, any limitations, and `GO/NO-GO` for human review. **Do not push, open PR, merge or deploy.**
