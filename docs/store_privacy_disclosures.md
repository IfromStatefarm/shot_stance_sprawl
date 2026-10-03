# Store privacy disclosures

**Source-of-truth build review:** October 1, 2026

This file is the release-entry checklist for App Store Connect and Google Play
Console. It describes the current Snap & Go codebase. Re-audit it whenever a
data flow, SDK, backend collection, retention rule, or store policy changes.
The public policy in `docs/privacy_policy.md` must be published verbatim (or
with legally reviewed, substantively equivalent text) at
`https://keepkidswrestling.com/Snap-and-go/privacy` before submission. The standalone
deletion-request page in `web/account-deletion/index.html` must be published at
`https://keepkidswrestling.com/Snap-and-go/account-deletion`.

## Common declarations

- Data is used for app functionality, account management, security, fraud or
  abuse prevention, and purchase verification—not advertising.
- The app does not sell data or track users across other companies' apps and
  websites.
- Data sent to Firebase, Apple, and Google is encrypted in transit.
- The app offers an in-app account deletion flow and a data export flow under
  **Settings > Account**.
- Account-linked data is retained while the account is active and deleted on
  account deletion, subject to security/legal exceptions and service-provider
  backup deletion that may take up to 180 days.
- The product decision is **13+ general audience**, not Google Play Families
  and not Apple's Kids category. A neutral age-range screen appears before
  onboarding. An under-13 selection is restricted to local training mode;
  Firebase-connected services and store purchases are not initialized for
  that path. See `docs/age_audience_decision.md` for the release-blocking
  decision and exact console selections.

## Apple privacy manifest and App Store Connect

`ios/Runner/PrivacyInfo.xcprivacy` declares the following app-collected data.
In App Store Connect, select the matching categories as **Data Linked to You**,
used for **App Functionality**, and **not used for tracking**.

| App Store category | Data type | Why it is collected |
| --- | --- | --- |
| Contact Info | Name | Display name and team/social profile |
| Contact Info | Email Address | Authentication and account management |
| Health & Fitness | Fitness | Linked progress, workout shares, schedules, completions, streaks, and badges |
| User Content | Emails or Text Messages | Optional message attached to a shared workout |
| User Content | Photos or Videos | Profile-provider photo and uploaded team photo; workout videos remain local |
| User Content | Other User Content | Team name/state, reactions, schedules, and social content |
| Identifiers | User ID | Firebase UID, username, relationships, and account ownership |
| Identifiers | Device ID | Random installation record, Firebase installation ID, and push token |
| Purchases | Purchase History | Product, transaction/purchase credential, entitlement, expiry, and renewal state |
| Usage Data | Product Interaction | Account-linked social action and notification-state events |

Answer **No** to tracking and keep `NSPrivacyTracking` false. Do not list
payment information: payment details are entered with Apple/Google and are not
available to the developer. Do not list audio data or uploaded workout video:
those files remain on-device in the current build. Third-party SDK privacy
manifests still need to be present in the release archive; generate Xcode's
privacy report and compare it with this table before upload.

## Google Play Data Safety

### Top-level answers

| Question | Answer for the current build |
| --- | --- |
| Does the app collect or share required user-data types? | **Yes — collects data** |
| Is user data encrypted in transit? | **Yes** |
| Can users request deletion? | **Yes — in-app Settings > Account > Delete account, plus the public web request page** |
| Does the app share user data? | **No**, assuming Firebase/Google/Apple remain contracted service providers and only user-directed teammate/recipient disclosure occurs |
| Does the app independently review against a security standard? | **No**, unless the developer has obtained a qualifying independent review |

Google Play's definition of collection includes data transmitted off-device,
including data sent by SDKs and data processed ephemerally. For every row
below choose **Collected**, **not shared**, **optional**, and the listed
purposes. "Optional" is accurate because the core local workout experience is
available without an account; the data may be required to use the specific
connected feature.

| Google Play category | Data type | Processing | Purposes to select |
| --- | --- | --- | --- |
| Personal info | Name | Stored, account-linked | App functionality; Account management |
| Personal info | Email address | Stored by authentication/account systems | App functionality; Account management; Fraud prevention, security, and compliance |
| Personal info | User IDs | Stored, account-linked | App functionality; Account management; Fraud prevention, security, and compliance |
| Photos and videos | Photos | Team photo stored; profile photo URL may come from sign-in provider | App functionality |
| Messages | Other in-app messages | Optional shared-workout message stored | App functionality |
| Other content | Other user-generated content | Team details, reactions, and shared-workout content stored | App functionality |
| Health and fitness | Fitness info | Workout configuration, progress, completions, streaks, and badges stored when connected | App functionality |
| Financial info | Purchase history | Store transaction/purchase credential and subscription state stored | App functionality; Account management; Fraud prevention, security, and compliance |
| App activity | App interactions | Social actions, share status, and notification state stored | App functionality; Fraud prevention, security, and compliance |
| Device or other IDs | Device or other IDs | App/Firebase installation IDs and push token stored | App functionality; Fraud prevention, security, and compliance |

## Release verification

Before each store submission:

1. Publish the current public privacy policy and deletion-request page. Confirm
   both load without authentication and that the deletion page's prefilled
   email request works on mobile and desktop.
2. Enter `https://keepkidswrestling.com/Snap-and-go/account-deletion` as Google Play's
   account-deletion URL, then confirm App Store Connect and Google Play Console
   answers exactly match the tables above; console-only forms cannot be changed
   from this repository.
3. Generate and inspect the Xcode privacy report for third-party SDK additions.
4. Review `pubspec.lock`, Android merged manifests, iOS permissions, Firebase
   products, backend collections, and Cloud Functions for new collection.
5. Exercise team-code joining, team-photo replacement/deletion, data export,
   account deletion (including staged photos and server-only qualification
   records), device-token cleanup, and purchase deletion in the production-like
   environment.
6. Confirm Firebase database/storage locations, TTL policies, backup behavior,
   processor contracts, and access controls still support the public policy.
7. Confirm the Google target audience includes only 13+ groups, Families is
   not selected, the Apple submission is outside the Kids category with a 13+
   minimum age, and listing assets do not target children under 13. Exercise
   both branches of the neutral age screen on clean installs.
