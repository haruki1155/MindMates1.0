# Appointment Workflow Improvement Design

## Goal

Make the admin appointment workflow predictable from request through completion, with date-driven Today and Upcoming queues, durable Completed counts, linked follow-up appointments, clear action states, and user reminders.

## Scope

This change covers the Flutter admin web portal, the shared appointment model/repository, callable Cloud Functions, Firestore rules/indexes, and appointment-related tests. It preserves the existing `appointments`, `appointments/{id}/history`, `notifications`, and `appointment_slots` collections.

## Canonical lifecycle

The persisted lifecycle values are:

- `requested`: a new appointment waiting for staff action.
- `confirmed`: staff accepted the schedule; queue placement is derived from `scheduledAt`.
- `reschedule_proposed`: a schedule change is awaiting acceptance/action.
- `completed`: staff recorded that the session occurred.
- `not_attended`: staff recorded that the user did not attend.
- `declined`: staff declined the request.

`cancelled` is no longer a supported admin decision or user-facing appointment action for this feature. Existing historical records remain readable for compatibility, but new transitions must not create it.

Archiving is a separate storage flag. It never changes lifecycle status and never removes a record from historical metrics.

## Queue semantics

Queue membership is derived from canonical status, archive state, current local date, and the authoritative `scheduledAt` timestamp:

| Queue | Rule | Available actions |
|---|---|---|
| Needs Action | `requested`, legacy requested values, or `reschedule_proposed` | Review, confirm, request new schedule |
| Upcoming | `confirmed` and scheduled date is after today | View only; no completion/no-attendance action |
| Today | `confirmed` and scheduled date equals today | Record completed, record missed appointment |
| Completed | `completed` or `not_attended` | View, create follow-up |
| Archived | `archivedAt != null`, displayed separately | View only; no restore |

An appointment confirmed for a date three days in the future remains in Upcoming until that calendar date. It then appears in Today, where outcome actions become available. Upcoming is grouped and sorted by confirmed `scheduledAt` date and time.

## Follow-up behavior

Follow-up is available for completed and not-attended appointments. It creates a new `requested` appointment with `parentAppointmentId` pointing to the source appointment, `appointmentType: follow_up`, and `createdFrom: staff_follow_up`. The source record is not mutated. A transaction creates the new appointment, history event, audit event, and user notification together. The new request appears in Needs Action.

## Backend contract

`reviewAppointment` remains the staff entry point. Supported new actions are `confirmed`, `reschedule_proposed`, `completed`, `not_attended`, and `declined`. The callable rejects unsupported `cancelled` and restore actions.

The backend validates lifecycle transitions server-side. Completed and not-attended are only valid from `confirmed`, and only when the appointment is due or an explicitly authorized administrator override is supplied. Follow-up uses a dedicated `createFollowUpAppointment` callable and is idempotent for the source appointment unless a deliberate repeat is requested.

The existing reminder scheduler remains server-owned. It sends one 24-hour and one-hour reminder for confirmed appointments, de-duplicates by appointment/stage, resets reminders after an accepted reschedule, and stops for terminal outcomes.

## Admin UI

The appointment page hierarchy is:

1. Page title and workflow explanation.
2. Summary cards for Needs Action, Today, Upcoming, and Completed.
3. Search and Department filters.
4. Queue tabs.
5. Date-grouped appointment list.
6. Contextual actions based on queue and lifecycle.

The Today card selects the Today queue directly. Department is the only category-like filter shown near search; no generic popup-style Clear Filter control is shown. A selected Department can be cleared inline in the field.

Every async decision shows a per-appointment loading state, disables duplicate submission, leaves unrelated rows interactive, and reports success/failure without closing the dialog prematurely.

Archived records can be viewed in a separate history mode, but no Restore button, restore callable, or restore menu item is exposed.

## Data integrity and compatibility

No destructive migration is required. Existing `pending`, `upcoming`, and `reschedule_required` values are normalized to requested for display. Existing cancelled/no-show records remain readable. New follow-up fields are optional and backward-compatible.

Completed counts are calculated across all records, including archived records, and are not based solely on the currently visible active queue.

## Validation

Tests must cover queue classification, date boundaries, transitions, follow-up transaction behavior, stable archived counts, reminder de-duplication, removal of restore/cancel actions, and UI loading/action visibility. Flutter targeted tests, `flutter analyze`, Functions tests/build, and relevant Firestore rule/index checks are required before implementation is declared complete.
