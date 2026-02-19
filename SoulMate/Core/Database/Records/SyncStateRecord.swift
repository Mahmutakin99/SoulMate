import Foundation
import GRDB

struct SyncStateRecord: Codable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "message_sync_state"

    var ownerUID: String
    var chatID: String
    var lastSyncedTimestampMs: Int64?
    var lastSyncedMessageID: String?
    var bootstrapIncomplete: Bool
    var gapDetected: Bool
    var schemaVersion: Int
    var appVersion: String
    var updatedAtMs: Int64

    init(
        ownerUID: String,
        chatID: String,
        lastSyncedTimestampMs: Int64?,
        lastSyncedMessageID: String?,
        bootstrapIncomplete: Bool,
        gapDetected: Bool,
        schemaVersion: Int,
        appVersion: String,
        updatedAtMs: Int64
    ) {
        self.ownerUID = ownerUID
        self.chatID = chatID
        self.lastSyncedTimestampMs = lastSyncedTimestampMs
        self.lastSyncedMessageID = lastSyncedMessageID
        self.bootstrapIncomplete = bootstrapIncomplete
        self.gapDetected = gapDetected
        self.schemaVersion = schemaVersion
        self.appVersion = appVersion
        self.updatedAtMs = updatedAtMs
    }

    enum Columns: String, ColumnExpression {
        case ownerUID = "owner_uid"
        case chatID = "chat_id"
        case lastSyncedTimestampMs = "last_synced_timestamp_ms"
        case lastSyncedMessageID = "last_synced_message_id"
        case bootstrapIncomplete = "bootstrap_incomplete"
        case gapDetected = "gap_detected"
        case schemaVersion = "schema_version"
        case appVersion = "app_version"
        case updatedAtMs = "updated_at_ms"
    }

    enum CodingKeys: String, CodingKey {
        case ownerUID = "owner_uid"
        case chatID = "chat_id"
        case lastSyncedTimestampMs = "last_synced_timestamp_ms"
        case lastSyncedMessageID = "last_synced_message_id"
        case bootstrapIncomplete = "bootstrap_incomplete"
        case gapDetected = "gap_detected"
        case schemaVersion = "schema_version"
        case appVersion = "app_version"
        case updatedAtMs = "updated_at_ms"
    }

    init(row: Row) {
        ownerUID = row["owner_uid"]
        chatID = row["chat_id"]
        lastSyncedTimestampMs = row["last_synced_timestamp_ms"]
        lastSyncedMessageID = row["last_synced_message_id"]
        bootstrapIncomplete = row["bootstrap_incomplete"]
        gapDetected = row["gap_detected"]
        schemaVersion = row["schema_version"]
        appVersion = row["app_version"]
        updatedAtMs = row["updated_at_ms"]
    }

    func encode(to container: inout PersistenceContainer) {
        container["owner_uid"] = ownerUID
        container["chat_id"] = chatID
        container["last_synced_timestamp_ms"] = lastSyncedTimestampMs
        container["last_synced_message_id"] = lastSyncedMessageID
        container["bootstrap_incomplete"] = bootstrapIncomplete
        container["gap_detected"] = gapDetected
        container["schema_version"] = schemaVersion
        container["app_version"] = appVersion
        container["updated_at_ms"] = updatedAtMs
    }
}
