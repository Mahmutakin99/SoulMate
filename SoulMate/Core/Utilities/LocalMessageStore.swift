//
//  LocalMessageStore.swift
//  SoulMate
//
//  Created by MAHMUT AKIN on 02/02/2026.
//

import Foundation
import SQLite3

enum LocalMessageStoreError: LocalizedError {
    case databaseUnavailable
    case databaseOpenFailed
    case statementPreparationFailed
    case executionFailed

    var errorDescription: String? {
        switch self {
        case .databaseUnavailable:
            return L10n.t("chat.local.error.database_unavailable")
        case .databaseOpenFailed:
            return L10n.t("chat.local.error.database_open_failed")
        case .statementPreparationFailed:
            return L10n.t("chat.local.error.statement_failed")
        case .executionFailed:
            return L10n.t("chat.local.error.execution_failed")
        }
    }
}

enum LocalMessageDirection: String {
    case incoming
    case outgoing
}

enum LocalMessageUploadState: String {
    case pendingUpload
    case uploaded
    case failed
    case blocked
}

struct LocalPendingUpload {
    let messageID: String
    let chatID: String
    let senderID: String
    let recipientID: String
    let sentAt: TimeInterval
    let payloadType: ChatPayloadType
    let payloadValue: String
    let isSecret: Bool
}

struct LocalStoredReceipt {
    let messageID: String
    let senderID: String
    let recipientID: String
    let deliveredAt: TimeInterval
    let readAt: TimeInterval?
    let updatedAt: TimeInterval
}

struct LocalStoredReaction {
    let messageID: String
    let reactorUID: String
    let emoji: String
    let updatedAt: TimeInterval
}

final class LocalMessageStore {
    static let shared = LocalMessageStore()

    private let queue = DispatchQueue(label: "com.soulmate.localmessagestore.queue", qos: .utility)
    private let fileManager: FileManager
    private var db: OpaquePointer?
    private var cachedStatements: [String: OpaquePointer] = [:]

    private init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        do {
            try openDatabase()
            try createSchemaIfNeeded()
        } catch {
            db = nil
            #if DEBUG
            print("LocalMessageStore başlatılamadı: \(error.localizedDescription)")
            #endif
        }
    }

    deinit {
        cachedStatements.values.forEach { sqlite3_finalize($0) }
        cachedStatements.removeAll()
        if let db {
            sqlite3_close(db)
        }
    }

    func insertIfNeeded(
        chatID: String,
        message: ChatMessage,
        direction: LocalMessageDirection,
        uploadState: LocalMessageUploadState
    ) throws -> Bool {
        try queue.sync {
            guard let db else { throw LocalMessageStoreError.databaseUnavailable }
            return try executeInsert(
                db: db,
                chatID: chatID,
                message: message,
                direction: direction,
                uploadState: uploadState
            ) > 0
        }
    }

    func insertBatchIfNeeded(
        chatID: String,
        messages: [ChatMessage],
        direction: LocalMessageDirection,
        uploadState: LocalMessageUploadState
    ) throws -> Int {
        guard !messages.isEmpty else { return 0 }

        return try queue.sync {
            guard let db else { throw LocalMessageStoreError.databaseUnavailable }

            guard sqlite3_exec(db, "BEGIN IMMEDIATE TRANSACTION;", nil, nil, nil) == SQLITE_OK else {
                throw LocalMessageStoreError.executionFailed
            }

            do {
                var insertedCount = 0
                for message in messages {
                    insertedCount += try executeInsert(
                        db: db,
                        chatID: chatID,
                        message: message,
                        direction: direction,
                        uploadState: uploadState
                    )
                }

                guard sqlite3_exec(db, "COMMIT;", nil, nil, nil) == SQLITE_OK else {
                    throw LocalMessageStoreError.executionFailed
                }

                return insertedCount
            } catch {
                sqlite3_exec(db, "ROLLBACK;", nil, nil, nil)
                throw error
            }
        }
    }

    func markUploaded(messageID: String) throws {
        try updateUploadState(messageID: messageID, state: .uploaded)
    }

    func markUploadFailed(messageID: String) throws {
        try updateUploadState(messageID: messageID, state: .failed)
    }

    func markUploadBlocked(messageID: String) throws {
        try updateUploadState(messageID: messageID, state: .blocked)
    }

    func fetchRecent(chatID: String, limit: UInt) throws -> [ChatMessage] {
        try queue.sync {
            guard let db else { throw LocalMessageStoreError.databaseUnavailable }

            let sql = """
            SELECT id, sender_id, recipient_id, sent_at, payload_type, payload_value, is_secret
            FROM local_messages
            WHERE chat_id = ?
            ORDER BY sent_at DESC, id DESC
            LIMIT ?;
            """

            let statement = try statement(
                db: db,
                key: "fetchRecent",
                sql: sql
            )

            sqlite3_bind_text(statement, 1, chatID, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int64(statement, 2, Int64(limit))

            var rows: [ChatMessage] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                if let message = decodeChatMessage(from: statement) {
                    rows.append(message)
                }
            }

            return rows.reversed()
        }
    }

    func fetchOlder(chatID: String, beforeSentAt: TimeInterval, limit: UInt) throws -> [ChatMessage] {
        try queue.sync {
            guard let db else { throw LocalMessageStoreError.databaseUnavailable }

            let sql = """
            SELECT id, sender_id, recipient_id, sent_at, payload_type, payload_value, is_secret
            FROM local_messages
            WHERE chat_id = ? AND sent_at < ?
            ORDER BY sent_at DESC, id DESC
            LIMIT ?;
            """

            let statement = try statement(
                db: db,
                key: "fetchOlder",
                sql: sql
            )

            sqlite3_bind_text(statement, 1, chatID, -1, SQLITE_TRANSIENT)
            sqlite3_bind_double(statement, 2, beforeSentAt)
            sqlite3_bind_int64(statement, 3, Int64(limit))

            var rows: [ChatMessage] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                if let message = decodeChatMessage(from: statement) {
                    rows.append(message)
                }
            }

            return rows.reversed()
        }
    }

    func pendingUploads(chatID: String, limit: UInt) throws -> [LocalPendingUpload] {
        try queue.sync {
            guard let db else { throw LocalMessageStoreError.databaseUnavailable }

            let sql = """
            SELECT id, chat_id, sender_id, recipient_id, sent_at, payload_type, payload_value, is_secret
            FROM local_messages
            WHERE chat_id = ? AND upload_state IN (?, ?)
            ORDER BY created_at ASC
            LIMIT ?;
            """

            let statement = try statement(
                db: db,
                key: "pendingUploads",
                sql: sql
            )

            sqlite3_bind_text(statement, 1, chatID, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(statement, 2, LocalMessageUploadState.pendingUpload.rawValue, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(statement, 3, LocalMessageUploadState.failed.rawValue, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int64(statement, 4, Int64(limit))

            var rows: [LocalPendingUpload] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                guard let id = sqliteString(statement, index: 0),
                      let chatID = sqliteString(statement, index: 1),
                      let senderID = sqliteString(statement, index: 2),
                      let recipientID = sqliteString(statement, index: 3),
                      let payloadTypeRaw = sqliteString(statement, index: 5),
                      let payloadType = ChatPayloadType(rawValue: payloadTypeRaw),
                      let payloadValue = sqliteString(statement, index: 6) else {
                    continue
                }

                let sentAt = sqlite3_column_double(statement, 4)
                let isSecret = sqlite3_column_int(statement, 7) == 1

                rows.append(
                    LocalPendingUpload(
                        messageID: id,
                        chatID: chatID,
                        senderID: senderID,
                        recipientID: recipientID,
                        sentAt: sentAt,
                        payloadType: payloadType,
                        payloadValue: payloadValue,
                        isSecret: isSecret
                    )
                )
            }

            return rows
        }
    }

    func fetchUploadStates(chatID: String, messageIDs: [String]) throws -> [String: LocalMessageUploadState] {
        guard !messageIDs.isEmpty else { return [:] }

        return try queue.sync {
            guard let db else { throw LocalMessageStoreError.databaseUnavailable }
            let placeholders = Array(repeating: "?", count: messageIDs.count).joined(separator: ",")
            let sql = """
            SELECT id, upload_state
            FROM local_messages
            WHERE chat_id = ? AND id IN (\(placeholders));
            """

            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK,
                  let statement else {
                throw LocalMessageStoreError.statementPreparationFailed
            }
            defer { sqlite3_finalize(statement) }

            sqlite3_bind_text(statement, 1, chatID, -1, SQLITE_TRANSIENT)
            for (index, id) in messageIDs.enumerated() {
                sqlite3_bind_text(statement, Int32(index + 2), id, -1, SQLITE_TRANSIENT)
            }

            var states: [String: LocalMessageUploadState] = [:]
            while sqlite3_step(statement) == SQLITE_ROW {
                guard let messageID = sqliteString(statement, index: 0),
                      let stateRaw = sqliteString(statement, index: 1),
                      let state = LocalMessageUploadState(rawValue: stateRaw) else {
                    continue
                }
                states[messageID] = state
            }
            return states
        }
    }

    func upsertReceipt(
        chatID: String,
        messageID: String,
        senderID: String,
        recipientID: String,
        deliveredAt: TimeInterval,
        readAt: TimeInterval?,
        updatedAt: TimeInterval
    ) throws {
        try queue.sync {
            guard let db else { throw LocalMessageStoreError.databaseUnavailable }
            let sql = """
            INSERT INTO local_message_receipts (
                chat_id, message_id, sender_id, recipient_id, delivered_at, read_at, updated_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(message_id) DO UPDATE SET
                chat_id = excluded.chat_id,
                sender_id = excluded.sender_id,
                recipient_id = excluded.recipient_id,
                delivered_at = excluded.delivered_at,
                read_at = excluded.read_at,
                updated_at = excluded.updated_at;
            """

            let statement = try statement(
                db: db,
                key: "upsertReceipt",
                sql: sql
            )

            sqlite3_bind_text(statement, 1, chatID, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(statement, 2, messageID, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(statement, 3, senderID, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(statement, 4, recipientID, -1, SQLITE_TRANSIENT)
            sqlite3_bind_double(statement, 5, deliveredAt)
            if let readAt {
                sqlite3_bind_double(statement, 6, readAt)
            } else {
                sqlite3_bind_null(statement, 6)
            }
            sqlite3_bind_double(statement, 7, updatedAt)

            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw LocalMessageStoreError.executionFailed
            }
        }
    }

    func markRead(messageID: String, readAt: TimeInterval, updatedAt: TimeInterval) throws {
        try queue.sync {
            guard let db else { throw LocalMessageStoreError.databaseUnavailable }
            let sql = """
            UPDATE local_message_receipts
            SET read_at = ?, updated_at = ?
            WHERE message_id = ?;
            """
            let statement = try statement(
                db: db,
                key: "markReceiptRead",
                sql: sql
            )

            sqlite3_bind_double(statement, 1, readAt)
            sqlite3_bind_double(statement, 2, updatedAt)
            sqlite3_bind_text(statement, 3, messageID, -1, SQLITE_TRANSIENT)

            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw LocalMessageStoreError.executionFailed
            }
        }
    }

    func fetchReceipts(chatID: String, messageIDs: [String]) throws -> [LocalStoredReceipt] {
        guard !messageIDs.isEmpty else { return [] }

        return try queue.sync {
            guard let db else { throw LocalMessageStoreError.databaseUnavailable }
            let placeholders = Array(repeating: "?", count: messageIDs.count).joined(separator: ",")
            let sql = """
            SELECT message_id, sender_id, recipient_id, delivered_at, read_at, updated_at
            FROM local_message_receipts
            WHERE chat_id = ? AND message_id IN (\(placeholders));
            """

            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK,
                  let statement else {
                throw LocalMessageStoreError.statementPreparationFailed
            }
            defer { sqlite3_finalize(statement) }

            sqlite3_bind_text(statement, 1, chatID, -1, SQLITE_TRANSIENT)
            for (index, id) in messageIDs.enumerated() {
                sqlite3_bind_text(statement, Int32(index + 2), id, -1, SQLITE_TRANSIENT)
            }

            var rows: [LocalStoredReceipt] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                guard let messageID = sqliteString(statement, index: 0),
                      let senderID = sqliteString(statement, index: 1),
                      let recipientID = sqliteString(statement, index: 2) else {
                    continue
                }

                let deliveredAt = sqlite3_column_double(statement, 3)
                let readAt = sqlite3_column_type(statement, 4) == SQLITE_NULL
                    ? nil
                    : sqlite3_column_double(statement, 4)
                let updatedAt = sqlite3_column_double(statement, 5)
                rows.append(
                    LocalStoredReceipt(
                        messageID: messageID,
                        senderID: senderID,
                        recipientID: recipientID,
                        deliveredAt: deliveredAt,
                        readAt: readAt,
                        updatedAt: updatedAt
                    )
                )
            }
            return rows
        }
    }

    func upsertReaction(
        chatID: String,
        messageID: String,
        reactorUID: String,
        emoji: String,
        updatedAt: TimeInterval
    ) throws {
        try queue.sync {
            guard let db else { throw LocalMessageStoreError.databaseUnavailable }
            let sql = """
            INSERT INTO local_message_reactions (
                chat_id, message_id, reactor_uid, emoji, updated_at
            ) VALUES (?, ?, ?, ?, ?)
            ON CONFLICT(chat_id, message_id, reactor_uid) DO UPDATE SET
                emoji = excluded.emoji,
                updated_at = excluded.updated_at;
            """
            let statement = try statement(
                db: db,
                key: "upsertReaction",
                sql: sql
            )

            sqlite3_bind_text(statement, 1, chatID, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(statement, 2, messageID, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(statement, 3, reactorUID, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(statement, 4, emoji, -1, SQLITE_TRANSIENT)
            sqlite3_bind_double(statement, 5, updatedAt)

            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw LocalMessageStoreError.executionFailed
            }
        }
    }

    func removeReaction(chatID: String, messageID: String, reactorUID: String) throws {
        try queue.sync {
            guard let db else { throw LocalMessageStoreError.databaseUnavailable }
            let sql = """
            DELETE FROM local_message_reactions
            WHERE chat_id = ? AND message_id = ? AND reactor_uid = ?;
            """
            let statement = try statement(
                db: db,
                key: "removeReaction",
                sql: sql
            )

            sqlite3_bind_text(statement, 1, chatID, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(statement, 2, messageID, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(statement, 3, reactorUID, -1, SQLITE_TRANSIENT)

            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw LocalMessageStoreError.executionFailed
            }
        }
    }

    func fetchReactions(chatID: String, messageIDs: [String]) throws -> [LocalStoredReaction] {
        guard !messageIDs.isEmpty else { return [] }

        return try queue.sync {
            guard let db else { throw LocalMessageStoreError.databaseUnavailable }
            let placeholders = Array(repeating: "?", count: messageIDs.count).joined(separator: ",")
            let sql = """
            SELECT message_id, reactor_uid, emoji, updated_at
            FROM local_message_reactions
            WHERE chat_id = ? AND message_id IN (\(placeholders));
            """

            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK,
                  let statement else {
                throw LocalMessageStoreError.statementPreparationFailed
            }
            defer { sqlite3_finalize(statement) }

            sqlite3_bind_text(statement, 1, chatID, -1, SQLITE_TRANSIENT)
            for (index, id) in messageIDs.enumerated() {
                sqlite3_bind_text(statement, Int32(index + 2), id, -1, SQLITE_TRANSIENT)
            }

            var rows: [LocalStoredReaction] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                guard let messageID = sqliteString(statement, index: 0),
                      let reactorUID = sqliteString(statement, index: 1),
                      let emoji = sqliteString(statement, index: 2) else {
                    continue
                }

                rows.append(
                    LocalStoredReaction(
                        messageID: messageID,
                        reactorUID: reactorUID,
                        emoji: emoji,
                        updatedAt: sqlite3_column_double(statement, 3)
                    )
                )
            }
            return rows
        }
    }

    func deleteConversation(chatID: String) throws {
        try queue.sync {
            guard let db else { throw LocalMessageStoreError.databaseUnavailable }

            let statements: [(key: String, sql: String)] = [
                ("deleteConversationMessages", "DELETE FROM local_messages WHERE chat_id = ?;"),
                ("deleteConversationReceipts", "DELETE FROM local_message_receipts WHERE chat_id = ?;"),
                ("deleteConversationReactions", "DELETE FROM local_message_reactions WHERE chat_id = ?;")
            ]

            for item in statements {
                let statement = try statement(
                    db: db,
                    key: item.key,
                    sql: item.sql
                )
                sqlite3_bind_text(statement, 1, chatID, -1, SQLITE_TRANSIENT)
                guard sqlite3_step(statement) == SQLITE_DONE else {
                    throw LocalMessageStoreError.executionFailed
                }
            }
        }
    }

    func count(chatID: String) throws -> Int {
        try queue.sync {
            guard let db else { throw LocalMessageStoreError.databaseUnavailable }

            let sql = "SELECT COUNT(*) FROM local_messages WHERE chat_id = ?;"
            let statement = try statement(
                db: db,
                key: "countConversation",
                sql: sql
            )

            sqlite3_bind_text(statement, 1, chatID, -1, SQLITE_TRANSIENT)
            guard sqlite3_step(statement) == SQLITE_ROW else {
                throw LocalMessageStoreError.executionFailed
            }
            return Int(sqlite3_column_int64(statement, 0))
        }
    }

    func existingMessageIDs(chatID: String, ids: [String]) throws -> Set<String> {
        guard !ids.isEmpty else { return [] }

        return try queue.sync {
            guard let db else { throw LocalMessageStoreError.databaseUnavailable }

            let placeholders = Array(repeating: "?", count: ids.count).joined(separator: ",")
            let sql = """
            SELECT id
            FROM local_messages
            WHERE chat_id = ? AND id IN (\(placeholders));
            """

            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK,
                  let statement else {
                throw LocalMessageStoreError.statementPreparationFailed
            }
            defer { sqlite3_finalize(statement) }

            sqlite3_bind_text(statement, 1, chatID, -1, SQLITE_TRANSIENT)
            for (index, id) in ids.enumerated() {
                sqlite3_bind_text(statement, Int32(index + 2), id, -1, SQLITE_TRANSIENT)
            }

            var existing: Set<String> = []
            while sqlite3_step(statement) == SQLITE_ROW {
                if let id = sqliteString(statement, index: 0) {
                    existing.insert(id)
                }
            }
            return existing
        }
    }

    private func updateUploadState(messageID: String, state: LocalMessageUploadState) throws {
        try queue.sync {
            guard let db else { throw LocalMessageStoreError.databaseUnavailable }

            let sql = "UPDATE local_messages SET upload_state = ? WHERE id = ?;"
            let statement = try statement(
                db: db,
                key: "updateUploadState",
                sql: sql
            )

            sqlite3_bind_text(statement, 1, state.rawValue, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(statement, 2, messageID, -1, SQLITE_TRANSIENT)

            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw LocalMessageStoreError.executionFailed
            }
        }
    }

    @discardableResult
    private func executeInsert(
        db: OpaquePointer,
        chatID: String,
        message: ChatMessage,
        direction: LocalMessageDirection,
        uploadState: LocalMessageUploadState
    ) throws -> Int {
        let sql = """
        INSERT OR IGNORE INTO local_messages (
            id, chat_id, sender_id, recipient_id, sent_at,
            payload_type, payload_value, is_secret, direction,
            upload_state, created_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """

        let statement = try statement(
            db: db,
            key: "insertIgnore",
            sql: sql
        )

        sqlite3_bind_text(statement, 1, message.id, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(statement, 2, chatID, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(statement, 3, message.senderID, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(statement, 4, message.recipientID, -1, SQLITE_TRANSIENT)
        sqlite3_bind_double(statement, 5, message.sentAt.timeIntervalSince1970)
        sqlite3_bind_text(statement, 6, message.type.rawValue, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(statement, 7, message.value, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int(statement, 8, message.isSecret ? 1 : 0)
        sqlite3_bind_text(statement, 9, direction.rawValue, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(statement, 10, uploadState.rawValue, -1, SQLITE_TRANSIENT)
        sqlite3_bind_double(statement, 11, Date().timeIntervalSince1970)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw LocalMessageStoreError.executionFailed
        }

        return Int(sqlite3_changes(db))
    }

    private func statement(db: OpaquePointer, key: String, sql: String) throws -> OpaquePointer {
        if let cached = cachedStatements[key] {
            sqlite3_reset(cached)
            sqlite3_clear_bindings(cached)
            return cached
        }

        var prepared: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &prepared, nil) == SQLITE_OK,
              let prepared else {
            throw LocalMessageStoreError.statementPreparationFailed
        }

        cachedStatements[key] = prepared
        return prepared
    }

    private func decodeChatMessage(from statement: OpaquePointer) -> ChatMessage? {
        guard let id = sqliteString(statement, index: 0),
              let senderID = sqliteString(statement, index: 1),
              let recipientID = sqliteString(statement, index: 2),
              let payloadTypeRaw = sqliteString(statement, index: 4),
              let payloadType = ChatPayloadType(rawValue: payloadTypeRaw),
              let payloadValue = sqliteString(statement, index: 5) else {
            return nil
        }

        let sentAt = sqlite3_column_double(statement, 3)
        let isSecret = sqlite3_column_int(statement, 6) == 1

        return ChatMessage(
            id: id,
            senderID: senderID,
            recipientID: recipientID,
            sentAt: Date(timeIntervalSince1970: sentAt),
            type: payloadType,
            value: payloadValue,
            isSecret: isSecret
        )
    }

    private func sqliteString(_ statement: OpaquePointer?, index: Int32) -> String? {
        guard let cString = sqlite3_column_text(statement, index) else {
            return nil
        }
        return String(cString: cString)
    }

    private func openDatabase() throws {
        let dbURL = try databaseFileURL()
        try createDirectoryIfNeeded(at: dbURL.deletingLastPathComponent())

        var handle: OpaquePointer?
        if sqlite3_open_v2(dbURL.path, &handle, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil) != SQLITE_OK {
            throw LocalMessageStoreError.databaseOpenFailed
        }

        db = handle
        sqlite3_exec(db, "PRAGMA journal_mode=WAL;", nil, nil, nil)
        sqlite3_exec(db, "PRAGMA synchronous=NORMAL;", nil, nil, nil)
        sqlite3_exec(db, "PRAGMA foreign_keys=ON;", nil, nil, nil)
    }

    private func createSchemaIfNeeded() throws {
        guard let db else { throw LocalMessageStoreError.databaseUnavailable }

        let createTable = """
        CREATE TABLE IF NOT EXISTS local_messages (
            id TEXT PRIMARY KEY,
            chat_id TEXT NOT NULL,
            sender_id TEXT NOT NULL,
            recipient_id TEXT NOT NULL,
            sent_at REAL NOT NULL,
            payload_type TEXT NOT NULL,
            payload_value TEXT NOT NULL,
            is_secret INTEGER NOT NULL,
            direction TEXT NOT NULL,
            upload_state TEXT NOT NULL,
            created_at REAL NOT NULL
        );
        """

        let createChatSentIndex = "CREATE INDEX IF NOT EXISTS idx_local_messages_chat_sent ON local_messages(chat_id, sent_at DESC);"
        let createChatIDIndex = "CREATE INDEX IF NOT EXISTS idx_local_messages_chat_id ON local_messages(chat_id, id);"
        let createUploadIndex = "CREATE INDEX IF NOT EXISTS idx_local_messages_upload_state ON local_messages(upload_state, created_at);"
        let createReceiptsTable = """
        CREATE TABLE IF NOT EXISTS local_message_receipts (
            chat_id TEXT NOT NULL,
            message_id TEXT PRIMARY KEY,
            sender_id TEXT NOT NULL,
            recipient_id TEXT NOT NULL,
            delivered_at REAL NOT NULL,
            read_at REAL,
            updated_at REAL NOT NULL
        );
        """
        let createReceiptsChatIndex = "CREATE INDEX IF NOT EXISTS idx_local_message_receipts_chat_message ON local_message_receipts(chat_id, message_id);"
        let createReceiptsUpdatedIndex = "CREATE INDEX IF NOT EXISTS idx_local_message_receipts_updated ON local_message_receipts(chat_id, updated_at);"
        let createReactionsTable = """
        CREATE TABLE IF NOT EXISTS local_message_reactions (
            chat_id TEXT NOT NULL,
            message_id TEXT NOT NULL,
            reactor_uid TEXT NOT NULL,
            emoji TEXT NOT NULL,
            updated_at REAL NOT NULL,
            PRIMARY KEY (chat_id, message_id, reactor_uid)
        );
        """
        let createReactionsMessageIndex = "CREATE INDEX IF NOT EXISTS idx_local_message_reactions_message ON local_message_reactions(chat_id, message_id);"
        let createReactionsUpdatedIndex = "CREATE INDEX IF NOT EXISTS idx_local_message_reactions_updated ON local_message_reactions(chat_id, updated_at);"

        for sql in [
            createTable,
            createChatSentIndex,
            createChatIDIndex,
            createUploadIndex,
            createReceiptsTable,
            createReceiptsChatIndex,
            createReceiptsUpdatedIndex,
            createReactionsTable,
            createReactionsMessageIndex,
            createReactionsUpdatedIndex
        ] {
            if sqlite3_exec(db, sql, nil, nil, nil) != SQLITE_OK {
                throw LocalMessageStoreError.executionFailed
            }
        }
    }

    private func databaseFileURL() throws -> URL {
        let appSupportURL = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )

        let directoryURL = appSupportURL
            .appendingPathComponent("LocalMessageQueue", isDirectory: true)

        return directoryURL.appendingPathComponent("local_messages.sqlite", isDirectory: false)
    }

    private func createDirectoryIfNeeded(at url: URL) throws {
        if !fileManager.fileExists(atPath: url.path) {
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
