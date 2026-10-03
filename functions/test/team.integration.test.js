const assert = require("node:assert/strict");
const {test} = require("node:test");
const {initializeApp} = require("firebase-admin/app");
const {getFirestore} = require("firebase-admin/firestore");
const {initializeApp: initializeClientApp} = require("firebase/app");
const {getAuth, connectAuthEmulator, signInWithEmailAndPassword} =
  require("firebase/auth");
const {getStorage, connectStorageEmulator, ref, uploadBytes, getDownloadURL} =
  require("firebase/storage");

initializeApp({
  projectId: "demo-snap-and-go",
  storageBucket: "demo-snap-and-go.appspot.com",
});
const db = getFirestore();
const workoutSnapshot = {
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

async function account(email) {
  const response = await fetch(
      "http://127.0.0.1:9099/identitytoolkit.googleapis.com/v1/accounts:signUp?key=fake", {
        method: "POST",
        headers: {"content-type": "application/json"},
        body: JSON.stringify({email, password: "TestPassword123!", returnSecureToken: true}),
      });
  const data = await response.json();
  assert.equal(response.status, 200, JSON.stringify(data));
  await db.collection("users").doc(data.localId).set({displayName: email});
  const app = initializeClientApp({
    apiKey: "fake", projectId: "demo-snap-and-go",
    storageBucket: "demo-snap-and-go.appspot.com",
  }, email);
  const auth = getAuth(app);
  connectAuthEmulator(auth, "http://127.0.0.1:9099", {disableWarnings: true});
  await signInWithEmailAndPassword(auth, email, "TestPassword123!");
  const storage = getStorage(app);
  connectStorageEmulator(storage, "127.0.0.1", 9199);
  return {uid: data.localId, token: data.idToken, storage};
}

async function call(name, token, data = {}) {
  const response = await fetch(
      `http://127.0.0.1:5001/demo-snap-and-go/us-central1/${name}`, {
        method: "POST",
        headers: {
          "content-type": "application/json",
          authorization: `Bearer ${token}`,
        },
        body: JSON.stringify({data}),
      });
  const body = await response.json();
  if (!response.ok) {
    const error = new Error(body.error?.message || response.statusText);
    error.status = body.error?.status;
    throw error;
  }
  return body.result;
}

test("team creator and member roles survive edits, leaves, and deletion", async () => {
  const owner = await account("team-owner@example.test");
  const member = await account("team-member@example.test");
  const outsider = await account("team-outsider@example.test");
  const path = `teamPhotoUploads/${owner.uid}/firstphoto123`;
  await uploadBytes(ref(owner.storage, path), new Uint8Array([0xff, 0xd8, 0xff]),
      {contentType: "image/jpeg"});

  const created = await call("createTeam", owner.token, {
    name: "Mat Club", state: "Iowa", photoPath: path,
  });
  const teamId = created.teamId;
  const access = await db.collection("teams").doc(teamId)
      .collection("private").doc("access").get();
  const code = access.data().code;
  const photoPath = (await db.collection("teams").doc(teamId).get()).data().photoPath;
  assert.ok(await getDownloadURL(ref(owner.storage, photoPath)));
  assert.match(code, /^[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}$/);
  await assert.rejects(call("joinTeam", owner.token, {code}),
      /Leave your current team first/);

  await call("joinTeam", member.token, {code});
  assert.ok(await getDownloadURL(ref(member.storage, photoPath)));
  await assert.rejects(getDownloadURL(ref(outsider.storage, photoPath)));
  const sent = await call("sendWorkout", owner.token, {
    recipientUids: [member.uid], workoutSourceKey: "team-mission-1",
    workoutSnapshot,
  });
  assert.equal(sent.results[0].recipientUid, member.uid);
  assert.equal((await db.collection("workoutShares")
      .doc(sent.results[0].shareId).get()).data().teamId, teamId);
  await call("sendWorkout", member.token, {
    recipientUids: [owner.uid], workoutSourceKey: "team-mission-2",
    workoutSnapshot,
  });
  await assert.rejects(call("sendWorkout", owner.token, {
    recipientUids: [outsider.uid], workoutSourceKey: "team-mission-3",
    workoutSnapshot,
  }), /Only current teammates/);
  await assert.rejects(call("editTeam", member.token,
      {name: "Changed", state: "Iowa"}), /Only the team creator/);
  const replacementPath = `teamPhotoUploads/${owner.uid}/secondphoto123`;
  await uploadBytes(ref(owner.storage, replacementPath),
      new Uint8Array([0xff, 0xd8, 0xfe]), {contentType: "image/jpeg"});
  await call("editTeam", owner.token, {
    name: "New Mat Club", state: "Illinois", photoPath: replacementPath,
  });
  assert.equal((await db.collection("teams").doc(teamId).get()).data().name,
      "New Mat Club");
  const updatedPhotoPath = (await db.collection("teams").doc(teamId).get())
      .data().photoPath;
  assert.notEqual(updatedPhotoPath, photoPath);
  assert.ok(await getDownloadURL(ref(member.storage, updatedPhotoPath)));
  await assert.rejects(getDownloadURL(ref(member.storage, photoPath)));
  assert.equal((await db.collection("teams").doc(teamId)
      .collection("private").doc("access").get()).data().code, code);

  await call("leaveTeam", member.token);
  await assert.rejects(call("sendWorkout", owner.token, {
    recipientUids: [member.uid], workoutSourceKey: "team-mission-4",
    workoutSnapshot,
  }), /Only current teammates/);
  assert.equal((await db.collection("users").doc(member.uid)
      .collection("privateData").doc("team").get()).exists, false);
  await call("joinTeam", member.token, {code});
  await call("deleteTeam", owner.token);
  assert.equal((await db.collection("teams").doc(teamId).get()).exists, false);
  assert.equal((await db.collection("users").doc(member.uid)
      .collection("privateData").doc("team").get()).exists, false);
  await assert.rejects(call("joinTeam", member.token, {code}),
      /Team code not found/);
});
