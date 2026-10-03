# Android release signing

Release builds use a dedicated upload key. They never fall back to the Android debug key.

## Local signing material

The development machine keeps both private files outside the repository:

- Keystore: `%USERPROFILE%/.android/keystores/shot-stance-sprawl-upload.jks`
- Credentials: `%USERPROFILE%/.gradle/shot_stance_sprawl_upload.properties`
- Public certificate: `%USERPROFILE%/.android/keystores/shot-stance-sprawl-upload-certificate.pem`

Back up the keystore and credentials in the team's password manager or encrypted secrets vault. Losing the upload key requires an upload-key reset in Play Console. The PEM certificate is public and can be supplied to Google Play when requested.

For another workstation, copy `android/signing.properties.example` to the private credentials path, fill in the real values, and keep the keystore outside the checkout. Paths in Java properties files should use forward slashes.

## CI signing

CI can either set `SHOT_STANCE_SPRAWL_SIGNING_PROPERTIES` to a securely materialized properties file or supply all four variables:

- `SHOT_STANCE_SPRAWL_KEYSTORE_PATH`
- `SHOT_STANCE_SPRAWL_STORE_PASSWORD`
- `SHOT_STANCE_SPRAWL_KEY_ALIAS`
- `SHOT_STANCE_SPRAWL_KEY_PASSWORD`

Treat the keystore and all passwords as protected CI secrets. Release tasks stop with an actionable error when any value or the keystore is missing.

## Play App Signing

In Google Play Console, open the app and go to **Test and release > Setup > App signing**. Enroll in Play App Signing and choose a Google-managed app-signing key unless an existing production-key migration requires a different option. Google then protects the app-signing key; this repository's key is only the upload key.

Upload the first release AAB built with this upload key. If Play Console asks to register the upload certificate separately, upload `shot-stance-sprawl-upload-certificate.pem`. Confirm that Play Console's **Upload key certificate** SHA-256 fingerprint matches the local certificate before promoting the release.

Enrollment changes Play Console state and must be completed by an account with the required Play Console permissions.

## Build and verify

Before promoting the release, publish `docs/privacy_policy.md` at the in-app
privacy URL and complete Play Console's Data Safety and target-audience forms
from `docs/store_privacy_disclosures.md`.
Apply the audience decision in `docs/age_audience_decision.md`: target only
13+ age groups, do not enroll in Families, and verify the under-13 local-mode
branch on a clean install.

```powershell
flutter build appbundle --flavor prod --release
& "C:/Program Files/Android/Android Studio/jbr/bin/keytool.exe" -printcert -jarfile build/app/outputs/bundle/prodRelease/app-prod-release.aab
```

The signer must identify the upload certificate and must not contain `CN=Android Debug`.
