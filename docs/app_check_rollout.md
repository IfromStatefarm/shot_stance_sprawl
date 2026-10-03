# App Check rollout

App Check is initialized in the Flutter app and every callable rejects missing
or invalid App Check tokens. `ENFORCE_APP_CHECK` defaults to `true`, and the
checked-in `functions/.env.snap-and-go-prod` configuration also sets it to
`true`. A missing project configuration therefore fails closed instead of
silently exposing callable functions.

## Rollout sequence

1. Configure Play Integrity for the production Android app and App Attest with
   DeviceCheck fallback for the production Apple app.
2. Keep local/development builds on the App Check debug provider. Register
   debug tokens only in the development project; never add them to production
   builds or source control.
3. Deploy development first and exercise authentication, friend discovery,
   sharing, scheduling, completion, export, and deletion on real devices.
4. In Firebase Console, open **App Check > APIs** and confirm legitimate Cloud
   Functions traffic is verified before deploying production.
5. Run `npm --prefix functions run check`. This is also a Functions predeploy
   hook and fails if the code default or `snap-and-go-prod` environment value
   does not enforce App Check.
6. Deploy with `firebase deploy --only functions --project prod`, confirm the
   CLI reports that `.env.snap-and-go-prod` was loaded, then repeat the callable
   test matrix against `snap-and-go-prod` before launch.
7. Enable Cloud Firestore App Check enforcement separately in the Firebase
   console after its legitimate traffic is verified.

The local integration-test project has an explicit
`functions/.env.demo-snap-and-go` opt-out because the test harness does not mint
App Check tokens. For an interactive local override, use the ignored
`functions/.env.local` file. Never set `ENFORCE_APP_CHECK=false` in a live
project configuration.

Enforcement rejects missing or invalid tokens; it is intentionally a rollout
control, not a substitute for Authentication or Firestore Security Rules.
