# PACC appointment Phase 4 validation and release gate

## Code audit result

The audit document matches the broad architecture: appointment changes use
callables, direct appointment/history writes are denied, Firestore is the
state source, and notifications persist before FCM is attempted. Phase 4 found
and corrected two contract defects: the portal exposed retired
`reschedule_required`, and reschedule reservation keys were inconsistent.

## Automated checks completed

| Area | Result | Evidence |
|---|---|---|
| Flutter appointment provider | Pass | `flutter test test/providers/appointment_provider_test.dart` |
| Flutter appointment UI analysis | Pass | targeted `flutter analyze` |
| Cloud Functions type check | Pass | `npm run build` in `functions` |
| Direct appointment/history writes | Pass by rule review | `firestore.rules` denies client mutations |
| Notification ownership/read-only fields | Pass by rule review | owner-only `readAt` change |
| Legacy `pending` display | Pass by source review | `AppointmentStatus.parse` maps it to requested |

## Workflow matrix for physical-device / emulator sign-off

| Workflow | Expected assertion |
|---|---|
| Student request | one PACC slot and requested history event are created; portal sees it |
| Staff confirm | confirmed state, persistent notification, FCM, live mobile update |
| Staff reschedule | original schedule remains until acceptance |
| Student acceptance | transaction moves the single PACC slot, clears proposal, resets reminders |
| Student reschedule | original schedule remains and portal receives a review notification |
| Cancellation | record remains, slot is released, no future reminders |
| Reminders | each 24-hour/one-hour deterministic notification ID is emitted once |
| Token failure | invalid FCM token is removed; appointment state stays committed |
| Notification tap | foreground/background/terminated taps resolve the appointment after authentication |

## Release blockers

Physical Firebase Emulator and device checks are still required. They cannot be
truthfully executed without the project Firebase credentials, deployed
functions, APNs credentials, VAPID key, and two test accounts. Do not label
the feature production-ready until every row above is signed off.

## Deployment sequence

```powershell
cd 'C:\Users\Mj\Desktop\Coding Projects\mind_mates'
flutter test
Push-Location functions; npm run build; Pop-Location
firebase deploy --only functions
firebase deploy --only firestore:rules,firestore:indexes
flutter build appbundle --release --dart-define=FCM_VAPID_KEY=<web-vapid-key>
```

For iOS, configure APNs in Firebase, then build/archive with Xcode. Verify the
`sendAppointmentReminders` scheduler job after Functions deployment and test
Android/iOS background plus terminated notification taps on physical devices.
