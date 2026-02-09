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
    var onPaired: ((String) -> Void)?

    private let firebase: FirebaseManager

    private var currentUID: String?
    private var currentPartnerID: String?
    private var ownProfileObserver: FirebaseObservationToken?
    private var partnerProfileObserver: FirebaseObservationToken?
    private var hasEmittedPaired = false

    init(firebase: FirebaseManager = .shared) {
        self.firebase = firebase
    }

    deinit {
        ownProfileObserver?.cancel()
        partnerProfileObserver?.cancel()
    }

    func start() {
        guard let uid = firebase.currentUserID() else {
            emitError(FirebaseManagerError.unauthenticated)
            return
        }

        currentUID = uid
        onStateChanged?(.loading, L10n.t("pairing.status.profile_loading"))

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

    func pair(with code: String) {
        guard let uid = currentUID else {
            emitError(FirebaseManagerError.unauthenticated)
            return
        }

        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count == 6, trimmed.allSatisfy(\.isNumber) else {
            emitError(FirebaseManagerError.invalidPairCode)
            return
        }

        onStateChanged?(.loading, L10n.t("pairing.status.request_sending"))

        firebase.fetchUID(for: trimmed) { [weak self] result in
            switch result {
            case .success(let partnerUID):
                guard partnerUID != uid else {
                    self?.onStateChanged?(.notPaired, L10n.t("pairing.error.self_pair"))
                    return
                }
                self?.updatePartner(to: partnerUID)
            case .failure(let error):
                self?.emitError(error)
                self?.onStateChanged?(.notPaired, L10n.t("pairing.error.partner_not_found"))
            }
        }
    }

    func clearPairing() {
        guard let uid = currentUID else {
            emitError(FirebaseManagerError.unauthenticated)
            return
        }

        onStateChanged?(.loading, L10n.t("pairing.status.unpairing"))
        firebase.clearPartnerID(uid: uid) { [weak self] result in
            switch result {
            case .success:
                self?.currentPartnerID = nil
                self?.partnerProfileObserver?.cancel()
                self?.partnerProfileObserver = nil
                self?.hasEmittedPaired = false
                self?.onStateChanged?(.notPaired, L10n.t("pairing.status.unpaired"))
            case .failure(let error):
                self?.emitError(error)
            }
        }
    }

    private func updatePartner(to partnerUID: String) {
        guard let uid = currentUID else { return }

        firebase.updatePartnerID(for: uid, partnerUID: partnerUID) { [weak self] result in
            switch result {
            case .success:
                self?.currentPartnerID = partnerUID
                self?.hasEmittedPaired = false
                self?.observePartner(uid: partnerUID)
                self?.onStateChanged?(.waiting, L10n.t("pairing.status.waiting_mutual"))
            case .failure(let error):
                self?.emitError(error)
            }
        }
    }

    private func handleOwnProfile(_ profile: UserPairProfile) {
        onPairCodeUpdated?(profile.sixDigitUID)
        currentUID = profile.uid

        let partnerID = profile.partnerID?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let partnerID, !partnerID.isEmpty else {
            currentPartnerID = nil
            partnerProfileObserver?.cancel()
            partnerProfileObserver = nil
            hasEmittedPaired = false
            onStateChanged?(.notPaired, L10n.t("pairing.status.not_paired"))
            return
        }

        if currentPartnerID != partnerID {
            currentPartnerID = partnerID
            hasEmittedPaired = false
            observePartner(uid: partnerID)
        }
    }

    private func observePartner(uid: String) {
        partnerProfileObserver?.cancel()
        partnerProfileObserver = firebase.observeUserProfile(uid: uid) { [weak self] profile in
            guard let self, let currentUID = self.currentUID else { return }

            if profile.partnerID == currentUID {
                self.onStateChanged?(.paired, L10n.t("pairing.status.paired"))
                if !self.hasEmittedPaired {
                    self.hasEmittedPaired = true
                    self.onPaired?(uid)
                }
            } else {
                self.hasEmittedPaired = false
                self.onStateChanged?(.waiting, L10n.t("pairing.status.waiting_mutual"))
            }
        }
    }

    private func emitError(_ error: Error) {
        let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        onError?(message)
    }
}
