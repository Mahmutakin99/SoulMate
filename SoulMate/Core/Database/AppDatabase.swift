import Foundation
import GRDB
import SQLite3

final class AppDatabase {
    static let shared = AppDatabase()

    let dbPool: DatabasePool
    private let fileManager: FileManager

    private init(fileManager: FileManager = .default) {
        self.fileManager = fileManager

        let dbURL = AppDatabase.databaseURL(fileManager: fileManager)
        do {
            try fileManager.createDirectory(at: dbURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            self.dbPool = try Self.openDatabase(at: dbURL)
        } catch {
            do {
                try Self.backupBrokenDatabaseFiles(at: dbURL, fileManager: fileManager)
                self.dbPool = try Self.openDatabase(at: dbURL)
            } catch {
                fatalError("AppDatabase initialization failed: \(error)")
            }
        }
    }

    func startDeferredLegacyImportIfNeeded() {
        LegacyImportCoordinator.shared.scheduleIfNeeded(database: self)
    }

    func runLegacyImportIfNeeded() throws {
        try Self.importLegacySQLiteIfNeeded(dbPool: dbPool, fileManager: fileManager)
    }

    private static func databaseURL(fileManager: FileManager) -> URL {
        do {
            let appSupport = try fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            return appSupport
                .appendingPathComponent("SoulMateGRDB", isDirectory: true)
                .appendingPathComponent("app_database.sqlite", isDirectory: false)
        } catch {
            let fallback = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            return fallback.appendingPathComponent("app_database.sqlite", isDirectory: false)
        }
    }

    private static func openDatabase(at dbURL: URL) throws -> DatabasePool {
        var config = Configuration()
        config.foreignKeysEnabled = true
        config.prepareDatabase { db in
            try db.execute(sql: "PRAGMA journal_mode=WAL;")
            try db.execute(sql: "PRAGMA synchronous=NORMAL;")
        }

        let dbPool = try DatabasePool(path: dbURL.path, configuration: config)
        try Migrations.makeMigrator().migrate(dbPool)
        return dbPool
    }

    private static func backupBrokenDatabaseFiles(at dbURL: URL, fileManager: FileManager) throws {
        let stamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let relatedFiles = [
            dbURL,
            URL(fileURLWithPath: dbURL.path + "-shm"),
            URL(fileURLWithPath: dbURL.path + "-wal")
        ]

        for fileURL in relatedFiles where fileManager.fileExists(atPath: fileURL.path) {
            let backupURL = fileURL
                .deletingLastPathComponent()
                .appendingPathComponent("\(fileURL.lastPathComponent).broken-\(stamp)")
            try? fileManager.removeItem(at: backupURL)
            try fileManager.moveItem(at: fileURL, to: backupURL)
        }
    }

    private static func importLegacySQLiteIfNeeded(dbPool: DatabasePool, fileManager: FileManager) throws {
        let hasMessages = try dbPool.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM messages") ?? 0
        }
        guard hasMessages == 0 else { return }

        let legacyURL = try legacyDatabaseURL(fileManager: fileManager)
        guard fileManager.fileExists(atPath: legacyURL.path) else { return }

        var handle: OpaquePointer?
        guard sqlite3_open_v2(legacyURL.path, &handle, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK,
              let handle else {
            sqlite3_close(handle)
            return
        }
        defer { sqlite3_close(handle) }

        let hasLegacyTable = sqliteTableExists(handle: handle, tableName: "local_messages")
        guard hasLegacyTable else { return }

        let legacyMessageSQL = """
        SELECT id, chat_id, sender_id, recipient_id, sent_at, payload_type, payload_value, is_secret, direction, upload_state, created_at
        FROM local_messages
        ORDER BY created_at ASC;
        """

        var messageStmt: OpaquePointer?
        guard sqlite3_prepare_v2(handle, legacyMessageSQL, -1, &messageStmt, nil) == SQLITE_OK,
              let messageStmt else {
            sqlite3_finalize(messageStmt)
            return
        }
        defer { sqlite3_finalize(messageStmt) }

        struct LegacyMessageRow {
            let ownerUID: String
            let chatID: String
            let messageID: String
            let senderID: String
            let recipientID: String
            let sentAtMs: Int64
            let serverTimestampMs: Int64
            let payloadType: String
            let payloadValue: String
            let isSecret: Bool
            let direction: String
            let uploadState: String
            let createdAtMs: Int64
            let updatedAtMs: Int64
        }

        struct LegacyReceiptRow {
            let ownerUID: String
            let chatID: String
            let messageID: String
            let senderID: String
            let recipientID: String
            let deliveredAtMs: Int64
            let readAtMs: Int64?
            let updatedAtMs: Int64
        }

        struct LegacyReactionRow {
            let ownerUID: String
            let chatID: String
            let messageID: String
            let reactorUID: String
            let emoji: String
            let updatedAtMs: Int64
        }

        var legacyMessages: [LegacyMessageRow] = []
        while sqlite3_step(messageStmt) == SQLITE_ROW {
            guard
                let id = sqliteString(messageStmt, index: 0),
                let chatID = sqliteString(messageStmt, index: 1),
                let senderID = sqliteString(messageStmt, index: 2),
                let recipientID = sqliteString(messageStmt, index: 3),
                let payloadType = sqliteString(messageStmt, index: 5),
                let payloadValue = sqliteString(messageStmt, index: 6),
                let direction = sqliteString(messageStmt, index: 8),
                let uploadState = sqliteString(messageStmt, index: 9)
            else {
                continue
            }

            let sentAtSeconds = sqlite3_column_double(messageStmt, 4)
            let isSecret = sqlite3_column_int(messageStmt, 7) == 1
            let createdAtSeconds = sqlite3_column_double(messageStmt, 10)
            let sentAtMs = Int64(sentAtSeconds * 1000)
            let createdAtMs = Int64(createdAtSeconds * 1000)

            legacyMessages.append(
                LegacyMessageRow(
                    ownerUID: "",
                    chatID: chatID,
                    messageID: id,
                    senderID: senderID,
                    recipientID: recipientID,
                    sentAtMs: sentAtMs,
                    serverTimestampMs: sentAtMs,
                    payloadType: payloadType,
                    payloadValue: payloadValue,
                    isSecret: isSecret,
                    direction: direction,
                    uploadState: uploadState,
                    createdAtMs: createdAtMs,
                    updatedAtMs: createdAtMs
                )
            )
        }

        guard !legacyMessages.isEmpty else { return }

        let hasReceiptTable = sqliteTableExists(handle: handle, tableName: "local_message_receipts")
        var legacyReceipts: [LegacyReceiptRow] = []
        if hasReceiptTable {
            let receiptSQL = """
            SELECT chat_id, message_id, sender_id, recipient_id, delivered_at, read_at, updated_at
            FROM local_message_receipts;
            """
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(handle, receiptSQL, -1, &stmt, nil) == SQLITE_OK,
               let stmt {
                defer { sqlite3_finalize(stmt) }
                while sqlite3_step(stmt) == SQLITE_ROW {
                    guard
                        let chatID = sqliteString(stmt, index: 0),
                        let messageID = sqliteString(stmt, index: 1),
                        let senderID = sqliteString(stmt, index: 2),
                        let recipientID = sqliteString(stmt, index: 3)
                    else { continue }

                    let deliveredAtMs = Int64(sqlite3_column_double(stmt, 4) * 1000)
                    let readAtMs: Int64?
                    if sqlite3_column_type(stmt, 5) == SQLITE_NULL {
                        readAtMs = nil
                    } else {
                        readAtMs = Int64(sqlite3_column_double(stmt, 5) * 1000)
                    }
                    let updatedAtMs = Int64(sqlite3_column_double(stmt, 6) * 1000)

                    legacyReceipts.append(
                        LegacyReceiptRow(
                            ownerUID: "",
                            chatID: chatID,
                            messageID: messageID,
                            senderID: senderID,
                            recipientID: recipientID,
                            deliveredAtMs: deliveredAtMs,
                            readAtMs: readAtMs,
                            updatedAtMs: updatedAtMs
                        )
                    )
                }
            }
        }

        let hasReactionTable = sqliteTableExists(handle: handle, tableName: "local_message_reactions")
        var legacyReactions: [LegacyReactionRow] = []
        if hasReactionTable {
            let reactionSQL = """
            SELECT chat_id, message_id, reactor_uid, emoji, updated_at
            FROM local_message_reactions;
            """
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(handle, reactionSQL, -1, &stmt, nil) == SQLITE_OK,
               let stmt {
                defer { sqlite3_finalize(stmt) }
                while sqlite3_step(stmt) == SQLITE_ROW {
                    guard
                        let chatID = sqliteString(stmt, index: 0),
                        let messageID = sqliteString(stmt, index: 1),
                        let reactorUID = sqliteString(stmt, index: 2),
                        let emoji = sqliteString(stmt, index: 3)
                    else { continue }

                    legacyReactions.append(
                        LegacyReactionRow(
                            ownerUID: "",
                            chatID: chatID,
                            messageID: messageID,
                            reactorUID: reactorUID,
                            emoji: emoji,
                            updatedAtMs: Int64(sqlite3_column_double(stmt, 4) * 1000)
                        )
                    )
                }
            }
        }

        try dbPool.write { db in
            for messageBatch in batched(legacyMessages, size: 500) {
                for message in messageBatch {
                    try db.execute(
                        sql: """
                        INSERT INTO messages (
                            owner_uid, chat_id, message_id, sender_id, recipient_id,
                            sent_at_ms, server_timestamp_ms, payload_type, payload_value,
                            is_secret, direction, upload_state, created_at_ms, updated_at_ms
                        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                        ON CONFLICT(chat_id, message_id) DO NOTHING;
                        """,
                        arguments: [
                            message.ownerUID, message.chatID, message.messageID, message.senderID, message.recipientID,
                            message.sentAtMs, message.serverTimestampMs, message.payloadType, message.payloadValue,
                            message.isSecret ? 1 : 0, message.direction, message.uploadState, message.createdAtMs, message.updatedAtMs
                        ]
                    )
                }
            }

            for receiptBatch in batched(legacyReceipts, size: 500) {
                for receipt in receiptBatch {
                    try db.execute(
                        sql: """
                        INSERT INTO message_receipts (
                            owner_uid, chat_id, message_id, sender_id, recipient_id,
                            delivered_at_ms, read_at_ms, updated_at_ms
                        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                        ON CONFLICT(chat_id, message_id) DO UPDATE SET
                            owner_uid = excluded.owner_uid,
                            sender_id = excluded.sender_id,
                            recipient_id = excluded.recipient_id,
                            delivered_at_ms = excluded.delivered_at_ms,
                            read_at_ms = excluded.read_at_ms,
                            updated_at_ms = excluded.updated_at_ms;
                        """,
                        arguments: [
                            receipt.ownerUID, receipt.chatID, receipt.messageID, receipt.senderID, receipt.recipientID,
                            receipt.deliveredAtMs, receipt.readAtMs, receipt.updatedAtMs
                        ]
                    )
                }
            }

            for reactionBatch in batched(legacyReactions, size: 500) {
                for reaction in reactionBatch {
                    try db.execute(
                        sql: """
                        INSERT INTO message_reactions (
                            owner_uid, chat_id, message_id, reactor_uid, emoji, updated_at_ms
                        ) VALUES (?, ?, ?, ?, ?, ?)
                        ON CONFLICT(chat_id, message_id, reactor_uid) DO UPDATE SET
                            owner_uid = excluded.owner_uid,
                            emoji = excluded.emoji,
                            updated_at_ms = excluded.updated_at_ms;
                        """,
                        arguments: [
                            reaction.ownerUID, reaction.chatID, reaction.messageID, reaction.reactorUID, reaction.emoji, reaction.updatedAtMs
                        ]
                    )
                }
            }
        }
    }

    private static func batched<T>(_ items: [T], size: Int) -> [[T]] {
        guard size > 0, !items.isEmpty else { return [] }
        var result: [[T]] = []
        result.reserveCapacity((items.count + size - 1) / size)

        var start = 0
        while start < items.count {
            let end = min(start + size, items.count)
            result.append(Array(items[start..<end]))
            start = end
        }
        return result
    }

    private static func legacyDatabaseURL(fileManager: FileManager) throws -> URL {
        let appSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return appSupport
            .appendingPathComponent("LocalMessageQueue", isDirectory: true)
            .appendingPathComponent("local_messages.sqlite", isDirectory: false)
    }

    private static func sqliteTableExists(handle: OpaquePointer, tableName: String) -> Bool {
        let sql = "SELECT name FROM sqlite_master WHERE type='table' AND name=? LIMIT 1;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK,
              let stmt else {
            sqlite3_finalize(stmt)
            return false
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, tableName, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        return sqlite3_step(stmt) == SQLITE_ROW
    }

    private static func sqliteString(_ statement: OpaquePointer?, index: Int32) -> String? {
        guard let cString = sqlite3_column_text(statement, index) else {
            return nil
        }
        return String(cString: cString)
    }
}
