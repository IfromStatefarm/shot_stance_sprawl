# Firebase environments

Snap & Go uses two Firebase projects:

- Development: `snap-and-go-dev`
- Production: `snap-and-go-prod`

Both projects register the Android and iOS application identifier
`com.snapandgo.shadowwrestling`.

The runtime reads Flutter's `appFlavor` value (`dev` or `prod`) first. The
`FIREBASE_ENV` Dart definition remains a fallback for platform builds whose
native flavor or scheme has not been configured yet. Startup validates that
the bundled native Firebase configuration belongs to the project expected by
the selected flavor and fails fast if they do not match.

## Live development

A normal Android development run connects to the live `snap-and-go-dev`
project through the `dev` product flavor:

```powershell
flutter run --flavor dev
```

On iOS, the standard Runner scheme packages the development Firebase plist for
debug/profile builds and the production plist for release archives. No custom
Xcode flavor is required:

```sh
flutter run
flutter build ipa --release --dart-define=FIREBASE_ENV=prod
```

The Xcode build phase validates and copies the appropriate file from
`firebase/environments/<dev|prod>/GoogleService-Info.plist`. See
`docs/ios_release.md` for Apple signing, CocoaPods, archiving, and TestFlight.

## Local Firebase emulators

Start the Auth, Firestore, Functions, and Storage emulators from the repository root:

```powershell
firebase use dev
firebase emulators:start --only auth,firestore,functions,storage
```

Run the app against the emulators:

```powershell
flutter run --flavor dev --dart-define=USE_FIREBASE_EMULATORS=true
```

Android emulators use `10.0.2.2` to reach the host machine. Desktop, iOS
simulators, and web use `127.0.0.1`. A physical device can provide a reachable
host explicitly:

```powershell
flutter run --dart-define=FIREBASE_ENV=dev --dart-define=USE_FIREBASE_EMULATORS=true --dart-define=FIREBASE_EMULATOR_HOST=192.168.1.10
```

To explicitly select the live development project:

```powershell
flutter run --flavor dev --dart-define=USE_FIREBASE_EMULATORS=false
```

Development builds activate Firebase App Check's debug providers. The SDK
prints a debug token on first launch; register that token in the development
project's App Check settings. CI can provide a registered token without
committing it:

```powershell
flutter run --flavor dev --dart-define=FIREBASE_APP_CHECK_DEBUG_TOKEN=your-registered-debug-token
```

## Production builds

Production never connects to emulators, including if
`USE_FIREBASE_EMULATORS=true` is accidentally supplied to a release build.

```powershell
flutter build apk --flavor prod --release
```

Android reads `android/app/src/dev/google-services.json` for `dev` variants
and `android/app/src/prod/google-services.json` for `prod` variants. Never put
a shared `google-services.json` directly under `android/app`; a shared file can
silently package the wrong Firebase project. The Google Services Gradle plugin
fails the build when the selected flavor's file is absent.

Production Android builds use Play Integrity. Production iOS builds use App
Attest with DeviceCheck fallback.

## Regenerating FlutterFire configuration

Run these commands after changing an app registration. They place each Android
service file directly in its Gradle source set and each iOS file in the path
consumed by the Xcode build phase.

```powershell
flutterfire configure --yes --project=snap-and-go-dev --platforms=android,ios --android-package-name=com.snapandgo.shadowwrestling --ios-bundle-id=com.snapandgo.shadowwrestling --out=lib/firebase_options_dev.dart --android-out=android/app/src/dev/google-services.json --ios-out=firebase/environments/dev/GoogleService-Info.plist

flutterfire configure --yes --project=snap-and-go-prod --platforms=android,ios --android-package-name=com.snapandgo.shadowwrestling --ios-bundle-id=com.snapandgo.shadowwrestling --out=lib/firebase_options_prod.dart --android-out=android/app/src/prod/google-services.json --ios-out=firebase/environments/prod/GoogleService-Info.plist
```

The checked-in `.firebaserc` aliases `dev` and `prod`. Do not deploy rules or
functions without selecting the intended alias first.

Cloud Functions App Check enforcement is fail-closed by default. The checked-in
`functions/.env.snap-and-go-prod` file explicitly sets
`ENFORCE_APP_CHECK=true`; the Functions predeploy check verifies both values.
Before a production deployment, follow `docs/app_check_rollout.md` and confirm
the Firebase CLI reports that the production environment file was loaded.

Team photos need a default Firebase Storage bucket in both projects. Confirm
the native Firebase app configuration and Functions default app reference the
same bucket before deploying the team feature. Deploy Storage rules with the
Firestore rules and Functions for each environment.
