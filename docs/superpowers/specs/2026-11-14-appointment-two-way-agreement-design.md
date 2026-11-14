# Appointment two-way agreement and voluntary cancellation

Status: approved by the user for local implementation on November14,2026. Implementation and focused local validation completed; not deployed. See the implementation plan for verification and release limitations.

## Agreed requirements

- Appointment-details editing is already implemented; do not redesign that feature.
- Students may suggest another available time for an approved future appointment.
- PACC may suggest another available time when the requested or approved time is unsuitable.
- A changed schedule requires agreement from the other side before it becomes confirmed.
- The current appointment time remains reserved while a change is awaiting agreement.
- Students may cancel requested or approved future appointments. The reason is optional, and cancellation takes effect after the student confirms the cancellation dialog, without requiring PACC approval.
- Preserve the existing appointment UI, saved intake, privacy, authorization, availability policy, active-appointment guard, revision/conflict handling, and history.

## Approach

Recommended: extend the existing appointment and its trusted server operations with a pending schedule proposal. Retain one appointment ID, its current reserved schedule, and one current proposal. Reuse existing provider/repository, availability, notification and history infrastructure.

Alternatives considered: creating another appointment for each suggestion would duplicate active bookings/history; replacing the reserved schedule immediately would violate the user's reservation requirement. Neither is suitable.

## Scheduling behavior

1. An initial student request already expresses the student's agreement to its selected time. PACC confirming that exact request completes the agreement; no redundant second student confirmation is needed.
2. Either side may propose a genuinely available alternative for a future active appointment. A proposal does not replace the current schedule or release its reservation.
3. Only the other side may accept the current proposal. Students cannot approve their own proposals; staff cannot accept their own proposals on the student's behalf.
4. A student receiving a PACC proposal sees Accept proposed time and Suggest another time. PACC reviewing a student proposal can accept or suggest another time. A counterproposal supersedes the previous proposal and requires agreement from its recipient.
5. Acceptance atomically rechecks ownership/role, current appointment/proposal identity and revision, future eligibility, PACC availability, booking policy and target-slot occupancy. It claims the replacement and releases the old reservation in the same transaction. If the target is no longer available, the current appointment and reservation remain intact and the user can suggest another time.
6. Proposed replacement slots are not additionally reserved while awaiting acceptance. This avoids one appointment holding two times. Their availability is checked when proposed and again on acceptance; the UI explains that a proposal is not a guaranteed reservation.
7. Saving an unchanged schedule preserves its existing approval. Repeated requests are idempotent; outdated acceptance links, simultaneous counterproposals and cancellation/acceptance races cannot overwrite newer decisions.
8. Show who needs to respond, the current reserved time, and the proposed time separately. For a student proposal, show Awaiting PACC confirmation; for a PACC proposal, show Your confirmation needed. Do not present the proposed time as the confirmed appointment.
9. Existing legacy proposal records must remain readable; no automatic acceptance or bulk migration. The old/current schedule's reminder behavior must remain truthful, and no confirmation/reminder may announce an unaccepted proposed time.
10. While a proposal is pending, block a separate confirmation of the old time: the recipient must accept the current proposal or explicitly supersede it. PACC accepting a student proposal confirms that replacement, including when the original appointment was still requested.
11. A proposal must not extend the current appointment's existing expiry or reservation lifecycle. Once the current appointment becomes past, terminal or archived, pending acceptance is invalid. Existing expiry/terminal processing must invalidate the proposal and release locks according to the appointment policy; no orphaned proposal or additional reservation may survive it.

## Cancellation behavior

- Show Cancel appointment for the student's own requested or confirmed future appointment, including an appointment with a pending schedule proposal.
- Explain the effect in a confirmation dialog. Provide an optional reason field; blank input is valid.
- On confirmation, a trusted server transaction verifies owner, eligible state and current revision, marks the appointment cancelled, invalidates any proposal, releases its current reservation and active-booking lock, and records history and the PACC notification.
- Never delete the appointment or counseling history. Preserve existing privacy and history/archive behavior. Cancellation must not be offered for completed, already cancelled, expired, declined, archived or past appointments.
- Cancel and dismiss dialog changes nothing. A failed cancellation retains the appointment and entered optional reason; retry must not create duplicate history or notifications.

## UI and implementation boundaries

- Student app: extend current appointment details, schedule editor/review, status indicators and notifications. Keep current visual design and native time controls.
- PACC portal: show current/proposed schedules and recipient-specific actions with clear success/conflict recovery.
- Backend/Rules: server-authorized proposals, counterproposals, acceptance and cancellation; atomic slot/lock management; idempotent history and privacy-safe notifications. Clients must not directly write lifecycle or reservation fields.
- Tests first for every new behavior. Cover both proposal directions, original reservation retention, no-op approval, optional reason, cancellation across eligible states, slot conflicts, stale actions, duplicate retries, races, role/owner restrictions, notifications/queue/reminders, navigation and accessible layouts.
- Confirmed appointments retain reminders for their currently agreed time while a proposal is pending; requested appointments retain their existing reminder policy. Acceptance/cancellation invalidates obsolete queued reminders, with authoritative state/revision checks at dispatch.
- Legacy appointments display their actual current reservation; never claim that an earlier released slot is still held or silently recreate it. Resolve compatibility through explicit, server-validated actions.
- Persist history and notification intent transactionally; deliver external notifications afterward with existing retry/deduplication safeguards. Omit optional cancellation reasons and counseling content from push/email previews.
- Availability/conflict validation distinguishes this appointment's own current reservation from another appointment's reservation; no-op selections do not conflict with themselves.
- Validate student and staff vertical slices locally using the focused Flutter suites, Functions build and demo-project emulator tests. Hosted deployment, production data changes, and merge remain separate actions.

## Approval scope and remaining acceptance

User approved this design and implementation: reserve the current slot, optional cancellation reasons, no second reservation, initial exact-time PACC approval completes agreement, and counterproposals supersede older proposals.

Implementation branch is feat/appointment-two-way-agreement, based on the prior UI progress published in PR #32. That prior PR has conflicts with newer main. This implementation remains uncommitted and preserves unrelated pubspec.lock/tool settings. No merge, push, deployment, or production changes were performed.

Builder check: no fundamental contradiction found. Recorded explicit handling for old-time confirmation while a proposal is pending and proposal invalidation at the current appointment's expiry/terminal boundary. These are proposed implementation safeguards, not new user requirements.
