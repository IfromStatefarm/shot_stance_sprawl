# Account authentication

The workout engine remains local-first. Firebase Authentication is consulted
only by account, team, legacy friend, and shared-workout entry points.
When Firebase cannot initialize, the app opens in local mode and keeps workout
history on the device.

## Data boundaries

- `users/{uid}` is owner-readable and contains profile settings plus the
  server-owned unread counter. Firestore rules reject email and phone fields.
- `safeProfiles/{uid}` is the connected-friend projection. It contains only
  display name, photo, username, and language.
- `users/{uid}/privateData/account` is owner-readable account metadata.
- `users/{uid}/privateData/localProgress` is the idempotent snapshot used to
  attach existing device progress after sign-in. Recordings, local file paths,
  custom audio, and purchases are never uploaded in this snapshot.
- `usernames/{normalizedUsername}` reserves usernames transactionally.
- `friendships/{pairId}` stores pending/accepted friend connections and is
  readable only by the two members.
Users connect through team access codes. The app does not request address-book
permission, upload contact numbers, or maintain a phone-number lookup index.

Direct workout sending requires an accepted `friendships/{pairId}` document in
both the Flutter picker and the protected callable. Block actions replace the
connection with a blocked friendship state. Reports are created only through an
authenticated, App-Check-protected callable in the server-only `userReports`
collection.

## Console setup still required per environment

In both `snap-and-go-dev` and `snap-and-go-prod`:

1. Enable Email/Password, Google, and Apple in Authentication > Sign-in
   method.
2. Add Android SHA-1 and SHA-256 fingerprints. Download the refreshed Android
   configuration after adding them.
3. Configure the Google OAuth consent screen and Apple provider credentials.
   The iOS Runner already includes the Sign in with Apple entitlement, but the
   capability must also be enabled for the App ID in the Apple Developer portal.
4. Upload an APNs authentication key for iOS push notifications.
5. Register App Check debug tokens only in development. Keep Play Integrity and
   App Attest/DeviceCheck enforcement for production.

## Backend setup

The `functions/` directory implements protected team management, uncapped data
export, and recent-sign-in account deletion. Export and
deletion cover the account's server-only social qualification, partner-week,
crew-progress, and user-report records in addition to its client-readable data.
Before deployment,
deploy Functions and Firestore rules using the explicit project alias.

Google Play also requires a deletion path that works without the installed app.
Publish `web/account-deletion/index.html` at
`https://keepkidswrestling.com/Snap-and-go/account-deletion`; its email link lets a user
start a verified deletion request without signing in or reinstalling Snap & Go.

Use the Emulator Suite first:

```powershell
firebase use dev
firebase emulators:start --only auth,firestore,functions
```

For a release, host the `/Snap-and-go/invite` landing route and configure
Android App Links and iOS Universal Links for the production web domain. The
in-app QR flow already uses the registered `snapandgo://friend/<username>`
scheme; the HTTPS landing route is intentionally not claimed until its domain
association files are live.
