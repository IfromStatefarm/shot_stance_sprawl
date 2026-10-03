const {getMessaging} = require("firebase-admin/messaging");
const {FieldValue, Timestamp, getFirestore} = require("firebase-admin/firestore");
const {logger} = require("firebase-functions");
const {HttpsError, onCall} = require("firebase-functions/v2/https");
const {onSchedule} = require("firebase-functions/v2/scheduler");
const {enforceAppCheck} = require("./app_check");
const {
  pairId,
  workoutShareId,
  relayQualificationId,
  nextWorkoutSendRateState,
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
  utcDateKey,
  utcWeekKey,
} = require("./social_helpers");

const db = getFirestore();
const callableOptions = {enforceAppCheck};
const reactions = new Set([
  "clap", "fire", "strong", "respect", "rematch", "fist_bump",
]);
const maxWorkoutRecipientsPerRequest = 20;
const maxWorkoutSendsPerDay = 50;
const maxWorkoutSendsPerRecipientPerDay = 5;

function requireUid(request) {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Sign in first.");
  return uid;
}

function friendAccessRef(ownerUid, friendUid) {
  return db.collection("users").doc(ownerUid)
      .collection("friendAccess").doc(friendUid);
}

function friendAccessData(friendUid, friendshipId) {
  return {
    friendUid,
    friendshipId,
    acceptedAt: FieldValue.serverTimestamp(),
  };
}

function safeProfileData(value = {}) {
  const displayName = typeof value.displayName === "string" ?
    value.displayName.trim().slice(0, 80) : "Snap & Go athlete";
  const photoUrl = typeof value.photoUrl === "string" &&
      value.photoUrl.length <= 2048 ? value.photoUrl : null;
  const username = typeof value.username === "string" &&
      /^[a-z0-9_]{3,20}$/.test(value.username) ? value.username : null;
  const language = value.language === "es" ? "es" : "en";
  return {
    displayName: displayName || "Snap & Go athlete",
    photoUrl,
    ...(username ? {username} : {}),
    language,
  };
}

function inputText(value, name, {required = true, max = 128} = {}) {
  const text = String(value ?? "").trim();
  if (required && !text) {
    throw new HttpsError("invalid-argument", `${name} is required.`);
  }
  if (text.length > max) {
    throw new HttpsError("invalid-argument", `${name} is too long.`);
  }
  return text;
}

function asInvalidArgument(error) {
  if (error instanceof HttpsError) return error;
  return new HttpsError("invalid-argument", error.message || "Invalid request.");
}

function eventData(type, actorUid, targetUid, shareId, extra = {}) {
  return {
    type,
    actorUid,
    targetUid,
    userIds: [actorUid, targetUid].sort(),
    workoutShareId: shareId,
    createdAt: FieldValue.serverTimestamp(),
    ...extra,
  };
}

async function displayNameFor(uid) {
  const profile = await db.collection("users").doc(uid).get();
  return profile.data()?.displayName || "A friend";
}

async function notifySocialUpdate({
  recipientUid,
  type,
  shareId,
  actorName,
  workoutTitle,
}) {
  try {
    const devices = await db.collection("users").doc(recipientUid)
        .collection("devices").limit(500).get();
    if (devices.empty) return;
    const tokenDocuments = devices.docs.filter((document) =>
      typeof document.data().fcmToken === "string" && document.data().fcmToken);
    if (!tokenDocuments.length) return;
    const copy = socialNotificationCopy(type, {actorName, workoutTitle});
    const response = await getMessaging().sendEachForMulticast({
      tokens: tokenDocuments.map((document) => document.data().fcmToken),
      notification: copy,
      data: socialNotificationData(type, shareId),
      android: {
        priority: "high",
        notification: {
          channelId: "snap_go_social_notifications",
          sound: "default",
        },
      },
      apns: {
        headers: {"apns-priority": "10"},
        payload: {
          aps: {sound: "default"},
        },
      },
    });
    const invalidCodes = new Set([
      "messaging/invalid-registration-token",
      "messaging/registration-token-not-registered",
    ]);
    const cleanup = db.batch();
    let hasCleanup = false;
    response.responses.forEach((result, index) => {
      if (!result.success && invalidCodes.has(result.error?.code)) {
        cleanup.delete(tokenDocuments[index].ref);
        hasCleanup = true;
      }
    });
    if (hasCleanup) await cleanup.commit();
  } catch (error) {
    logger.warn("Social notification failed", {
      recipientUid, type, shareId, error,
    });
  }
}

exports.sendFriendRequest = onCall(callableOptions, async (request) => {
  const uid = requireUid(request);
  const username = inputText(request.data?.username, "username",
      {required: false, max: 20}).toLowerCase();
  let recipientUid = inputText(request.data?.recipientUid, "recipientUid",
      {required: false, max: 128});
  if (!recipientUid && username) {
    const usernameDocument = await db.collection("usernames").doc(username).get();
    recipientUid = usernameDocument.data()?.uid || "";
  }
  if (!recipientUid) {
    throw new HttpsError("not-found", "No account matches that friend invite.");
  }
  if (recipientUid === uid) {
    throw new HttpsError("invalid-argument", "You cannot add yourself.");
  }

  const profile = await db.collection("users").doc(recipientUid).get();
  if (!profile.exists || profile.data()?.discoverable === false ||
      profile.data()?.accountSafety?.allowFriendRequests === false) {
    throw new HttpsError("not-found", "That account is not accepting requests.");
  }
  const userIds = [uid, recipientUid].sort();
  const reference = db.collection("friendships").doc(pairId(uid, recipientUid));
  return db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(reference);
    const existingStatus = snapshot.data()?.status;
    if (existingStatus === "accepted") {
      transaction.set(
          friendAccessRef(uid, recipientUid),
          friendAccessData(recipientUid, reference.id));
      transaction.set(
          friendAccessRef(recipientUid, uid),
          friendAccessData(uid, reference.id));
      return {status: "already-friends"};
    }
    if (existingStatus === "pending") return {status: "already-pending"};
    if (existingStatus === "blocked") {
      throw new HttpsError("permission-denied", "This connection is blocked.");
    }
    transaction.set(reference, {
      userIds,
      requestedBy: uid,
      status: "pending",
      blockedBy: null,
      createdAt: FieldValue.serverTimestamp(),
      acceptedAt: null,
      updatedAt: FieldValue.serverTimestamp(),
    });
    return {status: "sent"};
  });
});

exports.acceptFriendRequest = onCall(callableOptions, async (request) => {
  const uid = requireUid(request);
  const friendshipId = inputText(request.data?.friendshipId, "friendshipId");
  const reference = db.collection("friendships").doc(friendshipId);
  await db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(reference);
    const data = snapshot.data();
    if (!data || !data.userIds?.includes(uid)) {
      throw new HttpsError("not-found", "Friend request not found.");
    }
    if (data.requestedBy === uid || data.status !== "pending") {
      throw new HttpsError("failed-precondition", "This request cannot be accepted.");
    }
    transaction.update(reference, {
      status: "accepted",
      acceptedAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
    const otherUid = data.userIds.find((memberUid) => memberUid !== uid);
    transaction.set(
        friendAccessRef(uid, otherUid),
        friendAccessData(otherUid, reference.id));
    transaction.set(
        friendAccessRef(otherUid, uid),
        friendAccessData(uid, reference.id));
  });
  return {status: "accepted"};
});

exports.blockUser = onCall(callableOptions, async (request) => {
  const uid = requireUid(request);
  const otherUid = inputText(request.data?.otherUid, "otherUid");
  if (uid === otherUid) throw new HttpsError("invalid-argument", "Invalid user.");
  const userIds = [uid, otherUid].sort();
  const reference = db.collection("friendships").doc(pairId(uid, otherUid));
  const batch = db.batch();
  batch.set(reference, {
    userIds,
    requestedBy: uid,
    status: "blocked",
    blockedBy: uid,
    createdAt: FieldValue.serverTimestamp(),
    acceptedAt: null,
    updatedAt: FieldValue.serverTimestamp(),
  }, {merge: true});
  batch.delete(friendAccessRef(uid, otherUid));
  batch.delete(friendAccessRef(otherUid, uid));
  await batch.commit();
  return {status: "blocked"};
});

// Backfills the private friend-access projection for accounts created before
// the Step 16 rules. New accept/block operations keep it current afterward.
exports.syncFriendAccess = onCall(callableOptions, async (request) => {
  const uid = requireUid(request);
  const friendships = await db.collection("friendships")
      .where("userIds", "array-contains", uid)
      .limit(500)
      .get();
  const acceptedFriendships = friendships.docs
      .filter((document) => document.data().status === "accepted");
  const otherUids = [...new Set(acceptedFriendships
      .map((document) => document.data().userIds
          ?.find((memberUid) => memberUid !== uid))
      .filter(Boolean))];
  const profileRefs = [uid, ...otherUids]
      .map((profileUid) => db.collection("users").doc(profileUid));
  const profiles = profileRefs.length ? await db.getAll(...profileRefs) : [];
  const writer = db.bulkWriter();
  profiles.forEach((profile) => {
    if (profile.exists) {
      writer.set(
          db.collection("safeProfiles").doc(profile.id),
          safeProfileData(profile.data()),
          {merge: true});
    }
  });
  acceptedFriendships.forEach((friendship) => {
    const otherUid = friendship.data().userIds
        ?.find((memberUid) => memberUid !== uid);
    if (!otherUid) return;
    writer.set(
        friendAccessRef(uid, otherUid),
        friendAccessData(otherUid, friendship.id));
    writer.set(
        friendAccessRef(otherUid, uid),
        friendAccessData(uid, friendship.id));
  });
  await writer.close();
  return {synced: otherUids.length};
});

exports.reportUser = onCall(callableOptions, async (request) => {
  const reporterUid = requireUid(request);
  const reportedUid = inputText(request.data?.otherUid, "otherUid");
  if (reporterUid === reportedUid) {
    throw new HttpsError("invalid-argument", "Invalid user.");
  }
  let reason;
  try {
    reason = sanitizeReportReason(request.data?.reason);
  } catch (error) {
    throw asInvalidArgument(error);
  }
  const reportedProfile = await db.collection("users").doc(reportedUid).get();
  if (!reportedProfile.exists) {
    throw new HttpsError("not-found", "Account not found.");
  }
  await db.collection("userReports").add({
    reporterUid,
    reportedUid,
    reason,
    source: "friend_discovery",
    status: "open",
    createdAt: FieldValue.serverTimestamp(),
  });
  return {status: "reported"};
});

async function sendWorkout(request) {
  const senderUid = requireUid(request);
  const isBatchRequest = Array.isArray(request.data?.recipientUids);
  const rawRecipientUids = isBatchRequest ? request.data.recipientUids :
    [request.data?.recipientUid];
  if (!rawRecipientUids.length || rawRecipientUids.length >
      maxWorkoutRecipientsPerRequest) {
    throw new HttpsError(
        "invalid-argument",
        `Choose between 1 and ${maxWorkoutRecipientsPerRequest} friends.`);
  }
  const recipientUids = [...new Set(rawRecipientUids.map((value) =>
    inputText(value, "recipientUid")))];
  if (recipientUids.includes(senderUid)) {
    throw new HttpsError("invalid-argument", "You cannot send a workout to yourself.");
  }
  let workoutSnapshot;
  try {
    workoutSnapshot = sanitizeWorkoutSnapshot(request.data?.workoutSnapshot);
  } catch (error) {
    throw asInvalidArgument(error);
  }
  const workoutSourceKey = inputText(
      request.data?.workoutSourceKey, "workoutSourceKey", {max: 128});
  const senderMessage = inputText(request.data?.senderMessage, "senderMessage",
      {required: false, max: 280});
  const senderProfileRef = db.collection("users").doc(senderUid);
  const senderTeamRef = senderProfileRef.collection("privateData").doc("team");
  const initialMembership = await senderTeamRef.get();
  const teamId = initialMembership.data()?.teamId;
  if (!teamId) {
    throw new HttpsError("failed-precondition", "Join or create a team first.");
  }
  const teamRef = db.collection("teams").doc(teamId);
  const statsRef = db.collection("socialStats").doc(senderUid);
  const today = utcDateKey();
  const rateRef = senderProfileRef.collection("privateData")
      .doc(`workoutSends_${today}`);
  const entries = recipientUids.map((recipientUid) => ({
    recipientUid,
    membershipRef: db.collection("users").doc(recipientUid)
        .collection("privateData").doc("team"),
    recipientProfileRef: db.collection("users").doc(recipientUid),
    shareRef: db.collection("workoutShares")
        .doc(workoutShareId(senderUid, recipientUid, workoutSourceKey)),
    eventRef: db.collection("socialEvents").doc(),
  }));
  const outcome = await db.runTransaction(async (transaction) => {
    const documents = await Promise.all([
      transaction.get(senderProfileRef),
      transaction.get(statsRef),
      transaction.get(rateRef),
      transaction.get(senderTeamRef),
      transaction.get(teamRef),
      ...entries.map((entry) => transaction.get(entry.membershipRef)),
      ...entries.map((entry) => transaction.get(entry.recipientProfileRef)),
      ...entries.map((entry) => transaction.get(entry.shareRef)),
    ]);
    const sender = documents[0];
    const stats = documents[1];
    const rate = documents[2];
    const offset = 5;
    const memberships = documents.slice(offset, offset + entries.length);
    const recipients = documents.slice(
        offset + entries.length, offset + (entries.length * 2));
    const existingShares = documents.slice(offset + (entries.length * 2));
    if (!sender.exists) {
      throw new HttpsError("failed-precondition", "Finish creating your account first.");
    }
    if (documents[3].data()?.teamId !== teamId ||
        documents[4].data()?.status !== "active") {
      throw new HttpsError("failed-precondition", "Your team is unavailable.");
    }

    const newEntries = [];
    const results = [];
    entries.forEach((entry, index) => {
      const membership = memberships[index].data();
      const recipient = recipients[index];
      const existingShare = existingShares[index];
      if (membership?.teamId !== teamId) {
        throw new HttpsError(
            "permission-denied", "Only current teammates can share workouts.");
      }
      if (!recipient.exists) {
        throw new HttpsError("not-found", "Friend not found.");
      }
      if (recipient.data()?.accountSafety?.allowWorkoutMessages === false &&
          senderMessage) {
        throw new HttpsError(
            "permission-denied", "This friend does not accept workout messages.");
      }
      if (existingShare.exists) {
        const existing = existingShare.data();
        if (existing.senderUid !== senderUid ||
            existing.recipientUid !== entry.recipientUid ||
            existing.workoutSourceKey !== workoutSourceKey) {
          throw new HttpsError("internal", "Workout share key collision.");
        }
        results.push({
          recipientUid: entry.recipientUid,
          shareId: entry.shareRef.id,
          status: existing.status || "sent",
          created: false,
        });
        return;
      }
      newEntries.push(entry);
      results.push({
        recipientUid: entry.recipientUid,
        shareId: entry.shareRef.id,
        status: "sent",
        created: true,
      });
    });

    let nextRateState;
    try {
      nextRateState = nextWorkoutSendRateState(
          rate.data(),
          newEntries.map((entry) => entry.recipientUid),
          {
            maxDaily: maxWorkoutSendsPerDay,
            maxPerRecipient: maxWorkoutSendsPerRecipientPerDay,
          });
    } catch (error) {
      throw new HttpsError("resource-exhausted", error.message);
    }

    if (newEntries.length) {
      transaction.set(rateRef, {
        date: today,
        ...nextRateState,
        updatedAt: FieldValue.serverTimestamp(),
        expiresAt: Timestamp.fromMillis(Date.now() + (8 * 24 * 60 * 60 * 1000)),
      }, {merge: true});

      const nextStats = workoutSentStats(stats.data(), newEntries.length);
      for (const entry of newEntries) {
        transaction.set(entry.shareRef, {
          senderUid,
          recipientUid: entry.recipientUid,
          teamId,
          workoutSourceKey,
          workoutSnapshot,
          senderMessage: senderMessage || null,
          status: "sent",
          sentAt: FieldValue.serverTimestamp(),
          acceptedAt: null,
          relayQualifiedAt: null,
          scheduledFor: null,
          scheduledReminderSentAt: null,
          startedAt: null,
          completedAt: null,
          declinedAt: null,
          recipientReadAt: null,
          recipientResultSummary: null,
          updatedAt: FieldValue.serverTimestamp(),
        });
        transaction.set(entry.eventRef, eventData(
            "workout_sent", senderUid, entry.recipientUid, entry.shareRef.id));
        transaction.set(entry.recipientProfileRef, {
          unreadSharedWorkoutCount: FieldValue.increment(1),
          updatedAt: FieldValue.serverTimestamp(),
        }, {merge: true});
      }
      transaction.set(statsRef, {
        ...nextStats,
        updatedAt: FieldValue.serverTimestamp(),
      }, {merge: true});
    }

    return {
      results,
      created: newEntries.map((entry) => ({
        recipientUid: entry.recipientUid,
        shareId: entry.shareRef.id,
      })),
      senderName: sender.data()?.displayName || "A friend",
      remainingDaily: maxWorkoutSendsPerDay - nextRateState.totalSends,
    };
  });
  await Promise.all(outcome.created.map((created) => notifySocialUpdate({
    recipientUid: created.recipientUid,
    type: "workout_received",
    shareId: created.shareId,
    actorName: outcome.senderName,
    workoutTitle: workoutNotificationTitle(workoutSnapshot),
  })));
  if (!isBatchRequest) return outcome.results[0];
  return {
    results: outcome.results,
    limits: {
      maxRecipientsPerRequest: maxWorkoutRecipientsPerRequest,
      maxDaily: maxWorkoutSendsPerDay,
      maxPerRecipientDaily: maxWorkoutSendsPerRecipientPerDay,
      remainingDaily: outcome.remainingDaily,
    },
  };
}

exports.sendWorkout = onCall(callableOptions, sendWorkout);
// Temporary compatibility for clients released before the batch callable.
exports.sendWorkoutShare = onCall(callableOptions, sendWorkout);

async function transitionAcceptedWorkout(
    request, allowedStatuses, nextStatus, fields = {}) {
  const uid = requireUid(request);
  const today = utcDateKey();
  const shareId = inputText(request.data?.shareId, "shareId");
  const shareRef = db.collection("workoutShares").doc(shareId);
  const acceptedEventRef = db.collection("socialEvents").doc();
  const acceptedNotification = await db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(shareRef);
    const data = snapshot.data();
    if (!data || data.recipientUid !== uid) {
      throw new HttpsError("not-found", "Workout share not found.");
    }
    if (nextStatus === "started" && data.status === "completed") return null;
    if (!allowedStatuses.includes(data.status)) {
      throw new HttpsError("failed-precondition", "Workout share is in the wrong state.");
    }
    if (data.status === nextStatus && nextStatus !== "scheduled") return null;
    const accepting = data.status === "sent";
    let relayQualified = false;
    if (accepting) {
      const senderStatsRef = db.collection("socialStats").doc(data.senderUid);
      const relayQualifierRef = db.collection("socialQualifications").doc(
          relayQualificationId(data.senderUid, uid, today));
      const [senderStatsSnapshot, relayQualifier] = await Promise.all([
        transaction.get(senderStatsRef),
        transaction.get(relayQualifierRef),
      ]);
      if (!relayQualifier.exists) {
        relayQualified = true;
        transaction.set(relayQualifierRef, {
          type: "relay_day_recipient",
          senderUid: data.senderUid,
          recipientUid: uid,
          date: today,
          workoutShareId: shareId,
          createdAt: FieldValue.serverTimestamp(),
        });
        transaction.set(senderStatsRef, {
          ...relayQualificationStats(senderStatsSnapshot.data(), today),
          updatedAt: FieldValue.serverTimestamp(),
        }, {merge: true});
      }
    }
    transaction.update(shareRef, {
      status: nextStatus,
      ...(accepting ? {
        acceptedAt: FieldValue.serverTimestamp(),
        relayQualifiedAt: FieldValue.serverTimestamp(),
      } : {}),
      ...fields,
      updatedAt: FieldValue.serverTimestamp(),
    });
    if (accepting) {
      transaction.set(acceptedEventRef, eventData(
          "workout_accepted", uid, data.senderUid, shareId));
      return {
        senderUid: data.senderUid,
        workoutTitle: workoutNotificationTitle(data.workoutSnapshot),
        relayQualified,
      };
    }
    return null;
  });
  if (acceptedNotification) {
    await notifySocialUpdate({
      recipientUid: acceptedNotification.senderUid,
      type: "workout_accepted",
      shareId,
      actorName: await displayNameFor(uid),
      workoutTitle: acceptedNotification.workoutTitle,
    });
  }
  return {status: nextStatus};
}

exports.acceptWorkoutShare = onCall(callableOptions, async (request) => {
  return transitionAcceptedWorkout(request, ["sent", "accepted"], "accepted");
});

exports.scheduleWorkoutShare = onCall(callableOptions, async (request) => {
  const milliseconds = Number(
      request.data?.scheduledForMillis ?? request.data?.scheduledAtMillis);
  const earliest = Date.now() - 5 * 60 * 1000;
  const latest = Date.now() + 365 * 24 * 60 * 60 * 1000;
  if (!Number.isFinite(milliseconds) || milliseconds < earliest || milliseconds > latest) {
    throw new HttpsError("invalid-argument", "Choose a valid date within one year.");
  }
  return transitionAcceptedWorkout(
      request, ["sent", "accepted", "scheduled"], "scheduled", {
    scheduledFor: Timestamp.fromMillis(milliseconds),
    scheduledReminderSentAt: null,
  });
});

exports.startWorkoutShare = onCall(callableOptions, async (request) => {
  return transitionAcceptedWorkout(
      request, ["sent", "accepted", "scheduled", "started", "completed"], "started", {
    startedAt: FieldValue.serverTimestamp(),
  });
});

exports.saveWorkoutShare = onCall(callableOptions, async (request) => {
  return transitionAcceptedWorkout(
      request, ["sent", "accepted", "scheduled", "started"], "accepted", {
        scheduledFor: null,
        scheduledReminderSentAt: null,
        startedAt: null,
      });
});

exports.removeWorkoutSchedule = onCall(callableOptions, async (request) => {
  return transitionAcceptedWorkout(
      request, ["scheduled", "accepted"], "accepted", {
        scheduledFor: null,
        scheduledReminderSentAt: null,
      });
});

exports.declineWorkoutShare = onCall(callableOptions, async (request) => {
  const uid = requireUid(request);
  const shareId = inputText(request.data?.shareId, "shareId");
  const shareRef = db.collection("workoutShares").doc(shareId);
  const profileRef = db.collection("users").doc(uid);
  const eventRef = db.collection("socialEvents").doc();
  await db.runTransaction(async (transaction) => {
    const [share, profile] = await Promise.all([
      transaction.get(shareRef),
      transaction.get(profileRef),
    ]);
    const data = share.data();
    if (!data || data.recipientUid !== uid) {
      throw new HttpsError("not-found", "Workout share not found.");
    }
    if (data.status === "declined") return;
    if (!["sent", "accepted", "scheduled", "started"].includes(data.status)) {
      throw new HttpsError(
          "failed-precondition", "This workout can no longer be declined.");
    }
    const wasUnread = !data.recipientReadAt;
    transaction.update(shareRef, {
      status: "declined",
      declinedAt: FieldValue.serverTimestamp(),
      ...(wasUnread ? {recipientReadAt: FieldValue.serverTimestamp()} : {}),
      updatedAt: FieldValue.serverTimestamp(),
    });
    transaction.set(eventRef, eventData(
        "workout_declined", uid, data.senderUid, shareId));
    if (wasUnread) {
      const unreadCount = Number(profile.data()?.unreadSharedWorkoutCount) || 0;
      transaction.set(profileRef, {
        unreadSharedWorkoutCount: Math.max(0, unreadCount - 1),
        updatedAt: FieldValue.serverTimestamp(),
      }, {merge: true});
    }
  });
  return {status: "declined"};
});

exports.completeWorkoutShare = onCall(callableOptions, async (request) => {
  let resultSummary;
  try {
    resultSummary = sanitizeResultSummary(request.data?.resultSummary);
  } catch (error) {
    throw asInvalidArgument(error);
  }
  const uid = requireUid(request);
  const today = utcDateKey();
  const week = utcWeekKey();
  const shareId = inputText(request.data?.shareId, "shareId");
  const shareRef = db.collection("workoutShares").doc(shareId);
  const eventRef = db.collection("socialEvents").doc();
  const completionOutcome = await db.runTransaction(async (transaction) => {
    const share = await transaction.get(shareRef);
    const data = share.data();
    if (!data || data.recipientUid !== uid) {
      throw new HttpsError("not-found", "Workout share not found.");
    }
    try {
      if (!shouldApplyWorkoutCompletion(data.status)) {
        return {
          applied: false,
          partnerUid: data.senderUid,
          workoutTitle: workoutNotificationTitle(data.workoutSnapshot),
        };
      }
    } catch (error) {
      throw new HttpsError("failed-precondition", error.message);
    }

    const senderUid = data.senderUid;
    const recipientStatsRef = db.collection("socialStats").doc(uid);
    const senderStatsRef = db.collection("socialStats").doc(senderUid);
    const relayQualifierRef = db.collection("socialQualifications").doc(
        relayQualificationId(senderUid, uid, today));
    const partnerWeekRef = db.collection("socialPartnerWeeks").doc(
        `${pairId(uid, senderUid)}_${week}`);
    const crewProgressRef = db.collection("socialCrewProgress").doc(
        workoutShareId(
            senderUid, "crew", data.teamId ?
              `crew:${week}:${data.teamId}:${data.workoutSourceKey}` :
              `crew:${week}:${data.workoutSourceKey}`));
    const friendshipRef = db.collection("friendships")
        .doc(pairId(uid, senderUid));
    const recipientTeamRef = db.collection("users").doc(uid)
        .collection("privateData").doc("team");
    const senderTeamRef = db.collection("users").doc(senderUid)
        .collection("privateData").doc("team");
    const [
      recipientStatsSnapshot,
      senderStatsSnapshot,
      relayQualifier,
      partnerWeekSnapshot,
      crewProgressSnapshot,
      friendshipSnapshot,
      recipientTeamSnapshot,
      senderTeamSnapshot,
      activeTeamSnapshot,
    ] = await Promise.all([
      transaction.get(recipientStatsRef),
      transaction.get(senderStatsRef),
      transaction.get(relayQualifierRef),
      transaction.get(partnerWeekRef),
      transaction.get(crewProgressRef),
      transaction.get(friendshipRef),
      data.teamId ? transaction.get(recipientTeamRef) : null,
      data.teamId ? transaction.get(senderTeamRef) : null,
      data.teamId ? transaction.get(db.collection("teams").doc(data.teamId)) : null,
    ]);

    const statsBefore = new Map([
      [uid, recipientStatsSnapshot.data() || {}],
      [senderUid, senderStatsSnapshot.data() || {}],
    ]);
    const statsAfter = new Map([
      [uid, recipientStats(recipientStatsSnapshot.data(), today)],
      [senderUid, senderStatsSnapshot.data() || {}],
    ]);

    const relayQualified = !data.relayQualifiedAt && !relayQualifier.exists;
    if (relayQualified) {
      statsAfter.set(
          senderUid,
          relayQualificationStats(statsAfter.get(senderUid), today));
    }

    const partnerWeekData = partnerWeekSnapshot.data() || {};
    const partnerCompletedUids = [...new Set([
      ...(Array.isArray(partnerWeekData.completedUserUids) ?
        partnerWeekData.completedUserUids : []),
      uid,
    ])];
    const partnerQualified = !partnerWeekData.qualifiedAt &&
      partnerCompletedUids.includes(uid) &&
      partnerCompletedUids.includes(senderUid);
    if (partnerQualified) {
      statsAfter.set(
          uid,
          partnerQualificationStats(statsAfter.get(uid), senderUid, week));
      statsAfter.set(
          senderUid,
          partnerQualificationStats(statsAfter.get(senderUid), uid, week));
    }

    const crewProgressData = crewProgressSnapshot.data() || {};
    const connected = data.teamId ?
      recipientTeamSnapshot.data()?.teamId === data.teamId &&
        senderTeamSnapshot.data()?.teamId === data.teamId &&
        activeTeamSnapshot.data()?.status === "active" :
      friendshipSnapshot.data()?.status === "accepted";
    const crewCompletedUids = [...new Set([
      ...(Array.isArray(crewProgressData.completedRecipientUids) ?
        crewProgressData.completedRecipientUids : []),
      ...(connected ? [uid] : []),
    ])];
    const crewQualified = connected && !crewProgressData.qualifiedAt &&
      crewCompletedUids.length >= 3;
    const crewMembers = crewQualified ? crewCompletedUids.slice(0, 3) : [];
    const additionalCrewStatsRefs = crewMembers
        .filter((memberUid) => !statsBefore.has(memberUid))
        .map((memberUid) => db.collection("socialStats").doc(memberUid));
    const additionalCrewStats = await Promise.all(
        additionalCrewStatsRefs.map((ref) => transaction.get(ref)));
    additionalCrewStats.forEach((snapshot) => {
      statsBefore.set(snapshot.id, snapshot.data() || {});
      statsAfter.set(snapshot.id, snapshot.data() || {});
    });
    if (crewQualified) {
      for (const memberUid of new Set([senderUid, ...crewMembers])) {
        statsAfter.set(
            memberUid,
            crewQualificationStats(statsAfter.get(memberUid), week));
      }
    }

    if (relayQualified) {
      transaction.set(relayQualifierRef, {
        type: "relay_day_recipient",
        senderUid,
        recipientUid: uid,
        date: today,
        workoutShareId: shareId,
        createdAt: FieldValue.serverTimestamp(),
      });
    }
    transaction.set(partnerWeekRef, {
      userIds: [uid, senderUid].sort(),
      week,
      completedUserUids: partnerCompletedUids,
      ...(partnerQualified ? {
        qualifiedAt: FieldValue.serverTimestamp(),
      } : {}),
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
    if (connected) {
      transaction.set(crewProgressRef, {
        senderUid,
        workoutSourceKey: data.workoutSourceKey,
        week,
        completedRecipientUids: crewCompletedUids,
        ...(crewQualified ? {
          qualifiedMemberUids: crewMembers,
          qualifiedAt: FieldValue.serverTimestamp(),
        } : {}),
        updatedAt: FieldValue.serverTimestamp(),
      }, {merge: true});
    }
    transaction.update(shareRef, {
      status: "completed",
      completedAt: FieldValue.serverTimestamp(),
      ...(!data.relayQualifiedAt ? {
        relayQualifiedAt: FieldValue.serverTimestamp(),
      } : {}),
      recipientResultSummary: resultSummary,
      updatedAt: FieldValue.serverTimestamp(),
    });
    transaction.set(eventRef, eventData(
        "workout_completed", uid, senderUid, shareId));
    for (const [statsUid, stats] of statsAfter.entries()) {
      transaction.set(db.collection("socialStats").doc(statsUid), {
        ...stats,
        updatedAt: FieldValue.serverTimestamp(),
      }, {merge: true});
    }
    const recipientBefore = statsBefore.get(uid) || {};
    const recipientAfter = statsAfter.get(uid) || {};
    const priorBadges = new Set(recipientBefore.socialBadges || []);
    return {
      applied: true,
      partnerUid: senderUid,
      workoutTitle: workoutNotificationTitle(data.workoutSnapshot),
      pointsAwarded: (Number(recipientAfter.socialProgressPoints) || 0) -
        (Number(recipientBefore.socialProgressPoints) || 0),
      friendWorkoutStreak: Number(recipientAfter.friendWorkoutStreak) || 0,
      partnerStreak: Number(recipientAfter.partnerStreaks?.[senderUid]) || 0,
      crewStreak: Number(recipientAfter.crewStreak) || 0,
      partnerQualified,
      crewQualified: crewQualified && crewMembers.includes(uid),
      newBadgeIds: (recipientAfter.socialBadges || [])
          .filter((badge) => !priorBadges.has(badge)),
    };
  });
  if (completionOutcome.applied) {
    await notifySocialUpdate({
      recipientUid: completionOutcome.partnerUid,
      type: "workout_completed",
      shareId,
      actorName: await displayNameFor(uid),
      workoutTitle: completionOutcome.workoutTitle,
    });
  }
  return {
    status: "completed",
    applied: completionOutcome.applied,
    partnerUid: completionOutcome.partnerUid,
    rewards: completionOutcome.applied ? {
      pointsAwarded: completionOutcome.pointsAwarded,
      friendWorkoutStreak: completionOutcome.friendWorkoutStreak,
      partnerStreak: completionOutcome.partnerStreak,
      crewStreak: completionOutcome.crewStreak,
      partnerQualified: completionOutcome.partnerQualified,
      crewQualified: completionOutcome.crewQualified,
      newBadgeIds: completionOutcome.newBadgeIds,
    } : null,
  };
});

exports.reactToWorkoutShare = onCall(callableOptions, async (request) => {
  const uid = requireUid(request);
  const shareId = inputText(request.data?.shareId, "shareId");
  const reaction = inputText(request.data?.reaction, "reaction", {max: 20});
  if (!reactions.has(reaction)) {
    throw new HttpsError("invalid-argument", "Choose a supported reaction.");
  }
  const share = await db.collection("workoutShares").doc(shareId).get();
  const data = share.data();
  if (!data || (data.senderUid !== uid && data.recipientUid !== uid)) {
    throw new HttpsError("not-found", "Workout share not found.");
  }
  const otherUid = data.senderUid === uid ? data.recipientUid : data.senderUid;
  await db.collection("socialEvents").add(eventData(
      "reaction", uid, otherUid, shareId, {reaction}));
  if (reaction === "fist_bump") {
    await notifySocialUpdate({
      recipientUid: otherUid,
      type: "fist_bump",
      shareId,
      actorName: await displayNameFor(uid),
      workoutTitle: workoutNotificationTitle(data.workoutSnapshot),
    });
  }
  return {status: "recorded"};
});

if (process.env.ENABLE_SCHEDULED_WORKOUT_PUSH === "true") {
  exports.sendScheduledWorkoutReminders = onSchedule(
      {schedule: "every 5 minutes", timeZone: "Etc/UTC"},
      async () => {
      const now = Timestamp.now();
      const reminderCutoff = Timestamp.fromMillis(
          now.toMillis() + (10 * 60 * 1000));
      const dueShares = await db.collection("workoutShares")
          .where("status", "==", "scheduled")
          .where("scheduledFor", ">", now)
          .where("scheduledFor", "<=", reminderCutoff)
          .limit(200)
          .get();

      await Promise.all(dueShares.docs.map(async (document) => {
        const reminder = await db.runTransaction(async (transaction) => {
          const snapshot = await transaction.get(document.ref);
          const data = snapshot.data();
          if (!data || data.status !== "scheduled" ||
              data.scheduledReminderSentAt) {
            return null;
          }
          const scheduledFor = data.scheduledFor;
          if (!(scheduledFor instanceof Timestamp) ||
              scheduledFor.toMillis() <= Date.now()) {
            return null;
          }
          transaction.update(document.ref, {
            scheduledReminderSentAt: FieldValue.serverTimestamp(),
            updatedAt: FieldValue.serverTimestamp(),
          });
          return {
            recipientUid: data.recipientUid,
            senderUid: data.senderUid,
            workoutTitle: workoutNotificationTitle(data.workoutSnapshot),
          };
        });
        if (!reminder) return;
        await notifySocialUpdate({
          recipientUid: reminder.recipientUid,
          type: "scheduled_workout_reminder",
          shareId: document.id,
          actorName: await displayNameFor(reminder.senderUid),
          workoutTitle: reminder.workoutTitle,
        });
      }));
      });
}

exports.markWorkoutSharesRead = onCall(callableOptions, async (request) => {
  const uid = requireUid(request);
  const shareIds = [...new Set(Array.isArray(request.data?.shareIds) ?
    request.data.shareIds.map((id) => inputText(id, "shareId")) : [])];
  if (!shareIds.length || shareIds.length > 100) {
    throw new HttpsError("invalid-argument", "Send between 1 and 100 share IDs.");
  }
  const references = shareIds.map((id) => db.collection("workoutShares").doc(id));
  const profileRef = db.collection("users").doc(uid);
  await db.runTransaction(async (transaction) => {
    const snapshots = await Promise.all(references.map((ref) => transaction.get(ref)));
    const profile = await transaction.get(profileRef);
    let newlyRead = 0;
    snapshots.forEach((snapshot, index) => {
      const data = snapshot.data();
      if (!data || data.recipientUid !== uid || data.recipientReadAt) return;
      newlyRead++;
      transaction.update(references[index], {
        recipientReadAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      });
    });
    if (newlyRead) {
      const current = Number(profile.data()?.unreadSharedWorkoutCount) || 0;
      transaction.set(profileRef, {
        unreadSharedWorkoutCount: Math.max(0, current - newlyRead),
        updatedAt: FieldValue.serverTimestamp(),
      }, {merge: true});
    }
  });
  return {status: "read"};
});
