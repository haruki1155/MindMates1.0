# Task: Staff Web Dashboard calendar and college-filtered appointments

Date: 2026-11-14 | Branch: feat/web-staff-calendar-college-filter-20261114 | Base: main after PR #40

1. Inspect existing portal routing, Staff screens, privacy-safe appointment queue and service/testing records. Preserve all merged work.
2. Add verified college ID to staff queue projection from authoritative user profile; preserve clinical data exclusions. Add server unit test.
3. Add `collegeId` to `AppointmentQueueItem` with empty-string compatibility for legacy queue docs.
4. Implement reusable calendar with month navigation, daily counseling counts, selected-day details and hover tooltips. Distinguish typed testing entries and explicitly label the absent testing source; do not fabricate booking data.
5. Replace Staff dashboard summary list with calendar and link to Appointments, keeping existing PACC availability metric for compatibility.
6. Upgrade Staff Appointments to a responsive scrollable DataTable with college filter using public college catalog; cache queue stream to prevent excessive refresh on every keystroke; preserve search, statuses and read-only access.
7. Add widget tests for calendar rendering, source gating, college selection and table privacy.
8. Run `flutter pub get`, targeted `flutter test`, `flutter analyze`, Functions `npm ci && npm run build` and `node --test lib/appointment_privacy.test.js`. Run existing affected Staff tests and Firebase rules privacy tests.
9. Preview with a staging Staff account and synthetic appointment records. No production writes, no schema change to private appointments.
10. Only after successful tests/code review and user approval create PR. Integrate actual testing schedules in a separately scoped follow-up after official PACC source is identified.

## Known limitations
- Verified testing bookings are not available in the current code/data. The UI is ready but not populated.
- Existing queue documents will show Unassigned college until the updated projection callable is deployed to staging and refreshed.
- Flutter and Firebase runtime tests require the user's WSL Flutter/Firebase environment; connector-side static review is not execution.

## Field testing fix — Staff/Counselor data visibility

- Reproduced screenshot symptom: Staff dashboard calendar rendered but had zero plotted records while Admin showed appointments.
- Data-flow cause: Admin and Counselor read the canonical `appointments` collection, while Staff can only read the server-generated `appointment_queue` projection. The original Staff reader blocked on `refreshPortalAppointmentQueue`; a staging callable error could blank the page, then an empty queue could look like zero bookings even if canonical appointments existed.
- Staff now subscribes immediately to `appointment_queue` without waiting for the callable; its original one-shot backfill is best effort. The user may manually choose **Refresh schedules**, which calls the existing privileged `refreshPortalAppointmentQueue` and displays a count or error code.
- Both Staff dashboard/calendar and Appointments table remain visible on queue errors; empty projection is explicitly labelled unavailable/potentially unsynced rather than proof that no appointments exist.
- Counselor org-wide appointment overview remains visible even if the separate assigned-case query fails; the clinical appointment query exposes a safe Firebase error category if denied.
- Added widget tests for Staff error/empty states, refresh button and Counselor partial-query failure; added Firestore emulator tests for collection-list permissions (Counselor full appointments, Staff only queue).
- **Deployment dependency**: actual staging data requires `syncPortalAppointmentQueue` and `refreshPortalAppointmentQueue` Functions to be deployed to the same Firebase project as the Web staging app; staging Firestore rules must permit portalStaff to list `appointment_queue`. A PR or frontend-only preview cannot populate missing server queue data.
- The app routes staging to project `mindmate-staging`. Verify the Admin and Staff sessions use this same project; inspect browser error codes and never bypass clinical access controls to simulate results.
- A verified `collegeId` also requires the latest Staff projection Function to be deployed. Do not copy student/clinical fields directly into client-facing documents.
- Testing Service schedules remain unconnected pending an official trusted PACC schedule source; avoid fabricated testing bookings.
- Regression and Flutter analysis still require an actual WSL run on the latest branch. Do **not** label this implementation PR-ready until rerun results are confirmed.
