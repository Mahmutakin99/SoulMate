const { onValueCreated } = require("firebase-functions/v2/database");
const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const logger = require("firebase-functions/logger");
const admin = require("firebase-admin");

admin.initializeApp();

const INVALID_TOKEN_CODES = new Set([
  "messaging/registration-token-not-registered",
  "messaging/invalid-registration-token"
]);

const CALLABLE_REGION = "europe-west1";
const DATABASE_TRIGGER_REGION = "us-central1";
const REQUEST_EXPIRY_SECONDS = 24 * 60 * 60;
const CLOUD_MESSAGE_TTL_SECONDS = 7 * 24 * 60 * 60;

const REQUEST_TYPE = {
  PAIR: "pair",
  UNPAIR: "unpair"
};

const REQUEST_STATUS = {
  PENDING: "pending",
  ACCEPTED: "accepted",
  REJECTED: "rejected",
  EXPIRED: "expired"
};

function nowSeconds() {
  return Math.floor(Date.now() / 1000);
}

function normalizedString(value) {
  if (typeof value !== "string") {
    return "";
  }
  return value.trim();
}

function readPartnerID(profile) {
  return normalizedString(profile?.partnerID);
}

function readName(profile, key) {
  const value = profile?.[key];
  if (typeof value !== "string") {
    return "";
  }
  return value.trim();
}

function readPairCode(profile) {
  const value = profile?.sixDigitUID;
  return typeof value === "string" ? value : "";
}

function requestChatID(uidA, uidB) {
  return [uidA, uidB].sort().join("_");
}

async function loadUserProfile(uid) {
  const snap = await admin.database().ref(`/users/${uid}`).get();
  return snap.val() || {};
}

function isRequestExpired(requestData) {
  const expiresAt = Number(requestData?.expiresAt || 0);
  return expiresAt > 0 && nowSeconds() >= expiresAt;
}

async function hasPendingRequestBetween(fromUID, toUID, type) {
  const snap = await admin.database()
    .ref("/relationshipRequests")
    .orderByChild("fromUID")
    .equalTo(fromUID)
    .get();

  if (!snap.exists()) {
    return false;
  }

  const requests = snap.val() || {};
  const now = nowSeconds();
  return Object.values(requests).some((item) => {
    if (!item || typeof item !== "object") {
      return false;
    }
    return item.toUID === toUID &&
      item.type === type &&
      item.status === REQUEST_STATUS.PENDING &&
      Number(item.expiresAt || 0) > now;
  });
}

exports.sendEncryptedMessagePush = onValueCreated(
  {
    ref: "/chats/{chatId}/messages/{messageId}",
    region: DATABASE_TRIGGER_REGION
  },
  async (event) => {
    const message = event.data.val();
    if (!message) return;

    const recipientID = typeof message.recipientID === "string" ? message.recipientID : "";
    const senderID = typeof message.senderID === "string" ? message.senderID : "";
    const encryptedPayload = typeof message.payload === "string" ? message.payload : "";

    if (!recipientID || !senderID || !encryptedPayload) {
      logger.warn("Eksik mesaj alanı, push atlanıyor.", {
        chatId: event.params.chatId,
        messageId: event.params.messageId
      });
      return;
    }

    const tokenSnapshot = await admin.database().ref(`/users/${recipientID}/fcmToken`).get();
    const token = tokenSnapshot.val();

    if (typeof token !== "string" || token.length === 0) {
      logger.info("Alıcı token yok, push atlanıyor.", {
        recipientID,
        chatId: event.params.chatId
      });
      return;
    }

    const payload = {
      token,
      data: {
        enc_body: encryptedPayload,
        sender_id: senderID,
        chat_id: String(event.params.chatId || "")
      },
      apns: {
        headers: {
          "apns-priority": "10"
        },
        payload: {
          aps: {
            alert: {
              title: "SoulMate",
              body: "Yeni bir mesajın var"
            },
            sound: "default",
            "mutable-content": 1
          }
        }
      }
    };

    try {
      await admin.messaging().send(payload);
      logger.info("Push başarıyla gönderildi.", {
        recipientID,
        chatId: event.params.chatId,
        messageId: event.params.messageId
      });
    } catch (error) {
      logger.error("Push gönderimi başarısız.", {
        recipientID,
        chatId: event.params.chatId,
        messageId: event.params.messageId,
        errorCode: error.code,
        errorMessage: error.message
      });

      if (INVALID_TOKEN_CODES.has(error.code)) {
        await admin.database().ref(`/users/${recipientID}/fcmToken`).remove();
        logger.info("Geçersiz token temizlendi.", { recipientID });
      }
    }
  }
);

exports.ackMessageStored = onCall(
  { region: CALLABLE_REGION },
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) {
      throw new HttpsError("unauthenticated", "auth_required");
    }

    const chatID = normalizedString(request.data?.chatID);
    const messageID = normalizedString(request.data?.messageID);
    if (!chatID || !messageID) {
      throw new HttpsError("invalid-argument", "invalid_ack_input");
    }

    const messageRef = admin.database().ref(`/chats/${chatID}/messages/${messageID}`);
    const snap = await messageRef.get();
    if (!snap.exists()) {
      return { success: true, alreadyAcked: true };
    }

    const message = snap.val() || {};
    if (normalizedString(message.recipientID) !== uid) {
      throw new HttpsError("failed-precondition", "ack_forbidden");
    }

    await messageRef.remove();
    return { success: true };
  }
);

exports.cleanupExpiredTransientMessages = onSchedule(
  {
    region: DATABASE_TRIGGER_REGION,
    schedule: "every 6 hours",
    timeZone: "Etc/UTC"
  },
  async () => {
    const cutoff = nowSeconds() - CLOUD_MESSAGE_TTL_SECONDS;
    const chatsSnapshot = await admin.database().ref("/chats").get();
    if (!chatsSnapshot.exists()) {
      return;
    }

    const updates = {};
    let deleteCount = 0;

    chatsSnapshot.forEach((chatSnap) => {
      const chatID = chatSnap.key;
      const messages = chatSnap.child("messages");
      if (!messages.exists()) {
        return;
      }

      messages.forEach((messageSnap) => {
        const message = messageSnap.val() || {};
        const sentAt = Number(message.sentAt || 0);
        if (sentAt > 0 && sentAt <= cutoff) {
          updates[`/chats/${chatID}/messages/${messageSnap.key}`] = null;
          deleteCount += 1;
        }
      });
    });

    if (deleteCount > 0) {
      await admin.database().ref().update(updates);
    }

    logger.info("Transient message cleanup completed.", {
      deletedMessages: deleteCount,
      cutoff
    });
  }
);

exports.deleteConversationForUnpair = onCall(
  { region: CALLABLE_REGION },
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) {
      throw new HttpsError("unauthenticated", "Authentication is required.");
    }

    const partnerUID = normalizedString(request.data?.partnerUID);
    if (!partnerUID) {
      throw new HttpsError("invalid-argument", "partnerUID is required.");
    }
    if (partnerUID === uid) {
      throw new HttpsError("invalid-argument", "partnerUID cannot be the same as uid.");
    }

    const requesterProfile = await loadUserProfile(uid);
    if (readPartnerID(requesterProfile) !== partnerUID) {
      throw new HttpsError("failed-precondition", "Requester is not actively paired with partnerUID.");
    }

    const chatID = requestChatID(uid, partnerUID);
    try {
      await Promise.all([
        admin.database().ref(`/chats/${chatID}`).remove(),
        admin.database().ref(`/events/${chatID}`).remove()
      ]);
    } catch (error) {
      logger.error("Conversation delete failed.", {
        uid,
        partnerUID,
        chatID,
        errorMessage: error?.message || String(error)
      });
      throw new HttpsError("internal", "Conversation delete failed.");
    }

    logger.info("Conversation deleted for unpair.", { uid, partnerUID, chatID });
    return { success: true, chatID };
  }
);

exports.createPairRequest = onCall(
  { region: CALLABLE_REGION },
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) {
      throw new HttpsError("unauthenticated", "auth_required");
    }

    const partnerCode = normalizedString(request.data?.partnerCode);
    if (!/^[0-9]{6}$/.test(partnerCode)) {
      throw new HttpsError("invalid-argument", "invalid_pair_code");
    }

    const requesterProfile = await loadUserProfile(uid);
    if (readPartnerID(requesterProfile)) {
      throw new HttpsError("failed-precondition", "user_already_paired");
    }

    const partnerCodeSnap = await admin.database().ref(`/pairCodes/${partnerCode}`).get();
    const partnerUID = normalizedString(partnerCodeSnap.val());
    if (!partnerUID) {
      throw new HttpsError("failed-precondition", "partner_not_found");
    }
    if (partnerUID === uid) {
      throw new HttpsError("invalid-argument", "self_pair_not_allowed");
    }

    const partnerProfile = await loadUserProfile(partnerUID);
    if (readPartnerID(partnerProfile)) {
      throw new HttpsError("failed-precondition", "target_already_paired");
    }

    const duplicateOutgoing = await hasPendingRequestBetween(uid, partnerUID, REQUEST_TYPE.PAIR);
    const duplicateIncoming = await hasPendingRequestBetween(partnerUID, uid, REQUEST_TYPE.PAIR);
    if (duplicateOutgoing || duplicateIncoming) {
      throw new HttpsError("failed-precondition", "duplicate_pending_pair_request");
    }

    const createdAt = nowSeconds();
    const expiresAt = createdAt + REQUEST_EXPIRY_SECONDS;
    const requestRef = admin.database().ref("/relationshipRequests").push();
    const requestID = requestRef.key;
    if (!requestID) {
      throw new HttpsError("internal", "request_create_failed");
    }

    const payload = {
      id: requestID,
      type: REQUEST_TYPE.PAIR,
      status: REQUEST_STATUS.PENDING,
      fromUID: uid,
      toUID: partnerUID,
      fromFirstName: readName(requesterProfile, "firstName"),
      fromLastName: readName(requesterProfile, "lastName"),
      fromSixDigitUID: readPairCode(requesterProfile),
      createdAt,
      expiresAt
    };

    await requestRef.set(payload);
    return { success: true, requestID };
  }
);

exports.respondPairRequest = onCall(
  { region: CALLABLE_REGION },
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) {
      throw new HttpsError("unauthenticated", "auth_required");
    }

    const requestID = normalizedString(request.data?.requestID);
    const decision = normalizedString(request.data?.decision);

    if (!requestID) {
      throw new HttpsError("invalid-argument", "request_id_required");
    }
    if (decision !== "accept" && decision !== "reject") {
      throw new HttpsError("invalid-argument", "invalid_decision");
    }

    const requestRef = admin.database().ref(`/relationshipRequests/${requestID}`);
    const requestSnap = await requestRef.get();
    const requestData = requestSnap.val();
    if (!requestData) {
      throw new HttpsError("failed-precondition", "request_not_found");
    }
    if (requestData.type !== REQUEST_TYPE.PAIR) {
      throw new HttpsError("failed-precondition", "request_type_mismatch");
    }
    if (requestData.status !== REQUEST_STATUS.PENDING) {
      throw new HttpsError("failed-precondition", "request_not_pending");
    }
    if (requestData.toUID !== uid) {
      throw new HttpsError("permission-denied", "request_not_owned");
    }

    if (isRequestExpired(requestData)) {
      await requestRef.update({
        status: REQUEST_STATUS.EXPIRED,
        resolvedAt: nowSeconds()
      });
      throw new HttpsError("failed-precondition", "request_expired");
    }

    if (decision === "reject") {
      await requestRef.update({
        status: REQUEST_STATUS.REJECTED,
        resolvedAt: nowSeconds()
      });
      return { success: true, status: REQUEST_STATUS.REJECTED };
    }

    const fromUID = normalizedString(requestData.fromUID);
    if (!fromUID) {
      throw new HttpsError("internal", "request_invalid_sender");
    }

    const fromProfile = await loadUserProfile(fromUID);
    const toProfile = await loadUserProfile(uid);

    const fromPartner = readPartnerID(fromProfile);
    const toPartner = readPartnerID(toProfile);

    if ((fromPartner && fromPartner !== uid) || (toPartner && toPartner !== fromUID)) {
      throw new HttpsError("failed-precondition", "user_already_paired");
    }

    const updates = {
      [`/users/${fromUID}/partnerID`]: uid,
      [`/users/${uid}/partnerID`]: fromUID,
      [`/relationshipRequests/${requestID}/status`]: REQUEST_STATUS.ACCEPTED,
      [`/relationshipRequests/${requestID}/resolvedAt`]: nowSeconds()
    };

    await admin.database().ref().update(updates);
    return { success: true, status: REQUEST_STATUS.ACCEPTED };
  }
);

exports.createUnpairRequest = onCall(
  { region: CALLABLE_REGION },
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) {
      throw new HttpsError("unauthenticated", "auth_required");
    }

    const requesterProfile = await loadUserProfile(uid);
    const partnerUID = readPartnerID(requesterProfile);
    if (!partnerUID) {
      throw new HttpsError("failed-precondition", "user_not_paired");
    }

    const partnerProfile = await loadUserProfile(partnerUID);
    if (readPartnerID(partnerProfile) !== uid) {
      throw new HttpsError("failed-precondition", "not_mutual_pair");
    }

    const duplicateOutgoing = await hasPendingRequestBetween(uid, partnerUID, REQUEST_TYPE.UNPAIR);
    const duplicateIncoming = await hasPendingRequestBetween(partnerUID, uid, REQUEST_TYPE.UNPAIR);
    if (duplicateOutgoing || duplicateIncoming) {
      throw new HttpsError("failed-precondition", "duplicate_pending_unpair_request");
    }

    const createdAt = nowSeconds();
    const expiresAt = createdAt + REQUEST_EXPIRY_SECONDS;
    const requestRef = admin.database().ref("/relationshipRequests").push();
    const requestID = requestRef.key;
    if (!requestID) {
      throw new HttpsError("internal", "request_create_failed");
    }

    const payload = {
      id: requestID,
      type: REQUEST_TYPE.UNPAIR,
      status: REQUEST_STATUS.PENDING,
      fromUID: uid,
      toUID: partnerUID,
      fromFirstName: readName(requesterProfile, "firstName"),
      fromLastName: readName(requesterProfile, "lastName"),
      fromSixDigitUID: readPairCode(requesterProfile),
      createdAt,
      expiresAt
    };

    await requestRef.set(payload);
    return { success: true, requestID };
  }
);

exports.respondUnpairRequest = onCall(
  { region: CALLABLE_REGION },
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) {
      throw new HttpsError("unauthenticated", "auth_required");
    }

    const requestID = normalizedString(request.data?.requestID);
    const decision = normalizedString(request.data?.decision);

    if (!requestID) {
      throw new HttpsError("invalid-argument", "request_id_required");
    }
    if (decision !== "accept" && decision !== "reject") {
      throw new HttpsError("invalid-argument", "invalid_decision");
    }

    const requestRef = admin.database().ref(`/relationshipRequests/${requestID}`);
    const requestSnap = await requestRef.get();
    const requestData = requestSnap.val();
    if (!requestData) {
      throw new HttpsError("failed-precondition", "request_not_found");
    }
    if (requestData.type !== REQUEST_TYPE.UNPAIR) {
      throw new HttpsError("failed-precondition", "request_type_mismatch");
    }
    if (requestData.status !== REQUEST_STATUS.PENDING) {
      throw new HttpsError("failed-precondition", "request_not_pending");
    }
    if (requestData.toUID !== uid) {
      throw new HttpsError("permission-denied", "request_not_owned");
    }

    if (isRequestExpired(requestData)) {
      await requestRef.update({
        status: REQUEST_STATUS.EXPIRED,
        resolvedAt: nowSeconds()
      });
      throw new HttpsError("failed-precondition", "request_expired");
    }

    if (decision === "reject") {
      await requestRef.update({
        status: REQUEST_STATUS.REJECTED,
        resolvedAt: nowSeconds()
      });
      return { success: true, status: REQUEST_STATUS.REJECTED };
    }

    const fromUID = normalizedString(requestData.fromUID);
    if (!fromUID) {
      throw new HttpsError("internal", "request_invalid_sender");
    }

    const fromProfile = await loadUserProfile(fromUID);
    const toProfile = await loadUserProfile(uid);
    if (readPartnerID(fromProfile) !== uid || readPartnerID(toProfile) !== fromUID) {
      throw new HttpsError("failed-precondition", "not_mutual_pair");
    }

    const chatID = requestChatID(fromUID, uid);
    const updates = {
      [`/chats/${chatID}`]: null,
      [`/events/${chatID}`]: null,
      [`/users/${fromUID}/partnerID`]: null,
      [`/users/${uid}/partnerID`]: null,
      [`/relationshipRequests/${requestID}/status`]: REQUEST_STATUS.ACCEPTED,
      [`/relationshipRequests/${requestID}/resolvedAt`]: nowSeconds()
    };

    await admin.database().ref().update(updates);
    return { success: true, status: REQUEST_STATUS.ACCEPTED, chatID };
  }
);
