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
