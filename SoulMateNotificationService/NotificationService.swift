import CryptoKit
import Foundation
import Security
import UserNotifications
#if canImport(WidgetKit)
import WidgetKit
#endif

final class NotificationService: UNNotificationServiceExtension {
    private let appGroupIdentifier = "group.com.MahmutAKIN.SoulMate"
    private let keychainService = "com.MahmutAKIN.SoulMate.secure"
    private let keychainAccessGroup = "BQH8W6X63R.com.MahmutAKIN.SoulMate.shared"

    private var contentHandler: ((UNNotificationContent) -> Void)?
    private var bestAttemptContent: UNMutableNotificationContent?

    override func didReceive(
        _ request: UNNotificationRequest,
        withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void
    ) {
        self.contentHandler = contentHandler
        bestAttemptContent = (request.content.mutableCopy() as? UNMutableNotificationContent)

        guard let bestAttemptContent,
              let encryptedBody = request.content.userInfo["enc_body"] as? String,
              let senderID = request.content.userInfo["sender_id"] as? String,
              let decryptedBody = decryptPayload(encryptedBody, partnerUID: senderID) else {
            contentHandler(request.content)
            return
        }

        bestAttemptContent.body = decryptedBody
        persistForWidget(decryptedBody)
        contentHandler(bestAttemptContent)
    }

    override func serviceExtensionTimeWillExpire() {
        guard let contentHandler,
              let bestAttemptContent else { return }
        contentHandler(bestAttemptContent)
    }

    private func decryptPayload(_ encryptedBody: String, partnerUID: String) -> String? {
        guard let keyData = readSharedKey(partnerUID: partnerUID),
              let combined = Data(base64Encoded: encryptedBody),
              let sealedBox = try? AES.GCM.SealedBox(combined: combined),
              let plaintext = try? AES.GCM.open(sealedBox, using: SymmetricKey(data: keyData)) else {
            return nil
        }

        if let json = try? JSONSerialization.jsonObject(with: plaintext) as? [String: Any],
           let value = json["value"] as? String {
            return value
        }

        return String(data: plaintext, encoding: .utf8)
    }

    private func readSharedKey(partnerUID: String) -> Data? {
        let account = "crypto.shared.\(partnerUID.replacingOccurrences(of: "[^a-zA-Z0-9_-]", with: "_", options: .regularExpression))"

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccessGroup as String: keychainAccessGroup,
            kSecAttrAccount as String: account,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: true
        ]

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else { return nil }
        return result as? Data
    }

    private func persistForWidget(_ message: String) {
        let defaults = UserDefaults(suiteName: appGroupIdentifier)
        defaults?.set(message, forKey: "widget.latestMessage")

        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }
}
