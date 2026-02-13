//
//  PairingViewModel.swift
//  SoulMate
//
//  Created by MAHMUT AKIN on 02/02/2026.
//

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
    private let localMessageStore: LocalMessageStore

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

    var isUnpairRequestPending: Bool {
        hasOutgoingPendingUnpairRequest
    }

    init(
        firebase: FirebaseManager = .shared,
        encryption: EncryptionService = .shared,
        localMessageStore: LocalMessageStore = .shared
    ) {
        self.firebase = firebase
        self.encryption = encryption
        self.localMessageStore = localMessageStore
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
        firebase.syncIdentityPublicKeyIfNeeded(uid: uid) { result in
            if case .failure(let error) = result {
                #if DEBUG
                print("Pairing public key senkronlanamadı: \(error.localizedDescription)")
                #endif
            }
        }

        ownProfileObserver?.cancel()
        ownProfileObserver = firebase.observeUserProfile(
            uid: uid,
            onChange: { [weak self] profile in
                self?.handleOwnProfile(profile)
            },
            onCancelled: { [weak self] error in
                self?.emitError(error)
                self?.refreshIdleState()
            }
        )

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

    func sendUnpairRequest() {
        guard currentUID != nil else {
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

        firebase.createUnpairRequest { [weak self] result in
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

    func respondToRequest(
        request: RelationshipRequest,
        decision: RelationshipRequestDecision
    ) {
        guard currentUID != nil else {
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
                    decision: .reject
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

            onStateChanged?(.loading, L10n.t("pairing.status.request_processing"))
            let partnerUID = request.fromUID

            firebase.respondUnpairRequest(
                requestID: request.id,
                decision: .accept
            ) { [weak self] result in
                guard let self else { return }
                switch result {
                case .success:
                    self.deleteLocalConversation(with: partnerUID)
                    self.currentPartnerID = nil
                    self.isMutuallyPaired = false
                    self.hasEmittedPaired = false
                    self.partnerProfileObserver?.cancel()
                    self.partnerProfileObserver = nil
                    self.encryption.clearSharedKey(partnerUID: partnerUID)
                    self.clearWidgetConversationSnapshot()
                    self.onStateChanged?(.notPaired, L10n.t("pairing.status.unpaired"))
                    self.onNotice?(L10n.t("pairing.request.notice.unpair_accepted"))
                case .failure(let error):
                    self.refreshIdleState()
                    self.emitError(error)
                }
            }
        }
    }

    private func observeRequests(uid: String) {
        incomingRequestsObserver?.cancel()
        outgoingRequestsObserver?.cancel()

        incomingRequestsObserver = firebase.observeIncomingRequests(
            uid: uid,
            onChange: { [weak self] requests in
                guard let self else { return }
                let filtered = self.filterActiveRequests(requests)
                self.onIncomingRequestsUpdated?(filtered)
                self.refreshIdleState()
            },
            onCancelled: { [weak self] error in
                self?.emitError(error)
            }
        )

        outgoingRequestsObserver = firebase.observeOutgoingRequests(
            uid: uid,
            onChange: { [weak self] requests in
                guard let self else { return }
                let filtered = self.filterActiveRequests(requests)
                self.outgoingRequests = filtered
                self.hasLocalPendingUnpairRequest = filtered.contains(where: { $0.type == .unpair && $0.status == .pending && !$0.isExpired })
                self.onOutgoingRequestsUpdated?(filtered)
                self.refreshIdleState()
            },
            onCancelled: { [weak self] error in
                self?.emitError(error)
            }
        )
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
            if let oldPartner = currentPartnerID, !oldPartner.isEmpty {
                deleteLocalConversation(with: oldPartner)
            }
            currentPartnerID = nil
            hasLocalPendingUnpairRequest = false
            isMutuallyPaired = false
            hasEmittedPaired = false
            partnerProfileObserver?.cancel()
            partnerProfileObserver = nil
            clearWidgetConversationSnapshot()
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
        partnerProfileObserver = firebase.observeUserProfile(
            uid: uid,
            onChange: { [weak self] profile in
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
            },
            onCancelled: { [weak self] error in
                self?.emitError(error)
                self?.refreshIdleState()
            }
        )
    }

    private func emitError(_ error: Error) {
        let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        onError?(message)
    }

    private func clearWidgetConversationSnapshot() {
        guard let defaults = UserDefaults(suiteName: AppConfiguration.appGroupIdentifier) else { return }
        defaults.removeObject(forKey: AppConfiguration.SharedStoreKey.latestMessage)
        defaults.removeObject(forKey: AppConfiguration.SharedStoreKey.latestMood)
        defaults.removeObject(forKey: AppConfiguration.SharedStoreKey.latestDistance)
    }

    private func deleteLocalConversation(with partnerUID: String) {
        guard let currentUID = currentUID else { return }
        let chatID = FirebaseManager.chatID(for: currentUID, and: partnerUID)
        do {
            try localMessageStore.deleteConversation(chatID: chatID)
        } catch {
            emitError(error)
        }
    }
}
