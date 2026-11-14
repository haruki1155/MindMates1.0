# Appointment V2 Mockup Fidelity and Picker Integration Implementation Plan

> For agentic workers: use superpowers:executing-plans, test-driven-development, systematic-debugging, verification-before-completion and one final independent code review. Continue in the existing dirty checkout; do not recreate completed work.

**Goal:** Match the user's nine-screen mockup in the real Flutter student appointment flow, integrate the appointment pickers from feat/appointment-time-50-51, and preserve all trusted appointment behavior.
**Architecture:** Keep current Provider/repository/callable contracts. Selectively adapt the branch's contact-time helper and picker widgets into the already split intake and editable review. Apply feature-local styling to existing routes and callbacks. No new UI framework or state-management layer.
**Stack:** Flutter/Material, Provider, existing Firebase services and widget tests.
**Authority:** User's supplied nine-screen image and approved November 12 plan. This plan supersedes the earlier mistaken assumption that the current checkout included the branch picker changes. Mockup is a visual reference; sample data, extra choice values, and navigation labels never override current contracts.

## Verified starting point and safety
- Local HEAD: 0d0b7c993ad25066624a134733c2038336d0d84a, branch fix/mood-v2-primary-experience, with substantial uncommitted Gate 1/2 and V2 work.
- Fetched picker branch: origin/feat/appointment-time-50-51 at 3149ac3d8687035d65409599d755d4b0194e1983. Appointment commits: 1ca9cce, b5f8b08, a3d9f4e, 3149ac3. The branch includes unrelated work: do not merge/cherry-pick its entire history or replace the full screen.
- Preserve two intake stages, editable review, restored schedule after cancelled edits, no-op confirmation retention, owner/revision checks, stale request sequence, account-switch guards, required fields, follow-up links and request IDs.
- Prior local evidence: 89 focused tests passing; targeted calendar/notification analysis clean. Historical evidence must be distinguished from fresh acceptance.
- Physical staging app was launched, but user reports mockup mismatch and missing picker behavior. That report means visual acceptance is NOT met.
- No changes to AppointmentProvider, AppointmentRepository, models, Functions, Firestore rules/schema, dependencies, permission policy or availability. No commit/push/reset/merge, hosted writes/deployment, or unrelated formatting. Preserve pubspec.lock and other agent work. Device build/relaunch only at the manual acceptance checkpoint authorized by the user.

## Fixed design decisions
- Recommend and use selective integration plus feature-local restyling. Whole-branch merge would import unrelated work; cosmetic-only changes would omit the approved pickers and screen composition.
- Reproduce calm neutral background #F7F7F3, dark ink #172C35, white bordered cards, yellow #F3BE42 primary actions, teal overview hero, muted secondary copy, compact headers, four-step progress and bottom action areas as shown.
- Keep real app navigation destinations and current required fields even where the mockup abbreviates them. Never add unsupported therapy/sex options, synthetic timeline events, fixed demo availability, invented privacy guarantees, or unsupported notification links.
- Contact availability is a day preference and start/end range, distinct from the appointment date/hour. Appointment hour chips contain ONLY provider-returned slots. A native arbitrary appointment-time picker must not bypass hourly availability policy.

## Task 1 — Snapshot and selective picker integration
Files: lib/features/counseling/domain/best_contact_time.dart (from branch); pacc_counseling_screen.dart; test/features/counseling/best_contact_time_test.dart, pacc_best_time_test.dart, pacc_time_chips_test.dart (adapt branch tests); existing services/protection tests.
- [ ] Save scoped pre-edit diffs and ledger checkpoint; record source branch SHA and inspect those four appointment commits only.
- [ ] Add adapted failing tests for range format/parse, invalid end-before-start, cancellation, state after rebuild/back, legacy text preservation until explicit edit, and actual provider-only compact hour chips. Run RED against local screen, not branch source.
- [ ] Adapt BestContactTime helper and From/To native time picker with Weekdays/Weekends/Any day choices into Counseling Details. Preserve canonical existing bestTime string and untouched legacy strings. Update both stage and review-submission validators to validate the chosen range. Review shows the same value ultimately submitted.
- [ ] Replace large slot cards with compact selectable hour chips with >=48px tap targets; retain current async sequence, errors, selected values and backend policy.
- [ ] Update existing tests that fill the old free-text contact-time field. Run picker + services + provider/repository regressions; record exit codes.
Expected: both picker behaviors work in current V2 stages, no contract/schema change, legacy follow-up data preserved.

## Task 2 — Overview and details match reference
Files: appointment_list_view.dart; appointment_details_sheet.dart; relevant appointment widgets/tests.
- [ ] Add failing behavioral/layout tests for single details action, status hierarchy, no concern on cards, editor eligibility, calendar/follow-up reachability, narrow viewport and large text.
- [ ] Match reference overview header, teal hero, segmented status tabs, schedule count, empty white card and yellow request CTA. Preserve active booking guard and existing tab membership.
- [ ] Match details status-first white session card, PHT date/time/location/counselor rows and genuine activity data. Keep prominent eligible Edit date and time; no fabricated history. Style the existing modal/editor without replacing authorization/revision/request handling.
- [ ] Capture and inspect rendered overview/details states against image; test requested/confirmed/proposed/terminal, ownership and account-switch cases.
Expected: visual hierarchy resembles reference; existing actions remain reachable and correctly restricted.

## Task 3 — Booking shell and intake visual fidelity
Files: pacc_counseling_screen.dart; small feature-local presentation widgets only if reused; services/protection tests.
- [ ] Write failing tests for four-step progression, bottom CTA access with keyboard, back/continue draft retention, focus order and required field validation.
- [ ] Implement compact stage header: About you / Tell us about you / Choose a time / Review request, four-step thin progress and subtitle. Keep selected calendar and slots in current booking flow.
- [ ] Apply readable field labels, white rounded inputs, first/last name layout that preserves middle initial and all existing required fields, current keyboards, focus traversal and smaller logical groups.
- [ ] Put primary actions in SafeArea bottom regions, with sufficient scroll/keyboard insets; preserve system back and reduced-motion preference. Do not hide required validation errors off-screen.
- [ ] Inspect rendered personal and counseling stages at normal and large text, with keyboard shown. Verify no field or payload loss after review edits.
Expected: matches reference structure rather than merely changing words/colors; controllers and required values remain intact.

## Task 4 — Schedule, review and result visual fidelity
Files: pacc_counseling_screen.dart; existing booking tests.
- [ ] Add failing tests for loading/retry/closed/no-slot states, Edit Schedule cancellation, review edits, duplicate submission and selected-slot retention.
- [ ] Style existing combined calendar and branch compact hour chips like reference; PHT, selected state, month controls and actual slots remain clear. Show a real retry action for failures using existing provider behavior.
- [ ] Review renders three white sections (Schedule, Your information, Counseling details), contextual accessible Edit actions, bottom Send appointment request CTA; preserve exact Review request heading and payload.
- [ ] Result matches restrained success indicator, requested schedule summary, Request received and Awaiting confirmation, location, next-step explanation, and return-to-appointments action. It must never imply staff approval.
- [ ] Inspect all three rendered states against reference and rerun booking/edit/conflict regressions.
Expected: accurate copy, working submission/edits and reference-aligned layout.

## Task 5 — Calendar and notifications finish
Files: home_appointment_calendar_screen.dart; notifications_screen.dart; corresponding tests.
- [ ] Preserve already applied styling, date-cell wrap fix, agenda semantics, notification unread/mark-read and supported destinations. Only adjust remaining differences needed for reference fidelity.
- [ ] Match compact headers, quiet calendar/agenda cards and notification rows. Keep standalone calendar read-only unless existing approved behavior supports selection; the image alone does not authorize new interaction contracts.
- [ ] Verify notification title/body accessibility, no private concern previews, PHT and friendly lifecycle labels; preserve all IDs and permission paths.
Expected: consistent surfaces without recreating backend or introducing links/events.

## Task 6 — Fresh verification, visual acceptance and independent review
- [ ] Run flutter.bat test --no-pub --dart-define=APP_ENV=staging test/features/counseling test/providers/appointment_provider_test.dart test/repositories/appointment_repository_test.dart test/features/home/home_appointment_calendar_test.dart test/features/notifications/notifications_screen_presentation_test.dart test/models/app_notification_model_test.dart.
- [ ] Run dart.bat analyze --fatal-infos on changed source/tests; git diff --check. Log actual exits and counts. Broaden testing only for a specific failure/risk.
- [ ] Capture all nine screen states using disposable/local fixtures and existing test screenshot tools; if none exist, add a small test-only capture harness. Save images outside production assets. Compare each directly with reference; list justified differences. Passing widget tests alone cannot establish visual fidelity.
- [ ] Check 320px and actual TECNO viewport, text scales 1/1.4/1.6, keyboard, 48px interactive targets, semantic labels/order, screen-reader focus, reduced motion and supported dark-mode behavior. Record automated vs physical checks separately.
- [ ] Obtain one independent review of complete scoped diff for picker integration, data preservation, active guards, lifecycle, privacy, navigation, layout and mockup match. Fix important findings with RED/GREEN tests and rerun affected suite.
- [ ] Rebuild/relaunch the staging client only after local checks pass and confirm correct branch/picker source in build evidence. Use test account; do not claim end-to-end backend acceptance without separately verifying the staging backend revision and explicit authorization for needed hosted operations. Surface missing deployed callable/trigger as an environment gap, not a UI success.
- [ ] Record exact files, screenshot evidence, suite exits, review findings and user manual results in existing ledger. Keep work uncommitted. Mark overall V2 complete only when every applicable functional and visual criterion passes; explicitly label physical/hosted gaps.

## Acceptance matrix to fill during execution
| Criterion | Required evidence |
|---|---|
| Branch contact-time picker integrated | day/range, cancel/rebuild, validation and legacy regression tests |
| Actual hourly slots compact/selectable | provider fixture and chip selection/submission tests |
| All nine screens visually aligned | screenshots + direct reference comparison per screen |
| Intake and review preserved | back/edit/draft/payload, required/autofill and idempotency tests |
| Requested/confirmed editing safe | owner/revision/no-op/conflict/account-switch regressions |
| Calendar and notifications safe | agenda, unread, destinations, privacy and layout regressions |
| Accessibility | narrow/large-text/keyboard/semantics/targets evidence + physical gaps |
| Backend unchanged | scoped diff confirms no trusted-layer/schema/dependency changes |
| Independent review accepted | no unresolved critical/important findings |
| Manual acceptance | correct device build + user observations; hosted boundary explicit |

## Execution ledger
Continue recording in .superpowers/sdd/MindMate_Appointment_Implementation_Plan/progress.md with a section linking this plan; retain earlier milestone history. Do not mark the original design-stage prototype or previous passing tests as visual acceptance of the current app.
