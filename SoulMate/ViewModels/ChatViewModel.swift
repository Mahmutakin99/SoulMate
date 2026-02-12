import Foundation
#if canImport(CoreLocation)
import CoreLocation
#endif
#if canImport(WidgetKit)
import WidgetKit
#endif

final class ChatViewModel {
    enum ScreenState {
        case idle
        case loading
        case unpaired
        case waitingForMutualPairing
        case ready
    }

    var onStateChanged: ((ScreenState) -> Void)?
    var onMessagesUpdated: (() -> Void)?
    var onMessagesPrepended: ((Int) -> Void)?
    var onPairingCodeUpdated: ((String) -> Void)?
    var onPairingStatusUpdated: ((String) -> Void)?
    var onPartnerMoodUpdated: ((MoodStatus?) -> Void)?
    var onDistanceUpdated: ((String?) -> Void)?
    var onError: ((String) -> Void)?
    var onHeartbeatReceived: (() -> Void)?
    var onPairingInvalidated: (() -> Void)?

    private(set) var messages: [ChatMessage] = []
    private(set) var state: ScreenState = .idle {
        didSet { notifyOnMain { self.onStateChanged?(self.state) } }
    }

    private let firebase: FirebaseManager
    private let encryption: EncryptionService
    private let archiveService: ConversationArchiveService
    private let locationService: LocationSharingService
    private let jsonEncoder = JSONEncoder()
    private let jsonDecoder = JSONDecoder()

    private var currentUserID: String?
    private var partnerUserID: String?
    private var latestPartnerMoodTitle = L10n.t("mood.unknown")

    private var messageObserver: FirebaseObservationToken?
    private var heartbeatObserver: FirebaseObservationToken?
    private var ownProfileObserver: FirebaseObservationToken?
    private var profileObserver: FirebaseObservationToken?
    private var moodObserver: FirebaseObservationToken?
    private var pairingTimeoutWorkItem: DispatchWorkItem?
    private var loadedMessageIDs: Set<String> = []
    private var oldestLoadedSentAt: TimeInterval?
    private var isLoadingHistory = false
    private var hasReachedHistoryStart = false
    private var activeChatID: String?
    private var localArchiveLoadedChatID: String?
    private var lastUploadedLocation: CLLocation?
    private var lastLocationUploadDate: Date?
    private var didReportLocationPermissionDenied = false
    private let minimumLocationUploadDistanceMeters: CLLocationDistance = 35
    private let minimumLocationUploadInterval: TimeInterval = 25
    private let maxPartnerLocationAge: TimeInterval = 300
    private let pairingTimeoutSeconds: TimeInterval = 10

    private struct LocationPayload: Codable {
        let latitude: Double
        let longitude: Double
        let sentAt: TimeInterval
        let isSimulated: Bool?
    }

    init(
        firebase: FirebaseManager = .shared,
        encryption: EncryptionService = .shared,
        archiveService: ConversationArchiveService = .shared,
        locationService: LocationSharingService = LocationSharingService()
    ) {
        self.firebase = firebase
        self.encryption = encryption
        self.archiveService = archiveService
        self.locationService = locationService

        self.locationService.onLocationUpdate = { [weak self] location in
            self?.handleOwnLocationUpdate(location)
        }
        self.locationService.onDistanceUpdate = { [weak self] distanceInKilometers in
            self?.publishDistance(distanceInKilometers)
        }
        self.locationService.onAuthorizationDenied = { [weak self] in
            guard let self else { return }
            self.notifyOnMain {
                self.onDistanceUpdated?(nil)
            }
            guard !self.didReportLocationPermissionDenied else { return }
            self.didReportLocationPermissionDenied = true
            self.emitError(FirebaseManagerError.generic(L10n.t("chatvm.error.location_permission_required")))
        }
    }

    deinit {
        stopObservers()
    }

    func start() {
        guard let uid = firebase.currentUserID() else {
            cancelPairingTimeout()
            stopLocationSharing(resetDistance: true)
            state = .idle
            return
        }

        attachSession(uid: uid)
    }

    func authenticate(email: String, password: String, isSignUp: Bool) {
        let cleanEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let cleanPassword = password.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleanEmail.isEmpty, !cleanPassword.isEmpty else {
            emitError(FirebaseManagerError.generic(L10n.t("chatvm.error.empty_credentials")))
            return
        }

        guard cleanEmail.contains("@"), cleanEmail.contains(".") else {
            emitError(FirebaseManagerError.generic(L10n.t("chatvm.error.invalid_email")))
            return
        }

        if isSignUp, cleanPassword.count < 6 {
            emitError(FirebaseManagerError.generic(L10n.t("chatvm.error.signup_password_min")))
            return
        }

        state = .loading

        let completion: (Result<String, Error>) -> Void = { [weak self] result in
            switch result {
            case .success(let uid):
                self?.attachSession(uid: uid)
            case .failure(let error):
                self?.cancelPairingTimeout()
                self?.state = .idle
                self?.emitError(error)
            }
        }

        if isSignUp {
            firebase.createAccount(
                email: cleanEmail,
                password: cleanPassword,
                firstName: L10n.t("chatvm.default.first_name"),
                lastName: L10n.t("chatvm.default.last_name"),
                completion: completion
            )
        } else {
            firebase.signIn(email: cleanEmail, password: cleanPassword, completion: completion)
        }
    }

    func pair(with sixDigitUID: String) {
        guard let currentUserID else {
            emitError(FirebaseManagerError.unauthenticated)
            return
        }

        let trimmed = sixDigitUID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count == 6, trimmed.allSatisfy(\.isNumber) else {
            emitError(FirebaseManagerError.invalidPairCode)
            return
        }

        state = .loading

        firebase.fetchUID(for: trimmed) { [weak self] result in
            switch result {
            case .success(let partnerUID):
                guard partnerUID != currentUserID else {
                    self?.state = .unpaired
                    self?.emitError(FirebaseManagerError.generic(L10n.t("chatvm.error.self_pair")))
                    return
                }

                self?.firebase.updatePartnerID(for: currentUserID, partnerUID: partnerUID) { updateResult in
                    switch updateResult {
                    case .success:
                        self?.state = .waitingForMutualPairing
                        self?.notifyPairingStatus(L10n.t("chatvm.status.waiting_mutual"))
                        self?.schedulePairingTimeout()
                        self?.bindPartner(partnerUID: partnerUID)
                    case .failure(let error):
                        self?.cancelPairingTimeout()
                        self?.state = .unpaired
                        self?.emitError(error)
                    }
                }

            case .failure(let error):
                self?.cancelPairingTimeout()
                self?.state = .unpaired
                self?.emitError(error)
            }
        }
    }

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

    func shareDistance(kilometers: Double) {
        guard isSecureChannelReady else {
            emitError(FirebaseManagerError.generic(L10n.t("chatvm.error.secure_channel_inactive")))
            return
        }

        guard let currentUserID,
              let partnerUserID else {
            emitError(FirebaseManagerError.generic(L10n.t("chatvm.error.pair_before_distance")))
            return
        }

        do {
            let value = String(format: "%.2f", kilometers)
            let encrypted = try encryption.encrypt(Data(value.utf8), for: partnerUserID)
            firebase.updateLocationCiphertext(uid: currentUserID, ciphertext: encrypted) { [weak self] result in
                if case .failure(let error) = result {
                    self?.emitError(error)
                }
            }
            persistWidgetDistance("\(value) km")
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

    private func attachSession(uid: String) {
        if currentUserID != uid {
            resetMessageState(notify: true)
            localArchiveLoadedChatID = nil
        }
        currentUserID = uid
        state = .loading

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

    private func handleOwnProfileChange(_ profile: UserPairProfile) {
        notifyOnMain {
            self.onPairingCodeUpdated?(profile.sixDigitUID)
        }

        let partnerID = profile.partnerID?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let partnerID, !partnerID.isEmpty else {
            if partnerUserID == nil && state == .unpaired {
                return
            }
            invalidateCurrentPairing(notifyUI: true, shouldRouteToPairing: true)
            return
        }

        if partnerUserID != partnerID {
            bindPartner(partnerUID: partnerID)
        } else if state == .unpaired {
            state = .loading
            bindPartner(partnerUID: partnerID)
        }
    }

    private func invalidateCurrentPairing(notifyUI: Bool, shouldRouteToPairing: Bool) {
        let previousState = state
        let previousPartner = partnerUserID
        let hadActivePairing = previousPartner != nil

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

        partnerUserID = nil
        activeChatID = nil
        localArchiveLoadedChatID = nil

        resetMessageState(notify: notifyUI)
        stopLocationSharing(resetDistance: true)
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

    private func handleObserverCancellation(_ error: Error) {
        guard state != .unpaired else { return }
        emitError(error)
        invalidateCurrentPairing(notifyUI: true, shouldRouteToPairing: true)
    }

    private func bindPartner(partnerUID: String) {
        guard let currentUserID else { return }

        if partnerUserID != partnerUID {
            resetMessageState(notify: true)
            activeChatID = nil
            stopLocationSharing(resetDistance: true)
        }
        partnerUserID = partnerUID
        profileObserver?.cancel()

        profileObserver = firebase.observeUserProfile(
            uid: partnerUID,
            onChange: { [weak self] partnerProfile in
                guard let self else { return }

                guard let publicKey = partnerProfile.publicKey else {
                    self.messageObserver?.cancel()
                    self.heartbeatObserver?.cancel()
                    self.messageObserver = nil
                    self.heartbeatObserver = nil
                    self.activeChatID = nil
                    self.localArchiveLoadedChatID = nil
                    self.resetMessageState(notify: true)
                    self.stopLocationSharing(resetDistance: true)
                    self.state = .waitingForMutualPairing
                    self.notifyPairingStatus(L10n.t("chatvm.status.waiting_partner_key"))
                    self.schedulePairingTimeout()
                    return
                }

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
                    self.localArchiveLoadedChatID = nil
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

    private func observeChatIfReady() {
        guard let currentUserID,
              let partnerUserID else { return }

        messageObserver?.cancel()
        heartbeatObserver?.cancel()

        let chatID = FirebaseManager.chatID(for: currentUserID, and: partnerUserID)
        if activeChatID != chatID {
            resetMessageState(notify: true)
            localArchiveLoadedChatID = nil
        }
        activeChatID = chatID

        restoreArchivedConversationIfAvailable(chatID: chatID, currentUserID: currentUserID, partnerUserID: partnerUserID)
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

    private func bootstrapRecentMessagesAndListen(chatID: String, currentUserID: String, partnerUserID: String) {
        let initialLimit = AppConfiguration.ChatPerformance.initialMessageWindow
        firebase.fetchRecentEncryptedMessages(chatID: chatID, limit: initialLimit) { [weak self] result in
            guard let self else { return }
            guard self.activeChatID == chatID else { return }

            switch result {
            case .success(let envelopes):
                self.consumeInitialMessageBatch(envelopes, currentUserID: currentUserID, partnerUserID: partnerUserID)
                let startAt = envelopes.last?.sentAt
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

    private func restoreArchivedConversationIfAvailable(chatID: String, currentUserID: String, partnerUserID: String) {
        guard localArchiveLoadedChatID != chatID else { return }
        localArchiveLoadedChatID = chatID

        do {
            let archivedMessages = try archiveService.loadConversation(currentUID: currentUserID, partnerUID: partnerUserID)
            guard !archivedMessages.isEmpty else { return }

            var inserted = 0
            for message in archivedMessages {
                if appendMessageIfNeeded(message, notify: false) {
                    inserted += 1
                }
            }

            guard inserted > 0 else { return }
            notifyOnMain {
                self.onMessagesUpdated?()
            }
        } catch {
            emitError(FirebaseManagerError.generic(L10n.t("pairing.unpair.error.archive_load_failed")))
        }
    }

    private func observePartnerMoodIfReady() {
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
                    self.emitError(error)
                }
            },
            onCancelled: { [weak self] error in
                self?.handleObserverCancellation(error)
            }
        )
    }

    private func consumeInitialMessageBatch(
        _ envelopes: [EncryptedMessageEnvelope],
        currentUserID: String,
        partnerUserID: String
    ) {
        var inserted = 0
        var latestIncomingValue: String?

        for envelope in envelopes {
            do {
                let message = try decodeMessage(from: envelope, partnerUserID: partnerUserID)
                if appendMessageIfNeeded(message, notify: false) {
                    inserted += 1
                    if envelope.senderID != currentUserID {
                        latestIncomingValue = message.value
                    }
                }
            } catch {
                // Ignore invalid historical payloads to avoid blocking chat load.
            }
        }

        hasReachedHistoryStart = envelopes.count < Int(AppConfiguration.ChatPerformance.initialMessageWindow)

        if let latestIncomingValue {
            persistWidgetLatestMessage(latestIncomingValue)
            LiveActivityManager.shared.update(text: latestIncomingValue, mood: latestPartnerMoodTitle)
        }

        guard inserted > 0 else { return }
        notifyOnMain {
            self.onMessagesUpdated?()
        }
    }

    private func handleIncomingEnvelope(_ envelope: EncryptedMessageEnvelope) {
        guard let currentUserID,
              let partnerUserID else { return }

        do {
            let payload = try decodePayload(from: envelope, partnerUserID: partnerUserID)
            let message = message(from: envelope, payload: payload)

            let inserted = appendMessageIfNeeded(message)

            if inserted && envelope.senderID != currentUserID {
                persistWidgetLatestMessage(payload.value)
                LiveActivityManager.shared.update(text: payload.value, mood: latestPartnerMoodTitle)
            }
        } catch {
            emitError(error)
        }
    }

    private func loadOlderMessages() {
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
        let pageSize = AppConfiguration.ChatPerformance.historyPageSize

        firebase.fetchOlderEncryptedMessages(chatID: chatID, endingAtOrBefore: oldestLoadedSentAt, limit: pageSize) { [weak self] result in
            guard let self else { return }
            guard self.activeChatID == chatID else { return }
            self.isLoadingHistory = false

            switch result {
            case .failure(let error):
                self.emitError(error)

            case .success(let envelopes):
                var inserted = 0
                for envelope in envelopes {
                    do {
                        let message = try self.decodeMessage(from: envelope, partnerUserID: partnerUserID)
                        if self.appendMessageIfNeeded(message, notify: false) {
                            inserted += 1
                        }
                    } catch {
                        continue
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

    private func sendPayload(type: ChatPayloadType, value: String, isSecret: Bool) {
        guard isSecureChannelReady else {
            emitError(FirebaseManagerError.generic(L10n.t("chatvm.error.secure_channel_inactive")))
            return
        }

        guard let currentUserID,
              let partnerUserID else {
            emitError(FirebaseManagerError.generic(L10n.t("chatvm.error.pair_before_message")))
            return
        }

        let payload = ChatPayload(
            type: type,
            value: value,
            isSecret: isSecret,
            sentAt: Date().timeIntervalSince1970
        )

        do {
            let plainData = try jsonEncoder.encode(payload)
            let encryptedPayload = try encryption.encrypt(plainData, for: partnerUserID)

            let envelope = EncryptedMessageEnvelope(
                id: UUID().uuidString,
                senderID: currentUserID,
                recipientID: partnerUserID,
                payload: encryptedPayload,
                sentAt: payload.sentAt
            )

            let optimistic = ChatMessage(
                id: envelope.id,
                senderID: currentUserID,
                recipientID: partnerUserID,
                sentAt: Date(timeIntervalSince1970: payload.sentAt),
                type: payload.type,
                value: payload.value,
                isSecret: payload.isSecret
            )

            appendMessageIfNeeded(optimistic)

            let chatID = FirebaseManager.chatID(for: currentUserID, and: partnerUserID)
            firebase.sendEncryptedMessage(chatID: chatID, envelope: envelope) { [weak self] result in
                if case .failure(let error) = result {
                    self?.emitError(error)
                }
            }

        } catch {
            emitError(error)
        }
    }

    @discardableResult
    private func appendMessageIfNeeded(_ message: ChatMessage, notify: Bool = true) -> Bool {
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

    private func resetMessageState(notify: Bool) {
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
    private func trimMessagesIfNeeded(keepingLast limit: Int) -> Bool {
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

    private func decodeMessage(from envelope: EncryptedMessageEnvelope, partnerUserID: String) throws -> ChatMessage {
        let payload = try decodePayload(from: envelope, partnerUserID: partnerUserID)
        return message(from: envelope, payload: payload)
    }

    private func decodePayload(
        from envelope: EncryptedMessageEnvelope,
        partnerUserID: String
    ) throws -> ChatPayload {
        let decrypted = try encryption.decrypt(envelope.payload, from: partnerUserID)
        return try jsonDecoder.decode(ChatPayload.self, from: decrypted)
    }

    private func message(from envelope: EncryptedMessageEnvelope, payload: ChatPayload) -> ChatMessage {
        ChatMessage(
            id: envelope.id,
            senderID: envelope.senderID,
            recipientID: envelope.recipientID,
            sentAt: Date(timeIntervalSince1970: payload.sentAt),
            type: payload.type,
            value: payload.value,
            isSecret: payload.isSecret
        )
    }

    private func persistWidgetLatestMessage(_ message: String) {
        guard let defaults = UserDefaults(suiteName: AppConfiguration.appGroupIdentifier) else { return }
        defaults.set(message, forKey: AppConfiguration.SharedStoreKey.latestMessage)
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }

    private func persistWidgetMood(_ mood: String) {
        guard let defaults = UserDefaults(suiteName: AppConfiguration.appGroupIdentifier) else { return }
        defaults.set(mood, forKey: AppConfiguration.SharedStoreKey.latestMood)
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }

    private func persistWidgetDistance(_ distance: String) {
        guard let defaults = UserDefaults(suiteName: AppConfiguration.appGroupIdentifier) else { return }
        defaults.set(distance, forKey: AppConfiguration.SharedStoreKey.latestDistance)
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }

    private func handlePartnerLocationCiphertext(_ ciphertext: String?) {
        guard let ciphertext,
              let partnerUserID,
              !ciphertext.isEmpty else {
            notifyOnMain {
                self.onDistanceUpdated?(nil)
            }
            return
        }

        do {
            let decrypted = try encryption.decrypt(ciphertext, from: partnerUserID)

            if let payload = try? jsonDecoder.decode(LocationPayload.self, from: decrypted) {
                let now = Date().timeIntervalSince1970
                if now - payload.sentAt > maxPartnerLocationAge {
                    notifyOnMain {
                        self.onDistanceUpdated?(nil)
                    }
                    return
                }

                // Accept Simulator-provided coordinates as well to support real-device + simulator test pairs.
                locationService.updatePartnerLocation(latitude: payload.latitude, longitude: payload.longitude)
                return
            }

            notifyOnMain {
                self.onDistanceUpdated?(nil)
            }
        } catch {
            emitError(error)
        }
    }

    private func startLocationSharingIfNeeded() {
        guard isSecureChannelReady else {
            stopLocationSharing(resetDistance: true)
            return
        }

        locationService.requestPermissionAndStart()
    }

    private func stopLocationSharing(resetDistance: Bool) {
        locationService.stop()
        locationService.clearPartnerLocation()
        lastUploadedLocation = nil
        lastLocationUploadDate = nil

        guard resetDistance else { return }
        notifyOnMain {
            self.onDistanceUpdated?(nil)
        }
    }

    private func handleOwnLocationUpdate(_ location: CLLocation) {
        didReportLocationPermissionDenied = false
        guard isSecureChannelReady,
              let currentUserID,
              let partnerUserID else {
            return
        }

        guard shouldUpload(location: location) else { return }

        let payload = LocationPayload(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            sentAt: Date().timeIntervalSince1970,
            isSimulated: {
                if #available(iOS 15.0, *) {
                    return location.sourceInformation?.isSimulatedBySoftware
                }
                return nil
            }()
        )

        do {
            let plainData = try jsonEncoder.encode(payload)
            let ciphertext = try encryption.encrypt(plainData, for: partnerUserID)
            firebase.updateLocationCiphertext(uid: currentUserID, ciphertext: ciphertext) { [weak self] result in
                guard let self else { return }
                if case .failure(let error) = result {
                    self.emitError(error)
                }
            }
            lastUploadedLocation = location
            lastLocationUploadDate = Date()
        } catch {
            emitError(error)
        }
    }

    private func shouldUpload(location: CLLocation) -> Bool {
        guard let lastLocation = lastUploadedLocation,
              let lastDate = lastLocationUploadDate else {
            return true
        }

        let movedDistance = location.distance(from: lastLocation)
        if movedDistance >= minimumLocationUploadDistanceMeters {
            return true
        }

        let elapsed = Date().timeIntervalSince(lastDate)
        return elapsed >= minimumLocationUploadInterval
    }

    private func publishDistance(_ kilometers: Double) {
        guard kilometers.isFinite, kilometers >= 0 else { return }

        let formatted = formatDistance(kilometers: kilometers)
        persistWidgetDistance(formatted)
        notifyOnMain {
            self.onDistanceUpdated?(formatted)
        }
    }

    private func formatDistance(kilometers: Double) -> String {
        let numberFormatter = NumberFormatter()
        numberFormatter.locale = Locale.current
        numberFormatter.minimumFractionDigits = 0
        if kilometers < 10 {
            numberFormatter.maximumFractionDigits = 2
        } else if kilometers < 100 {
            numberFormatter.maximumFractionDigits = 1
        } else {
            numberFormatter.maximumFractionDigits = 0
        }

        let measurement = Measurement(value: kilometers, unit: UnitLength.kilometers)
        let formatter = MeasurementFormatter()
        formatter.locale = Locale.current
        formatter.unitOptions = .providedUnit
        formatter.numberFormatter = numberFormatter
        return formatter.string(from: measurement)
    }

    private func emitError(_ error: Error) {
        let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        notifyOnMain {
            self.onError?(message)
        }
    }

    private func stopObservers() {
        ownProfileObserver?.cancel()
        messageObserver?.cancel()
        heartbeatObserver?.cancel()
        profileObserver?.cancel()
        moodObserver?.cancel()
        ownProfileObserver = nil
        messageObserver = nil
        heartbeatObserver = nil
        profileObserver = nil
        moodObserver = nil
        activeChatID = nil
        localArchiveLoadedChatID = nil
        stopLocationSharing(resetDistance: false)
        cancelPairingTimeout()
    }

    private func notifyOnMain(_ block: @escaping () -> Void) {
        if Thread.isMainThread {
            block()
        } else {
            DispatchQueue.main.async(execute: block)
        }
    }

    private var isSecureChannelReady: Bool {
        state == .ready && currentUserID != nil && partnerUserID != nil
    }

    private func notifyPairingStatus(_ message: String) {
        notifyOnMain {
            self.onPairingStatusUpdated?(message)
        }
    }

    private func schedulePairingTimeout() {
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

    private func cancelPairingTimeout() {
        pairingTimeoutWorkItem?.cancel()
        pairingTimeoutWorkItem = nil
    }
}
