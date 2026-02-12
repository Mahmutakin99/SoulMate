import CryptoKit
import Foundation

enum ConversationArchiveError: Error {
    case serializationFailed
    case invalidArchive
}

final class ConversationArchiveService {
    static let shared = ConversationArchiveService(keychain: .shared)

    private struct StoredArchive: Codable {
        let version: Int
        let messages: [StoredMessage]
    }

    private struct StoredMessage: Codable {
        let id: String
        let senderID: String
        let recipientID: String
        let sentAt: TimeInterval
        let type: ChatPayloadType
        let value: String
        let isSecret: Bool
    }

    private let keychain: KeychainWrapper
    private let fileManager: FileManager
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(keychain: KeychainWrapper, fileManager: FileManager = .default) {
        self.keychain = keychain
        self.fileManager = fileManager
    }

    func saveConversation(currentUID: String, partnerUID: String, messages: [ChatMessage]) throws {
        let archiveURL = try archiveFileURL(currentUID: currentUID, partnerUID: partnerUID)
        let masterKey = try loadOrCreateMasterKey(for: currentUID)

        let limitedMessages = Array(
            messages
                .sorted(by: { $0.sentAt < $1.sentAt })
                .suffix(Int(AppConfiguration.Archive.maxLocalMessages))
        )

        let storedMessages = limitedMessages.map {
            StoredMessage(
                id: $0.id,
                senderID: $0.senderID,
                recipientID: $0.recipientID,
                sentAt: $0.sentAt.timeIntervalSince1970,
                type: $0.type,
                value: $0.value,
                isSecret: $0.isSecret
            )
        }

        let archive = StoredArchive(version: 1, messages: storedMessages)
        let payload = try encoder.encode(archive)
        let sealedBox = try AES.GCM.seal(payload, using: masterKey)

        guard let combined = sealedBox.combined else {
            throw ConversationArchiveError.serializationFailed
        }

        try combined.write(to: archiveURL, options: [.atomic])
        try? fileManager.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: archiveURL.path)
    }

    func loadConversation(currentUID: String, partnerUID: String) throws -> [ChatMessage] {
        let archiveURL = try archiveFileURL(currentUID: currentUID, partnerUID: partnerUID)
        guard fileManager.fileExists(atPath: archiveURL.path) else { return [] }

        let encryptedData = try Data(contentsOf: archiveURL)
        let masterKey = try loadOrCreateMasterKey(for: currentUID)

        let sealedBox: AES.GCM.SealedBox
        do {
            sealedBox = try AES.GCM.SealedBox(combined: encryptedData)
        } catch {
            throw ConversationArchiveError.invalidArchive
        }

        let plainData: Data
        do {
            plainData = try AES.GCM.open(sealedBox, using: masterKey)
        } catch {
            throw ConversationArchiveError.invalidArchive
        }

        let archive: StoredArchive
        do {
            archive = try decoder.decode(StoredArchive.self, from: plainData)
        } catch {
            throw ConversationArchiveError.invalidArchive
        }

        return archive.messages
            .map {
                ChatMessage(
                    id: $0.id,
                    senderID: $0.senderID,
                    recipientID: $0.recipientID,
                    sentAt: Date(timeIntervalSince1970: $0.sentAt),
                    type: $0.type,
                    value: $0.value,
                    isSecret: $0.isSecret
                )
            }
            .sorted(by: { $0.sentAt < $1.sentAt })
    }

    func deleteConversationArchive(currentUID: String, partnerUID: String) throws {
        let archiveURL = try archiveFileURL(currentUID: currentUID, partnerUID: partnerUID)
        guard fileManager.fileExists(atPath: archiveURL.path) else { return }
        try fileManager.removeItem(at: archiveURL)
    }

    private func archiveFileURL(currentUID: String, partnerUID: String) throws -> URL {
        let appSupportURL = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )

        let userDirectory = appSupportURL
            .appendingPathComponent(AppConfiguration.Archive.directoryName, isDirectory: true)
            .appendingPathComponent(normalized(currentUID), isDirectory: true)

        if !fileManager.fileExists(atPath: userDirectory.path) {
            try fileManager.createDirectory(at: userDirectory, withIntermediateDirectories: true)
        }

        let chatID = FirebaseManager.chatID(for: currentUID, and: partnerUID)
        return userDirectory.appendingPathComponent("\(chatID).bin", isDirectory: false)
    }

    private func loadOrCreateMasterKey(for uid: String) throws -> SymmetricKey {
        let account = "archive.master.\(normalized(uid))"
        if let keyData = keychain.readIfPresent(account: account) {
            return SymmetricKey(data: keyData)
        }

        let key = SymmetricKey(size: .bits256)
        let keyData = key.withUnsafeBytes { Data($0) }
        try keychain.save(keyData, for: account)
        return key
    }

    private func normalized(_ value: String) -> String {
        value.replacingOccurrences(of: "[^a-zA-Z0-9_-]", with: "_", options: .regularExpression)
    }
}
