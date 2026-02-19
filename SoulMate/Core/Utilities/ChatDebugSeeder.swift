#if DEBUG
import Foundation

extension LocalMessageStore {
    func seedDebugMessages(
        chatID: String,
        senderID: String,
        recipientID: String,
        count: Int = 10_000
    ) throws {
        guard count > 0 else { return }

        var messages: [ChatMessage] = []
        messages.reserveCapacity(count)
        let now = Date().timeIntervalSince1970
        for index in 0..<count {
            let secondsAgo = TimeInterval(count - index)
            let message = ChatMessage(
                id: "debug-\(chatID)-\(index)",
                senderID: index % 2 == 0 ? senderID : recipientID,
                recipientID: index % 2 == 0 ? recipientID : senderID,
                sentAt: Date(timeIntervalSince1970: now - secondsAgo),
                type: .text,
                value: "debug message #\(index)",
                isSecret: false
            )
            messages.append(message)
        }

        _ = try insertBatchIfNeeded(
            chatID: chatID,
            messages: messages,
            direction: .incoming,
            uploadState: .uploaded
        )
    }
}
#endif
