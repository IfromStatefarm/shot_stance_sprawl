# Account and team callables

The `createTeam`, `joinTeam`, `editTeam`, `leaveTeam`, and `deleteTeam` callables
own all team and access-code writes. Clients can read their own membership,
their team's details and roster, and teammate profile summaries. Only the team
creator can read the access code. Workout delivery checks current team
membership inside the same transaction that creates each share.

Team photos require Firebase Storage. Enable a default Storage bucket in each
Firebase project and deploy `storage.rules` along with `firestore.rules` and
Functions. The client and Functions must use the same project default bucket.
The client uploads a temporary photo under `teamPhotoUploads/{uid}`; a callable
checks it and copies it into the team photo directory. A deleted team removes
its members and invalidates its code.

For local integration tests, run the Auth, Firestore, Functions, and Storage
emulators together. `npm run test:team` exercises photo upload, team roles,
code behavior, and teammate workout sharing. `npm run test:rules` tests the
Firestore access boundary.

## App Check

All callable functions use a shared `ENFORCE_APP_CHECK` parameter that defaults
to `true`. Production also has an explicit checked-in value in
`.env.snap-and-go-prod`. Run `npm run check` before deployment; the same command
runs automatically as the Functions predeploy hook and fails if production
enforcement is disabled or removed. See `docs/app_check_rollout.md` for the
real-device and Firebase Console verification required before launch.

## Subscription verification

`verifySubscriptionPurchase` and `getSubscriptionEntitlement` are the only
authorities for Coach Mode. The Flutter client does not persist a paid-access
boolean. Store credentials are kept in the server-only
`subscriptionPurchases` collection, are bound to the Firebase UID that first
claims them, and are rechecked with Apple or Google before an entitlement is
returned.

Set the Apple credentials before deploying Functions:

```sh
firebase functions:secrets:set APPLE_IAP_ISSUER_ID
firebase functions:secrets:set APPLE_IAP_KEY_ID
firebase functions:secrets:set APPLE_IAP_PRIVATE_KEY
firebase functions:secrets:set APPLE_IAP_SHARED_SECRET
```

The App Store Connect API key needs in-app-purchase access. The shared secret
is retained for StoreKit 1 receipts. The default bundle ID and Android package
name are `com.snapandgo.shadowwrestling`; override `APPLE_IAP_BUNDLE_ID` or
`ANDROID_IAP_PACKAGE_NAME` as Functions parameters if a store listing differs.
Set `APPLE_IAP_APP_ID` to the app's numeric Apple ID from App Store Connect.
The notification endpoint uses that ID, the bundle ID, and Apple's bundled root
certificates to verify both the notification and transaction JWS signatures
before it looks up a stored purchase or triggers a subscription recheck.

In App Store Connect, point App Store Server Notifications V2 at the deployed
`handleAppStoreSubscriptionNotification` HTTPS function. In Google Play
Console, publish real-time developer notifications to the Firebase project's
`play-subscription-notifications` Pub/Sub topic and give the Functions runtime
service account Android Publisher API access. These notifications trigger an
immediate store recheck for cancellations, refunds, revocations, and
chargebacks; clients also recheck at startup, after restore, on account change,
and every 15 minutes while running.
