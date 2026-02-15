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
const REQUEST_DUPLICATE_SCAN_LIMIT = 200;
const SIMPLE_EMAIL_REGEX = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

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

const PASSWORD_POLICY_REGEX = /^(?=.*[a-z])(?=.*[A-Z])(?=.*\d).+$/;

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

async function ensureMutualPairForChat(uid, chatID) {
  const profile = await loadUserProfile(uid);
  const partnerUID = readPartnerID(profile);
  if (!partnerUID) {
    throw new HttpsError("failed-precondition", "not_mutual_pair");
  }

  const partnerProfile = await loadUserProfile(partnerUID);
  if (readPartnerID(partnerProfile) !== uid) {
    throw new HttpsError("failed-precondition", "not_mutual_pair");
  }

  if (requestChatID(uid, partnerUID) !== chatID) {
    throw new HttpsError("failed-precondition", "chat_mismatch");
  }

  return partnerUID;
}

function readInstallationID(data) {
  return normalizedString(data?.installationID);
}

function readAppVersion(data) {
  const value = normalizedString(data?.appVersion);
  return value ? value.slice(0, 32) : "unknown";
}

function readDeviceName(data) {
  const value = normalizedString(data?.deviceName);
  return value ? value.slice(0, 80) : "unknown-device";
}

function isPasswordPolicyValid(password) {
  return password.length >= 8 &&
    password.length <= 64 &&
    PASSWORD_POLICY_REGEX.test(password);
}

function displayNameFromProfile(profile, fallback) {
  const first = readName(profile, "firstName");
  const last = readName(profile, "lastName");
  const full = `${first} ${last}`.trim();
  return full || fallback;
}

async function collectRelationshipRequestRemovalUpdates(uid) {
  const updates = {};
  const requestsRef = admin.database().ref("/relationshipRequests");

  const fromSnap = await requestsRef
    .orderByChild("fromUID")
    .equalTo(uid)
    .get();
  if (fromSnap.exists()) {
    fromSnap.forEach((child) => {
      updates[`/relationshipRequests/${child.key}`] = null;
    });
  }

  const toSnap = await requestsRef
    .orderByChild("toUID")
    .equalTo(uid)
    .get();
  if (toSnap.exists()) {
    toSnap.forEach((child) => {
      updates[`/relationshipRequests/${child.key}`] = null;
    });
  }

  return updates;
}

async function pairCodeRemovalUpdate(uid, profile) {
  const code = readPairCode(profile);
  if (!/^[0-9]{6}$/.test(code)) {
    return {};
  }

  const codeRef = admin.database().ref(`/pairCodes/${code}`);
  const codeSnap = await codeRef.get();
  if (normalizedString(codeSnap.val()) !== uid) {
    return {};
  }

  return {
    [`/pairCodes/${code}`]: null
  };
}

async function sendPartnerAccountDeletedPush(partnerUID, sourceName) {
  if (!partnerUID) {
    return;
  }

  const tokenSnap = await admin.database().ref(`/users/${partnerUID}/fcmToken`).get();
  const token = normalizedString(tokenSnap.val());
  if (!token) {
    return;
  }

  const body = sourceName
    ? `${sourceName} hesabını sildi.`
    : "Partnerin hesabını sildi.";
  const payload = {
    token,
    notification: {
      title: "SoulMate",
      body
    },
    data: {
      type: "partner_account_deleted"
    },
    apns: {
      headers: {
        "apns-priority": "10"
      },
      payload: {
        aps: {
          alert: {
            title: "SoulMate",
            body
          },
          sound: "default"
        }
      }
    }
  };

  try {
    await admin.messaging().send(payload);
  } catch (error) {
    logger.error("Partner delete push failed.", {
      partnerUID,
      errorCode: error?.code,
      errorMessage: error?.message || String(error)
    });

    if (INVALID_TOKEN_CODES.has(error?.code)) {
      await admin.database().ref(`/users/${partnerUID}/fcmToken`).remove();
    }
  }
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
    .limitToLast(REQUEST_DUPLICATE_SCAN_LIMIT)
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

    const receiptRef = admin.database().ref(`/events/${chatID}/messageReceipts/${messageID}`);
    const existingReceiptSnap = await receiptRef.get();
    const existingReceipt = existingReceiptSnap.val() || {};
    const now = nowSeconds();
    const deliveredAt = Number(existingReceipt.deliveredAt || 0) > 0
      ? Number(existingReceipt.deliveredAt)
      : now;
    const readAt = Number(existingReceipt.readAt || 0) > 0
      ? Number(existingReceipt.readAt)
      : null;

    const updates = {
      [`/events/${chatID}/messageReceipts/${messageID}/senderID`]: normalizedString(message.senderID),
      [`/events/${chatID}/messageReceipts/${messageID}/recipientID`]: normalizedString(message.recipientID),
      [`/events/${chatID}/messageReceipts/${messageID}/deliveredAt`]: deliveredAt,
      [`/events/${chatID}/messageReceipts/${messageID}/updatedAt`]: now,
      [`/events/${chatID}/messageReceipts/${messageID}/readAt`]: readAt,
      [`/chats/${chatID}/messages/${messageID}`]: null
    };

    await admin.database().ref().update(updates);
    return { success: true, deliveredAt };
  }
);

exports.markMessageRead = onCall(
  { region: CALLABLE_REGION },
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) {
      throw new HttpsError("unauthenticated", "auth_required");
    }

    const chatID = normalizedString(request.data?.chatID);
    const messageID = normalizedString(request.data?.messageID);
    if (!chatID || !messageID) {
      throw new HttpsError("invalid-argument", "invalid_read_receipt_input");
    }

    const receiptRef = admin.database().ref(`/events/${chatID}/messageReceipts/${messageID}`);
    const receiptSnap = await receiptRef.get();
    if (!receiptSnap.exists()) {
      return { success: true, alreadyRead: true, receiptMissing: true };
    }

    const receipt = receiptSnap.val() || {};
    if (normalizedString(receipt.recipientID) !== uid) {
      throw new HttpsError("failed-precondition", "read_forbidden");
    }

    const existingReadAt = Number(receipt.readAt || 0);
    if (existingReadAt > 0) {
      return { success: true, alreadyRead: true };
    }

    const now = nowSeconds();
    await receiptRef.update({
      readAt: now,
      updatedAt: now
    });

    return { success: true, readAt: now };
  }
);

exports.checkEmailInUse = onCall(
  { region: CALLABLE_REGION },
  async (request) => {
    const email = normalizedString(request.data?.email).toLowerCase();
    if (!email || !SIMPLE_EMAIL_REGEX.test(email)) {
      throw new HttpsError("invalid-argument", "invalid_email");
    }

    try {
      await admin.auth().getUserByEmail(email);
      return { success: true, inUse: true };
    } catch (error) {
      if (error?.code === "auth/user-not-found") {
        return { success: true, inUse: false };
      }

      logger.error("checkEmailInUse failed.", {
        errorCode: error?.code,
        errorMessage: error?.message || String(error)
      });
      throw new HttpsError("internal", "email_check_failed");
    }
  }
);

exports.setMessageReaction = onCall(
  { region: CALLABLE_REGION },
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) {
      throw new HttpsError("unauthenticated", "auth_required");
    }

    const chatID = normalizedString(request.data?.chatID);
    const messageID = normalizedString(request.data?.messageID);
    const ciphertext = normalizedString(request.data?.ciphertext);
    const keyVersion = Number(request.data?.keyVersion || 0);

    if (!chatID || !messageID || !ciphertext || !Number.isFinite(keyVersion) || keyVersion <= 0) {
      throw new HttpsError("invalid-argument", "invalid_reaction_input");
    }

    await ensureMutualPairForChat(uid, chatID);

    const now = nowSeconds();
    const reactionRef = admin.database().ref(`/events/${chatID}/messageReactions/${messageID}/${uid}`);
    await reactionRef.set({
      ciphertext,
      keyVersion,
      updatedAt: now
    });

    return { success: true, updatedAt: now };
  }
);

exports.clearMessageReaction = onCall(
  { region: CALLABLE_REGION },
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) {
      throw new HttpsError("unauthenticated", "auth_required");
    }

    const chatID = normalizedString(request.data?.chatID);
    const messageID = normalizedString(request.data?.messageID);
    if (!chatID || !messageID) {
      throw new HttpsError("invalid-argument", "invalid_reaction_input");
    }

    await ensureMutualPairForChat(uid, chatID);

    const reactionRef = admin.database().ref(`/events/${chatID}/messageReactions/${messageID}/${uid}`);
    await reactionRef.remove();
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

    // Shallow query: fetch only chat IDs, not entire message trees
    const chatsShallow = await admin.database()
      .ref("/chats")
      .get();

    if (!chatsShallow.exists()) {
      logger.info("Transient message cleanup: no chats found.");
      return;
    }

    const chatIDs = Object.keys(chatsShallow.val() || {});
    let totalDeleted = 0;

    for (const chatID of chatIDs) {
      // Query only messages older than the cutoff
      const expiredSnap = await admin.database()
        .ref(`/chats/${chatID}/messages`)
        .orderByChild("sentAt")
        .endAt(cutoff)
        .get();

      if (!expiredSnap.exists()) {
        continue;
      }

      const updates = {};
      let batchCount = 0;
      expiredSnap.forEach((messageSnap) => {
        const sentAt = Number(messageSnap.val()?.sentAt || 0);
        if (sentAt > 0 && sentAt <= cutoff) {
          updates[`/chats/${chatID}/messages/${messageSnap.key}`] = null;
          batchCount += 1;
        }
      });

      if (batchCount > 0) {
        await admin.database().ref().update(updates);
        totalDeleted += batchCount;
      }
    }

    logger.info("Transient message cleanup completed.", {
      deletedMessages: totalDeleted,
      chatCount: chatIDs.length,
      cutoff
    });
  }
);

exports.cleanupExpiredRelationshipRequests = onSchedule(
  {
    region: DATABASE_TRIGGER_REGION,
    schedule: "every 12 hours",
    timeZone: "Etc/UTC"
  },
  async () => {
    const now = nowSeconds();

    // Fetch only expired pending requests
    const expiredSnap = await admin.database()
      .ref("/relationshipRequests")
      .orderByChild("expiresAt")
      .endAt(now)
      .get();

    if (!expiredSnap.exists()) {
      logger.info("Relationship request cleanup: nothing to clean.");
      return;
    }

    const updates = {};
    let marked = 0;

    expiredSnap.forEach((snap) => {
      const data = snap.val();
      if (data && data.status === REQUEST_STATUS.PENDING) {
        updates[`/relationshipRequests/${snap.key}/status`] = REQUEST_STATUS.EXPIRED;
        updates[`/relationshipRequests/${snap.key}/resolvedAt`] = now;
        marked += 1;
      }
    });

    if (marked > 0) {
      await admin.database().ref().update(updates);
    }

    logger.info("Expired relationship request cleanup completed.", {
      markedExpired: marked
    });
  }
);

exports.acquireSessionLock = onCall(
  { region: CALLABLE_REGION },
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) {
      throw new HttpsError("unauthenticated", "auth_required");
    }

    const installationID = readInstallationID(request.data);
    if (!installationID) {
      throw new HttpsError("invalid-argument", "session_lock_invalid_installation");
    }

    const lockRef = admin.database().ref(`/sessionLocks/${uid}`);
    const now = nowSeconds();
    const appVersion = readAppVersion(request.data);
    const deviceName = readDeviceName(request.data);

    let txResult;
    try {
      txResult = await lockRef.transaction((current) => {
        const owner = normalizedString(current?.installationID);
        if (owner && owner !== installationID) {
          return;
        }

        const acquiredAt = Number(current?.acquiredAt || 0) > 0
          ? Number(current.acquiredAt)
          : now;

        return {
          installationID,
          platform: "ios",
          deviceName,
          appVersion,
          acquiredAt,
          updatedAt: now
        };
      }, undefined, false);
    } catch (error) {
      logger.error("Session lock acquire failed.", {
        uid,
        installationID,
        errorMessage: error?.message || String(error)
      });
      throw new HttpsError("internal", "session_lock_acquire_failed");
    }

    if (!txResult.committed) {
      throw new HttpsError("failed-precondition", "session_locked_on_another_device");
    }

    return {
      success: true,
      uid,
      installationID,
      updatedAt: now
    };
  }
);

exports.releaseSessionLock = onCall(
  { region: CALLABLE_REGION },
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) {
      throw new HttpsError("unauthenticated", "auth_required");
    }

    const installationID = readInstallationID(request.data);
    if (!installationID) {
      throw new HttpsError("invalid-argument", "session_lock_invalid_installation");
    }

    const lockRef = admin.database().ref(`/sessionLocks/${uid}`);
    const snap = await lockRef.get();
    if (!snap.exists()) {
      return {
        success: true,
        released: true,
        alreadyReleased: true
      };
    }

    const current = snap.val() || {};
    const owner = normalizedString(current.installationID);
    if (owner && owner !== installationID) {
      return {
        success: true,
        released: false,
        reason: "session_lock_invalid_installation"
      };
    }

    try {
      await lockRef.remove();
    } catch (error) {
      logger.error("Session lock release failed.", {
        uid,
        installationID,
        errorMessage: error?.message || String(error)
      });
      throw new HttpsError("internal", "session_lock_release_failed");
    }

    return {
      success: true,
      released: true
    };
  }
);

exports.changeMyPassword = onCall(
  { region: CALLABLE_REGION },
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) {
      throw new HttpsError("unauthenticated", "auth_required");
    }

    const newPassword = normalizedString(request.data?.newPassword);
    if (!isPasswordPolicyValid(newPassword)) {
      throw new HttpsError("invalid-argument", "invalid_password_policy");
    }

    const authTime = Number(request.auth?.token?.auth_time || 0);
    const now = nowSeconds();
    if (!Number.isFinite(authTime) || authTime <= 0 || now - authTime > 300) {
      throw new HttpsError("failed-precondition", "requires_recent_login");
    }

    try {
      await admin.auth().updateUser(uid, { password: newPassword });
    } catch (error) {
      logger.error("changeMyPassword failed.", {
        uid,
        errorCode: error?.code,
        errorMessage: error?.message || String(error)
      });

      if (error?.code === "auth/invalid-password") {
        throw new HttpsError("invalid-argument", "invalid_password_policy");
      }
      throw new HttpsError("internal", "password_change_failed");
    }

    return { success: true };
  }
);

exports.deleteMyAccount = onCall(
  { region: CALLABLE_REGION },
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) {
      throw new HttpsError("unauthenticated", "auth_required");
    }

    const installationID = readInstallationID(request.data);
    if (!installationID) {
      throw new HttpsError("invalid-argument", "session_lock_invalid_installation");
    }

    const lockRef = admin.database().ref(`/sessionLocks/${uid}`);
    const lockSnap = await lockRef.get();
    if (lockSnap.exists()) {
      const lock = lockSnap.val() || {};
      const owner = normalizedString(lock.installationID);
      if (owner && owner !== installationID) {
        throw new HttpsError("failed-precondition", "session_lock_invalid_installation");
      }
    }

    const profile = await loadUserProfile(uid);
    const partnerUID = readPartnerID(profile);
    let partnerProfile = {};

    if (partnerUID) {
      partnerProfile = await loadUserProfile(partnerUID);
    }

    const sourceName = displayNameFromProfile(profile, "Partnerin");
    const now = nowSeconds();
    const updates = {
      [`/users/${uid}`]: null,
      [`/sessionLocks/${uid}`]: null
    };

    if (partnerUID && partnerUID !== uid) {
      const chatID = requestChatID(uid, partnerUID);
      updates[`/chats/${chatID}`] = null;
      updates[`/events/${chatID}`] = null;

      if (readPartnerID(partnerProfile) === uid) {
        updates[`/users/${partnerUID}/partnerID`] = null;
      }

      updates[`/systemNotices/${partnerUID}`] = {
        type: "partner_account_deleted",
        sourceUID: uid,
        sourceName,
        createdAt: now
      };
    }

    const requestCleanupUpdates = await collectRelationshipRequestRemovalUpdates(uid);
    Object.assign(updates, requestCleanupUpdates);

    const pairCodeUpdates = await pairCodeRemovalUpdate(uid, profile);
    Object.assign(updates, pairCodeUpdates);

    try {
      await admin.database().ref().update(updates);
    } catch (error) {
      logger.error("deleteMyAccount data cleanup failed.", {
        uid,
        partnerUID,
        errorMessage: error?.message || String(error)
      });
      throw new HttpsError("internal", "delete_account_failed");
    }

    if (partnerUID && partnerUID !== uid) {
      try {
        await sendPartnerAccountDeletedPush(partnerUID, sourceName);
      } catch (error) {
        logger.error("Partner notification push pipeline failed.", {
          uid,
          partnerUID,
          errorMessage: error?.message || String(error)
        });
      }
    }

    try {
      await admin.auth().deleteUser(uid);
    } catch (error) {
      logger.error("deleteMyAccount auth deletion failed.", {
        uid,
        errorCode: error?.code,
        errorMessage: error?.message || String(error)
      });
      throw new HttpsError("internal", "delete_account_failed");
    }

    return {
      success: true,
      deletedAt: now
    };
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
