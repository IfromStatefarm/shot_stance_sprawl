const {readFileSync} = require("node:fs");
const {after, afterEach, before, test} = require("node:test");
const {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} = require("@firebase/rules-unit-testing");
const {
  collection,
  deleteDoc,
  doc,
  getDoc,
  getDocs,
  query,
  serverTimestamp,
  setDoc,
  Timestamp,
  updateDoc,
  where,
  writeBatch,
} = require("firebase/firestore");

const projectId = "demo-snap-and-go";
const rules = readFileSync("../firestore.rules", "utf8");
let environment;

before(async () => {
  environment = await initializeTestEnvironment({
    projectId,
    firestore: {rules},
  });
});

afterEach(async () => environment.clearFirestore());
after(async () => environment.cleanup());

function client(uid) {
  return environment.authenticatedContext(uid).firestore();
}

async function seed(path, data) {
  await environment.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), path), data);
  });
}

function profile(uid, overrides = {}) {
  const now = Timestamp.fromDate(new Date("2026-08-11T12:00:00Z"));
  return {
    displayName: `${uid} Athlete`,
    photoUrl: null,
    language: "en",
    discoverable: true,
    accountSafety: {
      allowFriendRequests: true,
      allowWorkoutMessages: true,
    },
    unreadSharedWorkoutCount: 0,
    createdAt: now,
    updatedAt: now,
    ...overrides,
  };
}

function share(overrides = {}) {
  const now = Timestamp.fromDate(new Date("2026-08-11T12:00:00Z"));
  return {
    senderUid: "alice",
    recipientUid: "bob",
    workoutSourceKey: "daily:2026-08-11",
    workoutSnapshot: {schemaVersion: 2},
    senderMessage: null,
    status: "sent",
    sentAt: now,
    acceptedAt: null,
    scheduledFor: null,
    startedAt: null,
    completedAt: null,
    recipientReadAt: null,
    recipientResultSummary: null,
    updatedAt: now,
    ...overrides,
  };
}

test("social documents reject unauthenticated access", async () => {
  await seed("users/alice", profile("alice"));
  await seed("friendships/alice-bob", {
    userIds: ["alice", "bob"], status: "accepted",
  });
  await seed("workoutShares/share-a", share());
  const db = environment.unauthenticatedContext().firestore();

  await assertFails(getDoc(doc(db, "users/alice")));
  await assertFails(getDoc(doc(db, "friendships/alice-bob")));
  await assertFails(getDoc(doc(db, "workoutShares/share-a")));
});

test("owners can read private profiles but other users cannot", async () => {
  await seed("users/alice", profile("alice", {
    unreadSharedWorkoutCount: 7,
  }));
  await seed("users/alice/privateData/account", {
    email: "alice@example.com",
    providers: ["password"],
    updatedAt: Timestamp.now(),
  });

  await assertSucceeds(getDoc(doc(client("alice"), "users/alice")));
  await assertSucceeds(getDoc(
      doc(client("alice"), "users/alice/privateData/account")));
  await assertFails(getDoc(doc(client("bob"), "users/alice")));
  await assertFails(getDoc(
      doc(client("bob"), "users/alice/privateData/account")));
  await assertFails(getDocs(collection(client("alice"), "users")));
});

test("account bootstrap permits only owner data with true server times", async () => {
  const db = client("alice");
  const batch = writeBatch(db);
  batch.set(doc(db, "users/alice"), {
    ...profile("alice"),
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
  });
  batch.set(doc(db, "safeProfiles/alice"), {
    displayName: "Alice Athlete",
    photoUrl: null,
    language: "en",
  });
  batch.set(doc(db, "users/alice/privateData/account"), {
    email: "alice@example.com",
    providers: ["password"],
    updatedAt: serverTimestamp(),
  });
  await assertSucceeds(batch.commit());

  await assertFails(setDoc(doc(client("bob"), "users/alice"), {
    ...profile("alice"),
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
  }));
  await assertFails(setDoc(doc(client("bob"), "users/bob"), {
    ...profile("bob"),
    createdAt: Timestamp.fromDate(new Date("2030-01-01T00:00:00Z")),
    updatedAt: Timestamp.fromDate(new Date("2030-01-01T00:00:00Z")),
  }));
});

test("only connected friends can read safe profiles", async () => {
  await seed("safeProfiles/alice", {
    displayName: "Alice", photoUrl: null, username: "alice", language: "en",
  });
  await seed("users/alice/friendAccess/bob", {
    friendUid: "bob", friendshipId: "pair", acceptedAt: Timestamp.now(),
  });

  await assertSucceeds(getDoc(doc(client("alice"), "safeProfiles/alice")));
  await assertSucceeds(getDoc(doc(client("bob"), "safeProfiles/alice")));
  await assertFails(getDoc(doc(client("mallory"), "safeProfiles/alice")));
  await assertFails(getDocs(collection(client("bob"), "safeProfiles")));
  await assertFails(getDoc(
      doc(client("bob"), "users/alice/friendAccess/bob")));
});

test("friendship queries work only when constrained to the signed-in user", async () => {
  await seed("friendships/alice-bob", {
    userIds: ["alice", "bob"], requestedBy: "alice", status: "accepted",
  });
  await assertSucceeds(getDocs(query(
      collection(client("alice"), "friendships"),
      where("userIds", "array-contains", "alice"))));
  await assertFails(getDocs(query(
      collection(client("mallory"), "friendships"),
      where("userIds", "array-contains", "alice"))));
});

test("only share participants can read a workout share", async () => {
  await seed("workoutShares/share-a", share());
  await assertSucceeds(getDoc(doc(client("alice"), "workoutShares/share-a")));
  await assertSucceeds(getDoc(doc(client("bob"), "workoutShares/share-a")));
  await assertFails(getDoc(doc(client("mallory"), "workoutShares/share-a")));
  await assertSucceeds(getDocs(query(
      collection(client("alice"), "workoutShares"),
      where("senderUid", "==", "alice"))));
  await assertSucceeds(getDocs(query(
      collection(client("bob"), "workoutShares"),
      where("recipientUid", "==", "bob"))));
  await assertFails(getDocs(query(
      collection(client("mallory"), "workoutShares"),
      where("recipientUid", "==", "bob"))));
});

test("recipient can update only status and scheduling choices", async () => {
  await seed("workoutShares/share-a", share());
  const ref = doc(client("bob"), "workoutShares/share-a");

  await assertSucceeds(updateDoc(ref, {
    status: "accepted",
    scheduledFor: null,
  }));

  await environment.clearFirestore();
  await seed("workoutShares/share-a", share());
  await assertSucceeds(updateDoc(ref, {
    status: "scheduled",
    scheduledFor: Timestamp.fromDate(
        new Date(Date.now() + 24 * 60 * 60 * 1000)),
  }));

  await environment.clearFirestore();
  await seed("workoutShares/share-a", share());
  await assertFails(updateDoc(ref, {
    status: "completed",
    completedAt: serverTimestamp(),
  }));
  await assertFails(updateDoc(
      doc(client("alice"), "workoutShares/share-a"),
      {status: "accepted"}));
  await assertFails(updateDoc(ref, {senderUid: "bob"}));
});

test("clients cannot alter unread counts or server timestamps", async () => {
  await seed("users/alice", profile("alice", {
    unreadSharedWorkoutCount: 4,
  }));
  const ref = doc(client("alice"), "users/alice");

  await assertFails(updateDoc(ref, {
    unreadSharedWorkoutCount: 0,
    updatedAt: serverTimestamp(),
  }));
  await assertFails(updateDoc(ref, {
    language: "es",
    updatedAt: Timestamp.fromDate(new Date("2030-01-01T00:00:00Z")),
  }));
  await assertSucceeds(updateDoc(ref, {
    language: "es",
    updatedAt: serverTimestamp(),
  }));
});

test("owners can initialize missing legacy fields but not replace counters", async () => {
  const legacy = profile("alice");
  delete legacy.createdAt;
  delete legacy.unreadSharedWorkoutCount;
  await seed("users/alice", legacy);
  const ref = doc(client("alice"), "users/alice");

  await assertSucceeds(updateDoc(ref, {
    createdAt: serverTimestamp(),
    unreadSharedWorkoutCount: 0,
    updatedAt: serverTimestamp(),
  }));
  await assertFails(updateDoc(ref, {
    unreadSharedWorkoutCount: 10,
    updatedAt: serverTimestamp(),
  }));
});

test("trusted social data and unknown collections are default-denied", async () => {
  await seed("socialStats/alice", {relayStreak: 3});
  await seed("socialEvents/event-a", {
    userIds: ["alice", "bob"], type: "workout_completed",
  });
  const db = client("alice");

  await assertSucceeds(getDoc(doc(db, "socialStats/alice")));
  await assertSucceeds(getDoc(doc(db, "socialEvents/event-a")));
  await assertFails(getDoc(doc(client("mallory"), "socialEvents/event-a")));
  await assertFails(updateDoc(doc(db, "socialStats/alice"), {relayStreak: 99}));
  await assertFails(setDoc(doc(db, "unexpected/document"), {value: true}));
});

test("team members can read their team and teammate profiles, not the code", async () => {
  await seed("teams/team-a", {
    name: "Mat Club", state: "Iowa", photoPath: "teamPhotos/team-a/photo",
    ownerUid: "alice", status: "active",
  });
  await seed("teams/team-a/members/alice", {uid: "alice", role: "owner"});
  await seed("teams/team-a/members/bob", {uid: "bob", role: "member"});
  await seed("teams/team-a/private/access", {code: "ABCD-1234-5678"});
  await seed("teamCodes/hash", {teamId: "team-a"});
  await seed("users/alice/privateData/team", {teamId: "team-a", role: "owner"});
  await seed("users/bob/privateData/team", {teamId: "team-a", role: "member"});
  await seed("safeProfiles/alice", {displayName: "Alice", photoUrl: null,
    language: "en"});
  await seed("safeProfiles/bob", {displayName: "Bob", photoUrl: null,
    language: "en"});

  await assertSucceeds(getDoc(doc(client("bob"), "teams/team-a")));
  await assertSucceeds(getDocs(collection(client("bob"), "teams/team-a/members")));
  await assertSucceeds(getDoc(doc(client("bob"), "safeProfiles/alice")));
  await assertSucceeds(getDoc(doc(client("alice"), "teams/team-a/private/access")));
  await assertFails(getDoc(doc(client("bob"), "teams/team-a/private/access")));
  await assertFails(getDoc(doc(client("mallory"), "teams/team-a")));
  await assertFails(getDoc(doc(client("mallory"), "safeProfiles/alice")));
  await assertFails(getDoc(doc(client("bob"), "teamCodes/hash")));
  await assertFails(setDoc(doc(client("bob"), "teams/team-a/members/mallory"),
      {uid: "mallory", role: "member"}));
  await assertFails(updateDoc(doc(client("bob"), "teams/team-a"),
      {name: "Hijacked"}));
});

test("leaving a team removes teammate profile access", async () => {
  await seed("teams/team-a", {status: "active"});
  await seed("teams/team-a/members/alice", {uid: "alice", role: "owner"});
  await seed("teams/team-a/members/bob", {uid: "bob", role: "member"});
  await seed("users/alice/privateData/team", {teamId: "team-a", role: "owner"});
  await seed("users/bob/privateData/team", {teamId: "team-a", role: "member"});
  await seed("safeProfiles/alice", {displayName: "Alice", photoUrl: null,
    language: "en"});
  await assertSucceeds(getDoc(doc(client("bob"), "safeProfiles/alice")));
  await environment.withSecurityRulesDisabled(async (context) => {
    await deleteDoc(doc(context.firestore(), "teams/team-a/members/bob"));
  });
  await assertFails(getDoc(doc(client("bob"), "safeProfiles/alice")));
});
