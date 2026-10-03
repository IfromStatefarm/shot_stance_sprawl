const {initializeApp} = require("firebase-admin/app");
const {getAuth} = require("firebase-admin/auth");
const {FieldValue, getFirestore} = require("firebase-admin/firestore");
const {getStorage} = require("firebase-admin/storage");
const {HttpsError, onCall} = require("firebase-functions/v2/https");
const {enforceAppCheck} = require("./app_check");

initializeApp();

const db = getFirestore();
const standardCallableOptions = {enforceAppCheck};

function requireUid(request) {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Sign in first.");
  return uid;
}

function recordsFromSnapshots(...snapshots) {
  const records = new Map();
  for (const snapshot of snapshots) {
    for (const document of snapshot.docs) {
      records.set(document.ref.path, {id: document.id, ...document.data()});
    }
  }
  return [...records.values()];
}

exports.claimUsername = onCall(
    standardCallableOptions,
    async (request) => {
      const uid = requireUid(request);
      const username = String(request.data?.username || "").trim().toLowerCase();
      if (!/^[a-z0-9_]{3,20}$/.test(username)) {
        throw new HttpsError(
            "invalid-argument", "Use 3-20 letters, numbers, or underscores.");
      }

      const profileRef = db.collection("users").doc(uid);
      const safeProfileRef = db.collection("safeProfiles").doc(uid);
      const usernameRef = db.collection("usernames").doc(username);
      await db.runTransaction(async (transaction) => {
        const [profile, usernameDocument] = await Promise.all([
          transaction.get(profileRef),
          transaction.get(usernameRef),
        ]);
        if (!profile.exists) {
          throw new HttpsError(
              "failed-precondition", "Finish creating your account first.");
        }
        const ownerUid = usernameDocument.data()?.uid;
        if (ownerUid && ownerUid !== uid) {
          throw new HttpsError("already-exists", "That username is already taken.");
        }

        const oldUsername = profile.data()?.usernameNormalized;
        let oldUsernameDocument = null;
        if (oldUsername && oldUsername !== username) {
          oldUsernameDocument = await transaction.get(
              db.collection("usernames").doc(oldUsername));
        }
        if (oldUsernameDocument?.data()?.uid === uid) {
          transaction.delete(oldUsernameDocument.ref);
        }
        transaction.set(usernameRef, {
          uid,
          username,
          updatedAt: FieldValue.serverTimestamp(),
        });
        transaction.update(profileRef, {
          username,
          usernameNormalized: username,
          updatedAt: FieldValue.serverTimestamp(),
        });
        transaction.set(safeProfileRef, {username}, {merge: true});
      });
      return {username};
    },
);

exports.exportAccountData = onCall(
    standardCallableOptions,
    async (request) => {
      const uid = requireUid(request);
      const profileRef = db.collection("users").doc(uid);
      const [
        profile,
        account,
        progress,
        devices,
        friendships,
        legacyFriendships,
        receivedShares,
        sentShares,
        events,
        stats,
        relayQualificationsAsSender,
        relayQualificationsAsRecipient,
        partnerWeeks,
        crewProgressAsSender,
        crewProgressAsRecipient,
        crewProgressAsQualifiedMember,
        reportsAsReporter,
        reportsAsReportedUser,
      ] = await Promise.all([
        profileRef.get(),
        profileRef.collection("privateData").doc("account").get(),
        profileRef.collection("privateData").doc("localProgress").get(),
        profileRef.collection("devices").get(),
        db.collection("friendships").where("userIds", "array-contains", uid).get(),
        db.collection("friendships").where("memberUids", "array-contains", uid).get(),
        db.collection("workoutShares").where("recipientUid", "==", uid).get(),
        db.collection("workoutShares").where("senderUid", "==", uid).get(),
        db.collection("socialEvents").where("userIds", "array-contains", uid).get(),
        db.collection("socialStats").doc(uid).get(),
        db.collection("socialQualifications").where("senderUid", "==", uid).get(),
        db.collection("socialQualifications").where("recipientUid", "==", uid).get(),
        db.collection("socialPartnerWeeks").where("userIds", "array-contains", uid).get(),
        db.collection("socialCrewProgress").where("senderUid", "==", uid).get(),
        db.collection("socialCrewProgress")
            .where("completedRecipientUids", "array-contains", uid).get(),
        db.collection("socialCrewProgress")
            .where("qualifiedMemberUids", "array-contains", uid).get(),
        db.collection("userReports").where("reporterUid", "==", uid).get(),
        db.collection("userReports").where("reportedUid", "==", uid).get(),
      ]);
      const teamMembership = await profileRef.collection("privateData")
          .doc("team").get();
      const teamId = teamMembership.data()?.teamId;
      const team = teamId ? await db.collection("teams").doc(teamId).get() : null;
      const teamAccess = teamMembership.data()?.role === "owner" && teamId ?
        await db.collection("teams").doc(teamId)
            .collection("private").doc("access").get() : null;
      return {
        uid,
        publicProfile: profile.data() || null,
        privateAccount: account.data() || null,
        linkedProgress: progress.data() || null,
        devices: recordsFromSnapshots(devices),
        friendships: recordsFromSnapshots(friendships, legacyFriendships),
        receivedWorkoutShares: recordsFromSnapshots(receivedShares),
        sentWorkoutShares: recordsFromSnapshots(sentShares),
        socialEvents: recordsFromSnapshots(events),
        socialStats: stats.data() || null,
        socialQualifications: recordsFromSnapshots(
            relayQualificationsAsSender, relayQualificationsAsRecipient),
        socialPartnerWeeks: recordsFromSnapshots(partnerWeeks),
        socialCrewProgress: recordsFromSnapshots(
            crewProgressAsSender,
            crewProgressAsRecipient,
            crewProgressAsQualifiedMember),
        userReports: recordsFromSnapshots(
            reportsAsReporter, reportsAsReportedUser),
        teamMembership: teamMembership.data() || null,
        team: team?.data() || null,
        teamAccessCode: teamAccess?.data()?.code || null,
      };
    },
);

exports.deleteAccountData = onCall(
    standardCallableOptions,
    async (request) => {
      const uid = requireUid(request);
      const authenticatedAt = Number(request.auth?.token?.auth_time || 0) * 1000;
      if (!authenticatedAt || Date.now() - authenticatedAt > 10 * 60 * 1000) {
        throw new HttpsError(
            "failed-precondition",
            "Recent sign-in required. Sign out and sign back in.",
        );
      }

      await removeAccountFromTeam(uid);
      await getStorage().bucket().deleteFiles({
        prefix: `teamPhotoUploads/${uid}/`,
      });

      const [
        usernames,
        friendships,
        legacyFriendships,
        receivedShares,
        sentShares,
        events,
        subscriptionPurchases,
        relayQualificationsAsSender,
        relayQualificationsAsRecipient,
        partnerQualifications,
        crewProgressAsSender,
        crewProgressAsRecipient,
        crewProgressAsQualifiedMember,
        reportsAsReporter,
        reportsAsReportedUser,
      ] = await Promise.all([
        db.collection("usernames").where("uid", "==", uid).get(),
        db.collection("friendships").where("userIds", "array-contains", uid).get(),
        db.collection("friendships").where("memberUids", "array-contains", uid).get(),
        db.collection("workoutShares").where("recipientUid", "==", uid).get(),
        db.collection("workoutShares").where("senderUid", "==", uid).get(),
        db.collection("socialEvents").where("userIds", "array-contains", uid).get(),
        db.collection("subscriptionPurchases").where("uid", "==", uid).get(),
        db.collection("socialQualifications").where("senderUid", "==", uid).get(),
        db.collection("socialQualifications").where("recipientUid", "==", uid).get(),
        db.collection("socialPartnerWeeks").where("userIds", "array-contains", uid).get(),
        db.collection("socialCrewProgress").where("senderUid", "==", uid).get(),
        db.collection("socialCrewProgress")
            .where("completedRecipientUids", "array-contains", uid).get(),
        db.collection("socialCrewProgress")
            .where("qualifiedMemberUids", "array-contains", uid).get(),
        db.collection("userReports").where("reporterUid", "==", uid).get(),
        db.collection("userReports").where("reportedUid", "==", uid).get(),
      ]);
      const documents = new Map();
      for (const snapshot of [
        usernames,
        friendships,
        legacyFriendships,
        receivedShares,
        sentShares,
        events,
        subscriptionPurchases,
        relayQualificationsAsSender,
        relayQualificationsAsRecipient,
        partnerQualifications,
        crewProgressAsSender,
        crewProgressAsRecipient,
        crewProgressAsQualifiedMember,
        reportsAsReporter,
        reportsAsReportedUser,
      ]) {
        for (const document of snapshot.docs) {
          documents.set(document.ref.path, document.ref);
        }
      }
      for (const friendship of friendships.docs) {
        const otherUid = friendship.data().userIds
            ?.find((memberUid) => memberUid !== uid);
        if (otherUid) {
          documents.set(
              `users/${otherUid}/friendAccess/${uid}`,
              db.collection("users").doc(otherUid)
                  .collection("friendAccess").doc(uid));
        }
      }
      documents.set(`socialStats/${uid}`, db.collection("socialStats").doc(uid));
      documents.set(`safeProfiles/${uid}`, db.collection("safeProfiles").doc(uid));
      const writer = db.bulkWriter();
      for (const reference of documents.values()) writer.delete(reference);
      await writer.close();

      await db.recursiveDelete(db.collection("users").doc(uid));
      await getAuth().deleteUser(uid);
      return {deleted: true};
    },
);

Object.assign(exports, require("./social"));
const {removeAccountFromTeam, ...teamCallables} = require("./team");
Object.assign(exports, teamCallables);
const {_test: subscriptionTestHelpers, ...subscriptionFunctions} =
  require("./subscriptions");
Object.assign(exports, subscriptionFunctions);

