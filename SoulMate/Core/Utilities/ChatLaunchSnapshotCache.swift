import Foundation

enum MessageUIStatus: String, Codable {
    case sending
    case sent
    case delivered
    case read
    case failed
    case unknown
}

struct MessageUIModel: Codable, Hashable {
    let id: String
    let senderID: String
    let recipientID: String?
    let text: String
    let timestampMs: Int64
    let payloadType: String?
    let isSecret: Bool?
    let status: MessageUIStatus
}

private struct ChatLaunchSnapshotPayload: Codable {
    let ownerUID: String
    let chatID: String
    let createdAtMs: Int64
    let messages: [MessageUIModel]
}

final class ChatLaunchSnapshotCache {
    static let shared = ChatLaunchSnapshotCache()

    private let encoder: PropertyListEncoder
    private let decoder: PropertyListDecoder
    private let queue = DispatchQueue(label: "com.soulmate.chatlaunchsnapshot.queue", qos: .utility)
    private var saveWorkItem: DispatchWorkItem?

    private init() {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        self.encoder = encoder
        self.decoder = PropertyListDecoder()
    }

    func load(ownerUID: String, chatID: String) -> [MessageUIModel]? {
        let url = snapshotURL(ownerUID: ownerUID, chatID: chatID)
        guard let data = try? Data(contentsOf: url) else { return nil }

        if let payload = try? decoder.decode(ChatLaunchSnapshotPayload.self, from: data),
           payload.ownerUID == ownerUID,
           payload.chatID == chatID {
            return payload.messages
        }

        if let fallback = try? JSONDecoder().decode(ChatLaunchSnapshotPayload.self, from: data),
           fallback.ownerUID == ownerUID,
           fallback.chatID == chatID {
            return fallback.messages
        }

        return nil
    }

    func scheduleSave(ownerUID: String, chatID: String, messages: [MessageUIModel], debounce: TimeInterval = 1.0) {
        saveWorkItem?.cancel()

        let payload = ChatLaunchSnapshotPayload(
            ownerUID: ownerUID,
            chatID: chatID,
            createdAtMs: Int64(Date().timeIntervalSince1970 * 1000),
            messages: Array(messages.suffix(60))
        )

        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.save(ownerUID: ownerUID, chatID: chatID, payload: payload)
        }

        saveWorkItem = item
        queue.asyncAfter(deadline: .now() + debounce, execute: item)
    }

    func flushPendingSave(ownerUID: String, chatID: String, messages: [MessageUIModel]) {
        saveWorkItem?.cancel()
        let payload = ChatLaunchSnapshotPayload(
            ownerUID: ownerUID,
            chatID: chatID,
            createdAtMs: Int64(Date().timeIntervalSince1970 * 1000),
            messages: Array(messages.suffix(60))
        )
        queue.async { [weak self] in
            self?.save(ownerUID: ownerUID, chatID: chatID, payload: payload)
        }
    }

    private func save(ownerUID: String, chatID: String, payload: ChatLaunchSnapshotPayload) {
        let url = snapshotURL(ownerUID: ownerUID, chatID: chatID)
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try encoder.encode(payload)
            try data.write(to: url, options: [.atomic])
        } catch {
            #if DEBUG
            print("Snapshot save failed: \(error.localizedDescription)")
            #endif
        }
    }

    private func snapshotURL(ownerUID: String, chatID: String) -> URL {
        let fileManager = FileManager.default
        let cachesURL: URL
        do {
            cachesURL = try fileManager.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        } catch {
            return URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
                .appendingPathComponent("chat_snapshot_\(ownerUID)_\(chatID).bin")
        }

        return cachesURL
            .appendingPathComponent("ChatLaunchSnapshots", isDirectory: true)
            .appendingPathComponent("snapshot_\(ownerUID)_\(chatID).bin", isDirectory: false)
    }
}
