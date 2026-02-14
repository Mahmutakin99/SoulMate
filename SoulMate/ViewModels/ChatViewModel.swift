//
//  ChatViewModel.swift
//  SoulMate
//
//  Created by MAHMUT AKIN on 02/02/2026.
//

import Foundation
import CryptoKit
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
    var onIncomingPendingRequestCountChanged: ((Int) -> Void)?
    var onIncomingPendingRequestBadgeChanged: ((IncomingRequestBadgeState) -> Void)?
    var onMessageMetaUpdated: ((Set<String>) -> Void)?

    var messages: [ChatMessage] = []
    var state: ScreenState = .idle {
        didSet { notifyOnMain { self.onStateChanged?(self.state) } }
    }

    let firebase: FirebaseManager
    let encryption: EncryptionService
    let locationService: LocationSharingService
    let localMessageStore: LocalMessageStore
    let reactionUsageStore: ReactionUsageStore
    let jsonEncoder = JSONEncoder()
    let jsonDecoder = JSONDecoder()

    var currentUserID: String?
    var partnerUserID: String?
    var latestPartnerMoodTitle = L10n.t("mood.unknown")

    var messageObserver: FirebaseObservationToken?
    var heartbeatObserver: FirebaseObservationToken?
    var messageReceiptsObserver: FirebaseObservationToken?
    var messageReactionsObserver: FirebaseObservationToken?
    var ownProfileObserver: FirebaseObservationToken?
    var incomingRequestsObserver: FirebaseObservationToken?
    var profileObserver: FirebaseObservationToken?
    var moodObserver: FirebaseObservationToken?
    var pairingTimeoutWorkItem: DispatchWorkItem?
    var observerRebindWorkItem: DispatchWorkItem?
    var loadedMessageIDs: Set<String> = []
    var oldestLoadedSentAt: TimeInterval?
    var isLoadingHistory = false
    var hasReachedHistoryStart = false
    var activeChatID: String?
    var messageMetaByID: [String: ChatMessageMeta] = [:]
    var messageReceiptsByID: [String: MessageReceipt] = [:]
    var messageReactionsByMessageID: [String: [MessageReaction]] = [:]
    var outgoingUploadStateByMessageID: [String: LocalMessageUploadState] = [:]
    var pendingReadReceiptMessageIDs = Set<String>()
    var readReceiptWorkItem: DispatchWorkItem?
    var lastUploadedLocation: CLLocation?
    var lastLocationUploadDate: Date?
    var didReportLocationPermissionDenied = false
    var hasLoggedUnreadablePayloadWarning = false
    var latestPartnerPublicKey: String?
    var isAttemptingSharedKeyRecovery = false
    let errorThrottleWindow: TimeInterval = 5
    let errorThrottleLock = NSLock()
    var lastErrorEmissionByKey: [String: Date] = [:]
    let minimumLocationUploadDistanceMeters: CLLocationDistance = 35
    let minimumLocationUploadInterval: TimeInterval = 25
    let maxPartnerLocationAge: TimeInterval = 300
    let pairingTimeoutSeconds: TimeInterval = 10
    var widgetRefreshWorkItem: DispatchWorkItem?
    lazy var messageSyncService = MessageSyncService(
        firebase: firebase,
        encryption: encryption,
        localStore: localMessageStore
    )

    lazy var cachedNumberFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.locale = Locale.current
        formatter.minimumFractionDigits = 0
        return formatter
    }()

    lazy var cachedMeasurementFormatter: MeasurementFormatter = {
        let formatter = MeasurementFormatter()
        formatter.locale = Locale.current
        formatter.unitOptions = .providedUnit
        return formatter
    }()

    struct LocationPayload: Codable {
        let latitude: Double
        let longitude: Double
        let sentAt: TimeInterval
        let isSimulated: Bool?
    }

    init(
        firebase: FirebaseManager = .shared,
        encryption: EncryptionService = .shared,
        locationService: LocationSharingService = LocationSharingService(),
        localMessageStore: LocalMessageStore = .shared,
        reactionUsageStore: ReactionUsageStore = .shared
    ) {
        self.firebase = firebase
        self.encryption = encryption
        self.locationService = locationService
        self.localMessageStore = localMessageStore
        self.reactionUsageStore = reactionUsageStore

        self.messageSyncService.onError = { [weak self] error in
            self?.handleMessageSyncError(error)
        }

        self.messageSyncService.onOutgoingUploadStateChanged = { [weak self] messageID, uploadState in
            guard let self else { return }
            self.notifyOnMain {
                self.outgoingUploadStateByMessageID[messageID] = uploadState
                self.rebuildMessageMetadata(for: [messageID], notify: true)
            }
        }

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
}
