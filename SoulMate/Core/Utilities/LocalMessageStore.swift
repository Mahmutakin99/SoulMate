//
//  LocalMessageStore.swift
//  SoulMate
//
//  Created by MAHMUT AKIN on 02/02/2026.
//

import Foundation
import GRDB

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

struct ChatSyncCursor: Equatable {
    let timestampMs: Int64
    let messageID: String
}

enum MessageSyncPolicyDecision: Equatable {
    case skip
    case bootstrap(reason: String)
}

final class LocalMessageStore {
    static let shared = LocalMessageStore()
    private static let idQueryChunkSize = 180

    private let dbPool: DatabasePool

    private init() {
        let appDatabase = AppDatabase.shared
        self.dbPool = appDatabase.dbPool
        appDatabase.startDeferredLegacyImportIfNeeded()
    }

    func insertIfNeeded(
        chatID: String,
        message: ChatMessage,
        direction: LocalMessageDirection,
        uploadState: LocalMessageUploadState,
        serverTimestampMs: Int64? = nil
    ) throws -> Bool {
        try dbPool.write { db in
            let nowMs = Self.nowMs()
            let sentAtMs = Int64(message.sentAt.timeIntervalSince1970 * 1000)
            let orderedTimestampMs = serverTimestampMs ?? sentAtMs
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
                    "", chatID, message.id, message.senderID, message.recipientID,
                    sentAtMs, orderedTimestampMs, message.type.rawValue, message.value,
                    message.isSecret ? 1 : 0, direction.rawValue, uploadState.rawValue,
                    nowMs, nowMs
                ]
            )
            return db.changesCount > 0
        }
    }

    func insertBatchIfNeeded(
        chatID: String,
        messages: [ChatMessage],
        direction: LocalMessageDirection,
        uploadState: LocalMessageUploadState,
        serverTimestampMsByMessageID: [String: Int64] = [:]
    ) throws -> Int {
        guard !messages.isEmpty else { return 0 }

        return try dbPool.write { db in
            var insertedCount = 0
            for message in messages {
                let nowMs = Self.nowMs()
                let sentAtMs = Int64(message.sentAt.timeIntervalSince1970 * 1000)
                let orderedTimestampMs = serverTimestampMsByMessageID[message.id] ?? sentAtMs
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
                        "", chatID, message.id, message.senderID, message.recipientID,
                        sentAtMs, orderedTimestampMs, message.type.rawValue, message.value,
                        message.isSecret ? 1 : 0, direction.rawValue, uploadState.rawValue,
                        nowMs, nowMs
                    ]
                )
                insertedCount += Int(db.changesCount)
            }
            return insertedCount
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
        try dbPool.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                SELECT message_id, sender_id, recipient_id, sent_at_ms, payload_type, payload_value, is_secret
                FROM messages
                WHERE chat_id = ?
                ORDER BY server_timestamp_ms DESC, message_id DESC
                LIMIT ?;
                """,
                arguments: [chatID, Int(limit)]
            )

            return rows.compactMap { row in
                guard let payloadType = ChatPayloadType(rawValue: row["payload_type"]) else {
                    return nil
                }
                let sentAtMs: Int64 = row["sent_at_ms"]
                return ChatMessage(
                    id: row["message_id"],
                    senderID: row["sender_id"],
                    recipientID: row["recipient_id"],
                    sentAt: Date(timeIntervalSince1970: TimeInterval(sentAtMs) / 1000),
                    type: payloadType,
                    value: row["payload_value"],
                    isSecret: (row["is_secret"] as Int64) == 1
                )
            }.reversed()
        }
    }

    func fetchOlder(chatID: String, beforeSentAt: TimeInterval, limit: UInt) throws -> [ChatMessage] {
        let beforeMs = Int64(beforeSentAt * 1000)
        return try dbPool.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                SELECT message_id, sender_id, recipient_id, sent_at_ms, payload_type, payload_value, is_secret
                FROM messages
                WHERE chat_id = ? AND server_timestamp_ms < ?
                ORDER BY server_timestamp_ms DESC, message_id DESC
                LIMIT ?;
                """,
                arguments: [chatID, beforeMs, Int(limit)]
            )

            return rows.compactMap { row in
                guard let payloadType = ChatPayloadType(rawValue: row["payload_type"]) else {
                    return nil
                }
                let sentAtMs: Int64 = row["sent_at_ms"]
                return ChatMessage(
                    id: row["message_id"],
                    senderID: row["sender_id"],
                    recipientID: row["recipient_id"],
                    sentAt: Date(timeIntervalSince1970: TimeInterval(sentAtMs) / 1000),
                    type: payloadType,
                    value: row["payload_value"],
                    isSecret: (row["is_secret"] as Int64) == 1
                )
            }.reversed()
        }
    }

    func pendingUploads(chatID: String, limit: UInt) throws -> [LocalPendingUpload] {
        try dbPool.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                SELECT message_id, chat_id, sender_id, recipient_id, sent_at_ms, payload_type, payload_value, is_secret
                FROM messages
                WHERE chat_id = ? AND upload_state IN (?, ?)
                ORDER BY created_at_ms ASC
                LIMIT ?;
                """,
                arguments: [chatID, LocalMessageUploadState.pendingUpload.rawValue, LocalMessageUploadState.failed.rawValue, Int(limit)]
            )

            return rows.compactMap { row in
                guard let payloadType = ChatPayloadType(rawValue: row["payload_type"]) else {
                    return nil
                }
                return LocalPendingUpload(
                    messageID: row["message_id"],
                    chatID: row["chat_id"],
                    senderID: row["sender_id"],
                    recipientID: row["recipient_id"],
                    sentAt: TimeInterval(Int64(row["sent_at_ms"] as Int64)) / 1000,
                    payloadType: payloadType,
                    payloadValue: row["payload_value"],
                    isSecret: (row["is_secret"] as Int64) == 1
                )
            }
        }
    }

    func fetchUploadStates(chatID: String, messageIDs: [String]) throws -> [String: LocalMessageUploadState] {
        guard !messageIDs.isEmpty else { return [:] }

        let uniqueIDs = Array(Set(messageIDs))
        return try dbPool.read { db in
            var states: [String: LocalMessageUploadState] = [:]
            for chunk in Self.chunked(uniqueIDs, size: Self.idQueryChunkSize) where !chunk.isEmpty {
                let rows = try Row.fetchAll(
                    db,
                    sql: """
                    SELECT message_id, upload_state
                    FROM messages
                    WHERE chat_id = ? AND message_id IN (\(Self.sqlPlaceholders(count: chunk.count)));
                    """,
                    arguments: Self.arguments(chatID: chatID, ids: chunk)
                )

                for row in rows {
                    let messageID: String = row["message_id"]
                    guard let state = LocalMessageUploadState(rawValue: row["upload_state"]) else {
                        continue
                    }
                    states[messageID] = state
                }
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
        try dbPool.write { db in
            var record = ReceiptRecord(
                ownerUID: "",
                chatID: chatID,
                messageID: messageID,
                senderID: senderID,
                recipientID: recipientID,
                deliveredAtMs: Int64(deliveredAt * 1000),
                readAtMs: readAt.map { Int64($0 * 1000) },
                updatedAtMs: Int64(updatedAt * 1000)
            )
            try record.save(db)
        }
    }

    func markRead(messageID: String, readAt: TimeInterval, updatedAt: TimeInterval) throws {
        try dbPool.write { db in
            try db.execute(
                sql: """
                UPDATE message_receipts
                SET read_at_ms = ?, updated_at_ms = ?
                WHERE message_id = ?;
                """,
                arguments: [Int64(readAt * 1000), Int64(updatedAt * 1000), messageID]
            )
        }
    }

    func fetchReceipts(chatID: String, messageIDs: [String]) throws -> [LocalStoredReceipt] {
        guard !messageIDs.isEmpty else { return [] }

        let uniqueIDs = Array(Set(messageIDs))
        return try dbPool.read { db in
            var receipts: [LocalStoredReceipt] = []
            receipts.reserveCapacity(uniqueIDs.count)

            for chunk in Self.chunked(uniqueIDs, size: Self.idQueryChunkSize) where !chunk.isEmpty {
                let rows = try Row.fetchAll(
                    db,
                    sql: """
                    SELECT message_id, sender_id, recipient_id, delivered_at_ms, read_at_ms, updated_at_ms
                    FROM message_receipts
                    WHERE chat_id = ? AND message_id IN (\(Self.sqlPlaceholders(count: chunk.count)));
                    """,
                    arguments: Self.arguments(chatID: chatID, ids: chunk)
                )

                receipts.append(contentsOf: rows.compactMap { row in
                    let deliveredAtMs: Int64 = row["delivered_at_ms"]
                    let readAtMs: Int64? = row["read_at_ms"]
                    let updatedAtMs: Int64 = row["updated_at_ms"]

                    return LocalStoredReceipt(
                        messageID: row["message_id"],
                        senderID: row["sender_id"],
                        recipientID: row["recipient_id"],
                        deliveredAt: TimeInterval(deliveredAtMs) / 1000,
                        readAt: readAtMs.map { TimeInterval($0) / 1000 },
                        updatedAt: TimeInterval(updatedAtMs) / 1000
                    )
                })
            }

            return receipts
        }
    }

    func removeReceipt(chatID: String, messageID: String) throws {
        try dbPool.write { db in
            try db.execute(
                sql: """
                DELETE FROM message_receipts
                WHERE chat_id = ? AND message_id = ?;
                """,
                arguments: [chatID, messageID]
            )
        }
    }

    func upsertReaction(
        chatID: String,
        messageID: String,
        reactorUID: String,
        emoji: String,
        updatedAt: TimeInterval
    ) throws {
        try dbPool.write { db in
            var record = ReactionRecord(
                ownerUID: "",
                chatID: chatID,
                messageID: messageID,
                reactorUID: reactorUID,
                emoji: emoji,
                updatedAtMs: Int64(updatedAt * 1000)
            )
            try record.save(db)
        }
    }

    func removeReaction(chatID: String, messageID: String, reactorUID: String) throws {
        try dbPool.write { db in
            try db.execute(
                sql: """
                DELETE FROM message_reactions
                WHERE chat_id = ? AND message_id = ? AND reactor_uid = ?;
                """,
                arguments: [chatID, messageID, reactorUID]
            )
        }
    }

    func removeReactions(chatID: String, messageID: String) throws {
        try dbPool.write { db in
            try db.execute(
                sql: """
                DELETE FROM message_reactions
                WHERE chat_id = ? AND message_id = ?;
                """,
                arguments: [chatID, messageID]
            )
        }
    }

    func fetchReactions(chatID: String, messageIDs: [String]) throws -> [LocalStoredReaction] {
        guard !messageIDs.isEmpty else { return [] }

        let uniqueIDs = Array(Set(messageIDs))
        return try dbPool.read { db in
            var reactions: [LocalStoredReaction] = []
            reactions.reserveCapacity(uniqueIDs.count)

            for chunk in Self.chunked(uniqueIDs, size: Self.idQueryChunkSize) where !chunk.isEmpty {
                let rows = try Row.fetchAll(
                    db,
                    sql: """
                    SELECT message_id, reactor_uid, emoji, updated_at_ms
                    FROM message_reactions
                    WHERE chat_id = ? AND message_id IN (\(Self.sqlPlaceholders(count: chunk.count)));
                    """,
                    arguments: Self.arguments(chatID: chatID, ids: chunk)
                )

                reactions.append(contentsOf: rows.compactMap { row in
                    let updatedAtMs: Int64 = row["updated_at_ms"]
                    return LocalStoredReaction(
                        messageID: row["message_id"],
                        reactorUID: row["reactor_uid"],
                        emoji: row["emoji"],
                        updatedAt: TimeInterval(updatedAtMs) / 1000
                    )
                })
            }

            return reactions
        }
    }

    func deleteConversation(chatID: String) throws {
        try dbPool.write { db in
            try db.execute(sql: "DELETE FROM messages WHERE chat_id = ?;", arguments: [chatID])
            try db.execute(sql: "DELETE FROM message_receipts WHERE chat_id = ?;", arguments: [chatID])
            try db.execute(sql: "DELETE FROM message_reactions WHERE chat_id = ?;", arguments: [chatID])
            try db.execute(sql: "DELETE FROM message_sync_state WHERE chat_id = ?;", arguments: [chatID])
        }
    }

    func wipeAllData() throws {
        try dbPool.write { db in
            try db.execute(sql: "DELETE FROM messages;")
            try db.execute(sql: "DELETE FROM message_receipts;")
            try db.execute(sql: "DELETE FROM message_reactions;")
            try db.execute(sql: "DELETE FROM message_sync_state;")
        }
    }

    func count(chatID: String) throws -> Int {
        try dbPool.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM messages WHERE chat_id = ?;", arguments: [chatID]) ?? 0
        }
    }

    func existingMessageIDs(chatID: String, ids: [String]) throws -> Set<String> {
        try existingMessageIDs(chatID: chatID, candidateIDs: ids)
    }

    func existingMessageIDs(chatID: String, candidateIDs: [String]) throws -> Set<String> {
        guard !candidateIDs.isEmpty else { return [] }
        let uniqueIDs = Array(Set(candidateIDs))

        return try dbPool.read { db in
            var existing = Set<String>()
            existing.reserveCapacity(uniqueIDs.count)

            for chunk in Self.chunked(uniqueIDs, size: Self.idQueryChunkSize) where !chunk.isEmpty {
                let rows = try Row.fetchAll(
                    db,
                    sql: """
                    SELECT message_id
                    FROM messages
                    WHERE chat_id = ? AND message_id IN (\(Self.sqlPlaceholders(count: chunk.count)));
                    """,
                    arguments: Self.arguments(chatID: chatID, ids: chunk)
                )
                rows.forEach { row in
                    let messageID: String = row["message_id"]
                    existing.insert(messageID)
                }
            }
            return existing
        }
    }

    func fetchSyncState(chatID: String) throws -> SyncStateRecord? {
        try dbPool.read { db in
            try SyncStateRecord
                .filter(Column("owner_uid") == "" && Column("chat_id") == chatID)
                .fetchOne(db)
        }
    }

    func upsertSyncState(_ state: SyncStateRecord) throws {
        try dbPool.write { db in
            var mutableState = state
            try mutableState.save(db)
        }
    }

    func markBootstrapStarted(chatID: String, appVersion: String) throws {
        let nowMs = Self.nowMs()
        var state = try fetchSyncState(chatID: chatID) ?? SyncStateRecord(
            ownerUID: "",
            chatID: chatID,
            lastSyncedTimestampMs: nil,
            lastSyncedMessageID: nil,
            bootstrapIncomplete: true,
            gapDetected: false,
            schemaVersion: Migrations.schemaVersion,
            appVersion: appVersion,
            updatedAtMs: nowMs
        )
        state.bootstrapIncomplete = true
        state.schemaVersion = Migrations.schemaVersion
        state.appVersion = appVersion
        state.updatedAtMs = nowMs
        try upsertSyncState(state)
    }

    func markBootstrapCompleted(chatID: String, cursor: ChatSyncCursor?, appVersion: String) throws {
        let nowMs = Self.nowMs()
        var state = try fetchSyncState(chatID: chatID) ?? SyncStateRecord(
            ownerUID: "",
            chatID: chatID,
            lastSyncedTimestampMs: nil,
            lastSyncedMessageID: nil,
            bootstrapIncomplete: false,
            gapDetected: false,
            schemaVersion: Migrations.schemaVersion,
            appVersion: appVersion,
            updatedAtMs: nowMs
        )
        let nextTimestamp = cursor?.timestampMs
        let nextMessageID = cursor?.messageID
        let isNoOp =
            state.bootstrapIncomplete == false &&
            state.lastSyncedTimestampMs == nextTimestamp &&
            state.lastSyncedMessageID == nextMessageID &&
            state.schemaVersion == Migrations.schemaVersion &&
            state.appVersion == appVersion
        if isNoOp {
            return
        }
        state.bootstrapIncomplete = false
        state.lastSyncedTimestampMs = nextTimestamp
        state.lastSyncedMessageID = nextMessageID
        state.schemaVersion = Migrations.schemaVersion
        state.appVersion = appVersion
        state.updatedAtMs = nowMs
        try upsertSyncState(state)
    }

    func markGapDetected(chatID: String, gapDetected: Bool, appVersion: String) throws {
        let nowMs = Self.nowMs()
        var state = try fetchSyncState(chatID: chatID) ?? SyncStateRecord(
            ownerUID: "",
            chatID: chatID,
            lastSyncedTimestampMs: nil,
            lastSyncedMessageID: nil,
            bootstrapIncomplete: false,
            gapDetected: gapDetected,
            schemaVersion: Migrations.schemaVersion,
            appVersion: appVersion,
            updatedAtMs: nowMs
        )
        state.gapDetected = gapDetected
        state.schemaVersion = Migrations.schemaVersion
        state.appVersion = appVersion
        state.updatedAtMs = nowMs
        try upsertSyncState(state)
    }

    private func updateUploadState(messageID: String, state: LocalMessageUploadState) throws {
        try dbPool.write { db in
            try db.execute(
                sql: """
                UPDATE messages
                SET upload_state = ?, updated_at_ms = ?
                WHERE message_id = ?;
                """,
                arguments: [state.rawValue, Self.nowMs(), messageID]
            )
        }
    }

    private static func nowMs() -> Int64 {
        Int64(Date().timeIntervalSince1970 * 1000)
    }

    private static func chunked(_ values: [String], size: Int) -> [[String]] {
        guard size > 0, !values.isEmpty else { return [] }
        var chunks: [[String]] = []
        chunks.reserveCapacity((values.count / size) + 1)
        var index = 0
        while index < values.count {
            let end = min(index + size, values.count)
            chunks.append(Array(values[index..<end]))
            index = end
        }
        return chunks
    }

    private static func sqlPlaceholders(count: Int) -> String {
        guard count > 0 else { return "?" }
        return Array(repeating: "?", count: count).joined(separator: ",")
    }

    private static func arguments(chatID: String, ids: [String]) -> StatementArguments {
        var arguments = StatementArguments()
        arguments += [chatID]
        for id in ids {
            arguments += [id]
        }
        return arguments
    }
}
