# College-Based PACC Staff Assignment — Design

**Date:** 2026-11-15 · **Requirement:** evaluator #1 (PR 3 of the 11-requirements plan)
**Branch:** `feat/pr3-college-staff-assignments` from `origin/main` b4f7ba7 (includes PR #46; excludes unmerged PR #48)

## Intent
Let the super-administrator record which colleges each PACC staff member or counselor serves, from Web User Management, so later work (inquiry routing #2, college-scoped approval #8) has a trustworthy, server-enforced source of truth.

## Findings
- `users/{uid}.collegeId` already exists on staff records, but it is the staff member's **home** college captured at registration and edited by `updateStaffOrganization`. Reusing it would conflate "where I belong" with "whom I serve" and would allow only one college. It stays untouched.
- `colleges/{id}` is the institutional record (public read, server write, `active` flag). No assignment model exists anywhere.
- `firestore.rules` `users/{uid}`: read by owner or `isSystemAdmin()`; update only by the owner through `validSelfProfileUpdate()` (an allow-list); create false. A new field outside that allow-list is already immune to self-edits.
- Privileged staff writes go through super-admin callables with audit (`requireSuperAdmin`, `writeAudit`).

## Goals
1. View, assign, update and remove a staff member's colleges from User Management.
2. Only the configured super-administrator can change assignments; enforced in a callable and in rules (no client write path).
3. Validate against existing `colleges` IDs; no duplicate institutional data.
4. Staff and counselors only (approved/active for additions); removals always allowed for cleanup.
5. Optimistic concurrency and a full audit trail.
6. Backward compatible: existing staff with no assignments read as "Unassigned".

## Non-goals
Inquiry routing, appointment approval, escalation owner, primary/backup counselor designation (PACC policy not yet approved), automatic backfill from home `collegeId`.

## Anti-goals
Any client-side write that could set assignments; a staff member editing their own assignments; silently dropping an unknown college.

## Approaches
| | Approach | Trade-offs |
|---|---|---|
| A | New `college_staff_assignments/{collegeId}` docs listing staff UIDs | Natural "who serves college X" lookup and per-college revision, but a second collection mirroring user state; a staff-centric edit touches many docs; arguably the "duplicate collection" the request rules out. |
| **B (chosen — my call)** | **`users/{uid}.assignedCollegeIds: string[]`** plus `collegeAssignmentRevision`, `collegeAssignmentUpdatedAt/By`, written only by a super-admin callable | One document per edit, matches the staff-centric UI, no new collection, self-edit already blocked by the existing rules allow-list. Routing later queries `array-contains` server-side. |
| C | Reuse `users.collegeId` | Single college, conflates home vs served college, breaks existing org edits. Rejected. |

## Design
**Data (additive):** `assignedCollegeIds: string[]` (sorted, unique, ≤ 20), `collegeAssignmentRevision: int` (absent ⇒ 0), `collegeAssignmentUpdatedAt`, `collegeAssignmentUpdatedBy`.

**Callable `setStaffCollegeAssignments({userId, collegeIds, expectedRevision, reason})`** (us-central1, existing callable pattern):
- `requireSuperAdmin` (inherits PR #46 lifecycle gates).
- Pure validator `planCollegeAssignmentChange(target, requested, colleges, expectedRevision)` in `functions/src/college_assignments.ts`:
  - target must exist with `accessRole` `portalStaff` or `counselor` (`role-mismatch`);
  - IDs must be strings matching `[A-Za-z0-9_-]{1,128}`, ≤ 20 after de-dup (`invalid-argument`);
  - every ID must exist in `colleges` (`unknown-college`);
  - newly **added** IDs must be `active` and the target must be lifecycle-active (`staffAccountStatus` absent/approved, `accountStatus` absent/active) (`inactive-college`, `inactive-staff`); retained or removed IDs need neither, so archived colleges and suspended staff can always be cleaned up;
  - `expectedRevision` must equal stored revision (`stale-revision` ⇒ `failed-precondition`);
  - no-op when the set is unchanged.
- Transaction re-reads target and checks revision, writes fields, `revision + 1`, and `writeAudit` action `STAFF_COLLEGE_ASSIGNMENTS_UPDATED` (category `USER_MANAGEMENT`, target `staff`) with `before`, `after`, `added`, `removed`, `reason`.
- Reason required (3–500 chars), like other staff changes.

**Rules:** no new allow; add a comment and emulator tests proving students, staff, counselors and even the super-admin cannot write `assignedCollegeIds` client-side, and owners can read their own.

**Flutter:** `UserModel.assignedCollegeIds` + `collegeAssignmentRevision` (read-only; not added to `toJson`, so profile writes never touch them). Repository `setStaffCollegeAssignments(...)` via the existing callable seam. User Management staff menu gains **College assignments** (super-admin only) opening a dialog: active colleges as checkboxes, currently assigned archived colleges shown checked with "(archived)", explicit "Unassigned" when empty, required reason, save errors shown truthfully (`stale` → "updated by someone else, reload"). Staff detail shows **Assigned colleges** names or "Unassigned".

## Testing
Pure validator unit tests; emulator callable tests (super-admin success + audit, non-super/counselor/staff/student denied, unknown/inactive college, role mismatch, suspended-staff add denied but removal allowed, stale revision, removal to empty, no-op); rules tests (no client writes, owner read); Dart model, repository and dialog widget tests.

## Calls for review
1. Option B (field on `users`) over a new collection.
2. No primary/backup counselor yet.
3. Suspended staff and archived colleges: removals allowed, additions refused.
4. Cap of 20 colleges per person.
5. Super-admin only (matches `updateStaffOrganization`), not every `admin` role.
