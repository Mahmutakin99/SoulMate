import Foundation
import CryptoKit

extension ChatViewModel {
    func sendText(_ text: String, isSecret: Bool) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        sendPayload(type: .text, value: trimmed, isSecret: isSecret)
    }

    func sendEmoji(_ emoji: String) {
        sendPayload(type: .emoji, value: emoji, isSecret: false)
    }

    func sendGIF(urlString: String, isSecret: Bool) {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        sendPayload(type: .gif, value: trimmed, isSecret: isSecret)
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
                HapticEngine.playHeartbeatPattern()
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

    func isFromCurrentUser(_ message: ChatMessage) -> Bool {
        message.senderID == currentUserID
    }

    func loadOlderMessagesIfNeeded(visibleTopRow: Int) {
        guard state == .ready else { return }
        guard visibleTopRow <= AppConfiguration.ChatPerformance.historyPreloadTopRowThreshold else { return }
        loadOlderMessages()
    }

    func bootstrapRecentMessagesAndListen(chatID: String, currentUserID: String, partnerUserID: String) {
        messageSyncService.syncCloudBackfillIfNeeded { [weak self] result in
            guard let self else { return }
            guard self.activeChatID == chatID else { return }

            switch result {
            case .success(let envelopes):
                self.consumeInitialMessageBatch(envelopes, currentUserID: currentUserID, partnerUserID: partnerUserID)
                let latestCloudSentAt = envelopes.last?.sentAt ?? 0
                let latestLocalSentAt = self.messages.last?.sentAt.timeIntervalSince1970 ?? 0
                let startAt = max(latestCloudSentAt, latestLocalSentAt)
                self.messageObserver = self.firebase.observeEncryptedMessages(
                    chatID: chatID,
                    startingAt: startAt,
                    onMessage: { [weak self] envelope in
                        self?.handleIncomingEnvelope(envelope)
                    },
                    onCancelled: { [weak self] error in
                        self?.handleObserverCancellation(error)
                    }
                )

            case .failure(let error):
                self.emitError(error)
                self.messageObserver = self.firebase.observeEncryptedMessages(
                    chatID: chatID,
                    startingAt: nil,
                    onMessage: { [weak self] envelope in
                        self?.handleIncomingEnvelope(envelope)
                    },
                    onCancelled: { [weak self] error in
                        self?.handleObserverCancellation(error)
                    }
                )
            }
        }
    }

    func loadInitialMessagesFromLocal() {
        guard AppConfiguration.FeatureFlags.localFirstEphemeralMessaging else { return }

        do {
            let localMessages = try messageSyncService.loadInitialFromLocal()
            resetMessageState(notify: false)
            localMessages.forEach { _ = appendMessageIfNeeded($0, notify: false) }
            hasReachedHistoryStart = localMessages.count < Int(AppConfiguration.MessageQueue.localPageSize)

            notifyOnMain {
                self.onMessagesUpdated?()
            }
        } catch {
            emitError(error)
        }
    }

    func consumeInitialMessageBatch(
        _ envelopes: [EncryptedMessageEnvelope],
        currentUserID: String,
        partnerUserID: String
    ) {
        var inserted = 0
        var latestIncomingValue: String?

        do {
            let batchResults = try messageSyncService.consumeCloudEnvelopes(envelopes)
            for (index, result) in batchResults.enumerated() {
                if result.inserted, appendMessageIfNeeded(result.message, notify: false) {
                    inserted += 1
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
                            if envelope.senderID != currentUserID {
                                latestIncomingValue = recovered.message.value
                            }
                        }
                        continue
                    }
                    emitError(error)
                    break
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
        notifyOnMain {
            self.onMessagesUpdated?()
        }
    }

    func handleIncomingEnvelope(_ envelope: EncryptedMessageEnvelope) {
        guard let currentUserID,
              let partnerUserID else { return }

        do {
            let syncResult = try messageSyncService.consumeCloudEnvelope(envelope)
            let inserted = syncResult.inserted && appendMessageIfNeeded(syncResult.message)

            if inserted && envelope.senderID != currentUserID {
                persistWidgetLatestMessage(syncResult.message.value)
                LiveActivityManager.shared.update(text: syncResult.message.value, mood: latestPartnerMoodTitle)
            }
        } catch {
            guard !isRecoverablePartnerPayloadError(error) else {
                attemptSharedKeyRecoveryIfPossible(partnerUID: partnerUserID)

                if let recoveredSync = try? messageSyncService.consumeCloudEnvelope(envelope) {
                    let inserted = recoveredSync.inserted && appendMessageIfNeeded(recoveredSync.message)
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
        do {
            let localMessages = try messageSyncService.loadOlderFromLocal(beforeSentAt: oldestLoadedSentAt)
            for message in localMessages {
                if appendMessageIfNeeded(message, notify: false) {
                    localInserted += 1
                }
            }
        } catch {
            emitError(error)
        }

        if localInserted > 0 {
            isLoadingHistory = false
            notifyOnMain {
                self.onMessagesPrepended?(localInserted)
            }
            return
        }

        firebase.fetchOlderEncryptedMessages(chatID: chatID, endingAtOrBefore: oldestLoadedSentAt, limit: pageSize) { [weak self] result in
            guard let self else { return }
            guard self.activeChatID == chatID else { return }
            self.isLoadingHistory = false

            switch result {
            case .failure(let error):
                self.emitError(error)

            case .success(let envelopes):
                var inserted = 0
                do {
                    let batchResults = try self.messageSyncService.consumeCloudEnvelopes(envelopes)
                    for result in batchResults where result.inserted {
                        if self.appendMessageIfNeeded(result.message, notify: false) {
                            inserted += 1
                        }
                    }
                } catch {
                    for envelope in envelopes {
                        do {
                            let syncResult = try self.messageSyncService.consumeCloudEnvelope(envelope)
                            if syncResult.inserted, self.appendMessageIfNeeded(syncResult.message, notify: false) {
                                inserted += 1
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
                self.notifyOnMain {
                    self.onMessagesPrepended?(inserted)
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

        messageSyncService.send(payload: payload) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let optimisticMessage):
                self.appendMessageIfNeeded(optimisticMessage)
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

        if let last = messages.last, last.sentAt <= message.sentAt {
            messages.append(message)
        } else {
            let insertionIndex = messages.firstIndex(where: { $0.sentAt > message.sentAt }) ?? messages.endIndex
            messages.insert(message, at: insertionIndex)
        }
        _ = trimMessagesIfNeeded(keepingLast: AppConfiguration.ChatPerformance.maxInMemoryMessages)
        oldestLoadedSentAt = messages.first?.sentAt.timeIntervalSince1970

        if notify {
            notifyOnMain {
                self.onMessagesUpdated?()
            }
        }
        return true
    }

    func resetMessageState(notify: Bool) {
        messages.removeAll(keepingCapacity: true)
        loadedMessageIDs.removeAll(keepingCapacity: true)
        oldestLoadedSentAt = nil
        isLoadingHistory = false
        hasReachedHistoryStart = false

        guard notify else { return }
        notifyOnMain {
            self.onMessagesUpdated?()
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
        }

        oldestLoadedSentAt = messages.first?.sentAt.timeIntervalSince1970
        return true
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
