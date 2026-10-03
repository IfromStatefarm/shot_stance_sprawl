const {createHash, randomBytes} = require("node:crypto");
const {getFirestore, FieldValue} = require("firebase-admin/firestore");
const {getStorage} = require("firebase-admin/storage");
const {HttpsError, onCall} = require("firebase-functions/v2/https");
const {logger} = require("firebase-functions");
const {enforceAppCheck} = require("./app_check");

const db = getFirestore();
const options = {enforceAppCheck};
const photoTypes = new Set(["image/jpeg", "image/png", "image/webp"]);

function uidFor(request) {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Sign in first.");
  return uid;
}

function teamText(value, field, max) {
  const text = typeof value === "string" ? value.trim() : "";
  if (!text || text.length > max) {
    throw new HttpsError("invalid-argument", `Enter a valid ${field}.`);
  }
  return text;
}

function normalizedCode(value) {
  const code = String(value || "").replace(/[\s-]/g, "").toUpperCase();
  if (!/^[0-9A-F]{12}$/.test(code)) {
    throw new HttpsError("invalid-argument", "Enter a valid team access code.");
  }
  return code;
}

function codeHash(code) {
  return createHash("sha256").update(code).digest("hex");
}

function newCode() {
  const value = randomBytes(6).toString("hex").toUpperCase();
  return `${value.slice(0, 4)}-${value.slice(4, 8)}-${value.slice(8)}`;
}

function membershipRef(uid) {
  return db.collection("users").doc(uid).collection("privateData").doc("team");
}

function teamRef(teamId) {
  return db.collection("teams").doc(teamId);
}

async function stagedPhoto(uid, path) {
  const normalized = teamText(path, "team photo", 300);
  if (!new RegExp(`^teamPhotoUploads/${uid}/[a-zA-Z0-9_-]{8,80}$`).test(normalized)) {
    throw new HttpsError("invalid-argument", "Upload your own team photo first.");
  }
  const bucket = getStorage().bucket();
  const file = bucket.file(normalized);
  const [metadata] = await file.getMetadata().catch(() => {
    logger.warn("Team photo upload lookup failed", {
      bucket: bucket.name, path: normalized,
    });
    throw new HttpsError("not-found", "Team photo upload was not found.");
  });
  if (!photoTypes.has(metadata.contentType) ||
      Number(metadata.size) <= 0 ||
      Number(metadata.size) > 5 * 1024 * 1024) {
    throw new HttpsError("invalid-argument", "Use a photo under 5 MB.");
  }
  return file;
}

async function copyPhoto(uid, stagedPath, teamId) {
  const source = await stagedPhoto(uid, stagedPath);
  const destinationPath = `teamPhotos/${teamId}/${randomBytes(12).toString("hex")}`;
  const destination = getStorage().bucket().file(destinationPath);
  await source.copy(destination);
  return {source, destination, path: destinationPath};
}

async function discardPhoto(photo) {
  if (photo) await photo.destination.delete({ignoreNotFound: true}).catch(() => {});
}

async function createTeam(uid, data) {
  const name = teamText(data?.name, "team name", 80);
  const state = teamText(data?.state, "state", 40);
  const team = db.collection("teams").doc();
  const photo = await copyPhoto(uid, data?.photoPath, team.id);
  let code;
  try {
    // The mapping document enforces uniqueness even when two requests race.
    for (let attempt = 0; attempt < 5; attempt++) {
      code = newCode();
      const lookup = db.collection("teamCodes").doc(codeHash(normalizedCode(code)));
      try {
        await db.runTransaction(async (transaction) => {
          const [member, existingCode, account] = await Promise.all([
            transaction.get(membershipRef(uid)),
            transaction.get(lookup),
            transaction.get(db.collection("users").doc(uid)),
          ]);
          if (!account.exists) {
            throw new HttpsError("failed-precondition", "Finish creating your account first.");
          }
          if (member.exists) {
            throw new HttpsError("already-exists", "Leave your current team first.");
          }
          if (existingCode.exists) {
            throw new HttpsError("already-exists", "Code collision.");
          }
          transaction.create(team, {
            name, state, photoPath: photo.path, ownerUid: uid,
            status: "active", createdAt: FieldValue.serverTimestamp(),
            updatedAt: FieldValue.serverTimestamp(),
          });
          transaction.create(team.collection("private").doc("access"), {code});
          transaction.create(lookup, {teamId: team.id});
          transaction.create(membershipRef(uid), {
            teamId: team.id, role: "owner",
            joinedAt: FieldValue.serverTimestamp(),
            updatedAt: FieldValue.serverTimestamp(),
          });
          transaction.create(team.collection("members").doc(uid), {
            uid, role: "owner", joinedAt: FieldValue.serverTimestamp(),
          });
        });
        await photo.source.delete({ignoreNotFound: true}).catch(() => {});
        return {teamId: team.id};
      } catch (error) {
        if (error instanceof HttpsError && error.message === "Code collision.") continue;
        throw error;
      }
    }
    throw new HttpsError("internal", "Could not generate a team code.");
  } catch (error) {
    await discardPhoto(photo);
    throw error;
  }
}

async function joinTeam(uid, inputCode) {
  const code = normalizedCode(inputCode);
  const lookupRef = db.collection("teamCodes").doc(codeHash(code));
  await db.runTransaction(async (transaction) => {
    const [member, lookup, account] = await Promise.all([
      transaction.get(membershipRef(uid)),
      transaction.get(lookupRef),
      transaction.get(db.collection("users").doc(uid)),
    ]);
    if (!account.exists) {
      throw new HttpsError("failed-precondition", "Finish creating your account first.");
    }
    if (member.exists) {
      throw new HttpsError("already-exists", "Leave your current team first.");
    }
    const teamId = lookup.data()?.teamId;
    if (!teamId) throw new HttpsError("not-found", "Team code not found.");
    const team = await transaction.get(teamRef(teamId));
    if (team.data()?.status !== "active") {
      throw new HttpsError("not-found", "Team code not found.");
    }
    transaction.create(membershipRef(uid), {
      teamId, role: "member", joinedAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
    transaction.create(teamRef(teamId).collection("members").doc(uid), {
      uid, role: "member", joinedAt: FieldValue.serverTimestamp(),
    });
  });
  return {joined: true};
}

async function editTeam(uid, data) {
  const name = teamText(data?.name, "team name", 80);
  const state = teamText(data?.state, "state", 40);
  const member = await membershipRef(uid).get();
  if (member.data()?.role !== "owner") {
    throw new HttpsError("permission-denied", "Only the team creator can edit it.");
  }
  const teamId = member.data().teamId;
  const photo = data?.photoPath ? await copyPhoto(uid, data.photoPath, teamId) : null;
  let priorPhotoPath;
  try {
    await db.runTransaction(async (transaction) => {
      const [freshMember, team] = await Promise.all([
        transaction.get(membershipRef(uid)), transaction.get(teamRef(teamId)),
      ]);
      if (freshMember.data()?.teamId !== teamId ||
          freshMember.data()?.role !== "owner" ||
          team.data()?.status !== "active" || team.data()?.ownerUid !== uid) {
        throw new HttpsError("permission-denied", "Only the team creator can edit it.");
      }
      priorPhotoPath = team.data().photoPath;
      transaction.update(teamRef(teamId), {
        name, state, ...(photo ? {photoPath: photo.path} : {}),
        updatedAt: FieldValue.serverTimestamp(),
      });
    });
  } catch (error) {
    await discardPhoto(photo);
    throw error;
  }
  if (photo) {
    await photo.source.delete({ignoreNotFound: true}).catch(() => {});
    if (priorPhotoPath) {
      await getStorage().bucket().file(priorPhotoPath)
          .delete({ignoreNotFound: true}).catch(() => {});
    }
  }
  return {updated: true};
}

async function leaveTeam(uid) {
  await db.runTransaction(async (transaction) => {
    const member = await transaction.get(membershipRef(uid));
    if (!member.exists) return;
    if (member.data().role === "owner") {
      throw new HttpsError("failed-precondition", "Delete your team instead.");
    }
    transaction.delete(membershipRef(uid));
    transaction.delete(teamRef(member.data().teamId).collection("members").doc(uid));
  });
  return {left: true};
}

async function deleteTeam(uid) {
  const member = await membershipRef(uid).get();
  if (member.data()?.role !== "owner") {
    throw new HttpsError("permission-denied", "Only the team creator can delete it.");
  }
  const teamId = member.data().teamId;
  let photoPath;
  await db.runTransaction(async (transaction) => {
    const team = await transaction.get(teamRef(teamId));
    if (team.data()?.ownerUid !== uid) {
      throw new HttpsError("permission-denied", "Only the team creator can delete it.");
    }
    photoPath = team.data().photoPath;
    transaction.update(teamRef(teamId), {
      status: "deleting", updatedAt: FieldValue.serverTimestamp(),
    });
  });
  const access = await teamRef(teamId).collection("private").doc("access").get();
  if (access.data()?.code) {
    await db.collection("teamCodes")
        .doc(codeHash(normalizedCode(access.data().code))).delete();
  }
  while (true) {
    const page = await teamRef(teamId).collection("members").limit(100).get();
    const otherMembers = page.docs.filter((document) => document.id !== uid);
    if (otherMembers.length === 0) break;
    for (const document of otherMembers) {
      await db.runTransaction(async (transaction) => {
        const current = await transaction.get(membershipRef(document.id));
        if (current.data()?.teamId === teamId) {
          transaction.delete(membershipRef(document.id));
        }
        transaction.delete(document.ref);
      });
    }
  }
  await db.runTransaction(async (transaction) => {
    const freshMember = await transaction.get(membershipRef(uid));
    if (freshMember.data()?.teamId !== teamId ||
        freshMember.data()?.role !== "owner") {
      throw new HttpsError("failed-precondition", "Team deletion cannot finish.");
    }
    transaction.delete(teamRef(teamId).collection("private").doc("access"));
    transaction.delete(teamRef(teamId).collection("members").doc(uid));
    transaction.delete(membershipRef(uid));
    transaction.delete(teamRef(teamId));
  });
  if (photoPath) {
    await getStorage().bucket().file(photoPath)
        .delete({ignoreNotFound: true}).catch(() => {});
  }
  return {deleted: true};
}

async function removeAccountFromTeam(uid) {
  const member = await membershipRef(uid).get();
  if (!member.exists) return;
  if (member.data().role === "owner") await deleteTeam(uid);
  else await leaveTeam(uid);
}

exports.createTeam = onCall(options, async (request) =>
  createTeam(uidFor(request), request.data));
exports.joinTeam = onCall(options, async (request) =>
  joinTeam(uidFor(request), request.data?.code));
exports.editTeam = onCall(options, async (request) =>
  editTeam(uidFor(request), request.data));
exports.leaveTeam = onCall(options, async (request) =>
  leaveTeam(uidFor(request)));
exports.deleteTeam = onCall(options, async (request) =>
  deleteTeam(uidFor(request)));
exports.removeAccountFromTeam = removeAccountFromTeam;
