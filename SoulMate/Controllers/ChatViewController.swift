//
//  AuthViewController.swift
//  SoulMate
//
//  Created by MAHMUT AKIN on 02/02/2026.
//

import UIKit
#if canImport(GiphyUISDK)
import GiphyUISDK
#endif
#if canImport(SDWebImage)
import SDWebImage
#endif

final class ChatViewController: UIViewController {
    var onRequestPairingManagement: (() -> Void)?
    var onRequestSignOut: (() -> Void)?
    var onRequirePairing: (() -> Void)?
    static let quickEmojiVisibilityPreferenceKey = "chat.quick_emoji_visible"
    static let revealedSecretMessagesPreferenceKey = "chat.revealed_secret_message_ids"

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
    var isQuickEmojiVisible = UserDefaults.standard.object(
        forKey: ChatViewController.quickEmojiVisibilityPreferenceKey
    ) as? Bool ?? true

    let inputContainer = UIView()
    let messageTextField = UITextField()
    let secretSwitch = UISwitch()
    let secretLabel = UILabel()
    let composerSendButton = UIButton(type: .system)
    let gifButton = UIButton(type: .system)
    let emojiToggleButton = UIButton(type: .system)
    let heartButton = UIButton(type: .system)

    let heartbeatToast = UILabel()
    let accountButtonContainer = UIView()
    let accountButton = UIButton(type: .system)
    let accountBadgeLabel = UILabel()
    let detailsDimView = UIControl()
    let detailsDrawerView = UIView()
    let detailsTitleLabel = UILabel()
    let detailsStack = UIStackView()
    let secureInfoRow = UIView()
    let pairInfoRow = UIView()
    let distanceInfoRow = UIView()
    let partnerMoodInfoRow = UIView()
    let splashPreferenceRow = UIView()
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
        setDetailsDrawerVisibility(false, animated: false)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        gradientLayer.frame = view.bounds
    }
}
