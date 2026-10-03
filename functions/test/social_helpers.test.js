const test = require("node:test");
const assert = require("node:assert/strict");
const {
  pairId,
  workoutShareId,
  relayQualificationId,
  nextWorkoutSendRateState,
  nextDailyStreak,
  utcWeekKey,
  nextWeeklyStreak,
  migrateWorkoutSnapshot,
  sanitizeWorkoutSnapshot,
  sanitizeResultSummary,
  shouldApplyWorkoutCompletion,
  workoutSentStats,
  relayQualificationStats,
  recipientStats,
  partnerQualificationStats,
  crewQualificationStats,
  sanitizeReportReason,
  workoutNotificationTitle,
  socialNotificationData,
  socialNotificationCopy,
} = require("../social_helpers");

const validSnapshot = {
  schemaVersion: 2,
  title: {en: "Shot chain", es: "Cadena de ataques"},
  sourceType: "preset",
  presetId: "shot_chain",
  durationSeconds: 300,
  difficulty: 8,
  intervalRange: {minSeconds: 1, maxSeconds: 2},
  enabledCalloutIds: ["stance", "shot"],
  timedCalloutDurations: {shot: 15},
  purpose: {en: "Finish clean", es: "Termina bien"},
  category: "offense",
};

test("pair IDs are deterministic regardless of user order", () => {
  assert.equal(pairId("athlete-a", "athlete-b"), pairId("athlete-b", "athlete-a"));
  assert.notEqual(pairId("athlete-a", "athlete-b"), pairId("athlete-a", "athlete-c"));
});

test("workout share IDs are stable per sender, recipient, and source", () => {
  const first = workoutShareId("sender", "recipient", "mission:2026-08-10:a");
  assert.equal(
      first,
      workoutShareId("sender", "recipient", "mission:2026-08-10:a"));
  assert.notEqual(
      first,
      workoutShareId("sender", "other", "mission:2026-08-10:a"));
  assert.notEqual(
      first,
      workoutShareId("recipient", "sender", "mission:2026-08-10:a"));
  assert.notEqual(
      first,
      workoutShareId("sender", "recipient", "mission:2026-08-11:a"));
});

test("relay qualifications allow only one sender-recipient key per UTC day", () => {
  const first = relayQualificationId("sender", "recipient", "2026-08-10");
  assert.equal(
      first,
      relayQualificationId("sender", "recipient", "2026-08-10"));
  assert.notEqual(
      first,
      relayQualificationId("sender", "recipient", "2026-08-11"));
  assert.notEqual(
      first,
      relayQualificationId("sender", "another", "2026-08-10"));
});

test("social notifications use typed deep-link payloads", () => {
  const types = [
    "workout_received",
    "workout_accepted",
    "workout_completed",
    "fist_bump",
    "scheduled_workout_reminder",
  ];
  for (const type of types) {
    assert.deepEqual(socialNotificationData(type, "share-123"), {
      type,
      shareId: "share-123",
      deepLink: "snapandgo://workout/share-123",
    });
  }
  assert.throws(
      () => socialNotificationData("unknown", "share-123"),
      /Unsupported/);
});

test("social notification copy names the actor and workout", () => {
  const workoutTitle = workoutNotificationTitle(validSnapshot);
  const accepted = socialNotificationCopy("workout_accepted", {
    actorName: "Jordan",
    workoutTitle,
  });
  const completed = socialNotificationCopy("workout_completed", {
    actorName: "Jordan",
    workoutTitle,
  });
  const fistBump = socialNotificationCopy("fist_bump", {
    actorName: "Jordan",
    workoutTitle,
  });

  assert.equal(workoutTitle, "Shot chain");
  assert.match(accepted.body, /Jordan.*Shot chain/);
  assert.match(completed.body, /Jordan.*Shot chain/);
  assert.match(fistBump.title, /Jordan/);
});

test("server workout-send limits count only newly-created shares", () => {
  assert.deepEqual(nextWorkoutSendRateState({
    totalSends: 8,
    recipientCounts: {friend: 2},
  }, ["friend", "new-friend"]), {
    totalSends: 10,
    recipientCounts: {friend: 3, "new-friend": 1},
  });
  assert.deepEqual(nextWorkoutSendRateState({
    totalSends: 8,
    recipientCounts: {friend: 2},
  }, []), {
    totalSends: 8,
    recipientCounts: {friend: 2},
  });
});

test("server workout-send limits reject daily and per-friend abuse", () => {
  assert.throws(() => nextWorkoutSendRateState(
      {totalSends: 50}, ["friend"]), /Daily workout send limit/);
  assert.throws(() => nextWorkoutSendRateState({
    totalSends: 10,
    recipientCounts: {friend: 5},
  }, ["friend"]), /to this friend/);
});

test("user report reasons are allowlisted", () => {
  assert.equal(sanitizeReportReason(" Harassment "), "harassment");
  assert.throws(() => sanitizeReportReason("made-up-reason"), /supported/);
});

test("daily streaks increment once and reset after a gap", () => {
  assert.equal(nextDailyStreak(4, "2026-08-10", "2026-08-10"), 4);
  assert.equal(nextDailyStreak(4, "2026-08-09", "2026-08-10"), 5);
  assert.equal(nextDailyStreak(4, "2026-08-08", "2026-08-10"), 1);
});

test("weekly streaks use server UTC weeks and reset after a gap", () => {
  assert.equal(utcWeekKey(new Date("2026-08-12T23:59:00Z")), "2026-08-10");
  assert.equal(nextWeeklyStreak(2, "2026-08-03", "2026-08-10"), 3);
  assert.equal(nextWeeklyStreak(2, "2026-07-27", "2026-08-10"), 1);
  assert.equal(nextWeeklyStreak(2, "2026-08-10", "2026-08-10"), 2);
});

test("workout sanitizer retains only portable version 2 fields", () => {
  const clean = sanitizeWorkoutSnapshot({
    ...validSnapshot,
    customAudioPaths: {shot: "private.m4a"},
    videoEnabled: true,
  });
  assert.deepEqual(clean, validSnapshot);
  assert.equal(clean.customAudioPaths, undefined);
  assert.equal(clean.videoEnabled, undefined);
});

test("backend migrates and sanitizes version 1 shares", () => {
  const legacy = {
    schemaVersion: 1,
    titleEn: "Old custom drill",
    titleEs: "Entrenamiento anterior",
    purposeEn: "Still runnable",
    purposeEs: "Todavia funciona",
    category: "custom",
    totalDurationSeconds: 180,
    minIntervalSeconds: 2,
    maxIntervalSeconds: 4,
    calloutIds: ["stance", "sprawl"],
    calloutOverrideDurations: {stance: 20},
    difficulty: 5,
    customAudioPaths: {stance: "private.wav"},
  };
  const migrated = migrateWorkoutSnapshot(legacy);
  const clean = sanitizeWorkoutSnapshot(legacy);

  assert.equal(migrated.schemaVersion, 2);
  assert.equal(clean.schemaVersion, 2);
  assert.equal(clean.sourceType, "custom");
  assert.deepEqual(clean.enabledCalloutIds, ["stance", "sprawl"]);
  assert.deepEqual(clean.timedCalloutDurations, {stance: 20});
  assert.equal(clean.customAudioPaths, undefined);
  assert.deepEqual(clean.customWorkoutConfiguration, {adLibsEnabled: false});
});

test("workout sanitizer rejects invalid ranges and future versions", () => {
  assert.throws(() => sanitizeWorkoutSnapshot({
    ...validSnapshot,
    durationSeconds: 100000,
  }), /duration/);
  assert.throws(() => sanitizeWorkoutSnapshot({schemaVersion: 99}),
      /Unsupported/);
});

test("result summaries are bounded and normalized", () => {
  assert.deepEqual(sanitizeResultSummary({
    durationSeconds: 299.7,
    calloutsCompleted: 42,
    calloutCounts: {shot: 21, sprawl: 21},
  }), {
    durationSeconds: 300,
    calloutsCompleted: 42,
    calloutCounts: {shot: 21, sprawl: 21},
  });
});

test("workout completion applies once and retries become no-ops", () => {
  assert.equal(shouldApplyWorkoutCompletion("started"), true);
  assert.equal(shouldApplyWorkoutCompletion("completed"), false);
  assert.throws(
      () => shouldApplyWorkoutCompletion("accepted"),
      /Start this workout/);
});

test("social sends do not earn progress until a friend acts", () => {
  const sent = workoutSentStats({socialProgressPoints: 0}, 20);
  assert.equal(sent.totalSharedWorkouts, 20);
  assert.equal(sent.socialProgressPoints, 0);
  assert.ok(sent.socialBadges.includes("social_first_share"));

  const relay = relayQualificationStats({
    relayStreak: 2,
    lastRelayDate: "2026-08-09",
  }, "2026-08-10");
  assert.equal(relay.relayStreak, 3);
  assert.equal(relay.socialProgressPoints, 2);
  assert.ok(relay.socialBadges.includes("social_relay_3"));
});

test("completions outweigh relay qualifications and advance friend streaks", () => {
  const recipient = recipientStats({
    friendWorkoutStreak: 2,
    lastFriendWorkoutDate: "2026-08-09",
  }, "2026-08-10");
  assert.equal(recipient.friendWorkoutStreak, 3);
  assert.equal(recipient.socialProgressPoints, 12);
  assert.ok(recipient.socialBadges.includes("social_friend_streak_3"));
});

test("partner and crew streaks qualify by consecutive server weeks", () => {
  const partner = partnerQualificationStats({
    partnerStreaks: {friend: 1},
    partnerLastCompletedWeeks: {friend: "2026-08-03"},
  }, "friend", "2026-08-10");
  assert.equal(partner.partnerStreaks.friend, 2);
  assert.equal(partner.socialProgressPoints, 6);
  assert.ok(partner.socialBadges.includes("social_partner_2"));

  const crew = crewQualificationStats({
    crewStreak: 2,
    lastCrewWeek: "2026-08-03",
  }, "2026-08-10");
  assert.equal(crew.crewStreak, 3);
  assert.equal(crew.socialProgressPoints, 8);
  assert.ok(crew.socialBadges.includes("social_crew_3"));

  const duplicateWeek = crewQualificationStats(crew, "2026-08-10");
  assert.equal(duplicateWeek.totalCrewWeeks, crew.totalCrewWeeks);
  assert.equal(duplicateWeek.socialProgressPoints, crew.socialProgressPoints);
});
