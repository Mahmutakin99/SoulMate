//
//  AuthViewController.swift
//  SoulMate
//
//  Created by MAHMUT AKIN on 02/02/2026.
//

import Foundation

final class MessageSyncService {
    struct SyncConsumeResult {
        let message: ChatMessage
        let inserted: Bool
    }

    var onError: ((Error) -> Void)?

    private struct Context {
        let chatID: String
        let currentUID: String
        let partnerUID: String
    }

    private let firebase: FirebaseManager
    private let encryption: EncryptionService
    private let localStore: LocalMessageStore
    private let jsonEncoder = JSONEncoder()
    private let jsonDecoder = JSONDecoder()
    private let queue = DispatchQueue(label: "com.soulmate.messagesync.queue", qos: .utility)
    private let queueKey = DispatchSpecificKey<Void>()

    private var context: Context?
    private var pendingAckMessageIDs = Set<String>()
    private var retryWorkItem: DispatchWorkItem?
    private var retryDelay: TimeInterval = 1
    private let maxRetryDelay: TimeInterval = 60
    private var scheduledRetryDelay: TimeInterval?
    private var isRetryCycleRunning = false
    private let errorThrottleWindow: TimeInterval = 10
    private let errorLock = NSLock()
    private var lastErrorEmissionByKey: [String: Date] = [:]

    init(
        firebase: FirebaseManager,
        encryption: EncryptionService,
        localStore: LocalMessageStore
    ) {
        self.firebase = firebase
        self.encryption = encryption
        self.localStore = localStore
        self.queue.setSpecific(key: queueKey, value: ())
    }

    func start(chatID: String, currentUID: String, partnerUID: String) {
        queue.async {
            self.context = Context(chatID: chatID, currentUID: currentUID, partnerUID: partnerUID)
            self.pendingAckMessageIDs.removeAll(keepingCapacity: true)
            self.retryDelay = 1
            self.scheduledRetryDelay = nil
            self.isRetryCycleRunning = false
            self.scheduleRetry(after: 0.3)
        }
    }

    func stop() {
        queue.async {
            self.context = nil
            self.pendingAckMessageIDs.removeAll(keepingCapacity: true)
            self.retryWorkItem?.cancel()
            self.retryWorkItem = nil
            self.retryDelay = 1
            self.scheduledRetryDelay = nil
            self.isRetryCycleRunning = false
        }
    }

    func send(payload: ChatPayload, completion: @escaping (Result<ChatMessage, Error>) -> Void) {
        guard let context = currentContext() else {
            completion(.failure(FirebaseManagerError.generic(L10n.t("chat.local.error.context_missing"))))
            return
        }

        let message = ChatMessage(
            id: UUID().uuidString,
            senderID: context.currentUID,
            recipientID: context.partnerUID,
            sentAt: Date(timeIntervalSince1970: payload.sentAt),
            type: payload.type,
            value: payload.value,
            isSecret: payload.isSecret
        )

        do {
            let inserted = try localStore.insertIfNeeded(
                chatID: context.chatID,
                message: message,
                direction: .outgoing,
                uploadState: .pendingUpload
            )

            guard inserted else {
                completion(.success(message))
                return
            }

            completion(.success(message))
            uploadOutgoingMessage(context: context, message: message, payload: payload)
        } catch {
            completion(.failure(error))
        }
    }

    func loadInitialFromLocal() throws -> [ChatMessage] {
        guard let context = currentContext() else {
            throw FirebaseManagerError.generic(L10n.t("chat.local.error.context_missing"))
        }
        return try localStore.fetchRecent(
            chatID: context.chatID,
            limit: AppConfiguration.MessageQueue.localPageSize
        )
    }

    func loadOlderFromLocal(beforeSentAt: TimeInterval) throws -> [ChatMessage] {
        guard let context = currentContext() else {
            throw FirebaseManagerError.generic(L10n.t("chat.local.error.context_missing"))
        }

        return try localStore.fetchOlder(
            chatID: context.chatID,
            beforeSentAt: beforeSentAt,
            limit: AppConfiguration.MessageQueue.localPageSize
        )
    }

    func syncCloudBackfillIfNeeded(completion: @escaping (Result<[EncryptedMessageEnvelope], Error>) -> Void) {
        guard let context = currentContext() else {
            completion(.failure(FirebaseManagerError.generic(L10n.t("chat.local.error.context_missing"))))
            return
        }

        firebase.syncRecentCloudMessages(
            chatID: context.chatID,
            limit: AppConfiguration.MessageQueue.initialCloudSyncWindow,
            completion: completion
        )
    }

    func consumeCloudEnvelope(_ envelope: EncryptedMessageEnvelope) throws -> SyncConsumeResult {
        guard let context = currentContext() else {
            throw FirebaseManagerError.generic(L10n.t("chat.local.error.context_missing"))
        }

        let decrypted = try encryption.decrypt(envelope.payload, from: context.partnerUID)
        let payload = try jsonDecoder.decode(ChatPayload.self, from: decrypted)

        let message = ChatMessage(
            id: envelope.id,
            senderID: envelope.senderID,
            recipientID: envelope.recipientID,
            sentAt: Date(timeIntervalSince1970: payload.sentAt),
            type: payload.type,
            value: payload.value,
            isSecret: payload.isSecret
        )

        let direction: LocalMessageDirection = envelope.senderID == context.currentUID ? .outgoing : .incoming
        let inserted = try localStore.insertIfNeeded(
            chatID: context.chatID,
            message: message,
            direction: direction,
            uploadState: .uploaded
        )

        if envelope.recipientID == context.currentUID {
            acknowledgeMessage(chatID: context.chatID, messageID: envelope.id)
        }

        return SyncConsumeResult(message: message, inserted: inserted)
    }

    func consumeCloudEnvelopes(_ envelopes: [EncryptedMessageEnvelope]) throws -> [SyncConsumeResult] {
        guard let context = currentContext() else {
            throw FirebaseManagerError.generic(L10n.t("chat.local.error.context_missing"))
        }
        guard !envelopes.isEmpty else { return [] }

        struct DecodedEnvelope {
            let envelope: EncryptedMessageEnvelope
            let message: ChatMessage
            let direction: LocalMessageDirection
        }

        var decoded: [DecodedEnvelope] = []
        decoded.reserveCapacity(envelopes.count)

        for envelope in envelopes {
            let decrypted = try encryption.decrypt(envelope.payload, from: context.partnerUID)
            let payload = try jsonDecoder.decode(ChatPayload.self, from: decrypted)
            let message = ChatMessage(
                id: envelope.id,
                senderID: envelope.senderID,
                recipientID: envelope.recipientID,
                sentAt: Date(timeIntervalSince1970: payload.sentAt),
                type: payload.type,
                value: payload.value,
                isSecret: payload.isSecret
            )
            let direction: LocalMessageDirection = envelope.senderID == context.currentUID ? .outgoing : .incoming
            decoded.append(DecodedEnvelope(envelope: envelope, message: message, direction: direction))
        }

        let incomingMessages = decoded
            .filter { $0.direction == .incoming }
            .map(\.message)
        if !incomingMessages.isEmpty {
            _ = try localStore.insertBatchIfNeeded(
                chatID: context.chatID,
                messages: incomingMessages,
                direction: .incoming,
                uploadState: .uploaded
            )
        }

        let outgoingMessages = decoded
            .filter { $0.direction == .outgoing }
            .map(\.message)
        if !outgoingMessages.isEmpty {
            _ = try localStore.insertBatchIfNeeded(
                chatID: context.chatID,
                messages: outgoingMessages,
                direction: .outgoing,
                uploadState: .uploaded
            )
        }

        decoded.forEach { item in
            if item.envelope.recipientID == context.currentUID {
                acknowledgeMessage(chatID: context.chatID, messageID: item.envelope.id)
            }
        }

        return decoded.map { SyncConsumeResult(message: $0.message, inserted: true) }
    }

    private func uploadOutgoingMessage(context: Context, message: ChatMessage, payload: ChatPayload) {
        do {
            let plainData = try jsonEncoder.encode(payload)
            let encryptedPayload = try encryption.encrypt(plainData, for: context.partnerUID)
            let envelope = EncryptedMessageEnvelope(
                id: message.id,
                senderID: context.currentUID,
                recipientID: context.partnerUID,
                payload: encryptedPayload,
                sentAt: payload.sentAt
            )

            firebase.sendEncryptedMessage(chatID: context.chatID, envelope: envelope) { [weak self] result in
                guard let self else { return }
                switch result {
                case .success:
                    do {
                        try self.localStore.markUploaded(messageID: envelope.id)
                    } catch {
                        self.reportError(error)
                    }
                case .failure(let error):
                    do {
                        try self.localStore.markUploadFailed(messageID: envelope.id)
                    } catch let localStoreError {
                        self.reportError(localStoreError)
                    }
                    self.reportError(error)
                    self.scheduleRetryWithBackoff()
                }
            }
        } catch {
            do {
                try localStore.markUploadFailed(messageID: message.id)
            } catch let localStoreError {
                reportError(localStoreError)
            }
            reportError(error)
            scheduleRetryWithBackoff()
        }
    }

    private func acknowledgeMessage(chatID: String, messageID: String) {
        firebase.ackMessageStored(chatID: chatID, messageID: messageID) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success:
                self.queue.async {
                    self.pendingAckMessageIDs.remove(messageID)
                }
            case .failure(let error):
                self.queue.async {
                    let inserted = self.pendingAckMessageIDs.insert(messageID).inserted
                    if inserted || self.retryWorkItem == nil {
                        self.scheduleRetryWithBackoff()
                    }
                }
                self.reportError(error)
            }
        }
    }

    private func scheduleRetryWithBackoff() {
        queue.async {
            self.scheduleRetry(after: self.retryDelay)
            self.retryDelay = min(self.retryDelay * 2, self.maxRetryDelay)
        }
    }

    private func scheduleRetry(after delay: TimeInterval) {
        if let currentDelay = scheduledRetryDelay, currentDelay <= delay, retryWorkItem != nil {
            return
        }

        retryWorkItem?.cancel()
        scheduledRetryDelay = delay

        let workItem = DispatchWorkItem { [weak self] in
            self?.performRetryCycle()
        }
        retryWorkItem = workItem
        queue.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func performRetryCycle() {
        guard let context = context else { return }
        if isRetryCycleRunning { return }
        isRetryCycleRunning = true
        scheduledRetryDelay = nil
        var hasPendingWork = false

        do {
            let pending = try localStore.pendingUploads(chatID: context.chatID, limit: 40)
            hasPendingWork = hasPendingWork || !pending.isEmpty
            for record in pending {
                let payload = ChatPayload(
                    type: record.payloadType,
                    value: record.payloadValue,
                    isSecret: record.isSecret,
                    sentAt: record.sentAt
                )

                let message = ChatMessage(
                    id: record.messageID,
                    senderID: record.senderID,
                    recipientID: record.recipientID,
                    sentAt: Date(timeIntervalSince1970: record.sentAt),
                    type: record.payloadType,
                    value: record.payloadValue,
                    isSecret: record.isSecret
                )

                uploadOutgoingMessage(context: context, message: message, payload: payload)
            }
        } catch {
            reportError(error)
        }

        if !pendingAckMessageIDs.isEmpty {
            hasPendingWork = true
            let ackIDs = Array(pendingAckMessageIDs)
            ackIDs.forEach { acknowledgeMessage(chatID: context.chatID, messageID: $0) }
        }

        guard hasPendingWork else {
            retryWorkItem = nil
            retryDelay = 1
            isRetryCycleRunning = false
            return
        }

        isRetryCycleRunning = false
        scheduleRetry(after: 20)
        retryDelay = 1
    }

    private func reportError(_ error: Error) {
        let key: String = {
            let nsError = error as NSError
            return "\(nsError.domain)#\(nsError.code)"
        }()

        var shouldEmit = false
        let now = Date()
        errorLock.lock()
        if let last = lastErrorEmissionByKey[key], now.timeIntervalSince(last) < errorThrottleWindow {
            shouldEmit = false
        } else {
            lastErrorEmissionByKey[key] = now
            shouldEmit = true
        }
        errorLock.unlock()

        guard shouldEmit else { return }
        onError?(error)
    }

    private func currentContext() -> Context? {
        if DispatchQueue.getSpecific(key: queueKey) != nil {
            return context
        }
        return queue.sync { context }
    }
}
