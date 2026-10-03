# Firestore social schema

## Current team sharing model

Settings now opens **My Team**. An account can create one team with a name,
state, and photo, or join one by access code. `teams/{teamId}` holds its public
details and status. `teams/{teamId}/members/{uid}` is the team roster, while
`users/{uid}/privateData/team` is the authoritative one-team membership used
by workout delivery. The creator has the `owner` role; joined accounts have the
`member` role. All membership and team writes use callable Functions.

`teams/{teamId}/private/access` holds the stable creator-readable code.
`teamCodes/{sha256(normalizedCode)}` is a server-only lookup. Editing team info
never changes the code. Deletion invalidates it and removes all members;
joined accounts can leave without changing team details. Photos are uploaded
temporarily to `teamPhotoUploads/{uid}` and moved by the server to
`teamPhotos/{teamId}`. Storage rules allow team members to load that photo.

New workout shares record `teamId`. The `sendWorkout` transaction requires an
active team and verifies every recipient's current membership. Old shares stay
in their sender and recipient histories after a member leaves or a team is
deleted. Friendship data below supports legacy shares and account cleanup; new
sharing uses team membership and no longer uses friend requests.

Step 4 adds the data boundary for Snap & Go's friend-workout experience. Local
workouts remain independent of Firebase; these collections are used only after
an account signs in to a social feature.

## Collections

### `users/{uid}`

- `displayName`, `photoUrl`, `username`, `usernameNormalized`
- `language`: `en` or `es`
- `discoverable`: whether the athlete can be found
- `accountSafety`: `allowFriendRequests` and `allowWorkoutMessages`
- `unreadSharedWorkoutCount`: maintained only by trusted Functions
- `createdAt`, `updatedAt`

Email addresses never belong in this document. Private
account data remains under `users/{uid}/privateData/account`. The full user
document is owner-readable only; connected friends use `safeProfiles/{uid}`.

### `users/{uid}/devices/{tokenId}`

- `fcmToken`, `platform`, `lastActiveAt`

`tokenId` is a random, stable installation ID—not the FCM token. The signed-in
owner can register and remove their own devices. Functions use the tokens to
notify recipients and delete invalid registrations.

### `friendships/{pairId}`

- `userIds`: sorted two-item UID array
- `requestedBy`, `status`: `pending`, `accepted`, or `blocked`
- `blockedBy`, `createdAt`, `acceptedAt`, `updatedAt`

`pairId` is the SHA-256 digest of the two sorted UIDs. Clients can read their
own connections, but request, accept, and block mutations are callable
Functions so a client cannot manufacture an accepted friendship.

### `workoutShares/{shareId}`

- `senderUid`, `recipientUid`, `workoutSourceKey`
- `workoutSnapshot`: portable, versioned workout data
- `senderMessage`, `status`
- `sentAt`, `acceptedAt`, `scheduledFor`, `startedAt`, `completedAt`,
  `declinedAt`
- `recipientReadAt`, `recipientResultSummary`, `scheduledReminderSentAt`,
  `updatedAt`

Statuses advance through `sent -> accepted -> scheduled -> started ->
completed`; scheduling is optional, so an accepted workout may start directly.
`declined` is a terminal status that removes the share from the recipient inbox.
Only the sender and recipient can read a share. All writes pass through trusted
Functions.

The share document ID is a SHA-256 idempotency key derived by the callable from
the sender UID, recipient UID, and workout source key. Repeated calls return the
existing share and its current status without creating another event,
notification, unread increment, or streak/stat update.

The current workout snapshot schema is version 2:

- `title`: localized `en` and `es` values
- `sourceType`: `preset` or `custom`; preset snapshots include `presetId` when
  the originating format recorded it
- `durationSeconds`, `difficulty`, and `intervalRange`
- `enabledCalloutIds` and resolved `timedCalloutDurations`
- allowlisted `customWorkoutConfiguration` for custom workouts
- localized `purpose` and a display `category`

The Flutter model migrates unversioned prototypes and version 1 Step 4 shares
when reading them. The trusted backend accepts those legacy formats and stores
new shares in the canonical version 2 shape. Unsupported future versions fail
explicitly instead of being misinterpreted.

The workout definition is embedded in every share on purpose. This duplicates
a small payload, but makes the share immutable, avoids a second read for every
inbox card, preserves custom workouts if the sender later edits them, and keeps
the recipient independent of sender-owned files. Local recording paths, custom
audio paths, video settings, and purchases are stripped before storage.

### `socialEvents/{eventId}`

- `type`: `workout_sent`, `workout_accepted`, `workout_completed`,
  `workout_declined`, or `reaction`
- `actorUid`, `targetUid`, sorted `userIds`, `workoutShareId`
- optional `reaction`, plus `createdAt`

Events are immutable and backend-written. Participants can read their events;
clients cannot edit or delete them.

### `socialStats/{uid}`

- `relayStreak`, `friendWorkoutStreak`, `partnerStreaks`, `crewStreak`
- `totalSharedWorkouts`, `totalQualifiedRelays`,
  `totalCompletedFriendWorkouts`, `totalPartnerWeeks`, `totalCrewWeeks`
- `socialProgressPoints`, `socialBadges`
- backend bookkeeping: `lastRelayDate`, `lastFriendWorkoutDate`,
  `partnerLastCompletedWeeks`, `lastCrewWeek`, `updatedAt`

Stats and badges are derived in the same trusted transaction as the qualifying
share action. Clients can read only their own stats and cannot write them.
Sending increments only `totalSharedWorkouts`; it awards no social points.
An accepted relay earns 2 points, a friend-workout completion earns 12, a
qualified partner week earns 6, and a qualified crew week earns 8.

### Server-only social qualification records

- `socialQualifications/{sender-recipient-date}` allows one relay
  qualification per sender/recipient UTC day.
- `socialPartnerWeeks/{pair-week}` records which partner completed a received
  share in the server UTC week and qualifies only after both have done so.
- `socialCrewProgress/{sender-source-week}` records distinct accepted friends
  completing the same shared workout source and qualifies at three friends.

All dates and Monday-based week keys are calculated inside Cloud Functions.
Clients cannot read or write these bookkeeping collections. Transactions make
completion retries and concurrent partner/crew completions idempotent.

### Private friend-profile access

- `safeProfiles/{uid}` contains only display name, photo URL, username, and
  language. Owners maintain the non-sensitive projection; username changes are
  coordinated by the trusted `claimUsername` Function.
- `users/{uid}/friendAccess/{friendUid}` is a trusted, unreadable access proof
  written when a friendship is accepted and removed when either user blocks.

Clients read the full `users/{uid}` document only for their own account. A
connected friend can read only the `safeProfiles` projection. The idempotent
`syncFriendAccess` callable backfills access proofs for friendships accepted
before these rules were introduced.

### `users/{senderUid}/privateData/workoutSends_{UTC date}`

- `date`, `totalSends`, and a `recipientCounts` map
- `updatedAt` and `expiresAt` for operational cleanup

This server-only document enforces 50 new workout shares per UTC day and five
new shares to one recipient per UTC day. Existing idempotent shares do not
consume another slot. Firestore rules deny all client access to this data.

## Trusted callable API

- Friendship: `sendFriendRequest`, `acceptFriendRequest`, `blockUser`
- Sharing: `sendWorkout`, `markWorkoutSharesRead`
- Lifecycle: `acceptWorkoutShare`, `scheduleWorkoutShare`,
  `removeWorkoutSchedule`, `startWorkoutShare`, `saveWorkoutShare`,
  `declineWorkoutShare`, `completeWorkoutShare`
- Engagement: `reactToWorkoutShare`

Every callable requires authentication. App Check tokens are monitored during
the initial rollout and become mandatory when `ENFORCE_APP_CHECK` is enabled;
see `docs/app_check_rollout.md`. Firestore rules deny client writes to
friendships, events, stats, and authoritative share fields.
Recipients may directly change only the allowlisted share status and
`scheduledFor` choice; Functions own all lifecycle timestamps and results.
`sendWorkout` accepts up to 20 unique recipient IDs and creates all new shares,
unread increments, immutable events, rate counters, and trusted streak totals in
one transaction. `sendWorkoutShare` remains only as a single-recipient
backward-compatibility alias for older app versions.

The Shared Workouts inbox uses separate status-filtered queries for New,
Scheduled, and Completed. Each section loads 20 documents at a time using a
document cursor. A separate listener observes only the 20 newest unread shares;
it is merged into the paginated state so older history does not keep a live
listener open. Sender profiles are loaded for the visible page, and cached
Firestore results remain usable while offline.

Received snapshots are converted back into portable `DrillConfig` values. The
active `workoutShareId` is captured with the immutable drill session, marked
`started` at the starting bell, and passed to the summary. Completion writes
the elapsed seconds, completed callout count, server completion timestamp,
immutable completion event, and recipient stats in one transaction. A retry
against an already completed share returns without creating another event or
incrementing streaks.

Scheduling stores an absolute `scheduledFor` timestamp through the trusted
callable. Scheduled queries are ordered by the next workout time and completed
queries by completion time. The existing workout reminder service creates a
stable local notification ten minutes before the workout when permission is
available. It names both the sender and workout. Rescheduling replaces that
reminder, while removing the schedule, starting, saving, or declining cancels
it. Notification payloads are view-only: opening one never calls an acceptance
transition. This reminder path does not require a paid scheduled Cloud Function.
Deploy `firestore.rules`, `firestore.indexes.json`, and the Functions together
so the client and backend contracts stay aligned.

## Push notifications and deep links

Trusted Functions send FCM notifications for a new workout, the recipient's
first acceptance, completion, and a fist-bump reaction. Every payload contains
only string data with `type`, `shareId`, and a
`snapandgo://workout/{shareId}` deep link. The Flutter client handles foreground
messages with an actionable in-app banner, background taps with
`onMessageOpenedApp`, and terminated launches with `getInitialMessage`. The
top-level background handler initializes Firebase without trying to navigate.

The same workout route is used by app links and local scheduled reminders. It
loads the exact share after checking that the signed-in user is a participant;
sender-facing shares are read-only while recipient actions remain explicit.
Opening any notification only navigates and never changes acceptance or read
state by itself.

`sendScheduledWorkoutReminders` is an optional five-minute scheduled Function.
It is not exported unless the Functions environment contains
`ENABLE_SCHEDULED_WORKOUT_PUSH=true`, so the default deployment creates no
recurring scheduler job. When enabled, it atomically claims due shares through
`scheduledReminderSentAt` before sending an FCM reminder, preventing repeated
sends across overlapping runs. Keep it disabled when using only the
device-local reminder from Step 13.
