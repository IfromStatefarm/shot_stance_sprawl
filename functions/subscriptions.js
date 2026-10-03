const crypto = require("node:crypto");
const fs = require("node:fs");
const path = require("node:path");
const {
  Environment,
  SignedDataVerifier,
  VerificationException,
  VerificationStatus,
} = require("@apple/app-store-server-library");
const {GoogleAuth} = require("google-auth-library");
const {FieldValue, getFirestore} = require("firebase-admin/firestore");
const {defineSecret, defineString} = require("firebase-functions/params");
const {onMessagePublished} = require("firebase-functions/v2/pubsub");
const {HttpsError, onCall, onRequest} = require("firebase-functions/v2/https");
const {enforceAppCheck} = require("./app_check");

const db = getFirestore();
const productId = "snap_go_pro_monthly";
const purchaseCollection = "subscriptionPurchases";

const androidPackageName = defineString("ANDROID_IAP_PACKAGE_NAME", {
  default: "com.snapandgo.shadowwrestling",
});
const appleBundleId = defineString("APPLE_IAP_BUNDLE_ID", {
  default: "com.snapandgo.shadowwrestling",
});
const appleAppId = defineString("APPLE_IAP_APP_ID", {
  description: "The app's numeric Apple ID from App Store Connect.",
});
const appleIssuerId = defineSecret("APPLE_IAP_ISSUER_ID");
const appleKeyId = defineSecret("APPLE_IAP_KEY_ID");
const applePrivateKey = defineSecret("APPLE_IAP_PRIVATE_KEY");
const appleSharedSecret = defineSecret("APPLE_IAP_SHARED_SECRET");
const appleSecrets = [
  appleIssuerId,
  appleKeyId,
  applePrivateKey,
  appleSharedSecret,
];
const callableOptions = {enforceAppCheck, secrets: appleSecrets};
const appleRootCertificates = [
  "AppleIncRootCertificate.cer",
  "AppleRootCA-G2.cer",
  "AppleRootCA-G3.cer",
].map((file) => fs.readFileSync(
    path.join(__dirname, "apple-root-certificates", file)));
const appleNotificationVerifierCache = new Map();

function requireUid(request) {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Sign in first.");
  return uid;
}

function checkedString(value, name, maxLength = 200000) {
  if (typeof value !== "string" || !value.trim() || value.length > maxLength) {
    throw new HttpsError("invalid-argument", `${name} is invalid.`);
  }
  return value.trim();
}

function purchaseKey(provider, identity) {
  return crypto.createHash("sha256")
      .update(`${provider}:${identity}`)
      .digest("hex");
}

function storeAccountToken(uid) {
  const bytes = Buffer.from(crypto.createHash("sha256")
      .update(`snap-and-go-store-account:${uid}`).digest().subarray(0, 16));
  bytes[6] = (bytes[6] & 0x0f) | 0x50;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  const compact = bytes.toString("hex");
  return `${compact.slice(0, 8)}-${compact.slice(8, 12)}-` +
    `${compact.slice(12, 16)}-${compact.slice(16, 20)}-${compact.slice(20)}`;
}

function base64UrlJson(value) {
  return Buffer.from(JSON.stringify(value)).toString("base64url");
}

function decodeJwsPayload(value) {
  const pieces = String(value || "").split(".");
  if (pieces.length !== 3) return null;
  try {
    return JSON.parse(Buffer.from(pieces[1], "base64url").toString("utf8"));
  } catch (_) {
    return null;
  }
}

function configuredAppleAppId() {
  const value = String(appleAppId.value() || "").trim();
  if (!/^[1-9]\d*$/.test(value) || !Number.isSafeInteger(Number(value))) {
    throw new HttpsError(
        "failed-precondition", "APPLE_IAP_APP_ID is not configured.");
  }
  return Number(value);
}

function appleNotificationVerifier(environment) {
  const bundleId = appleBundleId.value();
  const appId = environment === Environment.PRODUCTION ?
    configuredAppleAppId() : undefined;
  const cacheKey = `${environment}:${bundleId}:${appId || ""}`;
  if (!appleNotificationVerifierCache.has(cacheKey)) {
    appleNotificationVerifierCache.set(cacheKey, new SignedDataVerifier(
        appleRootCertificates,
        true,
        environment,
        bundleId,
        appId,
    ));
  }
  return appleNotificationVerifierCache.get(cacheKey);
}

async function verifiedAppStoreNotificationIdentity(signedPayload, verifiers) {
  let retryableError;
  let lastError;
  for (const verifier of verifiers) {
    try {
      const notification = await verifier.verifyAndDecodeNotification(
          signedPayload);
      const signedTransaction = notification.data?.signedTransactionInfo;
      if (typeof signedTransaction !== "string" || !signedTransaction) {
        return null;
      }
      const transaction = await verifier.verifyAndDecodeTransaction(
          signedTransaction);
      const identity = transaction.originalTransactionId;
      return identity == null || String(identity).length > 200 ?
        null : String(identity);
    } catch (error) {
      lastError = error;
      if (error instanceof VerificationException &&
          error.status === VerificationStatus.RETRYABLE_VERIFICATION_FAILURE) {
        retryableError = error;
      }
    }
  }
  throw retryableError || lastError || new Error(
      "App Store notification verification failed.");
}

function timestampMillis(value) {
  if (value == null) return 0;
  if (typeof value === "number") return value;
  if (typeof value === "string") {
    const numeric = Number(value);
    return Number.isFinite(numeric) ? numeric : Date.parse(value);
  }
  if (typeof value.toMillis === "function") return value.toMillis();
  if (value instanceof Date) return value.getTime();
  return 0;
}

function normalizedResult({
  provider,
  active,
  status,
  expiresAt,
  willRenew,
  credential,
}) {
  const expiryMillis = timestampMillis(expiresAt);
  return {
    provider,
    active: Boolean(active) && expiryMillis > Date.now(),
    status,
    productId,
    expiresAt: new Date(expiryMillis || 0),
    willRenew: Boolean(willRenew),
    credential,
  };
}

function googleStateIsEntitled(state) {
  // Cancellation disables the next renewal; access remains paid through the
  // line item's expiry. Revocation/chargeback moves Play to a non-entitled
  // state and is therefore excluded here.
  return new Set([
    "SUBSCRIPTION_STATE_ACTIVE",
    "SUBSCRIPTION_STATE_IN_GRACE_PERIOD",
    "SUBSCRIPTION_STATE_CANCELED",
  ]).has(state);
}

async function verifyGoogle(purchaseToken, uid) {
  const auth = new GoogleAuth({
    scopes: ["https://www.googleapis.com/auth/androidpublisher"],
  });
  const client = await auth.getClient();
  const packageName = androidPackageName.value();
  const url = "https://androidpublisher.googleapis.com/androidpublisher/v3/" +
    `applications/${encodeURIComponent(packageName)}/purchases/` +
    `subscriptionsv2/tokens/${encodeURIComponent(purchaseToken)}`;
  const headers = await client.getRequestHeaders(url);
  const response = await fetch(url, {headers});
  if (response.status === 404) {
    throw new HttpsError("not-found", "Google Play purchase was not found.");
  }
  if (!response.ok) {
    const body = await response.text();
    console.error("Google Play verification failed", response.status, body);
    throw new HttpsError("unavailable", "Google Play verification failed.");
  }

  const subscription = await response.json();
  const linkedAccount = subscription.externalAccountIdentifiers
      ?.obfuscatedExternalAccountId;
  if (linkedAccount && linkedAccount !== storeAccountToken(uid)) {
    throw new HttpsError(
        "permission-denied", "This purchase belongs to another app account.");
  }
  const lineItems = Array.isArray(subscription.lineItems) ?
    subscription.lineItems.filter((item) => item.productId === productId) : [];
  if (!lineItems.length) {
    throw new HttpsError(
        "permission-denied", "The purchase is not for Snap & Go Pro.");
  }
  const expiresAt = lineItems.reduce((latest, item) => {
    const candidate = Date.parse(item.expiryTime || "");
    return Number.isFinite(candidate) && candidate > latest ? candidate : latest;
  }, 0);
  const state = String(subscription.subscriptionState || "");
  const status = ({
    SUBSCRIPTION_STATE_ACTIVE: "active",
    SUBSCRIPTION_STATE_IN_GRACE_PERIOD: "grace_period",
    SUBSCRIPTION_STATE_CANCELED: "canceled",
    SUBSCRIPTION_STATE_EXPIRED: "expired",
    SUBSCRIPTION_STATE_ON_HOLD: "on_hold",
    SUBSCRIPTION_STATE_PAUSED: "paused",
    SUBSCRIPTION_STATE_PENDING: "pending",
  })[state] || "inactive";
  const willRenew = lineItems.some(
      (item) => item.autoRenewingPlan?.autoRenewEnabled === true);
  return normalizedResult({
    provider: "google_play",
    active: googleStateIsEntitled(state),
    status,
    expiresAt,
    willRenew,
    credential: {purchaseToken},
  });
}

function appleAuthorizationToken() {
  const issuerId = appleIssuerId.value();
  const keyId = appleKeyId.value();
  const privateKey = applePrivateKey.value().replace(/\\n/g, "\n");
  if (!issuerId || !keyId || !privateKey) {
    throw new HttpsError(
        "failed-precondition", "App Store verification is not configured.");
  }
  const now = Math.floor(Date.now() / 1000);
  const header = base64UrlJson({alg: "ES256", kid: keyId, typ: "JWT"});
  const payload = base64UrlJson({
    iss: issuerId,
    iat: now,
    exp: now + 300,
    aud: "appstoreconnect-v1",
    bid: appleBundleId.value(),
  });
  const unsigned = `${header}.${payload}`;
  const signature = crypto.sign("sha256", Buffer.from(unsigned), {
    key: privateKey,
    dsaEncoding: "ieee-p1363",
  }).toString("base64url");
  return `${unsigned}.${signature}`;
}

async function fetchAppleSubscription(transactionId, environment) {
  const production = "https://api.storekit.itunes.apple.com";
  const sandbox = "https://api.storekit-sandbox.itunes.apple.com";
  const bases = environment === "Sandbox" ?
    [sandbox, production] : [production, sandbox];
  const authorization = appleAuthorizationToken();
  for (const base of bases) {
    const url = `${base}/inApps/v1/subscriptions/` +
      encodeURIComponent(transactionId);
    const response = await fetch(url, {
      headers: {Authorization: `Bearer ${authorization}`},
    });
    if (response.ok) return response.json();
    if (response.status !== 404) {
      const body = await response.text();
      console.error("App Store verification failed", response.status, body);
      throw new HttpsError("unavailable", "App Store verification failed.");
    }
  }
  throw new HttpsError("not-found", "App Store transaction was not found.");
}

function appleResultFromHistory(history, transactionId, uid) {
  const candidates = [];
  for (const group of history.data || []) {
    for (const last of group.lastTransactions || []) {
      const transaction = decodeJwsPayload(last.signedTransactionInfo);
      const renewal = decodeJwsPayload(last.signedRenewalInfo) || {};
      if (!transaction || transaction.productId !== productId) continue;
      if (transaction.bundleId !== appleBundleId.value()) continue;
      candidates.push({transaction, renewal, appleStatus: Number(last.status)});
    }
  }
  candidates.sort(
      (a, b) => Number(b.transaction.expiresDate || 0) -
        Number(a.transaction.expiresDate || 0));
  const latest = candidates[0];
  if (!latest) {
    throw new HttpsError(
        "permission-denied", "The transaction is not for Snap & Go Pro.");
  }
  const {transaction, renewal, appleStatus} = latest;
  if (transaction.appAccountToken &&
      transaction.appAccountToken.toLowerCase() !== storeAccountToken(uid)) {
    throw new HttpsError(
        "permission-denied", "This transaction belongs to another app account.");
  }
  const revoked = Number(transaction.revocationDate || 0) > 0 ||
    appleStatus === 5;
  const status = revoked ? "revoked" : ({
    1: "active",
    2: "expired",
    3: "billing_retry",
    4: "grace_period",
    5: "revoked",
  })[appleStatus] || "inactive";
  return normalizedResult({
    provider: "app_store",
    active: !revoked && (appleStatus === 1 || appleStatus === 4),
    status,
    expiresAt: Number(transaction.expiresDate || 0),
    willRenew: Number(renewal.autoRenewStatus || 0) === 1,
    credential: {
      transactionId: String(
          transaction.originalTransactionId || transactionId),
    },
  });
}

async function verifyAppleServerApi(transactionId, uid, environment) {
  const history = await fetchAppleSubscription(transactionId, environment);
  return appleResultFromHistory(history, transactionId, uid);
}

async function postAppleReceipt(baseUrl, receipt) {
  const response = await fetch(`${baseUrl}/verifyReceipt`, {
    method: "POST",
    headers: {"Content-Type": "application/json"},
    body: JSON.stringify({
      "receipt-data": receipt,
      "password": appleSharedSecret.value(),
      "exclude-old-transactions": false,
    }),
  });
  if (!response.ok) {
    throw new HttpsError("unavailable", "App Store verification failed.");
  }
  return response.json();
}

async function verifyAppleReceipt(receipt) {
  if (!appleSharedSecret.value()) {
    throw new HttpsError(
        "failed-precondition", "App Store receipt verification is not configured.");
  }
  let response = await postAppleReceipt("https://buy.itunes.apple.com", receipt);
  if (Number(response.status) === 21007) {
    response = await postAppleReceipt(
        "https://sandbox.itunes.apple.com", receipt);
  }
  if (Number(response.status) !== 0 ||
      response.receipt?.bundle_id !== appleBundleId.value()) {
    throw new HttpsError("permission-denied", "App Store receipt is invalid.");
  }
  const transactions = (response.latest_receipt_info || [])
      .filter((item) => item.product_id === productId)
      .sort((a, b) => Number(b.expires_date_ms) - Number(a.expires_date_ms));
  const latest = transactions[0];
  if (!latest) {
    throw new HttpsError(
        "permission-denied", "The receipt is not for Snap & Go Pro.");
  }
  const revoked = Boolean(latest.cancellation_date_ms);
  const renewal = (response.pending_renewal_info || []).find(
      (item) => item.original_transaction_id ===
        latest.original_transaction_id) || {};
  const expiresAt = Number(latest.expires_date_ms || 0);
  return normalizedResult({
    provider: "app_store",
    active: !revoked && expiresAt > Date.now(),
    status: revoked ? "revoked" :
      (expiresAt > Date.now() ? "active" : "expired"),
    expiresAt,
    willRenew: String(renewal.auto_renew_status || "0") === "1",
    credential: {
      transactionId: String(latest.original_transaction_id),
      receipt,
    },
  });
}

async function verifyApple(verificationData, purchaseId, uid) {
  const jws = decodeJwsPayload(verificationData);
  if (jws?.transactionId) {
    return verifyAppleServerApi(
        String(jws.transactionId), uid, jws.environment);
  }
  if (purchaseId && /^\d+$/.test(purchaseId)) {
    try {
      return await verifyAppleServerApi(purchaseId, uid);
    } catch (error) {
      if (!(error instanceof HttpsError) ||
          error.code !== "failed-precondition") throw error;
    }
  }
  return verifyAppleReceipt(verificationData);
}

async function verifyCredential(provider, credential, uid) {
  if (provider === "google_play") {
    return verifyGoogle(credential.purchaseToken, uid);
  }
  if (provider === "app_store") {
    if (credential.transactionId) {
      try {
        return await verifyAppleServerApi(credential.transactionId, uid);
      } catch (error) {
        if (!credential.receipt || !(error instanceof HttpsError) ||
            error.code !== "failed-precondition") throw error;
      }
    }
    return verifyAppleReceipt(credential.receipt);
  }
  throw new HttpsError("invalid-argument", "Unknown store provider.");
}

function publicEntitlement(uid, value) {
  const expiryMillis = timestampMillis(value?.expiresAt);
  return {
    userId: uid,
    active: Boolean(value?.active) && expiryMillis > Date.now(),
    status: value?.status || "inactive",
    productId: value?.productId || null,
    provider: value?.provider || null,
    expiresAt: expiryMillis ? new Date(expiryMillis).toISOString() : null,
    willRenew: Boolean(value?.willRenew),
  };
}

async function saveVerifiedPurchase(uid, result) {
  const identity = result.provider === "google_play" ?
    result.credential.purchaseToken : result.credential.transactionId;
  const reference = db.collection(purchaseCollection)
      .doc(purchaseKey(result.provider, identity));
  const entitlement = db.collection("users").doc(uid)
      .collection("privateData").doc("subscription");
  await db.runTransaction(async (transaction) => {
    const existing = await transaction.get(reference);
    const owner = existing.data()?.uid;
    if (owner && owner !== uid) {
      throw new HttpsError(
          "already-exists",
          "This store subscription is already linked to another account.");
    }
    transaction.set(reference, {
      uid,
      provider: result.provider,
      productId,
      credential: result.credential,
      createdAt: existing.exists ?
        existing.data().createdAt : FieldValue.serverTimestamp(),
      verifiedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
    transaction.set(entitlement, {
      active: result.active,
      status: result.status,
      productId,
      provider: result.provider,
      expiresAt: result.expiresAt,
      willRenew: result.willRenew,
      verifiedAt: FieldValue.serverTimestamp(),
    });
  });
  return publicEntitlement(uid, result);
}

function chooseBest(results) {
  return [...results].sort((a, b) => {
    if (a.active !== b.active) return a.active ? -1 : 1;
    return timestampMillis(b.expiresAt) - timestampMillis(a.expiresAt);
  })[0];
}

async function refreshUser(uid) {
  const purchases = await db.collection(purchaseCollection)
      .where("uid", "==", uid).limit(20).get();
  if (purchases.empty) return publicEntitlement(uid, null);
  const results = [];
  let lastError;
  for (const purchase of purchases.docs) {
    try {
      const data = purchase.data();
      results.push(await verifyCredential(
          data.provider, data.credential || {}, uid));
      await purchase.ref.set({verifiedAt: FieldValue.serverTimestamp()},
          {merge: true});
    } catch (error) {
      lastError = error;
      console.error("Stored subscription revalidation failed", purchase.id, error);
    }
  }
  if (!results.length) {
    throw lastError instanceof HttpsError ? lastError :
      new HttpsError("unavailable", "Subscription verification failed.");
  }
  const result = chooseBest(results);
  await db.collection("users").doc(uid).collection("privateData")
      .doc("subscription").set({
        active: result.active,
        status: result.status,
        productId,
        provider: result.provider,
        expiresAt: result.expiresAt,
        willRenew: result.willRenew,
        verifiedAt: FieldValue.serverTimestamp(),
      });
  return publicEntitlement(uid, result);
}

async function refreshPurchase(provider, identity) {
  const reference = db.collection(purchaseCollection)
      .doc(purchaseKey(provider, identity));
  const purchase = await reference.get();
  if (!purchase.exists) return false;
  await refreshUser(purchase.data().uid);
  return true;
}

exports.verifySubscriptionPurchase = onCall(
    callableOptions,
    async (request) => {
      const uid = requireUid(request);
      const requestedProduct = checkedString(
          request.data?.productId, "productId", 200);
      if (requestedProduct !== productId) {
        throw new HttpsError("invalid-argument", "Unknown subscription product.");
      }
      const source = checkedString(request.data?.source, "source", 100);
      const verificationData = checkedString(
          request.data?.verificationData, "verificationData");
      const purchaseId = typeof request.data?.purchaseId === "string" ?
        request.data.purchaseId : null;
      let result;
      if (source === "google_play") {
        result = await verifyGoogle(verificationData, uid);
      } else if (source === "app_store") {
        result = await verifyApple(verificationData, purchaseId, uid);
      } else {
        throw new HttpsError("invalid-argument", "Unsupported purchase source.");
      }
      return saveVerifiedPurchase(uid, result);
    });

exports.getSubscriptionEntitlement = onCall(
    callableOptions,
    async (request) => refreshUser(requireUid(request)));

exports.handlePlaySubscriptionNotification = onMessagePublished(
    "play-subscription-notifications",
    async (event) => {
      const notification = event.data.message.json?.subscriptionNotification;
      const token = notification?.purchaseToken;
      if (typeof token !== "string" || !token) return;
      await refreshPurchase("google_play", token);
    });

exports.handleAppStoreSubscriptionNotification = onRequest(
    {secrets: appleSecrets},
    async (request, response) => {
      const signedPayload = request.body?.signedPayload;
      if (typeof signedPayload !== "string" || !signedPayload) {
        response.status(400).send("invalid notification");
        return;
      }
      const verifiers = [
        appleNotificationVerifier(Environment.PRODUCTION),
        appleNotificationVerifier(Environment.SANDBOX),
      ];
      let identity;
      try {
        identity = await verifiedAppStoreNotificationIdentity(
            signedPayload, verifiers);
      } catch (error) {
        if (error instanceof VerificationException &&
            error.status === VerificationStatus.RETRYABLE_VERIFICATION_FAILURE) {
          console.error("App Store notification verification unavailable", error);
          response.status(503).send("verification unavailable");
          return;
        }
        console.warn("Rejected invalid App Store notification", error);
        response.status(400).send("invalid notification");
        return;
      }
      if (identity) {
        await refreshPurchase("app_store", identity);
      }
      response.status(200).send("ok");
    });

exports._test = {
  appleResultFromHistory,
  appleNotificationVerifier,
  decodeJwsPayload,
  googleStateIsEntitled,
  normalizedResult,
  publicEntitlement,
  purchaseKey,
  storeAccountToken,
  verifiedAppStoreNotificationIdentity,
};
