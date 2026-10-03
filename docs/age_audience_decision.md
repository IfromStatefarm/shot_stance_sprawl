# Age audience and minors compliance decision

**Decision date:** September 24, 2026  
**Release owner:** Keep Kids Wrestling

## Decision

Snap & Go is a general wrestling-training app for users age 13 and older. It
is not enrolled in Google Play Families and must not be submitted to Apple's
Kids category. Store listing text, screenshots, ads, and audience selections
must not present children under 13 as the intended audience.

Because the Keep Kids Wrestling brand and wrestling content may still attract
younger users, the app presents a neutral, one-time age-range screen before
onboarding. Both choices have equal visual weight and the screen does not
describe a reward for choosing the older range.

- **Under 13:** local training mode only. The user may run workouts and keep
  local progress, settings, photos, audio callouts, and review recordings on
  the device. The app does not initialize Firebase-connected services or the
  store purchase flow for this path.
- **13 or older:** account, team, social sharing, cloud, push, and
  purchase features may be used. Their normal permission and sign-in gates
  still apply.

Snap & Go does not claim to have verified parental consent, a parent dashboard,
or an adult-controlled child social account. Therefore an under-13 user cannot
create an account or enable social, cloud, notification, or
purchase features. Adding any of those capabilities for children is a new
product and legal decision, not a store-metadata-only change.

## Store configuration

### Google Play

- In **Target audience and content**, select only **13-15**, **16-17**, and
  **18 and over** as applicable to the actual listing and distribution plan.
- Do not select age groups under 13 and do not opt in to Families.
- Disclose the social features accurately in the IARC/content-rating
  questionnaire even though they are behind the 13+ gate.
- Keep Data Safety answers aligned with `docs/store_privacy_disclosures.md`.
- Review every listing asset for child-directed imagery or wording before each
  submission. Google may assess the audience from the listing and product,
  not only from the selected console boxes.

### Apple

- Do not submit to the Kids category.
- In the age-rating questionnaire, disclose messaging/social capabilities,
  user-generated content, accounts, and in-app purchases. Apply a **13+**
  minimum override if the questionnaire would otherwise produce a lower age.
- Keep the privacy labels aligned with
  `docs/store_privacy_disclosures.md`.

## Release-blocking invariants

The following checks block release:

1. A clean install and any install without a stored age decision must show the
   neutral age screen before onboarding or home.
2. The under-13 path must not initialize Firebase Messaging, show sign-in,
   open team/social features, accept social deep links, query store
   products, or start/restore a purchase.
3. Camera, microphone, photo, and workout files used in local mode must remain
   on-device unless the user is on the 13+ connected path and explicitly uses
   a separately gated upload or system share action.
4. Changing the target audience to include children under 13 requires, before
   release, a legal review plus appropriate parental consent, parental
   management, child-data controls, SDK review, social-safety controls, revised
   disclosures, and new tests.

Policy references:

- [Google Play Families Policy](https://support.google.com/googleplay/android-developer/answer/9893335)
- [Apple child-safety guidance](https://developer.apple.com/kids/)
