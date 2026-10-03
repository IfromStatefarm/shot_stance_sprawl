const {createHash} = require("node:crypto");

function pairId(firstUid, secondUid) {
  return createHash("sha256")
      .update([String(firstUid), String(secondUid)].sort().join("\u0000"))
      .digest("hex");
}

function workoutShareId(senderUid, recipientUid, workoutSourceKey) {
  return createHash("sha256")
      .update([
        String(senderUid),
        String(recipientUid),
        String(workoutSourceKey),
      ].join("\u0000"))
      .digest("hex");
}

function utcDateKey(value = new Date()) {
  return new Date(value).toISOString().slice(0, 10);
}

function relayQualificationId(senderUid, recipientUid, date = utcDateKey()) {
  return workoutShareId(senderUid, recipientUid, `relay:${date}`);
}

function nextWorkoutSendRateState(
    existing = {}, recipientUids = [],
    {maxDaily = 50, maxPerRecipient = 5} = {}) {
  const totalSends = Math.max(0, Number(existing.totalSends) || 0);
  const recipientCounts = {...objectMap(existing.recipientCounts)};
  if (totalSends + recipientUids.length > maxDaily) {
    throw new Error(`Daily workout send limit of ${maxDaily} reached.`);
  }
  for (const recipientUid of recipientUids) {
    const prior = Math.max(0, Number(recipientCounts[recipientUid]) || 0);
    if (prior + 1 > maxPerRecipient) {
      throw new Error(
          `Daily workout send limit to this friend of ${maxPerRecipient} reached.`);
    }
    recipientCounts[recipientUid] = prior + 1;
  }
  return {
    totalSends: totalSends + recipientUids.length,
    recipientCounts,
  };
}

function nextDailyStreak(current, lastDate, today = utcDateKey()) {
  if (lastDate === today) return Math.max(1, Number(current) || 0);
  const yesterday = new Date(`${today}T00:00:00.000Z`);
  yesterday.setUTCDate(yesterday.getUTCDate() - 1);
  return lastDate === utcDateKey(yesterday) ? (Number(current) || 0) + 1 : 1;
}

function utcWeekKey(value = new Date()) {
  const date = new Date(value);
  const day = date.getUTCDay() || 7;
  date.setUTCHours(0, 0, 0, 0);
  date.setUTCDate(date.getUTCDate() - day + 1);
  return utcDateKey(date);
}

function nextWeeklyStreak(current, lastWeek, week = utcWeekKey()) {
  if (lastWeek === week) return Math.max(1, Number(current) || 0);
  const previousWeek = new Date(`${week}T00:00:00.000Z`);
  previousWeek.setUTCDate(previousWeek.getUTCDate() - 7);
  return lastWeek === utcWeekKey(previousWeek) ?
    (Number(current) || 0) + 1 : 1;
}

function cleanText(value, name, {required = true, max = 120} = {}) {
  const text = String(value ?? "").trim();
  if (required && !text) throw new Error(`${name} is required.`);
  if (text.length > max) throw new Error(`${name} is too long.`);
  return text;
}

function finiteNumber(value, name, min, max) {
  const number = Number(value);
  if (!Number.isFinite(number) || number < min || number > max) {
    throw new Error(`${name} is outside the supported range.`);
  }
  return number;
}

function objectMap(value) {
  return value && typeof value === "object" && !Array.isArray(value) ? value : {};
}

function migrateWorkoutSnapshot(value) {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new Error("workoutSnapshot is required.");
  }
  const version = value.schemaVersion == null ? 0 : Number(value.schemaVersion);
  if (!Number.isInteger(version) || version < 0 || version > 2) {
    throw new Error(`Unsupported workout snapshot version ${value.schemaVersion}.`);
  }
  if (version === 2) return {...value};

  let legacy = {...value};
  if (version === 0) {
    const oldTitle = objectMap(value.title);
    const oldPurpose = objectMap(value.purpose);
    const oldIntervals = objectMap(value.intervalRange);
    legacy = {
      schemaVersion: 1,
      titleEn: value.titleEn ?? value.workoutTitle ?? oldTitle.en ?? value.title,
      titleEs: value.titleEs ?? oldTitle.es,
      purposeEn: value.purposeEn ?? oldPurpose.en ?? value.purpose,
      purposeEs: value.purposeEs ?? oldPurpose.es,
      category: value.category ?? "custom",
      presetId: value.presetId ?? value.activeWorkoutPresetId,
      totalDurationSeconds: value.totalDurationSeconds ?? value.durationSeconds,
      minIntervalSeconds: value.minIntervalSeconds ?? oldIntervals.minSeconds,
      maxIntervalSeconds: value.maxIntervalSeconds ?? oldIntervals.maxSeconds,
      calloutIds: value.calloutIds ?? value.enabledCalloutIds,
      calloutOverrideDurations:
        value.calloutOverrideDurations ?? value.timedCalloutDurations,
      difficulty: value.difficulty,
      adLibsEnabled: value.adLibsEnabled,
      customWorkoutConfiguration: value.customWorkoutConfiguration,
    };
  }

  const category = typeof legacy.category === "string" ? legacy.category : "custom";
  const presetId = typeof legacy.presetId === "string" && legacy.presetId.trim() ?
    legacy.presetId.trim() : undefined;
  const sourceType = legacy.sourceType === "preset" || legacy.sourceType === "custom" ?
    legacy.sourceType : (presetId || category !== "custom" ? "preset" : "custom");
  return {
    schemaVersion: 2,
    title: {
      en: legacy.titleEn ?? "Shared workout",
      es: legacy.titleEs ?? legacy.titleEn ?? "Entrenamiento compartido",
    },
    sourceType,
    ...(presetId ? {presetId} : {}),
    durationSeconds: legacy.totalDurationSeconds ?? 60,
    difficulty: legacy.difficulty ?? 5,
    intervalRange: {
      minSeconds: legacy.minIntervalSeconds ?? 2,
      maxSeconds: legacy.maxIntervalSeconds ?? 4,
    },
    enabledCalloutIds: legacy.calloutIds ?? [],
    timedCalloutDurations: legacy.calloutOverrideDurations ?? {},
    ...(sourceType === "custom" ? {
      customWorkoutConfiguration: legacy.customWorkoutConfiguration ?? {
        adLibsEnabled: legacy.adLibsEnabled === true,
      },
    } : {}),
    purpose: {
      en: legacy.purposeEn ?? "",
      es: legacy.purposeEs ?? legacy.purposeEn ?? "",
    },
    category,
  };
}

function sanitizeWorkoutSnapshot(value) {
  const migrated = migrateWorkoutSnapshot(value);
  const title = objectMap(migrated.title);
  const purpose = objectMap(migrated.purpose);
  const intervalRange = objectMap(migrated.intervalRange);
  const sourceType = migrated.sourceType;
  if (sourceType !== "preset" && sourceType !== "custom") {
    throw new Error("sourceType must be preset or custom.");
  }
  const presetId = migrated.presetId == null ? "" :
    cleanText(migrated.presetId, "preset ID", {required: false, max: 128});
  const calloutIds = [...new Set(Array.isArray(migrated.enabledCalloutIds) ?
    migrated.enabledCalloutIds.map((id) =>
      cleanText(id, "callout ID", {max: 64})) : [])];
  if (!calloutIds.length || calloutIds.length > 100 ||
      calloutIds.some((id) => !/^[a-zA-Z0-9_-]+$/.test(id))) {
    throw new Error("Choose between 1 and 100 valid workout callouts.");
  }
  const minIntervalSeconds = finiteNumber(
      intervalRange.minSeconds, "minimum interval", 0.25, 60);
  const maxIntervalSeconds = finiteNumber(
      intervalRange.maxSeconds, "maximum interval", minIntervalSeconds, 60);
  const rawOverrides = migrated.timedCalloutDurations;
  const timedCalloutDurations = {};
  if (rawOverrides && typeof rawOverrides === "object" && !Array.isArray(rawOverrides)) {
    for (const [id, duration] of Object.entries(rawOverrides)) {
      if (!calloutIds.includes(id)) continue;
      timedCalloutDurations[id] = Math.round(
          finiteNumber(duration, "callout duration", 1, 600));
    }
  }
  const rawCustomConfiguration = objectMap(migrated.customWorkoutConfiguration);
  if (rawCustomConfiguration.adLibsEnabled != null &&
      typeof rawCustomConfiguration.adLibsEnabled !== "boolean") {
    throw new Error("adLibsEnabled must be true or false.");
  }
  const snapshot = {
    schemaVersion: 2,
    title: {
      en: cleanText(title.en, "English title", {max: 80}),
      es: cleanText(title.es ?? title.en, "Spanish title", {max: 80}),
    },
    sourceType,
    ...(presetId ? {presetId} : {}),
    durationSeconds: Math.round(finiteNumber(
        migrated.durationSeconds, "workout duration", 10, 7200)),
    difficulty: Math.round(finiteNumber(
        migrated.difficulty, "difficulty", 1, 10)),
    intervalRange: {minSeconds: minIntervalSeconds, maxSeconds: maxIntervalSeconds},
    enabledCalloutIds: calloutIds,
    timedCalloutDurations,
    ...(sourceType === "custom" ? {
      customWorkoutConfiguration: {
        adLibsEnabled: rawCustomConfiguration.adLibsEnabled === true,
      },
    } : {}),
    purpose: {
      en: cleanText(purpose.en, "English purpose", {required: false, max: 240}),
      es: cleanText(purpose.es ?? purpose.en, "Spanish purpose",
          {required: false, max: 240}),
    },
    category: cleanText(migrated.category, "category", {max: 40}),
  };
  if (Buffer.byteLength(JSON.stringify(snapshot), "utf8") > 20000) {
    throw new Error("The shared workout is too large.");
  }
  return snapshot;
}

function sanitizeResultSummary(value) {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new Error("resultSummary is required.");
  }
  const rawCounts = value.calloutCounts;
  const calloutCounts = {};
  if (rawCounts && typeof rawCounts === "object" && !Array.isArray(rawCounts)) {
    const entries = Object.entries(rawCounts);
    if (entries.length > 100) throw new Error("Too many result callouts.");
    for (const [id, count] of entries) {
      const cleanId = cleanText(id, "result callout ID", {max: 64});
      calloutCounts[cleanId] = Math.round(
          finiteNumber(count, "callout count", 0, 100000));
    }
  }
  return {
    durationSeconds: Math.round(finiteNumber(
        value.durationSeconds, "result duration", 0, 14400)),
    calloutsCompleted: Math.round(finiteNumber(
        value.calloutsCompleted, "completed callouts", 0, 100000)),
    calloutCounts,
  };
}

function shouldApplyWorkoutCompletion(status) {
  if (status === "completed") return false;
  if (status !== "started") {
    throw new Error("Start this workout before completing it.");
  }
  return true;
}

function withSocialBadges(stats) {
  const badges = new Set(Array.isArray(stats.socialBadges) ?
    stats.socialBadges : []);
  if ((Number(stats.totalSharedWorkouts) || 0) >= 1) {
    badges.add("social_first_share");
  }
  if ((Number(stats.totalQualifiedRelays) || 0) >= 1) {
    badges.add("social_first_relay");
  }
  if ((Number(stats.relayStreak) || 0) >= 3) badges.add("social_relay_3");
  if ((Number(stats.relayStreak) || 0) >= 7) badges.add("social_relay_7");
  if ((Number(stats.totalCompletedFriendWorkouts) || 0) >= 1) {
    badges.add("social_friend_finisher");
  }
  if ((Number(stats.friendWorkoutStreak) || 0) >= 3) {
    badges.add("social_friend_streak_3");
  }
  if ((Number(stats.friendWorkoutStreak) || 0) >= 7) {
    badges.add("social_friend_streak_7");
  }
  const bestPartner = Math.max(
      0, ...Object.values(stats.partnerStreaks || {}).map(Number));
  if (bestPartner >= 2) badges.add("social_partner_2");
  if (bestPartner >= 5) badges.add("social_partner_5");
  if ((Number(stats.totalCrewWeeks) || 0) >= 1) badges.add("social_crew_1");
  if ((Number(stats.crewStreak) || 0) >= 3) badges.add("social_crew_3");
  if ((Number(stats.socialProgressPoints) || 0) >= 100) {
    badges.add("social_century");
  }
  return {...stats, socialBadges: [...badges].sort()};
}

function workoutSentStats(existing = {}, count = 1) {
  return withSocialBadges({
    ...existing,
    totalSharedWorkouts: (Number(existing.totalSharedWorkouts) || 0) +
      Math.max(0, Number(count) || 0),
  });
}

function relayQualificationStats(existing = {}, today = utcDateKey()) {
  return withSocialBadges({
    ...existing,
    relayStreak: nextDailyStreak(
        existing.relayStreak, existing.lastRelayDate, today),
    lastRelayDate: today,
    totalQualifiedRelays: (Number(existing.totalQualifiedRelays) || 0) + 1,
    socialProgressPoints: (Number(existing.socialProgressPoints) || 0) + 2,
  });
}

function recipientStats(existing = {}, today = utcDateKey()) {
  const friendWorkoutStreak = nextDailyStreak(
      existing.friendWorkoutStreak, existing.lastFriendWorkoutDate, today);
  const totalCompletedFriendWorkouts =
    (Number(existing.totalCompletedFriendWorkouts) || 0) + 1;
  return withSocialBadges({
    ...existing,
    friendWorkoutStreak,
    lastFriendWorkoutDate: today,
    totalCompletedFriendWorkouts,
    socialProgressPoints: (Number(existing.socialProgressPoints) || 0) + 12,
  });
}

function partnerQualificationStats(
    existing = {}, partnerUid, week = utcWeekKey()) {
  const partnerStreaks = {...(existing.partnerStreaks || {})};
  const partnerLastCompletedWeeks = {
    ...(existing.partnerLastCompletedWeeks || {}),
  };
  partnerStreaks[partnerUid] = nextWeeklyStreak(
      partnerStreaks[partnerUid], partnerLastCompletedWeeks[partnerUid], week);
  partnerLastCompletedWeeks[partnerUid] = week;
  return withSocialBadges({
    ...existing,
    partnerStreaks,
    partnerLastCompletedWeeks,
    totalPartnerWeeks: (Number(existing.totalPartnerWeeks) || 0) + 1,
    socialProgressPoints: (Number(existing.socialProgressPoints) || 0) + 6,
  });
}

function crewQualificationStats(existing = {}, week = utcWeekKey()) {
  if (existing.lastCrewWeek === week) return withSocialBadges(existing);
  return withSocialBadges({
    ...existing,
    crewStreak: nextWeeklyStreak(
        existing.crewStreak, existing.lastCrewWeek, week),
    lastCrewWeek: week,
    totalCrewWeeks: (Number(existing.totalCrewWeeks) || 0) + 1,
    socialProgressPoints: (Number(existing.socialProgressPoints) || 0) + 8,
  });
}

function sanitizeReportReason(value) {
  const reason = String(value ?? "").trim().toLowerCase();
  const supported = new Set([
    "spam",
    "harassment",
    "unsafe_content",
    "impersonation",
    "other",
  ]);
  if (!supported.has(reason)) throw new Error("Choose a supported report reason.");
  return reason;
}

const socialNotificationTypes = new Set([
  'workout_received',
  'workout_accepted',
  'workout_completed',
  'fist_bump',
  'scheduled_workout_reminder',
]);

function workoutNotificationTitle(snapshot) {
  const title = snapshot?.title;
  if (title && typeof title === 'object') {
    return String(title.en || title.es || 'Shared workout').trim()
        .slice(0, 80) || 'Shared workout';
  }
  return 'Shared workout';
}

function socialNotificationData(type, shareId) {
  if (!socialNotificationTypes.has(type)) {
    throw new Error('Unsupported social notification type.');
  }
  const normalizedShareId = String(shareId || '').trim();
  if (!normalizedShareId || normalizedShareId.length > 128) {
    throw new Error('A valid share ID is required.');
  }
  return {
    type,
    shareId: normalizedShareId,
    deepLink: `snapandgo://workout/${encodeURIComponent(normalizedShareId)}`,
  };
}

function socialNotificationCopy(
    type, {actorName = 'A friend', workoutTitle = 'Shared workout'} = {}) {
  const actor = String(actorName || 'A friend').trim().slice(0, 80) || 'A friend';
  const workout = String(workoutTitle || 'Shared workout')
      .trim().slice(0, 80) || 'Shared workout';
  switch (type) {
    case 'workout_received':
      return {
        title: `New workout from ${actor}`,
        body: `${workout} is waiting for you.`,
      };
    case 'workout_accepted':
      return {
        title: 'Workout accepted',
        body: `${actor} accepted ${workout}.`,
      };
    case 'workout_completed':
      return {
        title: 'Workout completed',
        body: `${actor} finished ${workout}.`,
      };
    case 'fist_bump':
      return {
        title: `Fist bump from ${actor}`,
        body: `${actor} reacted to ${workout}.`,
      };
    case 'scheduled_workout_reminder':
      return {
        title: 'Your team workout starts soon',
        body: `${workout} from ${actor} is ready.`,
      };
    default:
      throw new Error('Unsupported social notification type.');
  }
}

module.exports = {
  pairId,
  workoutShareId,
  relayQualificationId,
  utcDateKey,
  utcWeekKey,
  nextWorkoutSendRateState,
  nextDailyStreak,
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
};
