# Android release configuration

Release builds must not use the Android debug keystore or the template
`com.example.mind_mates` application ID.

The production package name is `ph.edu.ucu.mindmates` and must match the
production Firebase Android app in `android/app/src/production/google-services.json`.
Create an untracked
`android/key.properties` file with:

```properties
keyAlias=...
storeFile=.../release-upload.jks
storePassword=...
keyPassword=...
```

The keystore and passwords must be supplied by the deployment environment or
local secret manager. The Firebase Android configuration must contain a client
for the same production package name before release builds are enabled.

## Environment builds

Always begin with `flutter clean`; do not install an APK retained under
`build/` from a previous flavor. The tester-facing staging build is debug-only:

```powershell
flutter clean
flutter build apk --debug --flavor staging --dart-define=APP_ENV=staging
```

`APP_ENV=staging` is recommended for CI and release scripts. For local tester
builds, `flutter build apk --debug --flavor staging` is also sufficient: the
app derives the environment from Flutter's selected flavor, preventing a
staging native Firebase app from being initialized with development options.

The staging APK deliberately does not activate Firebase App Check. Matching
callable functions disable enforcement only when deployed to the exact
`mindmate-staging` project, so testers do not need per-device debug tokens.
Never point this flavor at production or distribute it as a production build.

Google sign-in for staging uses the Android OAuth registration for
`com.example.mind_mates.staging` and the repository's debug signing SHA-1.
If the debug keystore changes, register its new SHA-1/SHA-256 in the staging
Firebase Android app and download a fresh `google-services.json` before build.

Production release builds must use the production flavor and runtime identity:

```powershell
flutter clean
flutter build appbundle --release --flavor production --dart-define=APP_ENV=production
```

Staging release artifacts are intentionally unsupported. Production releases
use Play Integrity; do not distribute a sideloaded staging debug APK as a
production candidate.
