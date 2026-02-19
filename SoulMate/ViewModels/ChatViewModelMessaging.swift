//
//  ChatViewModelMessaging.swift
//  SoulMate
//
//  Created by MAHMUT AKIN on 02/02/2026.
//

import Foundation
import CryptoKit

extension ChatViewModel {
    private static let messageTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private static let defaultQuickReactionEmojis = ["❤️", "😂", "🥰", "🔥", "😮"]
    private static let defaultFrequentReactionSeed = [
        "❤️", "😂", "🥰", "🔥", "😮", "😢", "👍", "🙏", "👏", "🎉", "🤍", "😘"
    ]

    func sendText(_ text: String, isSecret: Bool) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        sendPayload(type: .text, value: trimmed, isSecret: isSecret)
    }

    func sendEmoji(_ emoji: String) {
        sendPayload(type: .emoji, value: emoji, isSecret: false)
    }

    func messageMeta(for messageID: String) -> ChatMessageMeta? {
        messageMetaByID[messageID]
    }

    func isIncomingMessageForCurrentUser(_ message: ChatMessage) -> Bool {
        guard let currentUserID else { return false }
        return message.recipientID == currentUserID && message.senderID != currentUserID
    }

    func currentUserReactionEmoji(for messageID: String) -> String? {
        guard let currentUserID else { return nil }
        return messageReactionsByMessageID[messageID]?.first(where: { $0.reactorUID == currentUserID })?.emoji
    }

    func quickReactionEmojis(maxCount: Int) -> [String] {
        guard let currentUserID else {
            return Array(Self.defaultQuickReactionEmojis.prefix(max(0, maxCount)))
        }
        return reactionUsageStore.topEmojis(
            uid: currentUserID,
            maxCount: maxCount,
            fallback: Self.defaultQuickReactionEmojis
        )
    }

    func frequentReactionEmojis(maxCount: Int) -> [String] {
        guard let currentUserID else {
            return Array(Self.defaultFrequentReactionSeed.prefix(max(0, maxCount)))
        }
        return reactionUsageStore.topEmojis(
            uid: currentUserID,
            maxCount: maxCount,
            fallback: Self.defaultFrequentReactionSeed
        )
    }

    func toggleReaction(messageID: String, emoji: String) {
        let trimmedEmoji = emoji.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedEmoji.isEmpty else { return }

        if currentUserReactionEmoji(for: messageID) == trimmedEmoji {
            clearReaction(messageID: messageID)
        } else {
            setReaction(messageID: messageID, emoji: trimmedEmoji)
        }
    }

    func setReaction(messageID: String, emoji: String) {
        guard state == .ready,
              let chatID = activeChatID,
              let currentUserID,
              let partnerUserID else {
            return
        }

        let trimmedEmoji = emoji.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedEmoji.isEmpty else { return }

        do {
            let payload = [
                "emoji": trimmedEmoji,
                "updatedAt": Date().timeIntervalSince1970
            ] as [String: Any]
            let data = try JSONSerialization.data(withJSONObject: payload)
            let ciphertext = try encryption.encrypt(data, for: partnerUserID)

            firebase.setMessageReaction(
                chatID: chatID,
                messageID: messageID,
                ciphertext: ciphertext,
                keyVersion: 1
            ) { [weak self] result in
                if case .failure(let error) = result {
                    self?.emitError(error)
                    return
                }

                let updatedAt = Date()
                do {
                    try self?.localMessageStore.upsertReaction(
                        chatID: chatID,
                        messageID: messageID,
                        reactorUID: currentUserID,
                        emoji: trimmedEmoji,
                        updatedAt: updatedAt.timeIntervalSince1970
                    )
                } catch {
                    self?.emitError(error)
                }

                let reaction = MessageReaction(
                    messageID: messageID,
                    reactorUID: currentUserID,
                    emoji: trimmedEmoji,
                    updatedAt: updatedAt
                )
                self?.notifyOnMain {
                    var currentReactions = self?.messageReactionsByMessageID[messageID] ?? []
                    currentReactions.removeAll(where: { $0.reactorUID == currentUserID })
                    currentReactions.append(reaction)
                    self?.messageReactionsByMessageID[messageID] = currentReactions
                    self?.rebuildMessageMetadata(for: [messageID], notify: true)
                }
                self?.reactionUsageStore.recordUsage(
                    emoji: trimmedEmoji,
                    uid: currentUserID,
                    at: updatedAt
                )
            }
        } catch {
            emitError(error)
        }
    }

    func clearReaction(messageID: String) {
        guard state == .ready,
              let chatID = activeChatID,
              let currentUserID else {
            return
        }

        firebase.clearMessageReaction(chatID: chatID, messageID: messageID) { [weak self] result in
            if case .failure(let error) = result {
                self?.emitError(error)
                return
            }

            do {
                try self?.localMessageStore.removeReaction(
                    chatID: chatID,
                    messageID: messageID,
                    reactorUID: currentUserID
                )
            } catch {
                self?.emitError(error)
            }

            self?.notifyOnMain {
                var currentReactions = self?.messageReactionsByMessageID[messageID] ?? []
                currentReactions.removeAll(where: { $0.reactorUID == currentUserID })
                self?.messageReactionsByMessageID[messageID] = currentReactions
                self?.rebuildMessageMetadata(for: [messageID], notify: true)
            }
        }
    }

    func markVisibleIncomingMessagesAsRead(_ ids: [String]) {
        guard state == .ready,
              let chatID = activeChatID,
              let currentUserID else {
            return
        }

        let targetIDs = Set(ids)
            .filter { id in
                guard let message = messageByID[id] else { return false }
                guard message.recipientID == currentUserID else { return false }
                return messageReceiptsByID[id]?.readAt == nil
            }
        guard !targetIDs.isEmpty else { return }

        pendingReadReceiptMessageIDs.formUnion(targetIDs)
        readReceiptWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard self.activeChatID == chatID else { return }
            let pendingIDs = Array(self.pendingReadReceiptMessageIDs)
            self.pendingReadReceiptMessageIDs.removeAll(keepingCapacity: true)

            pendingIDs.forEach { messageID in
                self.firebase.markMessageRead(chatID: chatID, messageID: messageID) { [weak self] result in
                    guard let self else { return }
                    switch result {
                    case .success:
                        self.notifyOnMain {
                            let now = Date()
                            if let existing = self.messageReceiptsByID[messageID] {
                                let updated = MessageReceipt(
                                    messageID: existing.messageID,
                                    senderID: existing.senderID,
                                    recipientID: existing.recipientID,
                                    deliveredAt: existing.deliveredAt,
                                    readAt: now,
                                    updatedAt: now
                                )
                                self.messageReceiptsByID[messageID] = updated
                                do {
                                    try self.localMessageStore.markRead(
                                        messageID: messageID,
                                        readAt: now.timeIntervalSince1970,
                                        updatedAt: now.timeIntervalSince1970
                                    )
                                } catch {
                                    self.emitError(error)
                                }
                                self.rebuildMessageMetadata(for: [messageID], notify: true)
                            }
                        }
                    case .failure(let error):
                        self.emitError(error)
                    }
                }
            }
        }
        readReceiptWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: workItem)
    }

    func observeMessageMetadataIfNeeded(chatID: String) {
        messageReceiptsObserver?.cancel()
        messageReactionsObserver?.cancel()

        messageReceiptsObserver = firebase.observeMessageReceipts(
            chatID: chatID,
            onEvent: { [weak self] event in
                guard let self else { return }
                self.messageMetadataProcessingQueue.async { [weak self] in
                    guard let self else { return }
                    switch event {
                    case .upsert(let receipt):
                        do {
                            try self.localMessageStore.upsertReceipt(
                                chatID: chatID,
                                messageID: receipt.messageID,
                                senderID: receipt.senderID,
                                recipientID: receipt.recipientID,
                                deliveredAt: receipt.deliveredAt.timeIntervalSince1970,
                                readAt: receipt.readAt?.timeIntervalSince1970,
                                updatedAt: receipt.updatedAt.timeIntervalSince1970
                            )
                        } catch {
                            self.emitError(error)
                        }

                        self.notifyOnMain {
                            var changedIDs = Set<String>()
                            if self.messageReceiptsByID[receipt.messageID] != receipt {
                                changedIDs.insert(receipt.messageID)
                            }
                            self.messageReceiptsByID[receipt.messageID] = receipt
                            self.rebuildMessageMetadata(for: changedIDs, notify: true)
                        }

                    case .remove(let messageID):
                        do {
                            try self.localMessageStore.removeReceipt(chatID: chatID, messageID: messageID)
                        } catch {
                            self.emitError(error)
                        }

                        self.notifyOnMain {
                            var changedIDs = Set<String>()
                            if self.messageReceiptsByID.removeValue(forKey: messageID) != nil {
                                changedIDs.insert(messageID)
                            }
                            self.rebuildMessageMetadata(for: changedIDs, notify: true)
                        }
                    }
                }
            },
            onCancelled: { [weak self] error in
                self?.handleObserverCancellation(error)
            }
        )

        messageReactionsObserver = firebase.observeMessageReactions(
            chatID: chatID,
            onEvent: { [weak self] event in
                guard let self else { return }
                self.messageMetadataProcessingQueue.async { [weak self] in
                    guard let self else { return }
                    enum ProcessedReactionEvent {
                        case replace(messageID: String, reactions: [MessageReaction])
                        case removeMessage(messageID: String)
                    }

                    let processed: ProcessedReactionEvent
                    switch event {
                    case .replace(let messageID, let reactors):
                        guard let partnerUserID = self.partnerUserID else { return }
                        var nextReactions: [MessageReaction] = []

                        for reactor in reactors {
                            do {
                                let decrypted = try self.encryption.decrypt(reactor.envelope.ciphertext, from: partnerUserID)
                                guard let payload = try JSONSerialization.jsonObject(with: decrypted) as? [String: Any],
                                      let emoji = payload["emoji"] as? String else {
                                    continue
                                }
                                let updatedAtRaw = payload["updatedAt"] as? TimeInterval ?? reactor.envelope.updatedAt
                                nextReactions.append(
                                    MessageReaction(
                                        messageID: messageID,
                                        reactorUID: reactor.reactorUID,
                                        emoji: emoji,
                                        updatedAt: Date(timeIntervalSince1970: updatedAtRaw)
                                    )
                                )
                            } catch {
                                self.emitError(error)
                            }
                        }

                        nextReactions.sort {
                            if $0.updatedAt == $1.updatedAt {
                                return $0.reactorUID < $1.reactorUID
                            }
                            return $0.updatedAt < $1.updatedAt
                        }

                        do {
                            try self.localMessageStore.removeReactions(chatID: chatID, messageID: messageID)
                            for reaction in nextReactions {
                                try self.localMessageStore.upsertReaction(
                                    chatID: chatID,
                                    messageID: messageID,
                                    reactorUID: reaction.reactorUID,
                                    emoji: reaction.emoji,
                                    updatedAt: reaction.updatedAt.timeIntervalSince1970
                                )
                            }
                        } catch {
                            self.emitError(error)
                        }

                        processed = .replace(messageID: messageID, reactions: nextReactions)

                    case .removeMessage(let messageID):
                        do {
                            try self.localMessageStore.removeReactions(chatID: chatID, messageID: messageID)
                        } catch {
                            self.emitError(error)
                        }
                        processed = .removeMessage(messageID: messageID)
                    }

                    self.notifyOnMain {
                        var changedIDs = Set<String>()
                        switch processed {
                        case .replace(let messageID, let nextReactions):
                            let previous = (self.messageReactionsByMessageID[messageID] ?? []).sorted {
                                if $0.updatedAt == $1.updatedAt {
                                    return $0.reactorUID < $1.reactorUID
                                }
                                return $0.updatedAt < $1.updatedAt
                            }
                            if previous != nextReactions {
                                changedIDs.insert(messageID)
                            }
                            self.messageReactionsByMessageID[messageID] = nextReactions

                        case .removeMessage(let messageID):
                            if self.messageReactionsByMessageID.removeValue(forKey: messageID) != nil {
                                changedIDs.insert(messageID)
                            }
                        }

                        self.rebuildMessageMetadata(for: changedIDs, notify: true)
                    }
                }
            },
            onCancelled: { [weak self] error in
                self?.handleObserverCancellation(error)
            }
        )
    }

    func hydrateMessageMetadataFromLocal(for messageIDs: [String]) {
        guard let chatID = activeChatID else { return }
        guard !messageIDs.isEmpty else { return }

        do {
            let idSet = Set(messageIDs)
            idSet.forEach { id in
                messageReceiptsByID[id] = nil
                messageReactionsByMessageID[id] = []
                outgoingUploadStateByMessageID[id] = nil
            }

            let receipts = try localMessageStore.fetchReceipts(chatID: chatID, messageIDs: messageIDs)
            for receipt in receipts {
                messageReceiptsByID[receipt.messageID] = MessageReceipt(
                    messageID: receipt.messageID,
                    senderID: receipt.senderID,
                    recipientID: receipt.recipientID,
                    deliveredAt: Date(timeIntervalSince1970: receipt.deliveredAt),
                    readAt: receipt.readAt.map { Date(timeIntervalSince1970: $0) },
                    updatedAt: Date(timeIntervalSince1970: receipt.updatedAt)
                )
            }

            let reactions = try localMessageStore.fetchReactions(chatID: chatID, messageIDs: messageIDs)
            for reaction in reactions {
                let row = MessageReaction(
                    messageID: reaction.messageID,
                    reactorUID: reaction.reactorUID,
                    emoji: reaction.emoji,
                    updatedAt: Date(timeIntervalSince1970: reaction.updatedAt)
                )
                var list = messageReactionsByMessageID[reaction.messageID] ?? []
                list.removeAll(where: { $0.reactorUID == reaction.reactorUID })
                list.append(row)
                messageReactionsByMessageID[reaction.messageID] = list
            }

            let uploadStates = try localMessageStore.fetchUploadStates(chatID: chatID, messageIDs: messageIDs)
            uploadStates.forEach { key, value in
                outgoingUploadStateByMessageID[key] = value
            }

            for id in idSet where (messageReactionsByMessageID[id] ?? []).isEmpty {
                messageReactionsByMessageID[id] = []
            }
        } catch {
            emitError(error)
        }
    }

    func rebuildMessageMetadata(for messageIDs: Set<String>, notify: Bool) {
        guard !messageIDs.isEmpty else { return }

        var changedIDs = Set<String>()
        for messageID in messageIDs {
            guard let message = messageByID[messageID] else {
                if messageMetaByID.removeValue(forKey: messageID) != nil {
                    changedIDs.insert(messageID)
                }
                continue
            }

            let nextMeta = composeMessageMeta(for: message)
            if messageMetaByID[messageID] != nextMeta {
                messageMetaByID[messageID] = nextMeta
                changedIDs.insert(messageID)
            }
        }

        guard notify, !changedIDs.isEmpty else { return }
        notifyOnMain {
            self.onMessageMetaUpdated?(changedIDs)
        }
    }

    func composeMessageMeta(for message: ChatMessage) -> ChatMessageMeta {
        let timeText = Self.messageTimeFormatter.string(from: message.sentAt)
        let isOutgoing = message.senderID == currentUserID

        let deliveryState: MessageDeliveryState?
        if isOutgoing {
            if let receipt = messageReceiptsByID[message.id] {
                if receipt.readAt != nil {
                    deliveryState = .read
                } else {
                    deliveryState = .delivered
                }
            } else if outgoingUploadStateByMessageID[message.id] == .uploaded {
                deliveryState = .sent
            } else {
                deliveryState = nil
            }
        } else {
            deliveryState = nil
        }

        let reactions = (messageReactionsByMessageID[message.id] ?? []).sorted {
            if $0.updatedAt == $1.updatedAt {
                return $0.reactorUID < $1.reactorUID
            }
            return $0.updatedAt < $1.updatedAt
        }

        return ChatMessageMeta(
            timeText: timeText,
            deliveryState: deliveryState,
            reactions: reactions
        )
    }

    func updateMood(_ mood: MoodStatus) {
        guard isSecureChannelReady else {
            emitError(FirebaseManagerError.generic(L10n.t("chatvm.error.secure_channel_inactive")))
            return
        }

        guard let currentUserID,
              let partnerUserID else {
            emitError(FirebaseManagerError.generic(L10n.t("chatvm.error.pair_before_mood")))
            return
        }

        do {
            let encrypted = try encryption.encrypt(Data(mood.rawValue.utf8), for: partnerUserID)
            firebase.updateMoodCiphertext(uid: currentUserID, ciphertext: encrypted) { [weak self] result in
                if case .failure(let error) = result {
                    self?.emitError(error)
                }
            }
        } catch {
            emitError(error)
        }
    }

    func sendHeartbeat() {
        guard isSecureChannelReady else {
            emitError(FirebaseManagerError.generic(L10n.t("chatvm.error.secure_channel_inactive")))
            return
        }

        guard let currentUserID,
              let partnerUserID else {
            emitError(FirebaseManagerError.generic(L10n.t("chatvm.error.pair_before_heartbeat")))
            return
        }

        let chatID = FirebaseManager.chatID(for: currentUserID, and: partnerUserID)
        firebase.sendHeartbeat(chatID: chatID, senderID: currentUserID) { [weak self] result in
            switch result {
            case .success:
                break
            case .failure(let error):
                self?.emitError(error)
            }
        }
    }

    func handleMemoryPressure() {
        let didTrim = trimMessagesIfNeeded(keepingLast: AppConfiguration.ChatPerformance.maxInMemoryMessagesOnPressure)
        guard didTrim else { return }
        notifyOnMain {
            self.onMessagesUpdated?()
        }
    }

    func numberOfMessages() -> Int {
        messages.count
    }

    func message(at index: Int) -> ChatMessage {
        messages[index]
    }

    func message(for id: String) -> ChatMessage? {
        messageByID[id]
    }

    func isFromCurrentUser(_ message: ChatMessage) -> Bool {
        message.senderID == currentUserID
    }

    func loadOlderMessagesIfNeeded(visibleTopRow: Int) {
        guard state == .ready else { return }
        guard visibleTopRow <= AppConfiguration.ChatPerformance.historyPreloadTopRowThreshold else { return }
        loadOlderMessages()
    }

    func bootstrapRecentMessagesAndListen(chatID: String, currentUserID: String, partnerUserID: String) {
        let localMessageCount = (try? localMessageStore.count(chatID: chatID)) ?? messages.count
        let syncState = try? localMessageStore.fetchSyncState(chatID: chatID)
        let decision = MessageSyncPolicy.shouldBootstrap(
            syncState: syncState,
            localMessageCount: localMessageCount,
            currentSchemaVersion: Migrations.schemaVersion,
            currentAppVersion: currentAppVersionString(),
            featureEnabled: AppConfiguration.FeatureFlags.enableConditionalBootstrap
        )

        let startingCursor = latestSyncedCursor ?? currentLatestCursorFromMessages()
        latestSyncedCursor = startingCursor

        messageObserver = firebase.observeEncryptedMessages(
            chatID: chatID,
            startingAt: startingCursor.map { TimeInterval($0.timestampMs) / 1000 },
            startingAfterMessageID: startingCursor?.messageID,
            onMessage: { [weak self] envelope in
                self?.handleIncomingEnvelope(envelope)
            },
            onCancelled: { [weak self] error in
                self?.handleObserverCancellation(error)
            }
        )

        guard case .bootstrap(let reason) = decision else {
            return
        }

        do {
            try localMessageStore.markBootstrapStarted(chatID: chatID, appVersion: currentAppVersionString())
        } catch {
            emitError(error)
        }

        #if DEBUG
        print("Cloud bootstrap tetiklendi: \(reason)")
        #endif

        messageSyncService.syncCloudBackfillIfNeeded { [weak self] result in
            guard let self else { return }
            guard self.activeChatID == chatID else { return }

            switch result {
            case .success(let envelopes):
                self.consumeInitialMessageBatch(envelopes, currentUserID: currentUserID, partnerUserID: partnerUserID)
                let latestCursor = self.currentLatestCursorFromMessages()
                self.latestSyncedCursor = latestCursor
                do {
                    try self.localMessageStore.markBootstrapCompleted(
                        chatID: chatID,
                        cursor: latestCursor,
                        appVersion: self.currentAppVersionString()
                    )
                    self.lastPersistedBootstrapCursor = latestCursor
                    self.pendingBootstrapPersistCursor = latestCursor
                } catch {
                    self.emitError(error)
                }

            case .failure(let error):
                self.emitError(error)
                do {
                    try self.localMessageStore.markGapDetected(
                        chatID: chatID,
                        gapDetected: true,
                        appVersion: self.currentAppVersionString()
                    )
                } catch {
                    self.emitError(error)
                }
            }
        }
    }

    func loadInitialMessagesFromLocal() {
        guard AppConfiguration.FeatureFlags.localFirstEphemeralMessaging else { return }
        guard let currentUserID, let partnerUserID, let chatID = activeChatID else { return }

        if AppConfiguration.FeatureFlags.enableHybridSnapshotLaunch,
           let snapshotModels = ChatLaunchSnapshotCache.shared.load(ownerUID: currentUserID, chatID: chatID),
           !snapshotModels.isEmpty {
            let snapshotMessages = snapshotModels.compactMap {
                self.chatMessageFromSnapshot(
                    $0,
                    currentUserID: currentUserID,
                    partnerUserID: partnerUserID
                )
            }
            if !snapshotMessages.isEmpty {
                resetMessageState(notify: false)
                snapshotMessages.forEach { _ = appendMessageIfNeeded($0, notify: false) }
                rebuildMessageMetadata(for: Set(snapshotMessages.map(\.id)), notify: true)
                notifyOnMain {
                    self.onMessagesUpdated?()
                    self.onMessageListDelta?(
                        MessageListDelta(kind: .initial, changedMessageIDs: Set(snapshotMessages.map(\.id)))
                    )
                    ChatPerfLogger.mark("t1_snapshotApplied")
                    ChatPerfLogger.logDelta(from: "t0_viewDidLoad", to: "t1_snapshotApplied", context: "launch_snapshot")
                    ChatPerfLogger.mark("launch_t3_chat_first_local_render")
                    ChatPerfLogger.logDelta(
                        from: "launch_t0_app_start",
                        to: "launch_t3_chat_first_local_render",
                        context: "snapshot_first_render"
                    )
                }
            }
        }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            do {
                let localMessages = try self.messageSyncService.loadInitialFromLocal()
                self.notifyOnMain {
                    guard self.activeChatID == chatID else { return }
                    self.resetMessageState(notify: false)
                    localMessages.forEach { _ = self.appendMessageIfNeeded($0, notify: false) }
                    self.hydrateMessageMetadataFromLocal(for: localMessages.map(\.id))
                    self.rebuildMessageMetadata(for: Set(localMessages.map(\.id)), notify: true)
                    self.hasReachedHistoryStart = localMessages.count < Int(AppConfiguration.MessageQueue.localPageSize)
                    self.latestSyncedCursor = self.currentLatestCursorFromMessages()
                    self.scheduleLaunchSnapshotSave()
                    self.onMessagesUpdated?()
                    self.onMessageListDelta?(
                        MessageListDelta(kind: .initial, changedMessageIDs: Set(localMessages.map(\.id)))
                    )
                    ChatPerfLogger.mark("t2_dbRecentLoaded")
                    ChatPerfLogger.logDelta(from: "t0_viewDidLoad", to: "t2_dbRecentLoaded", context: "local_db")
                    ChatPerfLogger.mark("launch_t3_chat_first_local_render")
                    ChatPerfLogger.logDelta(
                        from: "launch_t0_app_start",
                        to: "launch_t3_chat_first_local_render",
                        context: "local_db_first_render"
                    )
                }
            } catch {
                self.emitError(error)
            }
        }
    }

    func consumeInitialMessageBatch(
        _ envelopes: [EncryptedMessageEnvelope],
        currentUserID: String,
        partnerUserID: String
    ) {
        var inserted = 0
        var insertedMessageIDs = Set<String>()
        var latestIncomingValue: String?

        do {
                let batchResults = try messageSyncService.consumeCloudEnvelopes(envelopes)
                for (index, result) in batchResults.enumerated() {
                    if result.inserted, appendMessageIfNeeded(result.message, notify: false) {
                        inserted += 1
                        insertedMessageIDs.insert(result.message.id)
                        if envelopes[index].senderID != currentUserID {
                            latestIncomingValue = result.message.value
                        }
                    }
                }
        } catch {
            for envelope in envelopes {
                do {
                    let syncResult = try messageSyncService.consumeCloudEnvelope(envelope)
                    if syncResult.inserted, appendMessageIfNeeded(syncResult.message, notify: false) {
                        inserted += 1
                        insertedMessageIDs.insert(syncResult.message.id)
                        if envelope.senderID != currentUserID {
                            latestIncomingValue = syncResult.message.value
                        }
                    }
                } catch {
                    guard !isRecoverablePartnerPayloadError(error) else {
                        attemptSharedKeyRecoveryIfPossible(partnerUID: partnerUserID)
                        if let recovered = try? messageSyncService.consumeCloudEnvelope(envelope),
                           recovered.inserted,
                           appendMessageIfNeeded(recovered.message, notify: false) {
                            inserted += 1
                            insertedMessageIDs.insert(recovered.message.id)
                            if envelope.senderID != currentUserID {
                                latestIncomingValue = recovered.message.value
                            }
                        }
                        continue
                    }
                    emitError(error)
                    continue
                }
            }
        }

        let hasLocalOlderCandidates = messages.count >= Int(AppConfiguration.MessageQueue.localPageSize)
        hasReachedHistoryStart = envelopes.count < Int(AppConfiguration.MessageQueue.initialCloudSyncWindow) && !hasLocalOlderCandidates

        if let latestIncomingValue {
            persistWidgetLatestMessage(latestIncomingValue)
            LiveActivityManager.shared.update(text: latestIncomingValue, mood: latestPartnerMoodTitle)
        }

        guard inserted > 0 else { return }
        hydrateMessageMetadataFromLocal(for: Array(insertedMessageIDs))
        rebuildMessageMetadata(for: insertedMessageIDs, notify: true)
        notifyOnMain {
            self.onMessagesUpdated?()
            self.onMessageListDelta?(MessageListDelta(kind: .initial, changedMessageIDs: insertedMessageIDs))
        }
    }

    func handleIncomingEnvelope(_ envelope: EncryptedMessageEnvelope) {
        guard let currentUserID,
              let partnerUserID else { return }

        do {
            let syncResult = try messageSyncService.consumeCloudEnvelope(envelope)
            let inserted = syncResult.inserted && appendMessageIfNeeded(syncResult.message)
            hydrateMessageMetadataFromLocal(for: [syncResult.message.id])
            rebuildMessageMetadata(for: [syncResult.message.id], notify: true)

            if inserted && envelope.senderID != currentUserID {
                persistWidgetLatestMessage(syncResult.message.value)
                LiveActivityManager.shared.update(text: syncResult.message.value, mood: latestPartnerMoodTitle)
                ChatPerfLogger.mark("t3_firstDeltaApplied")
                ChatPerfLogger.logDelta(from: "t0_viewDidLoad", to: "t3_firstDeltaApplied", context: "rtdb_delta")
            }
        } catch {
            guard !isRecoverablePartnerPayloadError(error) else {
                attemptSharedKeyRecoveryIfPossible(partnerUID: partnerUserID)

                if let recoveredSync = try? messageSyncService.consumeCloudEnvelope(envelope) {
                    let inserted = recoveredSync.inserted && appendMessageIfNeeded(recoveredSync.message)
                    hydrateMessageMetadataFromLocal(for: [recoveredSync.message.id])
                    rebuildMessageMetadata(for: [recoveredSync.message.id], notify: true)
                    if inserted && envelope.senderID != currentUserID {
                        persistWidgetLatestMessage(recoveredSync.message.value)
                        LiveActivityManager.shared.update(text: recoveredSync.message.value, mood: latestPartnerMoodTitle)
                    }
                    return
                }

                if !hasLoggedUnreadablePayloadWarning {
                    hasLoggedUnreadablePayloadWarning = true
                    #if DEBUG
                    print("Mesaj çözümlenemedi, payload atlandı: \(error.localizedDescription)")
                    #endif
                }
                return
            }
            emitError(error)
        }
    }

    func loadOlderMessages() {
        guard let currentUserID,
              let partnerUserID,
              let oldestLoadedSentAt,
              let oldestLoadedMessageID,
              !isLoadingHistory,
              !hasReachedHistoryStart,
              state == .ready else {
            return
        }

        let chatID = FirebaseManager.chatID(for: currentUserID, and: partnerUserID)
        guard chatID == activeChatID else { return }

        isLoadingHistory = true
        let pageSize = AppConfiguration.MessageQueue.localPageSize

        var localInserted = 0
        var localInsertedIDs = Set<String>()
        do {
            let localMessages = try messageSyncService.loadOlderFromLocal(beforeSentAt: oldestLoadedSentAt)
            for message in localMessages {
                if appendMessageIfNeeded(message, notify: false) {
                    localInserted += 1
                    localInsertedIDs.insert(message.id)
                }
            }
        } catch {
            emitError(error)
        }

        if localInserted > 0 {
            isLoadingHistory = false
            hydrateMessageMetadataFromLocal(for: Array(localInsertedIDs))
            rebuildMessageMetadata(for: localInsertedIDs, notify: true)
            notifyOnMain {
                self.onMessagesPrepended?(localInserted)
                self.onMessageListDelta?(MessageListDelta(kind: .prepend, changedMessageIDs: localInsertedIDs))
            }
            return
        }

        let cursor = ChatSyncCursor(
            timestampMs: Int64(oldestLoadedSentAt * 1000),
            messageID: oldestLoadedMessageID
        )

        firebase.fetchOlderEncryptedMessages(chatID: chatID, before: cursor, limit: pageSize) { [weak self] result in
            guard let self else { return }
            guard self.activeChatID == chatID else { return }
            self.isLoadingHistory = false

            switch result {
            case .failure(let error):
                self.emitError(error)

            case .success(let envelopes):
                var inserted = 0
                var insertedMessageIDs = Set<String>()
                do {
                    let batchResults = try self.messageSyncService.consumeCloudEnvelopes(envelopes)
                    for result in batchResults where result.inserted {
                        if self.appendMessageIfNeeded(result.message, notify: false) {
                            inserted += 1
                            insertedMessageIDs.insert(result.message.id)
                        }
                    }
                } catch {
                    for envelope in envelopes {
                        do {
                            let syncResult = try self.messageSyncService.consumeCloudEnvelope(envelope)
                            if syncResult.inserted, self.appendMessageIfNeeded(syncResult.message, notify: false) {
                                inserted += 1
                                insertedMessageIDs.insert(syncResult.message.id)
                            }
                        } catch {
                            guard !self.isRecoverablePartnerPayloadError(error) else {
                                self.attemptSharedKeyRecoveryIfPossible(partnerUID: partnerUserID)
                                continue
                            }
                            self.emitError(error)
                            continue
                        }
                    }
                }

                self.hasReachedHistoryStart = envelopes.count < Int(pageSize + 1) || inserted == 0

                guard inserted > 0 else { return }
                self.hydrateMessageMetadataFromLocal(for: Array(insertedMessageIDs))
                self.rebuildMessageMetadata(for: insertedMessageIDs, notify: true)
                self.notifyOnMain {
                    self.onMessagesPrepended?(inserted)
                    self.onMessageListDelta?(MessageListDelta(kind: .prepend, changedMessageIDs: insertedMessageIDs))
                }
            }
        }
    }

    func sendPayload(type: ChatPayloadType, value: String, isSecret: Bool) {
        guard isSecureChannelReady else {
            emitError(FirebaseManagerError.generic(L10n.t("chatvm.error.secure_channel_inactive")))
            return
        }

        guard currentUserID != nil,
              partnerUserID != nil else {
            emitError(FirebaseManagerError.generic(L10n.t("chatvm.error.pair_before_message")))
            return
        }

        let payload = ChatPayload(
            type: type,
            value: value,
            isSecret: isSecret,
            sentAt: Date().timeIntervalSince1970
        )
        let sendPerfID = UUID().uuidString
        ChatPerfLogger.mark("send_t0_\(sendPerfID)")

        messageSyncService.send(payload: payload) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let optimisticMessage):
                self.appendMessageIfNeeded(optimisticMessage)
                self.outgoingUploadStateByMessageID[optimisticMessage.id] = .pendingUpload
                self.hydrateMessageMetadataFromLocal(for: [optimisticMessage.id])
                self.rebuildMessageMetadata(for: [optimisticMessage.id], notify: true)
                ChatPerfLogger.mark("send_t1_\(sendPerfID)")
                ChatPerfLogger.logDelta(
                    from: "send_t0_\(sendPerfID)",
                    to: "send_t1_\(sendPerfID)",
                    context: "send_to_render_latency_ms"
                )
            case .failure(let error):
                self.emitError(error)
            }
        }
    }

    @discardableResult
    func appendMessageIfNeeded(_ message: ChatMessage, notify: Bool = true) -> Bool {
        if loadedMessageIDs.contains(message.id) {
            return false
        }

        loadedMessageIDs.insert(message.id)

        let insertionIndex: Int
        if let last = messages.last,
           (last.sentAt, last.id) <= (message.sentAt, message.id) {
            insertionIndex = messages.endIndex
            messages.append(message)
        } else {
            insertionIndex = messages.firstIndex {
                ($0.sentAt, $0.id) > (message.sentAt, message.id)
            } ?? messages.endIndex
            messages.insert(message, at: insertionIndex)
        }
        messageByID[message.id] = message
        _ = trimMessagesIfNeeded(keepingLast: AppConfiguration.ChatPerformance.maxInMemoryMessages)
        oldestLoadedSentAt = messages.first?.sentAt.timeIntervalSince1970
        oldestLoadedMessageID = messages.first?.id
        latestSyncedCursor = currentLatestCursorFromMessages()
        scheduleBootstrapStatePersistIfNeeded()
        scheduleLaunchSnapshotSave()

        if notify {
            let deltaKind: MessageListDeltaKind = insertionIndex == messages.count - 1 ? .append : .prepend
            notifyOnMain {
                self.onMessagesUpdated?()
                self.onMessageListDelta?(MessageListDelta(kind: deltaKind, changedMessageIDs: [message.id]))
            }
        }
        return true
    }

    func resetMessageState(notify: Bool) {
        messages.removeAll(keepingCapacity: true)
        messageByID.removeAll(keepingCapacity: true)
        loadedMessageIDs.removeAll(keepingCapacity: true)
        oldestLoadedSentAt = nil
        oldestLoadedMessageID = nil
        latestSyncedCursor = nil
        isLoadingHistory = false
        hasReachedHistoryStart = false
        messageMetaByID.removeAll(keepingCapacity: true)
        messageReceiptsByID.removeAll(keepingCapacity: true)
        messageReactionsByMessageID.removeAll(keepingCapacity: true)
        outgoingUploadStateByMessageID.removeAll(keepingCapacity: true)
        bootstrapPersistWorkItem?.cancel()
        bootstrapPersistWorkItem = nil
        pendingBootstrapPersistCursor = nil
        lastPersistedBootstrapCursor = nil
        pendingReadReceiptMessageIDs.removeAll(keepingCapacity: true)
        readReceiptWorkItem?.cancel()
        readReceiptWorkItem = nil

        guard notify else { return }
        notifyOnMain {
            self.onMessagesUpdated?()
            self.onMessageListDelta?(MessageListDelta(kind: .initial, changedMessageIDs: []))
        }
    }

    @discardableResult
    func trimMessagesIfNeeded(keepingLast limit: Int) -> Bool {
        guard limit > 0, messages.count > limit else { return false }
        let removeCount = messages.count - limit
        let removedMessages = messages.prefix(removeCount)
        messages.removeFirst(removeCount)

        for message in removedMessages {
            loadedMessageIDs.remove(message.id)
            messageByID.removeValue(forKey: message.id)
        }

        oldestLoadedSentAt = messages.first?.sentAt.timeIntervalSince1970
        oldestLoadedMessageID = messages.first?.id
        latestSyncedCursor = currentLatestCursorFromMessages()
        return true
    }

    func flushLaunchSnapshotIfPossible() {
        guard let currentUserID, let activeChatID else { return }
        let models = messages.suffix(60).map(snapshotModel)
        ChatLaunchSnapshotCache.shared.flushPendingSave(
            ownerUID: currentUserID,
            chatID: activeChatID,
            messages: models
        )
    }

    private func scheduleLaunchSnapshotSave() {
        guard let currentUserID, let activeChatID else { return }
        let models = messages.suffix(60).map(snapshotModel)
        ChatLaunchSnapshotCache.shared.scheduleSave(
            ownerUID: currentUserID,
            chatID: activeChatID,
            messages: models
        )
    }

    private func snapshotModel(from message: ChatMessage) -> MessageUIModel {
        MessageUIModel(
            id: message.id,
            senderID: message.senderID,
            recipientID: message.recipientID,
            text: message.value,
            timestampMs: Int64(message.sentAt.timeIntervalSince1970 * 1000),
            payloadType: message.type.rawValue,
            isSecret: message.isSecret,
            status: .unknown
        )
    }

    private func chatMessageFromSnapshot(
        _ model: MessageUIModel,
        currentUserID: String,
        partnerUserID: String
    ) -> ChatMessage? {
        guard !model.id.isEmpty else { return nil }
        let payloadType = model.payloadType.flatMap(ChatPayloadType.init(rawValue:)) ?? .text
        let recipientID = model.recipientID ?? (model.senderID == currentUserID ? partnerUserID : currentUserID)
        return ChatMessage(
            id: model.id,
            senderID: model.senderID,
            recipientID: recipientID,
            sentAt: Date(timeIntervalSince1970: TimeInterval(model.timestampMs) / 1000),
            type: payloadType,
            value: model.text,
            isSecret: model.isSecret ?? false
        )
    }

    private func currentLatestCursorFromMessages() -> ChatSyncCursor? {
        guard let latestMessage = messages.last else { return nil }
        return ChatSyncCursor(
            timestampMs: Int64(latestMessage.sentAt.timeIntervalSince1970 * 1000),
            messageID: latestMessage.id
        )
    }

    private func currentAppVersionString() -> String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        return "\(version)(\(build))"
    }

    private func scheduleBootstrapStatePersistIfNeeded() {
        guard activeChatID != nil else { return }
        let cursor = latestSyncedCursor
        guard cursor != lastPersistedBootstrapCursor else { return }

        pendingBootstrapPersistCursor = cursor
        bootstrapPersistWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard let chatID = self.activeChatID else { return }
            let cursorToPersist = self.pendingBootstrapPersistCursor
            guard cursorToPersist != self.lastPersistedBootstrapCursor else { return }
            do {
                try self.localMessageStore.markBootstrapCompleted(
                    chatID: chatID,
                    cursor: cursorToPersist,
                    appVersion: self.currentAppVersionString()
                )
                self.lastPersistedBootstrapCursor = cursorToPersist
            } catch {
                self.emitError(error)
            }
        }

        bootstrapPersistWorkItem = workItem
        DispatchQueue.global(qos: .utility).asyncAfter(
            deadline: .now() + bootstrapPersistDebounceInterval,
            execute: workItem
        )
    }

    func attemptSharedKeyRecoveryIfPossible(partnerUID: String) {
        guard !isAttemptingSharedKeyRecovery else { return }
        guard let publicKey = latestPartnerPublicKey, !publicKey.isEmpty else { return }

        isAttemptingSharedKeyRecovery = true
        defer { isAttemptingSharedKeyRecovery = false }

        do {
            try encryption.establishSharedKey(with: publicKey, partnerUID: partnerUID)
            hasLoggedUnreadablePayloadWarning = false
            #if DEBUG
            print("Shared key yeniden senkronlandı (partner: \(partnerUID)).")
            #endif
        } catch {
            #if DEBUG
            print("Shared key toparlama başarısız: \(error.localizedDescription)")
            #endif
        }
    }

    func emitError(_ error: Error) {
        let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        let nsError = error as NSError
        let key = "\(nsError.domain)#\(nsError.code)#\(message)"
        let now = Date()
        errorThrottleLock.lock()
        if let last = lastErrorEmissionByKey[key], now.timeIntervalSince(last) < errorThrottleWindow {
            errorThrottleLock.unlock()
            return
        }
        lastErrorEmissionByKey[key] = now
        errorThrottleLock.unlock()

        notifyOnMain {
            self.onError?(message)
        }
    }

    func isRecoverablePartnerPayloadError(_ error: Error) -> Bool {
        if error is CryptoKitError {
            return true
        }

        if let encryptionError = error as? EncryptionError {
            switch encryptionError {
            case .invalidCiphertext, .missingSharedKey, .serializationFailed:
                return true
            case .missingIdentityKey, .invalidPartnerPublicKey:
                return false
            }
        }

        if error is DecodingError {
            return true
        }

        let nsError = error as NSError
        if nsError.domain.contains("CryptoKit") || nsError.domain.contains("crypto") {
            return true
        }

        return false
    }
}
