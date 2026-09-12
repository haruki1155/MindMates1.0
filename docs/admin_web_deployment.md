# MindMate Admin web deployment

Firebase Hosting is reserved for the staff administration portal. The student
and wellness application is distributed only as a native mobile application.

## Build and verify

From the repository root, run:

```powershell
flutter pub get
flutter test test/app_bootstrap_test.dart
flutter analyze
flutter build web --release --target lib/admin_main.dart --dart-define=RECAPTCHA_V3_SITE_KEY=YOUR_RECAPTCHA_V3_SITE_KEY
```

For the staging Admin portal, explicitly select the staging Firebase project:

```powershell
flutter build web --release --target lib/admin_main.dart --dart-define=APP_ENV=staging
firebase deploy --only hosting --project mindmate-staging
```

Never omit `APP_ENV=staging` from a staging Admin build. The build validates
that its Firebase project is `mindmate-staging` before initialization.

The production web entry point must remain `lib/admin_main.dart`. The default
`lib/main.dart` also selects the admin portal when compiled for web as a safety
measure, but deployment automation uses the explicit admin target.

## Deploy

Configure the immutable administrator when prompted by Firebase Functions. Use
the Firebase Authentication UID of the single super-administrator:

```powershell
firebase deploy --only functions --project mind-mates-cd2cf
# Prompt value: SUPER_ADMIN_UID=<the existing administrator UID>
firebase deploy --only firestore:rules,firestore:indexes --project mind-mates-cd2cf
```

The configured user must already have `accessRole: admin` in `users/{uid}`.
The first successful privileged operation mirrors this UID into the locked
`system_config/security` document used by Firestore Rules. Never assign
`accessRole: admin` to another profile.

Before opening the redesigned User Management page, preview and apply stable
anonymous IDs for existing app users:

```powershell
cd functions
npm run public-ids:dry-run
npm run public-ids:apply
cd ..
```

Future app-user profiles receive a privacy-safe `USR-XXXXXX` identifier from
the deployed `assignPublicIdOnUserCreate` trigger. The UID mappings and public
ID reservations are server-only collections.

```powershell
firebase deploy --only hosting --project mind-mates-cd2cf
```

After deployment, open `https://mind-mates-cd2cf.web.app/` in a private browser
window and confirm it displays `MindMate Admin`. Approved `portalStaff` and
`counselor` profiles may enter; only the configured super-administrator can
approve registrations, change access, disable accounts, or maintain the
organization directory.

Do not deploy a generic mobile web bundle to this Hosting site.
