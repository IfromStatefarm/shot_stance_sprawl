const assert = require("node:assert/strict");
const {test} = require("node:test");
const {initializeApp} = require("firebase-admin/app");
const {getAuth} = require("firebase-admin/auth");
const {getFirestore} = require("firebase-admin/firestore");

initializeApp({
  projectId: "demo-snap-and-go",
  storageBucket: "demo-snap-and-go.appspot.com",
});
const db = getFirestore();

async function createAccount(email) {
  const response = await fetch(
      "http://127.0.0.1:9099/identitytoolkit.googleapis.com/v1/accounts:signUp?key=fake", {
        method: "POST",
        headers: {"content-type": "application/json"},
        body: JSON.stringify({
          email,
          password: "TestPassword123!",
          returnSecureToken: true,
        }),
      });
  const data = await response.json();
  assert.equal(response.status, 200, JSON.stringify(data));
  await db.collection("users").doc(data.localId).set({displayName: email});
  return {uid: data.localId, token: data.idToken};
}

async function call(name, token) {
  const response = await fetch(
      `http://127.0.0.1:5001/demo-snap-and-go/us-central1/${name}`, {
        method: "POST",
        headers: {
          "content-type": "application/json",
          authorization: `Bearer ${token}`,
        },
        body: JSON.stringify({data: {}}),
      });
  const body = await response.json();
  assert.equal(response.status, 200, JSON.stringify(body));
  return body.result;
}

async function matchingCount(collection, field, operator, uid) {
  return (await db.collection(collection).where(field, operator, uid).get()).size;
}

test("export is uncapped and deletion removes every UID-bearing record", async () => {
  const account = await createAccount("account-data@example.test");
  const otherUid = "unrelated-user";
  const writer = db.bulkWriter();
  for (let index = 0; index < 501; index++) {
    writer.set(
        db.collection("users").doc(account.uid)
            .collection("devices").doc(`device-${index}`),
        {installationId: `installation-${index}`});
  }
  writer.set(db.collection("socialQualifications").doc("as-sender"), {
    senderUid: account.uid,
    recipientUid: otherUid,
  });
  writer.set(db.collection("socialQualifications").doc("as-recipient"), {
    senderUid: otherUid,
    recipientUid: account.uid,
  });
  writer.set(db.collection("socialPartnerWeeks").doc("partner-week"), {
    userIds: [account.uid, otherUid],
    completedUserUids: [account.uid],
  });
  writer.set(db.collection("socialCrewProgress").doc("crew-progress"), {
    senderUid: account.uid,
    completedRecipientUids: [account.uid, otherUid],
    qualifiedMemberUids: [account.uid],
  });
  writer.set(db.collection("userReports").doc("submitted-report"), {
    reporterUid: account.uid,
    reportedUid: otherUid,
    reason: "harassment",
  });
  writer.set(db.collection("userReports").doc("received-report"), {
    reporterUid: otherUid,
    reportedUid: account.uid,
    reason: "spam",
  });
  writer.set(db.collection("userReports").doc("unrelated-report"), {
    reporterUid: otherUid,
    reportedUid: "third-user",
    reason: "spam",
  });
  await writer.close();

  const exported = await call("exportAccountData", account.token);
  assert.equal(exported.devices.length, 501);
  assert.equal(exported.socialQualifications.length, 2);
  assert.equal(exported.socialPartnerWeeks.length, 1);
  assert.equal(exported.socialCrewProgress.length, 1);
  assert.equal(exported.userReports.length, 2);
  assert.equal(Object.hasOwn(exported, "collectionExportLimit"), false);

  assert.deepEqual(await call("deleteAccountData", account.token), {
    deleted: true,
  });

  assert.equal((await db.collection("users").doc(account.uid).get()).exists, false);
  assert.equal(await matchingCount(
      "socialQualifications", "senderUid", "==", account.uid), 0);
  assert.equal(await matchingCount(
      "socialQualifications", "recipientUid", "==", account.uid), 0);
  assert.equal(await matchingCount(
      "socialPartnerWeeks", "userIds", "array-contains", account.uid), 0);
  assert.equal(await matchingCount(
      "socialCrewProgress", "senderUid", "==", account.uid), 0);
  assert.equal(await matchingCount(
      "socialCrewProgress", "completedRecipientUids",
      "array-contains", account.uid), 0);
  assert.equal(await matchingCount(
      "socialCrewProgress", "qualifiedMemberUids",
      "array-contains", account.uid), 0);
  assert.equal(await matchingCount(
      "userReports", "reporterUid", "==", account.uid), 0);
  assert.equal(await matchingCount(
      "userReports", "reportedUid", "==", account.uid), 0);
  assert.equal(
      (await db.collection("userReports").doc("unrelated-report").get()).exists,
      true);
  await assert.rejects(getAuth().getUser(account.uid), /no user record/i);
});
