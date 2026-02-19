import Foundation
import GRDB

struct MessageRecord: Codable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "messages"

    var ownerUID: String
    var chatID: String
    var messageID: String
    var senderID: String
    var recipientID: String
    var sentAtMs: Int64
    var serverTimestampMs: Int64
    var payloadType: String
    var payloadValue: String
    var isSecret: Bool
    var direction: String
    var uploadState: String
    var createdAtMs: Int64
    var updatedAtMs: Int64

    init(
        ownerUID: String,
        chatID: String,
        messageID: String,
        senderID: String,
        recipientID: String,
        sentAtMs: Int64,
        serverTimestampMs: Int64,
        payloadType: String,
        payloadValue: String,
        isSecret: Bool,
        direction: String,
        uploadState: String,
        createdAtMs: Int64,
        updatedAtMs: Int64
    ) {
        self.ownerUID = ownerUID
        self.chatID = chatID
        self.messageID = messageID
        self.senderID = senderID
        self.recipientID = recipientID
        self.sentAtMs = sentAtMs
        self.serverTimestampMs = serverTimestampMs
        self.payloadType = payloadType
        self.payloadValue = payloadValue
        self.isSecret = isSecret
        self.direction = direction
        self.uploadState = uploadState
        self.createdAtMs = createdAtMs
        self.updatedAtMs = updatedAtMs
    }

    enum Columns: String, ColumnExpression {
        case ownerUID = "owner_uid"
        case chatID = "chat_id"
        case messageID = "message_id"
        case senderID = "sender_id"
        case recipientID = "recipient_id"
        case sentAtMs = "sent_at_ms"
        case serverTimestampMs = "server_timestamp_ms"
        case payloadType = "payload_type"
        case payloadValue = "payload_value"
        case isSecret = "is_secret"
        case direction
        case uploadState = "upload_state"
        case createdAtMs = "created_at_ms"
        case updatedAtMs = "updated_at_ms"
    }

    enum CodingKeys: String, CodingKey {
        case ownerUID = "owner_uid"
        case chatID = "chat_id"
        case messageID = "message_id"
        case senderID = "sender_id"
        case recipientID = "recipient_id"
        case sentAtMs = "sent_at_ms"
        case serverTimestampMs = "server_timestamp_ms"
        case payloadType = "payload_type"
        case payloadValue = "payload_value"
        case isSecret = "is_secret"
        case direction
        case uploadState = "upload_state"
        case createdAtMs = "created_at_ms"
        case updatedAtMs = "updated_at_ms"
    }

    init(row: Row) {
        ownerUID = row["owner_uid"]
        chatID = row["chat_id"]
        messageID = row["message_id"]
        senderID = row["sender_id"]
        recipientID = row["recipient_id"]
        sentAtMs = row["sent_at_ms"]
        serverTimestampMs = row["server_timestamp_ms"]
        payloadType = row["payload_type"]
        payloadValue = row["payload_value"]
        isSecret = row["is_secret"]
        direction = row["direction"]
        uploadState = row["upload_state"]
        createdAtMs = row["created_at_ms"]
        updatedAtMs = row["updated_at_ms"]
    }

    func encode(to container: inout PersistenceContainer) {
        container["owner_uid"] = ownerUID
        container["chat_id"] = chatID
        container["message_id"] = messageID
        container["sender_id"] = senderID
        container["recipient_id"] = recipientID
        container["sent_at_ms"] = sentAtMs
        container["server_timestamp_ms"] = serverTimestampMs
        container["payload_type"] = payloadType
        container["payload_value"] = payloadValue
        container["is_secret"] = isSecret
        container["direction"] = direction
        container["upload_state"] = uploadState
        container["created_at_ms"] = createdAtMs
        container["updated_at_ms"] = updatedAtMs
    }
}
