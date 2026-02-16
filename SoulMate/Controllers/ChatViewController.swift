//
//  ChatViewController.swift
//  SoulMate
//
//  Created by MAHMUT AKIN on 02/02/2026.
//

import UIKit
#if canImport(SDWebImage)
import SDWebImage
#endif

enum HeartbeatTempoPreference: Int, CaseIterable {
    case calm = 0
    case medium = 1
    case high = 2

    var cycleInterval: TimeInterval {
        switch self {
        case .calm:
            return 60.0 / 66.0
        case .medium:
            return 60.0 / 84.0
        case .high:
            return 60.0 / 108.0
        }
    }

    var title: String {
        if Locale.preferredLanguages.first?.lowercased().hasPrefix("tr") == true {
            switch self {
            case .calm:
                return "Sakin"
            case .medium:
                return "Orta"
            case .high:
                return "Yüksek"
            }
        }

        switch self {
        case .calm:
            return "Calm"
        case .medium:
            return "Medium"
        case .high:
            return "High"
        }
    }
}

enum HeartbeatIntensityPreference: Int, CaseIterable {
    case low = 0
    case medium = 1
    case high = 2

    var primaryImpact: CGFloat {
        switch self {
        case .low:
            return 0.45
        case .medium:
            return 0.7
        case .high:
            return 1.0
        }
    }

    var secondaryImpact: CGFloat {
        switch self {
        case .low:
            return 0.3
        case .medium:
            return 0.52
        case .high:
            return 0.8
        }
    }

    var title: String {
        if Locale.preferredLanguages.first?.lowercased().hasPrefix("tr") == true {
            switch self {
            case .low:
                return "Düşük"
            case .medium:
                return "Orta"
            case .high:
                return "Yüksek"
            }
        }

        switch self {
        case .low:
            return "Low"
        case .medium:
            return "Medium"
        case .high:
            return "High"
        }
    }
}

final class ChatViewController: UIViewController {
    var onRequestPairingManagement: (() -> Void)?
    var onRequestProfileManagement: (() -> Void)?
    var onRequirePairing: (() -> Void)?
    static let quickEmojiVisibilityPreferenceKey = "chat.quick_emoji_visible"
    static let revealedSecretMessagesPreferenceKey = "chat.revealed_secret_message_ids"
    static let inputBottomInsetKeyboardVisible: CGFloat = -6 // input alanı yükseklik
    static let inputBottomInsetKeyboardHidden: CGFloat = 20

    let viewModel: ChatViewModel

    let gradientLayer = CAGradientLayer()
    let moodTitleLabel = UILabel()
    let moodScrollView = UIScrollView()
    let moodStack = UIStackView()
    let moodSectionContainer = UIView()
    var moodButtons: [UIButton] = []
    var selectedMoodIndex: Int?

    let tableContainer = UIView()
    let tableView = UITableView(frame: .zero, style: .plain)
    let emptyStateLabel = UILabel()
    var tableMinHeightConstraint: NSLayoutConstraint!

    let emojiContainer = UIView()
    let emojiScrollView = UIScrollView()
    let emojiStack = UIStackView()
    var emojiButtons: [UIButton] = []
    var emojiContainerHeightConstraint: NSLayoutConstraint!
    var inputTopToEmojiConstraint: NSLayoutConstraint!
    var inputTopToTableConstraint: NSLayoutConstraint!
    var inputBottomConstraint: NSLayoutConstraint!
    var isQuickEmojiVisible = UserDefaults.standard.object(
        forKey: ChatViewController.quickEmojiVisibilityPreferenceKey
    ) as? Bool ?? true

    let inputContainer = UIView()
    let messageTextField = UITextField()
    let secretSwitch = UISwitch()
    let secretLabel = UILabel()
    let composerSendButton = UIButton(type: .system)
    let emojiToggleButton = UIButton(type: .system)
    let heartButton = UIButton(type: .system)

    let heartbeatToast = UILabel()
    let accountButtonContainer = UIView()
    let accountButton = UIButton(type: .system)
    let accountBadgeLabel = UILabel()
    let detailsButtonContainer = UIView()
    let detailsButton = UIButton(type: .system)
    let detailsDimView = UIControl()
    let detailsDrawerView = UIView()
    let detailsTitleLabel = UILabel()
    let detailsStack = UIStackView()
    let secureInfoRow = UIView()
    let pairInfoRow = UIView()
    let distanceInfoRow = UIView()
    let partnerMoodInfoRow = UIView()
    let splashPreferenceRow = UIView()
    let heartbeatTempoRow = UIView()
    let heartbeatIntensityRow = UIView()
    let secureStatusTitleLabel = UILabel()
    let secureStatusValueLabel = UILabel()
    let pairStatusTitleLabel = UILabel()
    let pairStatusValueLabel = UILabel()
    let distanceTitleLabel = UILabel()
    let distanceValueLabel = UILabel()
    let partnerMoodTitleLabel = UILabel()
    let partnerMoodValueLabel = UILabel()
    let splashPreferenceTitleLabel = UILabel()
    let splashPreferenceSwitch = UISwitch()
    let heartbeatTempoTitleLabel = UILabel()
    let heartbeatIntensityTitleLabel = UILabel()
    lazy var heartbeatTempoControl = UISegmentedControl(items: HeartbeatTempoPreference.allCases.map(\.title))
    lazy var heartbeatIntensityControl = UISegmentedControl(items: HeartbeatIntensityPreference.allCases.map(\.title))
    var detailsDrawerTrailingConstraint: NSLayoutConstraint!
    let detailsDrawerWidth: CGFloat = 274
    var isDetailsDrawerOpen = false

    var pendingErrorMessage: String?
    var isVisible = false
    let minimumGIFVisibleRatio: CGFloat = 0.65

    var lastRenderedState: ChatViewModel.ScreenState = .idle
    var hasTriggeredPairingRedirect = false
    var pairingStatusMessage: String?
    var latestDistanceDisplayValue = "--"
    var latestPartnerMoodValue = L10n.t("chat.sidebar.value.unknown")
    var isKeyboardModeActive = false
    var revealedSecretMessageIDs = Set(
        UserDefaults.standard.stringArray(forKey: ChatViewController.revealedSecretMessagesPreferenceKey) ?? []
    )
    var memoryWarningObserver: NSObjectProtocol?
    var showsSplashOnLaunch = UserDefaults.standard.object(
        forKey: AppConfiguration.UserPreferenceKey.showsSplashOnLaunch
    ) as? Bool ?? true
    var needsDeferredMessageReload = false
    var previousMessageCount = 0
    var previousLastMessageID: String?
    var gifPlaybackUpdateWorkItem: DispatchWorkItem?
    var incomingRequestBadgeState: IncomingRequestBadgeState = .empty
    var hasInitializedRequestIndicator = false
    var reactionPickerOverlay: UIControl?
    var reactionQuickPickerView: ReactionQuickPickerView?
    var activeReactionMessageID: String?
    var heartbeatTempoPreference: HeartbeatTempoPreference = {
        let rawValue = UserDefaults.standard.object(forKey: AppConfiguration.UserPreferenceKey.heartbeatTempoPreset) as? Int
        return HeartbeatTempoPreference(rawValue: rawValue ?? HeartbeatTempoPreference.calm.rawValue) ?? .calm
    }()
    var heartbeatIntensityPreference: HeartbeatIntensityPreference = {
        let rawValue = UserDefaults.standard.object(forKey: AppConfiguration.UserPreferenceKey.heartbeatIntensityPreset) as? Int
        return HeartbeatIntensityPreference(rawValue: rawValue ?? HeartbeatIntensityPreference.medium.rawValue) ?? .medium
    }()
    var heartbeatLoopTimer: Timer?
    var heartbeatHoldTimeoutWorkItem: DispatchWorkItem?
    var lastHeartbeatSendAt: Date?
    var isHeartbeatHoldActive = false
    var suppressHeartTapUntilNextRunLoop = false

    var theme: ChatTheme!
    lazy var dismissKeyboardTapGesture = UITapGestureRecognizer(target: self, action: #selector(handleBackgroundTap))

    init(viewModel: ChatViewModel = ChatViewModel()) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        if let memoryWarningObserver {
            NotificationCenter.default.removeObserver(memoryWarningObserver)
        }
        gifPlaybackUpdateWorkItem?.cancel()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        theme = ChatTheme.current(for: traitCollection)

        configureNavigationBar()
        setupBackground()
        setupUI()
        configureKeyboardDismissal()
        configureMemoryWarningObserver()
        registerForThemeChanges()
        bindViewModel()
        applyTheme()

        viewModel.start()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        isVisible = true
        updateVisibleGIFPlayback(isEnabled: true)

        if needsDeferredMessageReload {
            needsDeferredMessageReload = false
            tableView.reloadData()
            updateEmptyStateVisibility()
            scrollToBottom(animated: false)
            previousMessageCount = viewModel.numberOfMessages()
            previousLastMessageID = previousMessageCount > 0 ? viewModel.message(at: previousMessageCount - 1).id : nil
            scheduleVisibleGIFPlaybackUpdate(isEnabled: !(tableView.isDragging || tableView.isDecelerating), delay: 0.08)
        }

        if let pendingErrorMessage {
            self.pendingErrorMessage = nil
            presentError(pendingErrorMessage)
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        isVisible = false
        gifPlaybackUpdateWorkItem?.cancel()
        updateVisibleGIFPlayback(isEnabled: false)
        stopHeartbeatHoldSession()
        dismissReactionQuickPicker()
        setDetailsDrawerVisibility(false, animated: false)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        gradientLayer.frame = view.bounds
    }
}
