# Inquiry Response Target, Oversight and Takeover — Design

**Date:** 2026-11-15 · **Requirement:** evaluator #3 (PR 5)
**Base:** stacked on `feat/pr4-college-inquiry-routing` (d4b92d5, PR #50, open). Requirement #3 needs PR 4's routing, assignees and audited inquiry actions. PR 5 targets the PR 4 branch so its diff shows only its own changes; it must merge after PR #50.

## Findings
- After PR 4, inquiries have assignees, an owner, escalation, audited status changes and super-admin reassignment, but **no way to reply**: staff can only send a fixed "Form received" receipt. "Unanswered" therefore cannot be measured, and an administrator cannot answer.
- No urgency/priority field exists on inquiries (the two forms are feedback and a satisfaction survey). Urgent safety cases follow the separate MindAid emergency workflow, not this timer.
- The student app's Notifications screen shows each notification's title and body, so a reply delivered in the student's own notification reaches them without a student-app change.
- `system_config/{doc}` is readable only for `security`.

## Goals
1. Authored replies from assignees or the super-administrator, delivered to the student and mirrored to the other assignees.
2. A super-admin-configured response target and an **Overdue** view: unresolved inquiries with no reply past the target, showing college, assignees, age and last action.
3. Super-admin **takeover** of an inquiry, visible to the assignees, with conflicting updates rejected by revision.
4. Every action audited; replies idempotent on retry; no duplicate replies.

## Policy (not hardcoded)
The response target is a **super-admin setting** (24, 48 or 72 hours, per the plan's PACC options) stored in `system_config/inquiry_sla` and changed only through an audited callable. Until it is set, the Overdue view says so and nothing is flagged. No automatic escalation, timers or scheduled jobs. No urgency exception is invented; urgent safety cases stay in the MindAid emergency workflow.

## Definitions
- `deadline = createdAt + targetHours`.
- **Overdue** when the inquiry is not resolved, has no reply (`firstResponseAt == null`), and `now >= deadline` (exactly at the deadline counts as overdue). The acknowledgement receipt is not a reply.
- The Overdue view is a projection of data the super-admin can already read; it grants no access.

## Data (server-written)
- `inquiries/{id}`: `firstResponseAt`, `lastResponseAt`, `lastResponseBy`, `lastResponseByName`, `lastResponseRole`, `responseCount`, `takeover` (`null` or `{by, byName, at, reason}`); `routingRevision` now also increments on reply, takeover and status change.
- `inquiries/{id}/replies/{requestId}`: `{message, authorId, authorName, authorRole, createdAt}`. Doc ID = client `requestId`, so a retried call finds the existing reply instead of creating a second.
- `system_config/inquiry_sla`: `{hours, updatedBy, updatedAt}`.

## Operations
| Callable | Who | Effect | Audit |
|---|---|---|---|
| `setInquirySla({hours})` | super-admin | 24/48/72 | `INQUIRY_SLA_UPDATED` (new) |
| `replyToInquiry({inquiryId, message, expectedRevision, requestId})` | assignee (not after takeover) or super-admin | reply doc; response fields; `pending → in_progress`; owner claimed if none; student notification carries the reply; other assignees get a content-free "reply posted" notification | `INQUIRY_RESPONDED` |
| `takeOverInquiry({inquiryId, expectedRevision, reason})` | super-admin | `takeover`, owner = admin, open escalation handled, assignees notified (content-free) | `INQUIRY_TAKEN_OVER` (new) |
| `setInquiryStatus` (PR 4) | + optional `expectedRevision`; assignees refused after takeover | | existing |
| `reassignInquiry` (PR 4) | clears `takeover` (hands the inquiry back) | | existing |

Errors: stale revision or resolved inquiry → `failed-precondition`; assignee after takeover → `permission-denied`; message 1–2000 chars, reason 3–500 → `invalid-argument`.

## Rules
- `inquiries/{id}/replies/{replyId}`: read by the student owner, the inquiry's assignees (same lifecycle gates as the parent) and the super-admin; no client writes.
- `system_config/inquiry_sla`: readable by portal accounts; no client writes.

## Web
Super-admin: response-target selector and an **Overdue** panel on the Inquiries page (college, assignees, age, last action). Inquiry detail: reply timeline, reply composer (assignees until takeover, and the super-admin), **Take over** (super-admin, unresolved, not yet taken over), takeover shown in the routing panel. Status changes pass the current revision.

## Testing
Pure Dart overdue projection with a simulated clock (before / exactly at / after the deadline, replied, resolved, no target); emulator tests for each callable (authorization, takeover blocking late assignee replies, revision conflicts between staff and admin, reply retry idempotency, notifications, audit); rules tests for replies and the SLA document; widget tests for the overdue panel, reply composer and takeover.

## Calls for review
1. Stacked on PR #50 rather than main.
2. Response target choices 24/48/72 h, unset by default.
3. Overdue measured from creation to the first authored reply; acknowledgement does not count.
4. Takeover blocks assignee replies and status changes until the super-admin reassigns.
5. The student receives the reply text in their own notification.
