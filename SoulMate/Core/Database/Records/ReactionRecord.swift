import Foundation
import GRDB

struct ReactionRecord: Codable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "message_reactions"

    var ownerUID: String
    var chatID: String
    var messageID: String
    var reactorUID: String
    var emoji: String
    var updatedAtMs: Int64

    init(
        ownerUID: String,
        chatID: String,
        messageID: String,
        reactorUID: String,
        emoji: String,
        updatedAtMs: Int64
    ) {
        self.ownerUID = ownerUID
        self.chatID = chatID
        self.messageID = messageID
        self.reactorUID = reactorUID
        self.emoji = emoji
        self.updatedAtMs = updatedAtMs
    }

    enum Columns: String, ColumnExpression {
        case ownerUID = "owner_uid"
        case chatID = "chat_id"
        case messageID = "message_id"
        case reactorUID = "reactor_uid"
        case emoji
        case updatedAtMs = "updated_at_ms"
    }

    enum CodingKeys: String, CodingKey {
        case ownerUID = "owner_uid"
        case chatID = "chat_id"
        case messageID = "message_id"
        case reactorUID = "reactor_uid"
        case emoji
        case updatedAtMs = "updated_at_ms"
    }

    init(row: Row) {
        ownerUID = row["owner_uid"]
        chatID = row["chat_id"]
        messageID = row["message_id"]
        reactorUID = row["reactor_uid"]
        emoji = row["emoji"]
        updatedAtMs = row["updated_at_ms"]
    }

    func encode(to container: inout PersistenceContainer) {
        container["owner_uid"] = ownerUID
        container["chat_id"] = chatID
        container["message_id"] = messageID
        container["reactor_uid"] = reactorUID
        container["emoji"] = emoji
        container["updated_at_ms"] = updatedAtMs
    }
}
