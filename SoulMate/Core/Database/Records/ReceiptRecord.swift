import Foundation
import GRDB

struct ReceiptRecord: Codable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "message_receipts"

    var ownerUID: String
    var chatID: String
    var messageID: String
    var senderID: String
    var recipientID: String
    var deliveredAtMs: Int64
    var readAtMs: Int64?
    var updatedAtMs: Int64

    init(
        ownerUID: String,
        chatID: String,
        messageID: String,
        senderID: String,
        recipientID: String,
        deliveredAtMs: Int64,
        readAtMs: Int64?,
        updatedAtMs: Int64
    ) {
        self.ownerUID = ownerUID
        self.chatID = chatID
        self.messageID = messageID
        self.senderID = senderID
        self.recipientID = recipientID
        self.deliveredAtMs = deliveredAtMs
        self.readAtMs = readAtMs
        self.updatedAtMs = updatedAtMs
    }

    enum Columns: String, ColumnExpression {
        case ownerUID = "owner_uid"
        case chatID = "chat_id"
        case messageID = "message_id"
        case senderID = "sender_id"
        case recipientID = "recipient_id"
        case deliveredAtMs = "delivered_at_ms"
        case readAtMs = "read_at_ms"
        case updatedAtMs = "updated_at_ms"
    }

    enum CodingKeys: String, CodingKey {
        case ownerUID = "owner_uid"
        case chatID = "chat_id"
        case messageID = "message_id"
        case senderID = "sender_id"
        case recipientID = "recipient_id"
        case deliveredAtMs = "delivered_at_ms"
        case readAtMs = "read_at_ms"
        case updatedAtMs = "updated_at_ms"
    }

    init(row: Row) {
        ownerUID = row["owner_uid"]
        chatID = row["chat_id"]
        messageID = row["message_id"]
        senderID = row["sender_id"]
        recipientID = row["recipient_id"]
        deliveredAtMs = row["delivered_at_ms"]
        readAtMs = row["read_at_ms"]
        updatedAtMs = row["updated_at_ms"]
    }

    func encode(to container: inout PersistenceContainer) {
        container["owner_uid"] = ownerUID
        container["chat_id"] = chatID
        container["message_id"] = messageID
        container["sender_id"] = senderID
        container["recipient_id"] = recipientID
        container["delivered_at_ms"] = deliveredAtMs
        container["read_at_ms"] = readAtMs
        container["updated_at_ms"] = updatedAtMs
    }
}
