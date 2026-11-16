# College-Based Inquiry Routing — Design

**Date:** 2026-11-15 · **Requirement:** evaluator #2 (PR 4) · **Base:** `origin/main` 0560e13 (PR #3 merged as #49; PR #48 excluded)

## Findings (Phase 1)
- **PR #3** is merged: `users/{uid}.assignedCollegeIds` (+ `collegeAssignmentRevision`) written only by `setStaffCollegeAssignments`. That callable is **not deployed to staging** (`firebase functions:list`), so staging has no assignments yet.
- **Inquiries** (`inquiries/{id}`) are created directly by the student app (rules allow-list: userId, subject, message, category, email, name, role, formType, formData, status, createdAt). Today only two forms create them: `client_feedback` and `guidance_satisfaction_survey`.
- **Verified college:** students receive `users/{uid}.collegeId` server-side at registration (`resolveRegisteredCollege`, never client-supplied) with `verificationStatus: "verified"`. Employees have no college.
- **Security/privacy gaps on main:**
  1. Rules `read: isOwner || hasPortalAccess()` — every approved staff/counselor/admin can read **every** inquiry, including `formData`.
  2. Trigger `notifyPortalOfInquiry` fans out a notification to **all** staff, counselors and admins.
  3. `acknowledgeInquiry` accepts any portal account for any inquiry.
  4. Counselor narrowing (`scopeInquiriesForRole`) is **client-side only**.
  5. Status changes are client writes (rules allow `status`/`updatedAt`) with **no audit**.
  6. `portalStaff` can read inquiries through rules but has no Inquiries page.
- Notifications are per-recipient (`notifications/{id}`, owner read) with generic text; resolution archives them (`resolvePortalInquiryNotifications`).
- Referral content (PR #47) is static service descriptions; no referral records exist to integrate.

## Goals
1. Route each new inquiry, server-side, to the eligible staff/counselors assigned to the student's verified college.
2. Only those assignees and the configured super-administrator can read or act on it; enforced by rules and callables.
3. Explicit, visible triage for inquiries that cannot be routed.
4. Acknowledge, reassign, resolve and escalate through audited server operations.
5. Idempotent, content-free notifications to the right people only.
6. Existing inquiries handled safely (hidden from non-admins until routed; admin-run backfill).

## Non-goals / policy left to PACC (not hardcoded)
Named escalation recipient ("Mam Monette"), automatic escalation timing/SLA, primary/backup counselor selection. Escalation goes to the **configured super-administrator** (the existing `SUPER_ADMIN_UID`), the only privileged identity the system already defines; replacing it with a named role is a later configuration change. No timers.

## Anti-goals
Client-side-only filtering; any staff seeing another college's inquiry; notifications containing inquiry content; changing a user's home college; touching appointment approval.

## Approaches
| | Approach | Trade-offs |
|---|---|---|
| **A (chosen)** | Keep the student's direct create; the existing `notifyPortalOfInquiry` onCreate trigger becomes the **router** (idempotent transaction). Rules hide unrouted inquiries from everyone but the owner and super-admin. | Backward compatible with installed student apps; brief window before routing is safe because nothing is visible to staff until routed. |
| B | New submission callable that routes atomically; block direct creates | Atomic, but breaks installed mobile clients until they update. |
| C | Client filters by college | Not security. Rejected. |

## Data (server-written only; the create allow-list already excludes them)
On `inquiries/{id}`: `collegeId` (snapshot of the student's verified college, `""` if none), `routingStatus` (`routed` \| `needs_triage`), `routingReason` (`null` \| `missing_college` \| `unverified_profile` \| `unknown_college` \| `no_eligible_staff`), `assigneeIds: string[]`, `assigneeLabels: {uid: displayName}`, `ownerId` (who acknowledged/claimed; `null` until then), `routingMode` (`automatic` \| `manual`), `routedAt`, `routingRevision`, `escalation` (`null` or `{status: "requested"|"handled", reason, requestedBy, requestedAt, handledBy?, handledAt?}`).

## Routing rules
- Student profile must exist, `verificationStatus == "verified"`, have a well-formed `collegeId` that exists in `colleges`; otherwise `needs_triage` with the matching reason.
- Eligible = users with `assignedCollegeIds` array-contains the college, `accessRole` ∈ {portalStaff, counselor}, `staffAccountStatus` absent/approved, `accountStatus` absent/active, Firebase Auth enabled and email-verified (same gates as `requireStaff`).
- **Multiple eligible:** all become assignees (a shared college queue); the first to acknowledge becomes `ownerId`. No primary is chosen (policy).
- **None eligible:** `needs_triage / no_eligible_staff`.
- Idempotent: a transaction writes routing only if `routingStatus` is absent; retries only (re)send missing notifications.

## Operations (all super-admin gates use `requireSuperAdmin`; staff gates use `requireStaff` + assignee membership)
| Callable | Who | Effect | Audit |
|---|---|---|---|
| trigger `notifyPortalOfInquiry` | system | route + notify | `INQUIRY_ROUTED` |
| `acknowledgeInquiry` (tightened) | assignee or super-admin | `in_progress`, `acknowledgedAt`, claims `ownerId`, student receipt | `INQUIRY_ACKNOWLEDGED` |
| `setInquiryStatus({inquiryId, status})` (new; replaces client writes) | assignee or super-admin | pending/in_progress/resolved | `INQUIRY_STATUS_CHANGED` / `INQUIRY_RESOLVED` |
| `escalateInquiry({inquiryId, reason})` | assignee | `escalation.requested`, notify super-admin | `INQUIRY_ESCALATED` |
| `reassignInquiry({inquiryId, assigneeIds, expectedRevision, reason})` | super-admin | replaces assignees (eligible accounts only, 1–10; out-of-college allowed and recorded), `routed/manual`, escalation → handled, removed assignees' notifications archived, new assignees notified | `INQUIRY_REASSIGNED` |
| `routeExistingInquiries({limit})` | super-admin | routes inquiries with no `routingStatus` (≤ 100 per call); notifies only unresolved ones | `INQUIRY_ROUTED` per inquiry |

Errors: stale revision → `failed-precondition`; not an assignee → `permission-denied`; ineligible assignee → `failed-precondition`.

## Rules
```
read:   owner || isSystemAdmin() || (staff/counselor with hasPortalAccess() && uid in assigneeIds)
update: false   // all transitions via callables
create: unchanged allow-list (routing fields cannot be client-set)
```
Staff/counselor list queries must filter `assigneeIds array-contains uid`.

## Notifications
Deterministic IDs, created with `create()` and ALREADY_EXISTS treated as success: `portal_inquiry_<inquiryId>_<uid>` (assignees), `portal_inquiry_triage_<inquiryId>` (super-admin), `portal_inquiry_escalation_<inquiryId>_<rev>` (super-admin). Bodies are generic ("A new inquiry for your college is ready for review."); no subject, message or form data.

## Web
- Inquiries nav for portalStaff, counselor, admin.
- Repository: super-admin streams all; staff/counselors stream `array-contains uid`. `scopeInquiriesForRole` becomes a defensive assignee filter (it no longer exposes an "unassigned pool").
- List row badge: `Routed · <college>` / `Needs triage` / `Escalated`; detail **Routing** panel: college, assignees, owner, mode, escalation; actions: **Escalate** (assignee), **Reassign** and **Route existing inquiries** (super-admin).
- Status menu calls `setInquiryStatus`.

## Testing
Pure routing/eligibility/reassignment unit tests; emulator tests for the trigger handler (routing, triage reasons, inactive/unverified staff excluded, multiple recipients, idempotent retry, notification dedupe), each callable (authorization, cross-college isolation, stale revision, audit completeness); rules tests (cross-college read isolation, no client updates, list query shape); Flutter model/repository/widget tests.

## Calls for review
1. Shared college queue + claim-on-acknowledge instead of picking a primary.
2. Escalation target = configured super-administrator until PACC names a role.
3. Status changes move server-side (rules `update: false`).
4. Org-wide inquiry read limited to the super-administrator (not every `admin` role).
5. Unrouted legacy inquiries stay admin-only until `routeExistingInquiries` is run.
