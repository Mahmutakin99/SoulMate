import Foundation

extension ChatViewModel {
    func start() {
        guard let uid = firebase.currentUserID() else {
            stopObservers()
            stopLocationSharing(resetDistance: true)
            state = .idle
            return
        }

        attachSession(uid: uid)
    }

    func attachSession(uid: String) {
        if currentUserID != uid {
            resetMessageState(notify: true)
        }
        currentUserID = uid
        state = .loading
        latestPartnerPublicKey = nil
        hasLoggedUnreadablePayloadWarning = false
        observeIncomingPendingRequests(uid: uid)

        firebase.syncIdentityPublicKeyIfNeeded(uid: uid) { result in
            if case .failure(let error) = result {
                #if DEBUG
                print("Public key senkronlanamadı: \(error.localizedDescription)")
                #endif
            }
        }

        ownProfileObserver?.cancel()
        ownProfileObserver = firebase.observeUserProfile(
            uid: uid,
            onChange: { [weak self] profile in
                self?.handleOwnProfileChange(profile)
            },
            onCancelled: { [weak self] error in
                self?.handleObserverCancellation(error)
            }
        )

        firebase.fetchUserProfile(uid: uid) { [weak self] result in
            guard let self else { return }

            switch result {
            case .success(let profile):
                self.handleOwnProfileChange(profile)

            case .failure(let error):
                self.cancelPairingTimeout()
                self.stopLocationSharing(resetDistance: true)
                self.state = .idle
                self.emitError(error)
            }
        }
    }

    func handleOwnProfileChange(_ profile: UserPairProfile) {
        notifyOnMain {
            self.onPairingCodeUpdated?(profile.sixDigitUID)
        }

        let partnerID = profile.partnerID?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let partnerID, !partnerID.isEmpty else {
            if partnerUserID == nil && state == .unpaired {
                return
            }
            invalidateCurrentPairing(notifyUI: true, shouldRouteToPairing: true, wipeLocalConversation: true)
            return
        }

        if partnerUserID != partnerID {
            bindPartner(partnerUID: partnerID)
        } else if state == .unpaired {
            state = .loading
            bindPartner(partnerUID: partnerID)
        }
    }

    func invalidateCurrentPairing(
        notifyUI: Bool,
        shouldRouteToPairing: Bool,
        wipeLocalConversation: Bool = false
    ) {
        let previousState = state
        let previousPartner = partnerUserID
        let hadActivePairing = previousPartner != nil
        if wipeLocalConversation, let currentUserID, let previousPartner {
            let previousChatID = FirebaseManager.chatID(for: currentUserID, and: previousPartner)
            do {
                try localMessageStore.deleteConversation(chatID: previousChatID)
            } catch {
                emitError(error)
            }
        }

        messageObserver?.cancel()
        heartbeatObserver?.cancel()
        profileObserver?.cancel()
        moodObserver?.cancel()
        messageObserver = nil
        heartbeatObserver = nil
        profileObserver = nil
        moodObserver = nil

        if let previousPartner {
            encryption.clearSharedKey(partnerUID: previousPartner)
        }

        observerRebindWorkItem?.cancel()
        observerRebindWorkItem = nil
        partnerUserID = nil
        activeChatID = nil
        hasLoggedUnreadablePayloadWarning = false
        latestPartnerPublicKey = nil
        isAttemptingSharedKeyRecovery = false
        messageSyncService.stop()

        resetMessageState(notify: notifyUI)
        stopLocationSharing(resetDistance: true)
        clearWidgetConversationSnapshot()
        cancelPairingTimeout()

        if state != .unpaired {
            state = .unpaired
        }

        guard shouldRouteToPairing else { return }
        let shouldNotify = hadActivePairing || previousState == .ready || previousState == .waitingForMutualPairing
        guard shouldNotify else { return }
        notifyOnMain {
            self.onPairingInvalidated?()
        }
    }

    func handleObserverCancellation(_ error: Error) {
        guard state != .unpaired else { return }
        switch observerCancellationPolicy(for: error) {
        case .invalidatePairing:
            emitError(error)
            invalidateCurrentPairing(notifyUI: true, shouldRouteToPairing: true, wipeLocalConversation: true)
        case .transientRetry:
            emitError(error)
            scheduleObserverRebind()
        }
    }

    enum ObserverCancellationPolicy {
        case invalidatePairing
        case transientRetry
    }

    func observerCancellationPolicy(for error: Error) -> ObserverCancellationPolicy {
        let description = ((error as? LocalizedError)?.errorDescription ?? error.localizedDescription).lowercased()

        if description.contains("permission denied") ||
            description.contains("erişim reddedildi") ||
            description.contains("not_mutual_pair") {
            return .invalidatePairing
        }

        if description.contains("connection lost") ||
            description.contains("bağlantı koptu") ||
            description.contains("network error") ||
            description.contains("ağ hatası") ||
            description.contains("disconnected") ||
            description.contains("timed out") ||
            description.contains("zaman aşımı") {
            return .transientRetry
        }

        return .invalidatePairing
    }

    func scheduleObserverRebind() {
        observerRebindWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            guard let self,
                  let uid = self.currentUserID,
                  self.firebase.currentUserID() == uid else {
                return
            }

            if let partnerUID = self.partnerUserID, !partnerUID.isEmpty {
                self.bindPartner(partnerUID: partnerUID)
            } else {
                self.attachSession(uid: uid)
            }
        }

        observerRebindWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: workItem)
    }

    func bindPartner(partnerUID: String) {
        guard let currentUserID else { return }

        if partnerUserID != partnerUID {
            resetMessageState(notify: true)
            activeChatID = nil
            stopLocationSharing(resetDistance: true)
            hasLoggedUnreadablePayloadWarning = false
            latestPartnerPublicKey = nil
            isAttemptingSharedKeyRecovery = false
        }
        partnerUserID = partnerUID
        profileObserver?.cancel()

        profileObserver = firebase.observeUserProfile(
            uid: partnerUID,
            onChange: { [weak self] partnerProfile in
                guard let self else { return }

                guard let publicKey = partnerProfile.publicKey else {
                    self.latestPartnerPublicKey = nil
                    self.messageObserver?.cancel()
                    self.heartbeatObserver?.cancel()
                    self.messageObserver = nil
                    self.heartbeatObserver = nil
                    self.activeChatID = nil
                    self.messageSyncService.stop()
                    self.resetMessageState(notify: true)
                    self.stopLocationSharing(resetDistance: true)
                    self.state = .waitingForMutualPairing
                    self.notifyPairingStatus(L10n.t("chatvm.status.waiting_partner_key"))
                    self.schedulePairingTimeout()
                    return
                }

                self.latestPartnerPublicKey = publicKey

                do {
                    try self.encryption.establishSharedKey(with: publicKey, partnerUID: partnerUID)
                } catch {
                    self.emitError(error)
                    return
                }

                let mutual = partnerProfile.partnerID == currentUserID
                self.state = mutual ? .ready : .waitingForMutualPairing

                if mutual {
                    self.cancelPairingTimeout()
                    self.notifyPairingStatus(L10n.t("chatvm.status.paired"))
                    self.observeChatIfReady()
                    self.observePartnerMoodIfReady()
                    LiveActivityManager.shared.startIfNeeded(partnerName: L10n.t("chatvm.live.partner_name"))
                    self.handlePartnerLocationCiphertext(partnerProfile.locationCiphertext)
                } else {
                    self.messageObserver?.cancel()
                    self.heartbeatObserver?.cancel()
                    self.messageObserver = nil
                    self.heartbeatObserver = nil
                    self.activeChatID = nil
                    self.messageSyncService.stop()
                    self.resetMessageState(notify: true)
                    self.stopLocationSharing(resetDistance: true)
                    self.notifyPairingStatus(L10n.t("chatvm.status.waiting_mutual"))
                    self.schedulePairingTimeout()
                }
            },
            onCancelled: { [weak self] error in
                self?.handleObserverCancellation(error)
            }
        )
    }

    func observeChatIfReady() {
        guard let currentUserID,
              let partnerUserID else { return }

        let chatID = FirebaseManager.chatID(for: currentUserID, and: partnerUserID)
        let shouldRebindObservers = activeChatID != chatID || messageObserver == nil || heartbeatObserver == nil
        if !shouldRebindObservers {
            startLocationSharingIfNeeded()
            return
        }

        messageObserver?.cancel()
        heartbeatObserver?.cancel()

        if activeChatID != chatID {
            resetMessageState(notify: true)
        }
        activeChatID = chatID
        messageSyncService.start(chatID: chatID, currentUID: currentUserID, partnerUID: partnerUserID)

        loadInitialMessagesFromLocal()

        bootstrapRecentMessagesAndListen(chatID: chatID, currentUserID: currentUserID, partnerUserID: partnerUserID)
        startLocationSharingIfNeeded()

        heartbeatObserver = firebase.observeHeartbeat(
            chatID: chatID,
            currentUserID: currentUserID,
            onHeartbeat: { [weak self] in
                self?.notifyOnMain {
                    self?.onHeartbeatReceived?()
                }
                HapticEngine.playHeartbeatPattern()
            },
            onCancelled: { [weak self] error in
                self?.handleObserverCancellation(error)
            }
        )
    }

    func observePartnerMoodIfReady() {
        guard let partnerUserID else { return }

        moodObserver?.cancel()
        moodObserver = firebase.observeMoodCiphertext(
            uid: partnerUserID,
            onChange: { [weak self] ciphertext in
                guard let self,
                      let ciphertext,
                      let partnerUserID = self.partnerUserID else { return }

                do {
                    let decrypted = try self.encryption.decrypt(ciphertext, from: partnerUserID)
                    guard let moodRaw = String(data: decrypted, encoding: .utf8),
                          let mood = MoodStatus(rawValue: moodRaw) else {
                        return
                    }

                    self.persistWidgetMood(mood.title)
                    self.latestPartnerMoodTitle = mood.title
                    LiveActivityManager.shared.update(text: L10n.f("chatvm.live.mood_format", mood.title), mood: mood.title)
                    self.notifyOnMain {
                        self.onPartnerMoodUpdated?(mood)
                    }
                } catch {
                    guard !self.isRecoverablePartnerPayloadError(error) else {
                        self.attemptSharedKeyRecoveryIfPossible(partnerUID: partnerUserID)
                        return
                    }
                    self.emitError(error)
                }
            },
            onCancelled: { [weak self] error in
                self?.handleObserverCancellation(error)
            }
        )
    }

    func observeIncomingPendingRequests(uid: String) {
        incomingRequestsObserver?.cancel()
        incomingRequestsObserver = firebase.observeIncomingRequests(
            uid: uid,
            onChange: { [weak self] requests in
                guard let self else { return }
                let pendingCount = requests.filter { $0.status == .pending && !$0.isExpired }.count
                self.notifyOnMain {
                    self.onIncomingPendingRequestCountChanged?(pendingCount)
                }
            },
            onCancelled: { [weak self] error in
                self?.emitError(error)
                self?.notifyOnMain {
                    self?.onIncomingPendingRequestCountChanged?(0)
                }
            }
        )
    }

    func stopObservers() {
        ownProfileObserver?.cancel()
        incomingRequestsObserver?.cancel()
        messageObserver?.cancel()
        heartbeatObserver?.cancel()
        profileObserver?.cancel()
        moodObserver?.cancel()
        ownProfileObserver = nil
        incomingRequestsObserver = nil
        messageObserver = nil
        heartbeatObserver = nil
        profileObserver = nil
        moodObserver = nil
        activeChatID = nil
        messageSyncService.stop()
        stopLocationSharing(resetDistance: false)
        cancelPairingTimeout()
        observerRebindWorkItem?.cancel()
        observerRebindWorkItem = nil
        notifyOnMain {
            self.onIncomingPendingRequestCountChanged?(0)
        }
    }

    func notifyOnMain(_ block: @escaping () -> Void) {
        if Thread.isMainThread {
            block()
        } else {
            DispatchQueue.main.async(execute: block)
        }
    }

    var isSecureChannelReady: Bool {
        state == .ready && currentUserID != nil && partnerUserID != nil
    }

    func notifyPairingStatus(_ message: String) {
        notifyOnMain {
            self.onPairingStatusUpdated?(message)
        }
    }

    func schedulePairingTimeout() {
        cancelPairingTimeout()

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard self.state == .waitingForMutualPairing else { return }

            self.state = .unpaired
            self.stopLocationSharing(resetDistance: true)
            self.notifyPairingStatus(L10n.t("chatvm.status.timeout"))
            self.emitError(FirebaseManagerError.generic(L10n.t("chatvm.error.timeout_detail")))
        }

        pairingTimeoutWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + pairingTimeoutSeconds, execute: workItem)
    }

    func cancelPairingTimeout() {
        pairingTimeoutWorkItem?.cancel()
        pairingTimeoutWorkItem = nil
    }
}
