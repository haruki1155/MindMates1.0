# Student appointment date and time changes

Status: proposed for approval.

## Purpose
Let a student change the date and time of their own upcoming counseling appointment. After an actual change, PACC must confirm the revised schedule, including when the previous appointment was already confirmed.

## Agreed approach
Update the existing appointment in place, keeping its identity and history. The alternative of cancelling and creating a replacement was considered but splits history and risks losing the original booking before a new request succeeds. The user chose the existing-record approach.

## Student experience
- Provide an Edit date and time action from the existing upcoming appointment details. Reuse the existing date picker and available-slot presentation where practical. Show the current schedule, available new times, and a clear explanation that the revised appointment will await confirmation.
- The proposed scope changes date and time only; preserve concern, contact information, identity and other appointment details. Saving an unchanged schedule leaves the status and booking unchanged.
- Show success only after the server confirms the change. On a conflict, network error or concurrent update, retain the form and explain what happened so the student can retry or select another time.
- After success, the existing appointment appears as Awaiting Confirmation throughout student-facing surfaces; PACC's queue reflects the new time and pending status. Do not show the previous approval as applying to the new schedule.

## Trusted update and integrity
- A callable verifies authenticated ownership and checks the current appointment state on the server. Proposed eligible states: requested and confirmed future appointments; terminal, archived, past and PACC-proposed schedule changes are rejected until their current workflows resolve. Legacy records require explicit compatibility checks rather than assuming their slot locks exist.
- Reuse current scheduling, availability, booking-policy, timezone and slot-ID validation. Never trust client status, owner, timestamps, time labels or slot IDs. Treat the same slot as a no-op.
- In one transaction, reread appointment, current and destination slot locks, current availability and booking policy; verify current state/version and slot ownership, acquire the available destination, release only a matching old lock, update date/time and status to `requested`, and append a history event. Preserve the user active-appointment lock. If an expected old lock is missing or belongs to another appointment, fail safely without touching either booking. Two competing changes or bookings must never acquire the same slot.
- Preserve historical data and prior approval details in history; clear or supersede active confirmation/proposal fields as appropriate so stale approval is not represented as current. Define stale-client handling and idempotent retries explicitly in the implementation plan; a failed or repeated request must not release the wrong slot.
- Update the existing portal queue and notification mechanism so PACC is alerted to the revised request without exposing the student's concern in the notification. Avoid duplicate notifications on retries. Verify current staff approval and reminder behavior against the revised status/time, including invalidating old reminder state if necessary.
- Keep direct Firestore client writes blocked. No production deployment, migration, live appointment edits, APK install or push is authorized by this design alone.

## Validation
Use focused Flutter and Functions/Rules tests: owner vs other user, requested/confirmed and invalid states, past and unchanged slots, validation and slot conflicts, concurrency and retry, old lock mismatch, simultaneous staff review, event/queue/notification correctness, reminder lifecycle, and no data loss on failure. Verify responsive selection and clear status/error feedback. Emulator evidence is separate from hosted acceptance.

## Proposed calls for review
Only date and time are editable in this iteration. Reserve the newly chosen slot while it awaits PACC confirmation and release the old slot atomically; otherwise the student could lose both choices or two students could claim one time. A no-op does not revoke an existing approval. A PACC-proposed change is not directly edited until its current workflow is resolved.
