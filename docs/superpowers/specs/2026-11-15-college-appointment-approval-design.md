# College-Scoped Appointment Approval — Design

**Date:** 2026-11-15 · **Requirement:** evaluator #8 (PR 6) · **Base:** `origin/main` 0560e13 (PR #3 merged; PRs #48, #50, #51 not needed and not included)

## Findings
- Every staff action on an appointment goes through `requireClinicalAppointmentStaff` (`functions/src/index.ts`): any approved counselor **or admin** may confirm, reschedule, complete, mark no-show, accept/counter a student proposal, or initialise a legacy schedule for **any** student. No college check. The existing review test asserts that a non-assigned counselor may act.
- Two-way agreement (`appointment_agreement.ts::handleAppointmentAgreement`) authorises the staff side through an injected `authorizeStaff(uid)` with no appointment context.
- Slot reservation (`appointment_slots/pacc_<millis>`), the per-student lock (`appointment_user_locks`), schedule/proposal revisions and history are all enforced inside transactions; this PR does not change them.
- Appointment documents carry no verified college; the student's verified college is `users/{uid}.collegeId` (set server-side at registration, `verificationStatus: "verified"`).
- Rules: counselors and admins read all appointments (`hasClinicalAccess`); portal staff read only the non-clinical `appointment_queue`.
- **Pre-existing test breakage:** 23 of 45 appointment emulator tests fail on main with `auth/user-not-found` (fixtures predate PR #46's Auth check). CI does not catch it: `npm test`'s `lib/**/*.test.js` is expanded by `sh` (no globstar) to the 6 files under `lib/assessment/`. Fixed separately in this branch (test fixtures only).

## Goals
1. Clinical appointment decisions only by eligible counselors assigned to the student's verified college.
2. Unverifiable or unassigned appointments go to an administrative triage path for the configured super-administrator.
3. Super-administrator override of a college-scoped appointment only with a written, audited reason.
4. Preserve state machine, two-way agreement, schedules, slots, locks, history, notifications.
5. "My College's Approvals" for counselors; "Approval exceptions" for the super-administrator.

## Non-goals
Narrowing clinical **read** access by college (policy decision for PACC; reads stay as on main). Archive (operational, `requireStaff`) and walk-in import (record creation) are unchanged. CI glob fix (separate PR).

## Approaches
| | Approach | Trade-offs |
|---|---|---|
| **A (chosen)** | Server authority check per action, using the student's current verified college and live counselor assignments; approvals list computed by a callable | Always reflects current assignments; no schema change or backfill; one extra read set per action. |
| B | Stamp `collegeId`/scope on appointments at creation + backfill; rules/clients filter | Cheap listing, but stale when assignments change and needs a migration. |
| C | UI-only filtering | Not security. Rejected. |

## Authority (pure: `functions/src/appointment_approval.ts`)
**Scope** of an appointment (from the student profile, `colleges`, and counselors whose `assignedCollegeIds` contain the college):
- `college`: student `verificationStatus == "verified"`, well-formed `collegeId` that exists, and at least one **eligible counselor** (role `counselor`, `staffAccountStatus` absent/approved, `accountStatus` absent/active, Auth enabled + email verified).
- `exception` with reason `missing_college` | `unverified_profile` | `unknown_college` | `no_eligible_counselor`.

**Decision** for an actor already past `requireStaff` + counselor/admin role:
| Actor | Scope `college` | Scope `exception` |
|---|---|---|
| counselor serving the college | allow, mode `college` | — |
| counselor not serving it | `permission-denied` (`wrong_college`) | `permission-denied` (`needs_triage`) |
| configured super-admin | allow only with `exceptionReason` (3–500) → mode `admin_override`; else `failed-precondition` (`override_reason_required`) | allow, mode `admin_triage` |
| other admin | `permission-denied` (`not_super_admin`) | `permission-denied` |
| portal staff / student | refused earlier (unchanged) | |

## Wiring
- `authorizeAppointmentApproval(uid, appointment, exceptionReason)` (`appointment_approval_service.ts`) = existing clinical gate + scope + decision; returns the actor with `approvalAuthority {mode, collegeId, scopeReason, exceptionReason}`.
- Used by `reviewAppointment` (all actions), the staff side of `changeAppointmentAgreement` / `respondToAppointment` / `rescheduleStudentAppointment` (the agreement authoriser now receives the appointment and input), and `initializeAppointmentScheduleRevision`.
- History entries and audit metadata gain `approvalMode`, `collegeId`, and (override) `exceptionReason`.
- `listAppointmentApprovals` callable: pending decisions (`requested`, `reschedule_proposed`, or a pending student proposal), not archived. Counselor → items whose college they serve; super-admin → exceptions with reasons. Returns IDs, status, schedule, college and scope only (no concern or clinical text).

## Web
- Appointments page: **My College's Approvals** panel (counselor) / **Approval exceptions** panel (super-admin), with refresh and open-appointment.
- Appointment action dialog: super-admin sees an optional "Administrator exception reason" field, sent with review, agreement and initialisation calls; the server says when it is required.

## Testing
Pure scope/decision tests; emulator tests for every row of the table, two-way agreement on both sides, concurrent approvals (one wins), slot double-booking still prevented, notifications and audit; list callable scoping and privacy; existing appointment suites updated where they asserted the old "any counselor" behaviour; Flutter panel and repository tests.

## Calls for review
1. Super-admin only for exceptions/overrides (not every `admin`).
2. Override allowed with a mandatory reason rather than forbidden.
3. Reads unchanged (org-wide for counselors) pending PACC policy.
4. Approval list computed server-side on demand (refresh), not live.

## Deployment checklist (precondition; added after independent review)
Without assignment data every appointment becomes an exception, every counselor is refused, and the whole clinical queue falls to one super-administrator. Before deploying these Functions:
1. PR #3's `setStaffCollegeAssignments` is deployed and **every active counselor has `assignedCollegeIds`** covering the colleges they serve.
2. Every counselor profile has `accessRole: "counselor"` (records with only the legacy `role` field are not eligible approvers) and is approved, active and email-verified.
3. `SUPER_ADMIN_UID` is set for the target project and that account is verified and active; otherwise exceptions cannot be handled by anyone.
4. Other `admin` accounts are told they can no longer approve; exceptions and overrides belong to the configured super-administrator.
5. After deploying, the super-administrator opens **Approval exceptions** and checks how many appointments are `no_eligible_counselor`; a large number means assignments are incomplete.
6. Rollback: redeploy the previous versions of the six callables by name; no data migration is involved.

## Privacy note (added after independent review)
`appointments/{id}/history` is readable by the student, so history records only `approvalMode`. The college, the scope reason and any super-admin exception reason are written only to `admin_audit_logs`.
