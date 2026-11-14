# Staff dashboard calendar and Appointments college filter

Date: 2026-11-14 | Base: merged main after PR #40

## User requirements
1. Staff Web Dashboard: calendar rather than summary cards; number of appointments plotted per date; hover reveals schedule time and assigned counselor; distinguish counseling vs testing.
2. Staff Web Appointments: operational detail table, filterable by college.

## Existing architecture and constraints
- `AdminPortalPage.dashboard` and `AdminPortalPage.appointments` already route portalStaff to staff-only screens. This change does not alter access roles.
- Staff appointments are projected by the privileged server into `appointment_queue`; portalStaff cannot read the full `appointments` collection or clinical note subdocuments.
- The backend currently contains an official **counseling** appointment stream. Testing Service schedules are given through external PACC/SMS procedures and **no verified testing schedule collection** exists. We must not fabricate testing records or mislabel counseling requests as testing appointments.

## Design
- Dashboard uses a six-week monthly calendar with previous/next/current-month controls, date selection, counseling day counts, and Tooltip on hover/long-press with time and assigned counselor.
- Only confirmed/completed non-archived appointments are plotted; pending requests and cancelled/archived sessions are not represented as confirmed bookings.
- An explicit `Testing schedules not yet connected` notice is shown until a verified PACC testing schedule provider is available. Widget accepts a separate list of typed testing entries **only** when the integration explicitly marks the source connected. This prepares the visual presentation without inventing live bookings.
- The Staff Appointments page is a horizontally scrollable, accessible `DataTable`: Student, College, Service (currently Counseling), Date & time, Assigned counselor, and Status. Existing search and status chips are retained, plus an All colleges / named college / Unassigned dropdown.
- Server adds only `collegeId` to the staff-safe `appointment_queue` projection. `collegeId` comes from the student's authoritative `users/{userId}` profile inside the existing appointment projection transaction, never from an arbitrary client-submitted appointment field. Existing users with unknown college are **Unassigned**, not guessed.
- Display college names from public `colleges` catalog while filtering by stable `collegeId`, not free-text department/course. Restrict all appointment content to safe existing queue projection fields.
- Keep original counselor/admin appointment pages, session evidence, mobile services, notifications, Firebase rules, and PR #40 changes intact.

## Validation
- Flutter unit/widget tests: month navigation, confirmed count, hover details, test-type rendering from trusted inputs, absence of fabricated testing data, DataTable and college filtering; existing staff schedule metric test.
- Backend: `appointment_privacy.test.ts`, Firestore privacy rules, TypeScript build and appointment projection regression tests.
- Review branch diff and only open a PR after local tests and real staging Staff account preview.
- Staging Functions deployment is required for real college IDs to be populated in `appointment_queue`; old records are automatically refreshed by existing `refreshPortalAppointmentQueue` callable when the updated Function is deployed.
- Do not deploy Functions/rules to production without explicit approval.

## Outstanding integration dependency
Real Testing Service calendar entries cannot appear until PACC provides a trusted schedule data source/official record workflow and Staff-authorized safe projection. The calendar is **not** evidence of confirmed testing reservations at this stage.
