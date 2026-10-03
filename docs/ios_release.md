# iOS release setup and validation

The repository now contains the CocoaPods integration, Firebase build
selection, Apple capabilities, and release validation script. The remaining
inputs are intentionally not fabricated: the two Firebase plist files, an
Apple Developer Team ID, and a Mac signed into Xcode.

## 1. Add the Firebase iOS configurations

Register bundle ID `com.snapandgo.shadowwrestling` as an iOS app in both
Firebase projects. Download each app's `GoogleService-Info.plist` and place it
at the exact path below:

| Build | Firebase project | Repository path |
| --- | --- | --- |
| Debug/Profile | `snap-and-go-dev` | `firebase/environments/dev/GoogleService-Info.plist` |
| Release | `snap-and-go-prod` | `firebase/environments/prod/GoogleService-Info.plist` |

The Xcode **Configure Firebase** build phase validates `PROJECT_ID` and
`BUNDLE_ID`, copies the selected file into the application bundle, and adds the
Google client ID and reversed URL scheme to the built `Info.plist`. A missing
or mismatched file fails the build instead of silently connecting to the wrong
Firebase project.

The same files can be regenerated with FlutterFire CLI as described in
`docs/firebase_environments.md`. Firebase client configuration is not an
administrative credential, but the files still need normal source-control and
CI review because choosing the wrong project changes where user data is sent.

In each Firebase project, also complete the console-side setup:

1. Enable Email/Password, Google, and Apple authentication providers.
2. Upload the APNs authentication key under Project settings > Cloud Messaging.
3. Register App Check debug tokens only in development. Configure App Attest
   with DeviceCheck fallback for production.
4. Confirm Firestore, Functions, and Storage are deployed to the same project.

## 2. Select the Apple development team

Join the Apple Developer Program and create/confirm the explicit App ID
`com.snapandgo.shadowwrestling`. Enable these capabilities for the App ID:

- Push Notifications
- Sign in with Apple
- In-App Purchase
- App Attest

Copy the local signing template and replace its example with the 10-character
Team ID shown in Apple Developer membership details:

```sh
cp ios/Flutter/Signing.xcconfig.example ios/Flutter/Signing.xcconfig
```

`Signing.xcconfig` is ignored by Git. CI can create it from a protected Team ID
variable before the build. Xcode automatic signing will then create or select
the matching development and distribution profiles.

## 3. Install plugins and archive on a Mac

Install the current stable Flutter SDK, Xcode command-line tools, and
CocoaPods. From the repository root:

```sh
flutter pub get
cd ios
pod install --repo-update
cd ..
open ios/Runner.xcworkspace
```

Commit the generated `ios/Podfile.lock` after the first successful install so
local and CI archives resolve the same native SDK versions. Before each upload,
also set a new build number with `version: <marketing-version>+<build-number>`
in `pubspec.yaml` (or pass `--build-name` and `--build-number`). App Store
Connect rejects a second upload of the same build number.

Always open `Runner.xcworkspace`, not `Runner.xcodeproj`; the workspace links
the Flutter, Firebase, StoreKit, messaging, media, and other native
plugin pods. The current FlutterFire podspecs require iOS 15.0, which is set in
the Podfile and Xcode project.

For a reproducible preflight plus archive:

```sh
/bin/sh ios/scripts/validate_release_setup.sh
```

The script validates the production plist and Team ID, installs pods, runs
Flutter analysis/tests, and creates a signed release archive and IPA with the
production Firebase environment. Alternatively, select **Any iOS Device
(arm64)** in Xcode and use Product > Archive. Resolve every signing or archive
validation error before upload.

## 4. App Store Connect and TestFlight

Before uploading, publish `docs/privacy_policy.md` at the in-app privacy URL
and enter the Apple disclosures from `docs/store_privacy_disclosures.md` in
App Store Connect. Generate Xcode's privacy report from the release archive and
confirm it matches both the app manifest and the disclosure checklist.

Apply `docs/age_audience_decision.md`: do not use the Kids category, disclose
social and purchase capabilities, apply a 13+ minimum age, and verify the
under-13 local-mode branch on a clean install.

Before purchase testing, create the auto-renewable subscription product
`snap_go_pro_monthly`, complete paid-app agreements/tax/banking, attach the
subscription to the app version, and create a Sandbox Apple Account. Configure
the App Store Server API issuer, key ID, private key, and legacy shared secret
as Firebase Functions secrets as described in `functions/README.md`. Register
`handleAppStoreSubscriptionNotification` as the App Store Server Notifications
V2 URL for both sandbox and production. Coach Mode is granted only after the
callable verifies the transaction and is removed when the server reports an
expiry, refund, or revocation.

Upload the archive with Xcode Organizer or Transporter. After Apple finishes
processing it, verify on a physical TestFlight device:

- fresh install and upgrade from the previous build;
- email/password, Google, and Apple authentication;
- push permission plus foreground, background, and terminated notifications;
- monthly purchase, cancellation path, interrupted purchase, and restore;
- App Check acceptance for Auth-adjacent Firestore/Functions/Storage calls;
- camera, microphone, photo library, local notifications, and video
  export;
- `snapandgo://` account/workout links and account deletion/export.

Record the tested build number, device/iOS version, Firebase production project
ID, tester account, purchase transaction result, and any console logs. Only
after this matrix passes can iOS authentication, messaging, purchases, and the
remaining native plugins be called release-verified.
