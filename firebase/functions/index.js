const { onValueCreated } = require("firebase-functions/v2/database");
const logger = require("firebase-functions/logger");
const admin = require("firebase-admin");

admin.initializeApp();

const INVALID_TOKEN_CODES = new Set([
  "messaging/registration-token-not-registered",
  "messaging/invalid-registration-token"
]);

exports.sendEncryptedMessagePush = onValueCreated(
  {
    ref: "/chats/{chatId}/messages/{messageId}",
    region: "europe-west1"
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
