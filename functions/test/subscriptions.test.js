const assert = require("node:assert/strict");
const test = require("node:test");
const {initializeApp} = require("firebase-admin/app");

initializeApp({projectId: "demo-snap-and-go"});
const {
  appleNotificationVerifier,
  decodeJwsPayload,
  googleStateIsEntitled,
  normalizedResult,
  publicEntitlement,
  purchaseKey,
  storeAccountToken,
  verifiedAppStoreNotificationIdentity,
} = require("../subscriptions")._test;
const {Environment} = require("@apple/app-store-server-library");

function unsignedJws(payload) {
  const encode = (value) => Buffer.from(JSON.stringify(value)).toString("base64url");
  return `${encode({alg: "ES256"})}.${encode(payload)}.signature`;
}

test("decodeJwsPayload reads the signed payload body", () => {
  assert.deepEqual(decodeJwsPayload(unsignedJws({transactionId: "123"})), {
    transactionId: "123",
  });
  assert.equal(decodeJwsPayload("not-a-jws"), null);
});

test("App Store notifications reject payload-only JWS tokens", async () => {
  const forgedTransaction = unsignedJws({
    bundleId: "com.snapandgo.shadowwrestling",
    environment: "Sandbox",
    originalTransactionId: "123",
  });
  const forgedNotification = unsignedJws({
    notificationType: "DID_RENEW",
    data: {
      appAppleId: 123456789,
      bundleId: "com.snapandgo.shadowwrestling",
      environment: "Sandbox",
      signedTransactionInfo: forgedTransaction,
    },
  });
  const verifier = appleNotificationVerifier(Environment.SANDBOX);

  await assert.rejects(
      verifiedAppStoreNotificationIdentity(forgedNotification, [verifier]));
});

test("App Store notification identity comes from a verified transaction", async () => {
  const calls = [];
  const verifier = {
    async verifyAndDecodeNotification(value) {
      calls.push(["notification", value]);
      return {data: {signedTransactionInfo: "signed-transaction"}};
    },
    async verifyAndDecodeTransaction(value) {
      calls.push(["transaction", value]);
      return {originalTransactionId: "123"};
    },
  };

  assert.equal(await verifiedAppStoreNotificationIdentity(
      "signed-notification", [verifier]), "123");
  assert.deepEqual(calls, [
    ["notification", "signed-notification"],
    ["transaction", "signed-transaction"],
  ]);
});

test("normalizedResult never grants an expired subscription", () => {
  const result = normalizedResult({
    provider: "app_store",
    active: true,
    status: "active",
    expiresAt: Date.now() - 1,
    willRenew: true,
    credential: {transactionId: "123"},
  });
  assert.equal(result.active, false);
});

test("Play cancellation retains access only through the paid period", () => {
  assert.equal(
      googleStateIsEntitled("SUBSCRIPTION_STATE_CANCELED"), true);
  assert.equal(
      googleStateIsEntitled("SUBSCRIPTION_STATE_EXPIRED"), false);
  assert.equal(
      googleStateIsEntitled("SUBSCRIPTION_STATE_ON_HOLD"), false);
});

test("publicEntitlement removes active access after local expiry", () => {
  const entitlement = publicEntitlement("user-1", {
    active: true,
    status: "active",
    productId: "snap_go_pro_monthly",
    provider: "google_play",
    expiresAt: new Date(Date.now() - 1000),
    willRenew: true,
  });
  assert.equal(entitlement.active, false);
  assert.equal(entitlement.userId, "user-1");
});

test("purchase keys bind provider credentials without storing them in IDs", () => {
  const first = purchaseKey("google_play", "secret-token");
  const second = purchaseKey("google_play", "other-token");
  assert.match(first, /^[a-f0-9]{64}$/);
  assert.notEqual(first, second);
  assert.equal(first.includes("secret-token"), false);
});

test("store account tokens are stable UUIDs that hide Firebase UIDs", () => {
  const token = storeAccountToken("firebase-user-123");
  assert.equal(token, "f3a771a1-e34f-5c7e-b4c6-a49b28bb92ad");
  assert.match(token, /^[a-f0-9-]{36}$/);
  assert.equal(token, storeAccountToken("firebase-user-123"));
  assert.notEqual(token, storeAccountToken("another-user"));
  assert.equal(token.includes("firebase-user-123"), false);
});
