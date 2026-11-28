# MindMate Settings, Privacy, Reminders, and Help Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the personal app's blank Profile destinations with working Reminders, Privacy, Help, and About screens for Student, Teaching, and Non-Teaching users. Make appointment and optional daily Mood/Breathing reminders persist and deliver through the existing Firestore notification feed and FCM path.

**Architecture:** Keep Profile as the entry point. Store preferences in `reminder_preferences/{uid}`, use the existing Provider/Firestore patterns, and enforce owner-only access in Firestore Rules. Extend the existing ten-minute `Asia/Manila` scheduled Function for daily self-care reminders and existing appointment reminder switches. Reuse the current notification inbox, FCM service, Home routes, MindAid/Sleep consent screens, Terms dialog, `url_launcher`, and `permission_handler`.

**Tech Stack:** Flutter/Dart, Provider, Cloud Firestore, Firebase Functions (TypeScript), Firestore Rules Unit Testing, Firebase Messaging, existing `url_launcher` and `permission_handler` dependencies. No new dependency or Admin Portal changes.

**Spec:** `docs/superpowers/specs/2026-11-28-mindmate-settings-reminders-help-design.md`

## Global Constraints

- Build for personal app users in all three roles: Student, Teaching, and Non-Teaching. The Admin web app is out of scope.
- Keep Profile as the settings hub. Build four screens: Reminders, Privacy Settings, Help, and About MindMate. Rename the Profile action to "Mood reminders" and open the Mood section of Reminders. Route the Profile notification bell to the existing Notifications screen.
- Save preferences only in `reminder_preferences/{uid}`. Do not add settings to `users/{uid}` or let clients write `notifications`.
- Preference fields are `appointment24HourEnabled`, `appointment1HourEnabled`, `moodDailyEnabled`, `moodDailyTime`, `moodDailyUpdatedAt`, `breathingDailyEnabled`, `breathingDailyTime`, `breathingDailyUpdatedAt`, and server-timestamp `updatedAt`. Times are validated `HH:mm` values. Each self-care timestamp changes only when its own enabled flag or time changes; this lets the scheduler distinguish a schedule edit from an unrelated appointment-toggle edit. Missing preference documents preserve appointment reminders as enabled and leave Mood/Breathing reminders disabled.
- Preserve the existing appointment lifecycle and its confirmation, reschedule, inquiry, and service notifications. Only the existing 24-hour and one-hour appointment reminders follow their corresponding preference switches.
- Self-care reminders are daily, opt-in, and use `Asia/Manila`. Keep the approved 15-minute delivery grace. Skip stale reminders and reminders enabled/changed after their selected time until the next day. Use deterministic per-user, per-kind, per-date notification IDs and transactional creation so overlapping scheduler runs cannot duplicate an alert.
- Notification and FCM copy must remain generic and contain no mood text, assessment result, sleep data, or other sensitive user content. A denied OS push permission must not suppress the Firestore inbox notification.
- Do not add snooze, quiet hours, weekdays, multiple reminder times, mood-triggered content, data delete/export controls, or an unapproved privacy URL/contact. Use `pacc@ucu.edu.ph` for general Help only; do not identify it as a privacy office.
- Preserve all pre-existing worktree changes. In particular, apply only the necessary additions to the already-modified `firestore.rules` and `home_screen.dart`; do not stage, revert, or reformat unrelated work.
- Do not deploy Functions or Firestore Rules as part of implementation.

## Review Focus

- Missing preferences keep both appointment reminders on while new self-care reminders stay off.
- Firestore Rules allow only an authenticated owner to read/write their valid preference document; reject other users, extra fields, invalid types/times, and client deletion.
- Scheduler time windows use Philippine local date/time; late or newly enabled reminders do not generate stale same-day alerts; retries create no duplicate notification.
- Editing an appointment reminder or one self-care schedule does not suppress a different self-care schedule that is due that day.
- Appointment and self-care reminder switches affect only their intended reminder types. Other appointment and inquiry notifications retain current behavior.
- Notification feed and FCM-open paths route Mood and Breathing reminders to their existing destinations.
- Settings screens work across all personal app roles, reuse existing consent/Terms flows, and make no unsupported privacy or emergency-support claims.

## Files in Scope

New Flutter files:

- `lib/features/settings/models/reminder_preferences.dart`
- `lib/features/settings/screens/reminders_screen.dart`
- `lib/features/settings/screens/privacy_settings_screen.dart`
- `lib/features/settings/screens/help_screen.dart`
- `lib/features/settings/screens/about_screen.dart`
- `lib/providers/reminder_preferences_provider.dart`
- `lib/repositories/reminder_preferences_repository.dart`

Modified Flutter files:

- `lib/database/firestore_collections.dart`
- `lib/main.dart`
- `lib/features/profile/screens/profile_screen.dart`
- `lib/features/notifications/screens/notifications_screen.dart`
- `lib/services/firebase/app_notification_service.dart`
- `lib/features/home/screens/home_screen.dart`

New Functions files:

- `functions/src/self_care_reminders.ts`
- `functions/src/self_care_reminders.test.ts`
- `functions/src/reminder_preferences_rules.test.ts`

Modified Functions/Rules files:

- `functions/src/appointment_reminders.ts`
- `functions/src/appointment_reminders.test.ts`
- `functions/src/index.ts`
- `firestore.rules`

New focused Flutter tests:

- `test/features/settings/reminder_preferences_test.dart`
- `test/features/settings/reminders_screen_test.dart`
- `test/features/settings/privacy_settings_screen_test.dart`
- `test/features/settings/help_about_screens_test.dart`
- `test/services/firebase/app_notification_service_test.dart`

Modified focused Flutter tests:

- `test/features/profile/profile_screen_test.dart`
- `test/features/notifications/notifications_screen_presentation_test.dart`
- `test/features/home/home_screen_test.dart`

Do not modify `lib/routes/app_pages.dart` or `lib/routes/route_names.dart` unless implementation demonstrates the existing direct Profile navigation and named Mood/Breathing routes cannot support this flow.

---

## Implementation Tasks

### Task 1: Add the reminder preference contract and persistence

**Files:** `test/features/settings/reminder_preferences_test.dart`, `lib/features/settings/models/reminder_preferences.dart`, `lib/repositories/reminder_preferences_repository.dart`, `lib/providers/reminder_preferences_provider.dart`, `lib/database/firestore_collections.dart`, `lib/main.dart`.

- [x] First add failing unit tests for parsing and serializing all preference fields, appointment-on/self-care-off defaults when no document exists, valid 24-hour `HH:mm` values, independent per-kind schedule timestamps, and provider load/save/error states with a fake repository.
- [x] Run `flutter test test/features/settings/reminder_preferences_test.dart` and confirm the new tests fail for the missing implementation.
- [x] Implement the typed preference model, Firestore repository for `reminder_preferences/{uid}`, and a thin provider scoped to the requested user. On first save, create the complete document and set both per-kind timestamps; on later saves, patch only changed settings, update only the matching per-kind timestamp when Mood or Breathing enablement/time changes, and set `updatedAt` on every save. Do not rewrite unchanged timestamp values.
- [x] Add the collection constant and register the provider using the existing mobile `MultiProvider` pattern. Keep identity/profile documents unchanged and avoid retaining one user's preferences when the authenticated user changes.
- [x] Run `flutter test test/features/settings/reminder_preferences_test.dart` and `flutter analyze lib/features/settings/models/reminder_preferences.dart lib/repositories/reminder_preferences_repository.dart lib/providers/reminder_preferences_provider.dart lib/database/firestore_collections.dart lib/main.dart`.

### Task 2: Enforce the preference document contract in Firestore Rules

**Files:** `functions/src/reminder_preferences_rules.test.ts`, `firestore.rules`.

- [x] First add emulator-backed Rules tests for owner read/create/update, cross-user and unauthenticated denial, malformed or extra fields, invalid time strings, mismatched server timestamps, and denied client delete.
- [x] Run the focused Rules test with the Firestore Emulator and confirm the valid owner cases fail before the rule is added.
- [x] Add the exact `reminder_preferences/{userId}` match. Require `isOwner(userId)`, the agreed field allowlist and types, valid time strings, and `updatedAt == request.time`. On create require both per-kind timestamps to equal `request.time`; on update require each timestamp to equal `request.time` when its schedule fields change and remain unchanged otherwise. Deny delete. Do not widen `/users` or `/notifications` permissions.
- [x] Re-run the focused Rules test with the emulator and confirm it executes rather than skips for a missing `FIRESTORE_EMULATOR_HOST`.

### Task 3: Honor appointment reminder switches on the server

**Files:** `functions/src/appointment_reminders.ts`, `functions/src/appointment_reminders.test.ts`, `functions/src/index.ts`.

- [x] First add tests proving a missing preferences document means both existing stages are enabled, and each saved false value disables only its matching stage.
- [x] Run the targeted appointment reminder tests and confirm the new cases fail.
- [x] Add a small pure helper to resolve a stage's enabled state, then update `sendAppointmentReminders` to read each recipient's preferences and skip only disabled reminder stages. Keep the existing 24-hour/one-hour windows, appointment eligibility checks, revision handling, notification IDs, and default-on behavior when no preference document exists.
- [x] Run `npm --prefix functions test -- appointment_reminders`.

### Task 4: Add daily Mood and Breathing reminder scheduling

**Files:** `functions/src/self_care_reminders.ts`, `functions/src/self_care_reminders.test.ts`, `functions/src/index.ts`.

- [x] First add unit tests for Asia/Manila date keys and selected times, delivery only between the scheduled time and 15-minute cutoff, skipping when that reminder's per-kind timestamp is after its selected time, disabled reminders, midnight/date rollover, and deterministic IDs by user/kind/date. Verify an appointment-only change or the other self-care timestamp does not suppress this reminder. Add an emulator-backed test that repeated creation attempts leave one notification document.
- [x] Run the focused Functions tests and confirm the new helper and idempotency cases fail.
- [x] Implement pure due-time/ID helpers and extend the existing ten-minute `sendAppointmentReminders` schedule to query enabled preference documents and create due self-care notifications transactionally after re-reading current preferences. Reuse the current schedule; do not add another scheduled function.
- [x] Use stable types `mood_reminder` and `breathing_reminder`, generic title/body text, and only the fields needed by the notification feed. Add no mood, assessment, sleep, or preference values to notification data.
- [x] Extend the existing notification-created FCM trigger to deliver these two types through saved device tokens while keeping existing appointment validation and all other notification behavior intact.
- [x] Run `npm --prefix functions test -- self_care_reminders appointment_reminders` and run the emulator-backed duplicate-creation test with Firestore Emulator enabled.

### Task 5: Build the working Reminders screen

**Files:** `test/features/settings/reminders_screen_test.dart`, `lib/features/settings/screens/reminders_screen.dart`.

- [x] First add widget tests for appointment toggles, Mood/Breathing opt-in defaults, selecting and saving daily times, loading/saving errors, the Mood section initial focus, and the denied-push-permission explanation/system settings action.
- [x] Run `flutter test test/features/settings/reminders_screen_test.dart` and confirm the new behavior tests fail.
- [x] Build the screen using the preference provider and existing `permission_handler` support. Show appointment reminders as enabled when the preference document is absent; show daily Mood/Breathing reminders as off until enabled; persist changes; label times as Philippine time; and offer the OS settings action without claiming the app can override permission.
- [x] Verify all three app roles can use the same screen and that changing one reminder does not change another reminder's toggle, time, or same-day scheduler eligibility.
- [x] Run the focused screen and preference tests, then analyze the new screen.

### Task 6: Build Privacy Settings, Help, and About screens

**Files:** `test/features/settings/privacy_settings_screen_test.dart`, `test/features/settings/help_about_screens_test.dart`, `lib/features/settings/screens/privacy_settings_screen.dart`, `lib/features/settings/screens/help_screen.dart`, `lib/features/settings/screens/about_screen.dart`.

- [x] First add widget tests for the supported privacy explanations, links to existing MindAid and Sleep consent experiences, offline FAQ sections, working PACC email action, About purpose copy, and the existing Terms dialog action.
- [x] Run the focused screen tests and confirm the new screens/actions are missing.
- [x] Implement screens with truthful, concise descriptions. Reuse existing consent routes/providers and Terms behavior. Use `mailto:pacc@ucu.edu.ph` for general Help. Do not add global consent, data deletion/export, an invented privacy URL/contact, or an emergency hotline.
- [x] Run the focused tests and analyze the new screens.

### Task 7: Connect the Profile actions to the new screens and inbox

**Files:** `test/features/profile/profile_screen_test.dart`, `lib/features/profile/screens/profile_screen.dart`.

- [x] First add tests showing Reminders opens the Reminders screen at the top, Mood reminders opens its Mood section, Privacy/Help/About open their screens, and the header notification icon opens the existing per-user Notifications screen.
- [x] Run `flutter test test/features/profile/profile_screen_test.dart` and confirm the new navigation cases fail.
- [x] Replace only the corresponding placeholder branches and rename "Mood tracking settings" to "Mood reminders." Keep existing Student Information, Secret Chats profile, Terms, profile editing, and role visibility behavior unchanged.
- [x] Run the Profile tests and analyze `profile_screen.dart`.

### Task 8: Route reminder taps from the inbox, FCM, and foreground banner

**Files:** `test/features/notifications/notifications_screen_presentation_test.dart`, `test/services/firebase/app_notification_service_test.dart`, `test/features/home/home_screen_test.dart`, `lib/features/notifications/screens/notifications_screen.dart`, `lib/services/firebase/app_notification_service.dart`, `lib/features/home/screens/home_screen.dart`.

- [x] First add tests that tapping `mood_reminder` marks it read and opens `RouteNames.logMood`, tapping `breathing_reminder` marks it read and opens `RouteNames.mindfulBreathing`, FCM opened-message dispatch passes only recognized reminder types, and a foreground reminder banner opens the matching destination.
- [x] Run the focused tests and confirm the new reminder routes fail while existing inquiry and appointment route tests continue to pass.
- [x] Add type-based routing for the two self-care types to the existing notification inbox, FCM opened-message callback, and foreground banner. Keep appointment and inquiry routing unchanged; an unknown type must not navigate.
- [x] Run the notification, FCM service, and Home tests; analyze the three modified Flutter files.

### Task 9: Validate the complete scoped feature

**Files:** Only the files listed in Tasks 1–8.

- [x] Run the focused Flutter tests listed above and `flutter analyze` on the scoped Flutter files.
- [x] Run the appointment and self-care Functions tests together with the Firestore Emulator, and run the Rules test with the emulator; confirm Rules/idempotency tests execute rather than skip.
- [x] Inspect the final diff for accidental changes outside the listed feature surface, especially pre-existing `firestore.rules` and `home_screen.dart` work. Do not deploy or modify hosted resources.
