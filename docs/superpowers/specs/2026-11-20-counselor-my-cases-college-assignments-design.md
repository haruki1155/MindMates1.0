# Counselor My Cases and College Assignments — Approved Design

**Date:** 2026-11-20
**Reference:** MindMates1.0 `main`, inspected at `ba652bb16256a0a7d820ea7d4309254481ea2daa`.
**Decision:** Option A, explicitly approved by the owner.

## Intent

Make Counselor → My Cases show eligible counseling work based on a counselor's assigned colleges, and add a College Assignments page for the Counselor and Super Admin portals. Use the existing service-area assignment model and preserve all clinical-access protections. No access to real student records is required for development.

## Root cause and existing components

- `CounselorWorkflowPage` and Counselor dashboard read `AdminPortalRepository.watchMyAssignedAppointments()`.
- That method currently adds `assignedStaffId == currentUserId`; server appointment workflows do not populate that field, so valid college work does not show.
- `_watchCollegeScopedAppointments()` already watches `users/{counselorUid}.assignedCollegeIds`, requires an active approved counselor, and queries `appointments` by `studentVerificationStatus == verified` and `collegeId in assignedCollegeIds`.
- Firestore appointment list rules enforce the same verified-college entitlement. Empty assignments fail closed.
- `watchColleges()`, `watchUsers()`, and `watchOwnProfile(uid)` already exist in the repository.
- `showCollegeAssignmentDialog` and `showCollegeCounselorTransferDialog` already implement Super Admin changes through authorized callables. Existing uniqueness/revision checks are preserved.

## Approach and alternatives

- **Selected — College-based caseload:** Eligible appointments within the live assigned colleges become the counselor's cases. Reuses existing rules and query/index pattern; old `assignedStaffId` is not needed.
- Rejected — Individual staff assignment: Would require a new staff-assignment write workflow and backfill; current system does not use this as its active assignment source.
- Rejected — Unrestricted client filtering: Would fetch unrelated clinical appointments before filtering and violate the security boundary.

## Behavior

1. **My Cases:** For an active approved counselor, show eligible appointments in assigned colleges. Continue showing one case per student, using the newest appointment deterministically. Preserve the current inclusion of completed/cancelled/other terminal appointment statuses; adding an active-only filter is a separate product decision, not part of this fix. Existing case-history button, follow-up filtering, loading/error states and appointment navigation remain.
2. **No assignment:** Show zero cases; do not fall back to all appointments. Provide understandable guidance, especially on the My Assigned Colleges page.
3. **Assignment changes:** Adding or removing `assignedCollegeIds` changes the live My Cases results and does not retain stale cases.
4. **Counselor view:** A read-only “My Assigned Colleges” screen displays only the signed-in counselor's assignment IDs resolved to names via the existing `colleges` catalog. Show loading, errors, unassigned, inactive/archived and unknown-college states honestly. Do not call `watchUsers()` for this role.
5. **Admin view:** A “College Assignments” overview, Super Admin only, groups colleges with their assigned counselors or “Unassigned”; detects legacy multiple-owner conflicts and visibly identifies inactive/suspended counselor owners. Assignment and transfer buttons call the existing dialogs. The overview does not write Firestore directly.
6. **Navigation:** Add one `AdminPortalPage.collegeAssignments` destination, visible to counselors and Super Admin only; route the role to its corresponding screen.
7. **Case terminology:** Label the caseload accurately, without suggesting every historical case is currently active.

## Security and non-goals

- No broader Firestore rules, no `users` list query for counselors, no auto-assigning cases to staff, no manual edits to `assignedCollegeIds`, no new collection or callable.
- No change to clinical notes, case remarks, assessment, student roster/activation, announcements, administrative exports, or managed backup.
- No production or staging deployment, push, merge, or real-record inspection in the implementation session without separate owner authorization.
- Use synthetic emulator fixtures for verified/unverified, in-college/out-of-college, revoked, suspended, archived, empty, and conflicting-ownership cases.

## Acceptance

- An approved counselor with assigned colleges sees eligible My Cases even when appointment `assignedStaffId` is absent; dashboard and follow-ups stay consistent.
- Other colleges, unverified students and inactive counselors never leak through; revocation removes access immediately.
- One latest case card per student; case history still works; understandable empty, loading and error states.
- Counselor sees only their own assigned colleges. Super Admin sees college ownership and can invoke existing assign/reassign dialogs. Other roles cannot open either view.
- Relevant repository, widget, permission/rules, and existing assignment tests pass; Functions TypeScript build, Dart analysis and Flutter Web staging build succeed.
