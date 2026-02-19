import Foundation
import GRDB

enum Migrations {
    static let schemaVersion = 2

    static func makeMigrator() -> DatabaseMigrator {
        var migrator = DatabaseMigrator()
        let currentSchemaVersion = 2

        migrator.registerMigration("v1_initial") { db in
            try db.create(table: "messages") { t in
                t.column("owner_uid", .text).notNull().defaults(to: "")
                t.column("chat_id", .text).notNull()
                t.column("message_id", .text).notNull()
                t.column("sender_id", .text).notNull()
                t.column("recipient_id", .text).notNull()
                t.column("sent_at_ms", .integer).notNull()
                t.column("server_timestamp_ms", .integer).notNull()
                t.column("payload_type", .text).notNull()
                t.column("payload_value", .text).notNull()
                t.column("is_secret", .boolean).notNull().defaults(to: false)
                t.column("direction", .text).notNull()
                t.column("upload_state", .text).notNull()
                t.column("created_at_ms", .integer).notNull()
                t.column("updated_at_ms", .integer).notNull()

                t.primaryKey(["chat_id", "message_id"], onConflict: .ignore)
            }

            try db.create(index: "idx_messages_chat_server_ts", on: "messages", columns: ["chat_id", "server_timestamp_ms", "message_id"], ifNotExists: true)
            try db.create(index: "idx_messages_upload_created", on: "messages", columns: ["upload_state", "created_at_ms"], ifNotExists: true)
            try db.create(index: "idx_messages_chat_sent", on: "messages", columns: ["chat_id", "sent_at_ms", "message_id"], ifNotExists: true)
            try db.create(index: "idx_messages_message_id", on: "messages", columns: ["message_id"], ifNotExists: true)

            try db.create(table: "message_receipts") { t in
                t.column("owner_uid", .text).notNull().defaults(to: "")
                t.column("chat_id", .text).notNull()
                t.column("message_id", .text).notNull()
                t.column("sender_id", .text).notNull()
                t.column("recipient_id", .text).notNull()
                t.column("delivered_at_ms", .integer).notNull()
                t.column("read_at_ms", .integer)
                t.column("updated_at_ms", .integer).notNull()
                t.primaryKey(["chat_id", "message_id"], onConflict: .replace)
            }
            try db.create(index: "idx_receipts_chat_updated", on: "message_receipts", columns: ["chat_id", "updated_at_ms"], ifNotExists: true)

            try db.create(table: "message_reactions") { t in
                t.column("owner_uid", .text).notNull().defaults(to: "")
                t.column("chat_id", .text).notNull()
                t.column("message_id", .text).notNull()
                t.column("reactor_uid", .text).notNull()
                t.column("emoji", .text).notNull()
                t.column("updated_at_ms", .integer).notNull()
                t.primaryKey(["chat_id", "message_id", "reactor_uid"], onConflict: .replace)
            }
            try db.create(index: "idx_reactions_chat_message", on: "message_reactions", columns: ["chat_id", "message_id"], ifNotExists: true)
            try db.create(index: "idx_reactions_chat_updated", on: "message_reactions", columns: ["chat_id", "updated_at_ms"], ifNotExists: true)

            try db.create(table: "message_sync_state") { t in
                t.column("owner_uid", .text).notNull().defaults(to: "")
                t.column("chat_id", .text).notNull()
                t.column("last_synced_timestamp_ms", .integer)
                t.column("last_synced_message_id", .text)
                t.column("bootstrap_incomplete", .boolean).notNull().defaults(to: false)
                t.column("gap_detected", .boolean).notNull().defaults(to: false)
                t.column("schema_version", .integer).notNull().defaults(to: currentSchemaVersion)
                t.column("app_version", .text).notNull().defaults(to: "")
                t.column("updated_at_ms", .integer).notNull()
                t.primaryKey(["owner_uid", "chat_id"], onConflict: .replace)
            }
        }

        migrator.registerMigration("v2_perf_indexes") { db in
            try db.create(
                index: "idx_receipts_chat_message",
                on: "message_receipts",
                columns: ["chat_id", "message_id"],
                ifNotExists: true
            )
            try db.create(
                index: "idx_messages_chat_upload_created",
                on: "messages",
                columns: ["chat_id", "upload_state", "created_at_ms"],
                ifNotExists: true
            )
        }

        return migrator
    }
}
