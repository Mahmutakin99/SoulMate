import Foundation

final class PairingViewModel {
    enum State {
        case loading
        case notPaired
        case waiting
        case paired
    }

    var onStateChanged: ((State, String) -> Void)?
    var onPairCodeUpdated: ((String) -> Void)?
    var onError: ((String) -> Void)?
    var onNotice: ((String) -> Void)?
    var onPaired: ((String) -> Void)?
    var onIncomingRequestsUpdated: (([RelationshipRequest]) -> Void)?
    var onOutgoingRequestsUpdated: (([RelationshipRequest]) -> Void)?

    private let firebase: FirebaseManager
    private let encryption: EncryptionService
    private let archiveService: ConversationArchiveService
    private let jsonDecoder = JSONDecoder()

    private var currentUID: String?
    private var currentPartnerID: String?
    private var ownProfileObserver: FirebaseObservationToken?
    private var partnerProfileObserver: FirebaseObservationToken?
    private var incomingRequestsObserver: FirebaseObservationToken?
    private var outgoingRequestsObserver: FirebaseObservationToken?
    private var hasEmittedPaired = false
    private var isMutuallyPaired = false
    private var outgoingRequests: [RelationshipRequest] = []
    private var hasLocalPendingUnpairRequest = false

    init(
        firebase: FirebaseManager = .shared,
        encryption: EncryptionService = .shared,
        archiveService: ConversationArchiveService = .shared
    ) {
        self.firebase = firebase
        self.encryption = encryption
        self.archiveService = archiveService
    }

    deinit {
        ownProfileObserver?.cancel()
        partnerProfileObserver?.cancel()
        incomingRequestsObserver?.cancel()
        outgoingRequestsObserver?.cancel()
    }

    func start() {
        guard let uid = firebase.currentUserID() else {
            emitError(FirebaseManagerError.unauthenticated)
            return
        }

        currentUID = uid
        onStateChanged?(.loading, L10n.t("pairing.status.profile_loading"))
        observeRequests(uid: uid)

        ownProfileObserver?.cancel()
        ownProfileObserver = firebase.observeUserProfile(uid: uid) { [weak self] profile in
            self?.handleOwnProfile(profile)
        }

        firebase.fetchUserProfile(uid: uid) { [weak self] result in
            switch result {
            case .success(let profile):
                self?.handleOwnProfile(profile)
            case .failure(let error):
                self?.emitError(error)
            }
        }
    }

    func sendPairRequest(code: String) {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count == 6, trimmed.allSatisfy(\.isNumber) else {
            emitError(FirebaseManagerError.invalidPairCode)
            return
        }

        guard !hasActivePartner else {
            emitError(FirebaseManagerError.generic(L10n.t("pairing.request.error.user_already_paired")))
            return
        }

        onStateChanged?(.loading, L10n.t("pairing.status.request_sending"))
        firebase.createPairRequest(partnerCode: trimmed) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success:
                self.onStateChanged?(.waiting, L10n.t("pairing.status.waiting_mutual"))
                self.onNotice?(L10n.t("pairing.request.notice.pair_sent"))
            case .failure(let error):
                self.refreshIdleState()
                self.emitError(error)
            }
        }
    }

    func sendUnpairRequest(archiveChoice: ArchiveChoice) {
        guard let currentUID else {
            emitError(FirebaseManagerError.unauthenticated)
            return
        }
        guard let partnerUID = currentPartnerID, !partnerUID.isEmpty else {
            onStateChanged?(.notPaired, L10n.t("pairing.status.not_paired"))
            return
        }
        guard !hasOutgoingPendingUnpairRequest else {
            onNotice?(L10n.t("pairing.request.notice.unpair_already_pending"))
            refreshIdleState()
            return
        }

        onStateChanged?(.loading, L10n.t("pairing.status.unpair_request_sending"))
        let fallbackState = isMutuallyPaired ? State.paired : State.waiting

        prepareArchiveIfNeeded(
            currentUID: currentUID,
            partnerUID: partnerUID,
            archiveChoice: archiveChoice
        ) { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure(let error):
                self.restoreStateAfterOperation(fallback: fallbackState)
                self.emitError(error)
            case .success:
                self.firebase.createUnpairRequest(archiveChoice: archiveChoice) { [weak self] result in
                    guard let self else { return }
                    switch result {
                    case .success:
                        self.hasLocalPendingUnpairRequest = true
                        self.restoreStateAfterOperation(fallback: fallbackState)
                        self.onStateChanged?(.paired, L10n.t("pairing.status.unpair_request_pending"))
                        self.onNotice?(L10n.t("pairing.request.notice.unpair_sent"))
                    case .failure(let error):
                        self.restoreStateAfterOperation(fallback: fallbackState)
                        self.emitError(error)
                    }
                }
            }
        }
    }

    func respondToRequest(
        request: RelationshipRequest,
        decision: RelationshipRequestDecision,
        recipientArchiveChoice: ArchiveChoice? = nil
    ) {
        guard let currentUID else {
            emitError(FirebaseManagerError.unauthenticated)
            return
        }

        if request.isExpired {
            emitError(FirebaseManagerError.generic(L10n.t("pairing.request.error.expired")))
            return
        }

        switch request.type {
        case .pair:
            onStateChanged?(.loading, L10n.t("pairing.status.request_processing"))
            firebase.respondPairRequest(requestID: request.id, decision: decision) { [weak self] result in
                guard let self else { return }
                switch result {
                case .success:
                    self.refreshIdleState()
                    let key = decision == .accept
                        ? "pairing.request.notice.accepted"
                        : "pairing.request.notice.rejected"
                    self.onNotice?(L10n.t(key))
                case .failure(let error):
                    self.refreshIdleState()
                    self.emitError(error)
                }
            }

        case .unpair:
            if decision == .reject {
                onStateChanged?(.loading, L10n.t("pairing.status.request_processing"))
                firebase.respondUnpairRequest(
                    requestID: request.id,
                    decision: .reject,
                    recipientArchiveChoice: nil
                ) { [weak self] result in
                    guard let self else { return }
                    switch result {
                    case .success:
                        self.refreshIdleState()
                        self.onNotice?(L10n.t("pairing.request.notice.rejected"))
                    case .failure(let error):
                        self.refreshIdleState()
                        self.emitError(error)
                    }
                }
                return
            }

            guard let recipientArchiveChoice else {
                emitError(FirebaseManagerError.generic(L10n.t("pairing.unpair.error.archive_load_failed")))
                return
            }

            onStateChanged?(.loading, L10n.t("pairing.status.request_processing"))
            let partnerUID = request.fromUID

            prepareArchiveIfNeeded(
                currentUID: currentUID,
                partnerUID: partnerUID,
                archiveChoice: recipientArchiveChoice
            ) { [weak self] result in
                guard let self else { return }
                switch result {
                case .failure(let error):
                    self.refreshIdleState()
                    self.emitError(error)
                case .success:
                    self.firebase.respondUnpairRequest(
                        requestID: request.id,
                        decision: .accept,
                        recipientArchiveChoice: recipientArchiveChoice
                    ) { [weak self] result in
                        guard let self else { return }
                        switch result {
                        case .success:
                            self.currentPartnerID = nil
                            self.isMutuallyPaired = false
                            self.hasEmittedPaired = false
                            self.partnerProfileObserver?.cancel()
                            self.partnerProfileObserver = nil
                            self.encryption.clearSharedKey(partnerUID: partnerUID)
                            self.onStateChanged?(.notPaired, L10n.t("pairing.status.unpaired"))
                            self.onNotice?(L10n.t("pairing.request.notice.unpair_accepted"))
                        case .failure(let error):
                            self.refreshIdleState()
                            self.emitError(error)
                        }
                    }
                }
            }
        }
    }

    private func observeRequests(uid: String) {
        incomingRequestsObserver?.cancel()
        outgoingRequestsObserver?.cancel()

        incomingRequestsObserver = firebase.observeIncomingRequests(uid: uid) { [weak self] requests in
            guard let self else { return }
            let filtered = self.filterActiveRequests(requests)
            self.onIncomingRequestsUpdated?(filtered)
            self.refreshIdleState()
        }

        outgoingRequestsObserver = firebase.observeOutgoingRequests(uid: uid) { [weak self] requests in
            guard let self else { return }
            let filtered = self.filterActiveRequests(requests)
            self.outgoingRequests = filtered
            self.hasLocalPendingUnpairRequest = filtered.contains(where: { $0.type == .unpair && $0.status == .pending && !$0.isExpired })
            self.onOutgoingRequestsUpdated?(filtered)
            self.refreshIdleState()
        }
    }

    private func filterActiveRequests(_ requests: [RelationshipRequest]) -> [RelationshipRequest] {
        requests.filter { request in
            request.status == .pending && !request.isExpired
        }
    }

    private func restoreStateAfterOperation(fallback: State) {
        switch fallback {
        case .paired:
            onStateChanged?(.paired, L10n.t("pairing.status.paired"))
        case .waiting:
            onStateChanged?(.waiting, L10n.t("pairing.status.waiting_mutual"))
        case .loading, .notPaired:
            refreshIdleState()
        }
    }

    private func refreshIdleState() {
        if hasActivePartner {
            if hasOutgoingPendingUnpairRequest {
                onStateChanged?(.paired, L10n.t("pairing.status.unpair_request_pending"))
                return
            }

            if isMutuallyPaired {
                onStateChanged?(.paired, L10n.t("pairing.status.paired"))
            } else {
                onStateChanged?(.waiting, L10n.t("pairing.status.waiting_mutual"))
            }
            return
        }

        if hasOutgoingPendingPairRequest {
            onStateChanged?(.waiting, L10n.t("pairing.status.waiting_mutual"))
        } else {
            onStateChanged?(.notPaired, L10n.t("pairing.status.not_paired"))
        }
    }

    private var hasActivePartner: Bool {
        guard let currentPartnerID else { return false }
        return !currentPartnerID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var hasOutgoingPendingPairRequest: Bool {
        outgoingRequests.contains(where: { $0.type == .pair && $0.status == .pending && !$0.isExpired })
    }

    private var hasOutgoingPendingUnpairRequest: Bool {
        hasLocalPendingUnpairRequest || outgoingRequests.contains(where: { $0.type == .unpair && $0.status == .pending && !$0.isExpired })
    }

    private func handleOwnProfile(_ profile: UserPairProfile) {
        onPairCodeUpdated?(profile.sixDigitUID)
        currentUID = profile.uid

        let partnerID = profile.partnerID?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let partnerID, !partnerID.isEmpty else {
            currentPartnerID = nil
            hasLocalPendingUnpairRequest = false
            isMutuallyPaired = false
            hasEmittedPaired = false
            partnerProfileObserver?.cancel()
            partnerProfileObserver = nil
            refreshIdleState()
            return
        }

        if currentPartnerID != partnerID {
            currentPartnerID = partnerID
            isMutuallyPaired = false
            hasEmittedPaired = false
            observePartner(uid: partnerID)
        } else if isMutuallyPaired {
            onStateChanged?(.paired, L10n.t("pairing.status.paired"))
        } else {
            onStateChanged?(.waiting, L10n.t("pairing.status.waiting_mutual"))
        }
    }

    private func observePartner(uid: String) {
        partnerProfileObserver?.cancel()
        partnerProfileObserver = firebase.observeUserProfile(uid: uid) { [weak self] profile in
            guard let self, let currentUID = self.currentUID else { return }

            if profile.partnerID == currentUID {
                self.isMutuallyPaired = true
                self.onStateChanged?(.paired, L10n.t("pairing.status.paired"))
                if !self.hasEmittedPaired {
                    self.hasEmittedPaired = true
                    self.onPaired?(uid)
                }
            } else {
                self.isMutuallyPaired = false
                self.hasEmittedPaired = false
                self.onStateChanged?(.waiting, L10n.t("pairing.status.waiting_mutual"))
            }
        }
    }

    private func prepareArchiveIfNeeded(
        currentUID: String,
        partnerUID: String,
        archiveChoice: ArchiveChoice,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        switch archiveChoice {
        case .keep:
            let chatID = FirebaseManager.chatID(for: currentUID, and: partnerUID)
            archiveCurrentConversation(
                currentUID: currentUID,
                partnerUID: partnerUID,
                chatID: chatID,
                completion: completion
            )
        case .delete:
            do {
                try archiveService.deleteConversationArchive(currentUID: currentUID, partnerUID: partnerUID)
                completion(.success(()))
            } catch {
                completion(.failure(error))
            }
        }
    }

    private func archiveCurrentConversation(
        currentUID: String,
        partnerUID: String,
        chatID: String,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        firebase.fetchRecentEncryptedMessages(chatID: chatID, limit: AppConfiguration.Archive.maxLocalMessages) { [weak self] result in
            guard let self else {
                completion(.failure(FirebaseManagerError.generic(L10n.t("pairing.unpair.error.archive_failed"))))
                return
            }

            switch result {
            case .failure(let error):
                completion(.failure(error))
                return
            case .success(let envelopes):
                var archivedMessages: [ChatMessage] = []
                archivedMessages.reserveCapacity(envelopes.count)

                let sortedEnvelopes = envelopes.sorted { $0.sentAt < $1.sentAt }
                for envelope in sortedEnvelopes {
                    do {
                        let decryptedPayload = try self.encryption.decrypt(envelope.payload, from: partnerUID)
                        let payload = try self.jsonDecoder.decode(ChatPayload.self, from: decryptedPayload)
                        let message = ChatMessage(
                            id: envelope.id,
                            senderID: envelope.senderID,
                            recipientID: envelope.recipientID,
                            sentAt: Date(timeIntervalSince1970: payload.sentAt),
                            type: payload.type,
                            value: payload.value,
                            isSecret: payload.isSecret
                        )
                        archivedMessages.append(message)
                    } catch {
                        continue
                    }
                }

                do {
                    try self.archiveService.saveConversation(
                        currentUID: currentUID,
                        partnerUID: partnerUID,
                        messages: archivedMessages
                    )
                    if envelopes.isEmpty {
                        self.onNotice?(L10n.t("pairing.unpair.notice.no_messages_to_archive"))
                    } else if archivedMessages.isEmpty {
                        completion(.failure(FirebaseManagerError.generic(L10n.t("pairing.unpair.error.archive_failed"))))
                        return
                    }
                    completion(.success(()))
                } catch {
                    completion(.failure(error))
                }
            }
        }
    }

    private func emitError(_ error: Error) {
        let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        onError?(message)
    }
}
