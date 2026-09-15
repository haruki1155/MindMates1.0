# Appointment workflow audit and migration plan

## Existing architecture

- Flutter uses `AppointmentModel`, `AppointmentRepository`, and
  `AppointmentProvider` against the shared `appointments` collection.
- Admin and counselor decisions already use the `reviewAppointment` callable;
  both apps use `appointments/{id}/history` and `notifications`.
- FCM registration and a Function notification trigger already exist. Device
  tokens are stored at `user_devices/{uid}/tokens/{token}`.
- The mobile calendar/details screens and the PACC booking screen are the
  existing appointment UI; this work preserves them.

## Compatibility and schema

No collection was replaced. New records use `status: requested`; old
`pending`, `upcoming`, and `reschedule_required` records are read as
`requested` for display, without a destructive migration. New optional,
compatible fields are `proposedScheduledAt`, `proposedScheduledTime`,
`proposedBy`, `proposalStatus`, `cancelledBy`, `cancelledAt`, and
`cancellationReason`.

The authoritative time remains the existing `scheduledAt` Firestore Timestamp.
Proposal values do not replace it until accepted.

## Security and backend contract

Appointment document and history writes are now denied to clients. The
callables `createAppointmentRequest` and `respondToAppointment` handle student
requests/actions. `reviewAppointment` remains the Admin Portal entry point and
accepts canonical lifecycle values. Server transactions reserve a slot in the
private `appointment_slots` collection, append history, and create in-app
notifications. Firestore rules deny all access to slot records.

Deploy Firestore rules and Cloud Functions together; otherwise the mobile app
will be unable to create requests after rules are deployed. The Admin Portal
must use `reviewAppointment` rather than direct appointment writes.

## Incremental follow-up

1. Update Admin Portal labels/actions to `requested`, `declined`, and
   `reschedule_proposed`, retaining the callable name.
2. The `sendAppointmentReminders` scheduled Function now provides the 24-hour
   and one-hour policy, including de-duplication after reschedules.
3. Push and in-app notification taps now open appointment details when the
   affected appointment is already loaded; otherwise the calendar is opened
   after refresh. Validate terminated-app behavior on physical Android/iOS.
4. Add emulator tests for callable authorization, slot contention, reminders,
   and all
   lifecycle transitions before production deployment.
