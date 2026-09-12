# MindMate

MindMate is a Flutter wellness app with a separate staff administration portal and Firebase backend. The mobile app uses `lib/main.dart`; the admin web portal uses `lib/admin_main.dart`.

## Develop and verify

Install Flutter and Node.js 22, then run from the repository root:

```powershell
flutter pub get
flutter analyze
flutter test
cd functions
npm ci
npm test
```

The Android app has `development`, `staging`, and `production` flavors. For a staging tester build:

```powershell
flutter build apk --debug --flavor staging --dart-define=APP_ENV=staging
```

For the staff portal:

```powershell
flutter build web --release --target lib/admin_main.dart --dart-define=APP_ENV=staging
```

Use the matching Firebase project for each environment. Production Android releases require a local, untracked signing keystore and `android/key.properties`.

See [Android release signing](docs/android_release_signing.md), [admin web deployment](docs/admin_web_deployment.md), and [Firebase runtime verification](docs/firebase_runtime_verification.md) for deployment details.
