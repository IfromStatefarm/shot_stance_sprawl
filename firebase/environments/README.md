# Native Apple Firebase configuration

Place the Firebase iOS app configuration files at:

- `dev/GoogleService-Info.plist` for `snap-and-go-dev`
- `prod/GoogleService-Info.plist` for `snap-and-go-prod`

Both files must use bundle ID `com.snapandgo.shadowwrestling`. The Xcode build
validates the project and bundle IDs before copying the selected file into the
app. See `docs/ios_release.md` for download and validation steps.
