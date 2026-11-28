# MindMate Settings, Privacy, Reminders, and Help Design

**Status:** Draft for user review

## Intent

Turn the personal app's existing Profile settings entries into useful, working destinations for Student, Teaching, and Non-Teaching users. Reuse current profile, consent, in-app notification, FCM, and appointment-reminder paths. Add daily Mood and Breathing reminders that are account-based and delivered through the existing notification infrastructure.

## What Exists Today

- `ProfileScreen` lists Mood tracking settings, Privacy settings, Reminders, Help, About MindMate, and Terms. Most entries open `_BlankProfilePage`; the notification bell also opens that placeholder. Student Information, Secret Chats profile, and Terms already have working actions.
- The mobile app already has `NotificationsScreen`, a per-user Firestore notification feed, and FCM registration. The Home screen opens the feed and routes appointment and inquiry notifications. Feed taps do not yet route self-care reminders.
- `sendAppointmentReminders` runs every ten minutes in `Asia/Manila` and creates the existing 24-hour and one-hour appointment reminders. The FCM trigger sends supported notification types to saved device tokens.
- MindAid cloud consent and Sleep local/cloud storage consent already have their own models and write paths. Their decisions must be reused rather than copied into a new global consent flag.
- Firestore self-profile writes use a narrow allowlist. Preference data must not be added to the identity/profile document.
- `url_launcher` is already installed. The app uses `pacc@ucu.edu.ph` as a PACC contact. No official privacy-policy URL or privacy-office contact was found in the app source.
- Web boots the Admin app; these screens are for personal app users on mobile.

## Goals

- Keep Profile as the settings entry point; replace the blank destinations for Privacy, Reminders, Help, and About with useful screens. Rename the existing Mood tracking settings entry to Mood reminders and open the Mood section of Reminders so it is not left as a dead placeholder or given a second, duplicate preference store.
- Route the Profile notification bell to the existing per-user Notifications screen.
- Let users independently enable or disable the existing 24-hour and one-hour appointment reminders. If a user has no saved preferences yet, keep both enabled to preserve current behavior. Confirmations, schedule changes, inquiry replies, and other service updates remain governed by their existing flows.
- Add separate, opt-in daily Mood and Breathing reminders with a user-selected time. New self-care reminders default off. Use `Asia/Manila`, matching the existing appointment scheduler, and explain that selected times use Philippine time.
- Deliver reminders across the user's devices through the server scheduler, Firestore notification feed, and FCM. Tapping a Mood reminder opens mood logging; tapping a Breathing reminder opens mindful breathing.
- Make privacy controls accurately describe current behavior and provide access to the existing MindAid and Sleep consent controls.
- Provide practical feature help and a working PACC email action using the existing `pacc@ucu.edu.ph` address.

## Non-Goals and Anti-Goals

- Do not add client controls that turn off required assessment, mood, appointment, or safety data processing.
- Do not add delete/export actions or promise retention periods before the institution supplies an approved process.
- Do not create local-notification schedules, multiple reminders per day, selected weekdays, snooze, quiet hours, or mood-triggered/personalized reminder content in this release.
- Do not make app service notifications depend on the optional appointment-reminder switches.
- Do not send mood text, assessment results, sleep data, or other sensitive content in notification titles, bodies, or FCM data.
- Do not add a new notification or time-zone dependency unless implementation proves the existing Flutter/Firebase support is insufficient.
- Do not change Admin Portal settings.

## Reminder Design

Use a separate `reminder_preferences/{uid}` document rather than extending `users/{uid}`. Its client-writable contract contains the two appointment reminder booleans, daily Mood and Breathing enabled flags and `HH:mm` local times, `moodDailyUpdatedAt`, `breathingDailyUpdatedAt`, and `updatedAt`. All timestamps are written as server timestamps. Update each per-kind timestamp only when that reminder's enabled flag or time changes; keep it unchanged for unrelated preference edits. This lets the scheduler skip a reminder enabled or changed after its selected time without suppressing another schedule after an unrelated edit. The time zone is the fixed `Asia/Manila` product setting. Firestore rules must allow only the signed-in owner to read and write this document, validate allowed fields and types, enforce server timestamps, and reject extra fields. The server continues to own notification creation.

The existing ten-minute scheduled function will also process enabled self-care schedules. The server creates one notification per user, reminder kind, and Philippine calendar date using a deterministic document ID and a transaction/exists guard, so retries cannot create duplicates. Each self-care reminder has a 15-minute delivery grace period, matching the existing appointment reminder window. If the selected time is missed beyond that window, or that reminder's per-kind update timestamp is after today's selected time, skip it until the next day; do not send a stale catch-up alert. An unrelated appointment or other self-care preference edit must not suppress this reminder. Turning off a self-care reminder prevents its next notification; it does not delete notification history. Appointment reminders use the stored per-stage switches, with absent preferences treated as enabled for backward compatibility.

All reminder text is generic. The notification record's type identifies Mood or Breathing for routing, without including user content. The existing FCM creation trigger and app notification-open path will recognize those types. The in-app notification list will route them through the existing `/mood/log` and `/insights/mindful-breathing` destinations. If OS notification permission is denied, reminders remain visible in the in-app feed and the Reminders screen offers the system settings action; the app does not claim it can override OS permission.

The renamed Mood reminders row opens the Mood reminder section. The Reminders row opens the same page at its top. There is one source of truth for both controls.

## Privacy and Help Design

The Privacy screen will explain only data practices that are supported by current code and institution-approved privacy copy. It will link to the existing MindAid cloud-consent and Sleep storage-consent experiences, and may link to profile editing. It will not add a global consent switch that implies assessments, moods, or appointments stop being recorded.

The repository currently contains neither an official privacy-policy URL nor an identified privacy-office contact. The implementation must not invent either. Before release, the institution must approve the privacy notice text and supply the correct contact or process for privacy requests. Until then, the screen must not offer an unsupported data deletion/export request action. General Help may use the existing PACC email address; that address must not be represented as the Privacy Officer without confirmation.

Help will use a short offline-friendly FAQ for implemented features (account/profile, assessments, Mood and Sleep, appointments/inquiries, MindAid, notifications/reminders, and privacy) and an email action for `pacc@ucu.edu.ph`. It will reuse the app's existing non-emergency and crisis wording; it will not invent a hotline or imply real-time monitoring. About will reuse the existing MindMate purpose copy and the working Terms dialog. No build-version dependency is needed for this release.

## Approaches Considered

1. **Account-level server reminders — selected.** Extend the existing scheduled Function and notification feed. This uses the app's current delivery path, works across a user's devices and all three app-user roles, and keeps notification history in one place. It requires careful time/date handling, preference rules, and idempotent creation.
2. **Device-local self-care reminders.** This avoids adding self-care work to Functions and can operate offline, but schedules would be device-specific and require a new local-notification dependency and platform setup. It does not meet the selected account-level behavior.
3. **Presentation-only settings.** This would add screens without changing persistence or delivery. It fails the requirement that controls actually work and is not acceptable.

## Constraints and Open Release Input

- Keep existing appointment reminder behavior for accounts without a preference document.
- Keep FCM and Firestore notification delivery owner-scoped. Never grant clients write access to the `notifications` collection.
- Keep MindAid and Sleep consent data in their existing stores and maintain their existing default/privacy behavior.
- The official privacy notice, privacy-policy URL, and privacy-request contact/process are institution-owned inputs that must be confirmed before publishing legal copy or privacy-request actions.
- The selected reminder schedule uses `Asia/Manila`, daily recurrence, and a 15-minute self-care delivery grace period. Changing the timezone or adding weekday schedules is a later product decision.

## Expected Implementation Surface

Likely changes are limited to Profile navigation; new Settings Privacy, Reminders, Help, and About screens; a typed preference model/repository/provider and its app registration; the Firestore collection constant and owner-only rule; the existing appointment/self-care scheduler and its unit tests; the existing notification screen, FCM open dispatch, and Home routing; and focused tests for settings, rules, notification destinations, and reminder idempotency. No assessment, counseling-booking, forum, or Admin Portal business logic is part of this feature.
