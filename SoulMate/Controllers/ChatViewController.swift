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
    private static let quickEmojiVisibilityPreferenceKey = "chat.quick_emoji_visible"
    private static let revealedSecretMessagesPreferenceKey = "chat.revealed_secret_message_ids"

    private let viewModel: ChatViewModel

    private let gradientLayer = CAGradientLayer()
    private let moodTitleLabel = UILabel()
    private let moodScrollView = UIScrollView()
    private let moodStack = UIStackView()
    private let moodSectionContainer = UIView()
    private var moodButtons: [UIButton] = []
    private var selectedMoodIndex: Int?

    private let tableContainer = UIView()
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let emptyStateLabel = UILabel()
    private var tableMinHeightConstraint: NSLayoutConstraint!

    private let emojiContainer = UIView()
    private let emojiScrollView = UIScrollView()
    private let emojiStack = UIStackView()
    private var emojiButtons: [UIButton] = []
    private var emojiContainerHeightConstraint: NSLayoutConstraint!
    private var inputTopToEmojiConstraint: NSLayoutConstraint!
    private var inputTopToTableConstraint: NSLayoutConstraint!
    private var isQuickEmojiVisible = UserDefaults.standard.object(
        forKey: ChatViewController.quickEmojiVisibilityPreferenceKey
    ) as? Bool ?? true

    private let inputContainer = UIView()
    private let messageTextField = UITextField()
    private let secretSwitch = UISwitch()
    private let secretLabel = UILabel()
    private let composerSendButton = UIButton(type: .system)
    private let gifButton = UIButton(type: .system)
    private let emojiToggleButton = UIButton(type: .system)
    private let heartButton = UIButton(type: .system)

    private let heartbeatToast = UILabel()
    private let detailsDimView = UIControl()
    private let detailsDrawerView = UIView()
    private let detailsTitleLabel = UILabel()
    private let detailsStack = UIStackView()
    private let secureInfoRow = UIView()
    private let pairInfoRow = UIView()
    private let distanceInfoRow = UIView()
    private let partnerMoodInfoRow = UIView()
    private let splashPreferenceRow = UIView()
    private let secureStatusTitleLabel = UILabel()
    private let secureStatusValueLabel = UILabel()
    private let pairStatusTitleLabel = UILabel()
    private let pairStatusValueLabel = UILabel()
    private let distanceTitleLabel = UILabel()
    private let distanceValueLabel = UILabel()
    private let partnerMoodTitleLabel = UILabel()
    private let partnerMoodValueLabel = UILabel()
    private let splashPreferenceTitleLabel = UILabel()
    private let splashPreferenceSwitch = UISwitch()
    private var detailsDrawerTrailingConstraint: NSLayoutConstraint!
    private let detailsDrawerWidth: CGFloat = 274
    private var isDetailsDrawerOpen = false

    private var pendingErrorMessage: String?
    private var isVisible = false
    private let minimumGIFVisibleRatio: CGFloat = 0.65

    private var lastRenderedState: ChatViewModel.ScreenState = .idle
    private var hasTriggeredPairingRedirect = false
    private var pairingStatusMessage: String?
    private var latestDistanceDisplayValue = "--"
    private var latestPartnerMoodValue = L10n.t("chat.sidebar.value.unknown")
    private var isKeyboardModeActive = false
    private var revealedSecretMessageIDs = Set(
        UserDefaults.standard.stringArray(forKey: ChatViewController.revealedSecretMessagesPreferenceKey) ?? []
    )
    private var memoryWarningObserver: NSObjectProtocol?
    private var showsSplashOnLaunch = UserDefaults.standard.object(
        forKey: AppConfiguration.UserPreferenceKey.showsSplashOnLaunch
    ) as? Bool ?? true
    private var needsDeferredMessageReload = false

    private var theme: ChatTheme!
    private lazy var dismissKeyboardTapGesture = UITapGestureRecognizer(target: self, action: #selector(handleBackgroundTap))

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
            updateVisibleGIFPlayback(isEnabled: !(tableView.isDragging || tableView.isDecelerating))
        }

        if let pendingErrorMessage {
            self.pendingErrorMessage = nil
            presentError(pendingErrorMessage)
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        isVisible = false
        updateVisibleGIFPlayback(isEnabled: false)
        setDetailsDrawerVisibility(false, animated: false)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        gradientLayer.frame = view.bounds
    }

    private func configureNavigationBar() {
        title = L10n.t("chat.nav_title")

        let appearance = UINavigationBarAppearance()
        appearance.configureWithTransparentBackground()
        appearance.titleTextAttributes = [
            .font: UIFont(name: "AvenirNext-Bold", size: 34) ?? UIFont.systemFont(ofSize: 34, weight: .bold),
            .foregroundColor: theme.title
        ]

        navigationController?.navigationBar.standardAppearance = appearance
        navigationController?.navigationBar.scrollEdgeAppearance = appearance
        navigationController?.navigationBar.tintColor = theme.accent

        let pairingAction = UIAction(
            title: L10n.t("chat.menu.pairing_management"),
            image: UIImage(systemName: "link")
        ) { [weak self] _ in
            self?.onRequestPairingManagement?()
        }

        let signOutAction = UIAction(
            title: L10n.t("chat.menu.sign_out"),
            image: UIImage(systemName: "rectangle.portrait.and.arrow.right"),
            attributes: .destructive
        ) { [weak self] _ in
            self?.onRequestSignOut?()
        }

        let menu = UIMenu(title: "", children: [pairingAction, signOutAction])
        let accountItem = UIBarButtonItem(
            image: UIImage(systemName: "person.crop.circle"),
            primaryAction: nil,
            menu: menu
        )
        let detailsItem = UIBarButtonItem(
            image: UIImage(systemName: "sidebar.right"),
            style: .plain,
            target: self,
            action: #selector(detailsButtonTapped)
        )
        navigationItem.rightBarButtonItems = [accountItem, detailsItem]
    }

    private func setupBackground() {
        view.backgroundColor = .systemBackground
        gradientLayer.startPoint = CGPoint(x: 0, y: 0)
        gradientLayer.endPoint = CGPoint(x: 1, y: 1)
        view.layer.insertSublayer(gradientLayer, at: 0)
    }

    private func setupUI() {
        setupTableSection()
        setupEmojiSection()
        setupInputSection()
        setupHeartbeatToast()
        setupDetailsSidebar()
        layoutMainSections()
    }

    private func setupTableSection() {
        tableContainer.layer.cornerRadius = 24
        tableContainer.layer.cornerCurve = .continuous
        tableContainer.layer.borderWidth = 1
        tableContainer.translatesAutoresizingMaskIntoConstraints = false

        tableView.register(ChatMessageCell.self, forCellReuseIdentifier: ChatMessageCell.reuseIdentifier)
        tableView.dataSource = self
        tableView.delegate = self
        tableView.separatorStyle = .none
        tableView.backgroundColor = .clear
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 96
        tableView.keyboardDismissMode = .interactive
        tableView.translatesAutoresizingMaskIntoConstraints = false

        emptyStateLabel.text = L10n.t("chat.empty.pair_first")
        emptyStateLabel.numberOfLines = 0
        emptyStateLabel.textAlignment = .center
        emptyStateLabel.font = UIFont(name: "AvenirNext-Medium", size: 16) ?? .systemFont(ofSize: 16, weight: .medium)
        emptyStateLabel.translatesAutoresizingMaskIntoConstraints = false

        tableContainer.addSubview(tableView)
        tableContainer.addSubview(emptyStateLabel)
        view.addSubview(tableContainer)

        tableMinHeightConstraint = tableContainer.heightAnchor.constraint(greaterThanOrEqualToConstant: 220)
        tableMinHeightConstraint.priority = .defaultHigh

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: tableContainer.topAnchor, constant: 8),
            tableView.bottomAnchor.constraint(equalTo: tableContainer.bottomAnchor, constant: -8),
            tableView.leadingAnchor.constraint(equalTo: tableContainer.leadingAnchor, constant: 6),
            tableView.trailingAnchor.constraint(equalTo: tableContainer.trailingAnchor, constant: -6),

            emptyStateLabel.centerXAnchor.constraint(equalTo: tableContainer.centerXAnchor),
            emptyStateLabel.centerYAnchor.constraint(equalTo: tableContainer.centerYAnchor),
            emptyStateLabel.leadingAnchor.constraint(equalTo: tableContainer.leadingAnchor, constant: 28),
            emptyStateLabel.trailingAnchor.constraint(equalTo: tableContainer.trailingAnchor, constant: -28),
            tableMinHeightConstraint
        ])
    }

    private func setupEmojiSection() {
        emojiContainer.layer.cornerRadius = 18
        emojiContainer.layer.cornerCurve = .continuous
        emojiContainer.translatesAutoresizingMaskIntoConstraints = false

        emojiScrollView.showsHorizontalScrollIndicator = false
        emojiScrollView.translatesAutoresizingMaskIntoConstraints = false

        emojiStack.axis = .horizontal
        emojiStack.spacing = 10
        emojiStack.translatesAutoresizingMaskIntoConstraints = false

        emojiScrollView.addSubview(emojiStack)
        emojiContainer.addSubview(emojiScrollView)
        view.addSubview(emojiContainer)

        ["🥰", "😘", "😍", "❤️", "🤍", "🔥", "🫶", "😂", "😅", "🤣"].forEach { emoji in
            let button = UIButton(type: .system)

            var configuration = UIButton.Configuration.plain()
            var titleAttributes = AttributeContainer()
            titleAttributes.font = UIFont.systemFont(ofSize: 26)
            configuration.attributedTitle = AttributedString(emoji, attributes: titleAttributes)
            configuration.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8)
            button.configuration = configuration

            button.layer.cornerRadius = 14
            button.layer.cornerCurve = .continuous
            button.addAction(UIAction(handler: { [weak self] _ in
                self?.viewModel.sendEmoji(emoji)
            }), for: .touchUpInside)

            emojiButtons.append(button)
            emojiStack.addArrangedSubview(button)
        }

        NSLayoutConstraint.activate([
            emojiScrollView.topAnchor.constraint(equalTo: emojiContainer.topAnchor),
            emojiScrollView.bottomAnchor.constraint(equalTo: emojiContainer.bottomAnchor),
            emojiScrollView.leadingAnchor.constraint(equalTo: emojiContainer.leadingAnchor, constant: 10),
            emojiScrollView.trailingAnchor.constraint(equalTo: emojiContainer.trailingAnchor, constant: -10),

            emojiStack.leadingAnchor.constraint(equalTo: emojiScrollView.contentLayoutGuide.leadingAnchor),
            emojiStack.trailingAnchor.constraint(equalTo: emojiScrollView.contentLayoutGuide.trailingAnchor),
            emojiStack.centerYAnchor.constraint(equalTo: emojiScrollView.frameLayoutGuide.centerYAnchor)
        ])
    }

    private func setupInputSection() {
        inputContainer.layer.cornerRadius = 22
        inputContainer.layer.cornerCurve = .continuous
        inputContainer.translatesAutoresizingMaskIntoConstraints = false

        messageTextField.placeholder = L10n.t("chat.input.placeholder")
        messageTextField.borderStyle = .none
        messageTextField.layer.cornerRadius = 14
        messageTextField.layer.cornerCurve = .continuous
        messageTextField.layer.borderWidth = 1
        messageTextField.font = UIFont(name: "AvenirNext-Regular", size: 17) ?? .systemFont(ofSize: 17)
        messageTextField.returnKeyType = .send
        messageTextField.delegate = self
        messageTextField.addTarget(self, action: #selector(messageEditingDidBegin), for: .editingDidBegin)
        messageTextField.addTarget(self, action: #selector(messageEditingDidEnd), for: .editingDidEnd)
        messageTextField.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 12, height: 1))
        messageTextField.leftViewMode = .always
        messageTextField.translatesAutoresizingMaskIntoConstraints = false

        secretLabel.text = L10n.t("chat.label.secret")
        secretLabel.font = UIFont(name: "AvenirNext-DemiBold", size: 14) ?? .systemFont(ofSize: 14, weight: .semibold)
        secretLabel.translatesAutoresizingMaskIntoConstraints = false

        secretSwitch.translatesAutoresizingMaskIntoConstraints = false

        composerSendButton.translatesAutoresizingMaskIntoConstraints = false
        composerSendButton.addTarget(self, action: #selector(sendButtonTapped), for: .touchUpInside)

        gifButton.addTarget(self, action: #selector(gifButtonTapped), for: .touchUpInside)
        emojiToggleButton.addTarget(self, action: #selector(emojiToggleTapped), for: .touchUpInside)

        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(heartLongPress(_:)))
        heartButton.addGestureRecognizer(longPress)

        let composerRow = UIStackView(arrangedSubviews: [messageTextField, composerSendButton])
        composerRow.axis = .horizontal
        composerRow.alignment = .center
        composerRow.spacing = 8
        composerRow.translatesAutoresizingMaskIntoConstraints = false

        let controlsRow = UIStackView(arrangedSubviews: [secretLabel, secretSwitch, gifButton, emojiToggleButton, heartButton])
        controlsRow.axis = .horizontal
        controlsRow.alignment = .center
        controlsRow.spacing = 10
        controlsRow.translatesAutoresizingMaskIntoConstraints = false

        inputContainer.addSubview(composerRow)
        inputContainer.addSubview(controlsRow)
        view.addSubview(inputContainer)

        NSLayoutConstraint.activate([
            composerRow.topAnchor.constraint(equalTo: inputContainer.topAnchor, constant: 12),
            composerRow.leadingAnchor.constraint(equalTo: inputContainer.leadingAnchor, constant: 12),
            composerRow.trailingAnchor.constraint(equalTo: inputContainer.trailingAnchor, constant: -12),

            messageTextField.heightAnchor.constraint(equalToConstant: 46),
            composerSendButton.widthAnchor.constraint(equalToConstant: 36),
            composerSendButton.heightAnchor.constraint(equalToConstant: 36),

            controlsRow.topAnchor.constraint(equalTo: composerRow.bottomAnchor, constant: 10),
            controlsRow.leadingAnchor.constraint(equalTo: inputContainer.leadingAnchor, constant: 12),
            controlsRow.trailingAnchor.constraint(lessThanOrEqualTo: inputContainer.trailingAnchor, constant: -12),
            controlsRow.bottomAnchor.constraint(equalTo: inputContainer.bottomAnchor, constant: -12)
        ])
    }

    private func setupHeartbeatToast() {
        heartbeatToast.text = L10n.t("chat.toast.heartbeat_received")
        heartbeatToast.font = UIFont(name: "AvenirNext-DemiBold", size: 13) ?? .systemFont(ofSize: 13, weight: .semibold)
        heartbeatToast.layer.cornerRadius = 12
        heartbeatToast.layer.masksToBounds = true
        heartbeatToast.textAlignment = .center
        heartbeatToast.alpha = 0
        heartbeatToast.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(heartbeatToast)

        NSLayoutConstraint.activate([
            heartbeatToast.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            heartbeatToast.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            heartbeatToast.widthAnchor.constraint(equalToConstant: 176),
            heartbeatToast.heightAnchor.constraint(equalToConstant: 30)
        ])
    }

    private func setupDetailsSidebar() {
        detailsDimView.alpha = 0
        detailsDimView.isHidden = true
        detailsDimView.addTarget(self, action: #selector(closeDetailsDrawer), for: .touchUpInside)
        detailsDimView.translatesAutoresizingMaskIntoConstraints = false

        detailsDrawerView.layer.cornerRadius = 20
        detailsDrawerView.layer.cornerCurve = .continuous
        detailsDrawerView.translatesAutoresizingMaskIntoConstraints = false

        detailsTitleLabel.text = L10n.t("chat.sidebar.title")
        detailsTitleLabel.font = UIFont(name: "AvenirNext-Bold", size: 16) ?? .systemFont(ofSize: 16, weight: .bold)
        detailsTitleLabel.translatesAutoresizingMaskIntoConstraints = false

        detailsStack.axis = .vertical
        detailsStack.spacing = 10
        detailsStack.translatesAutoresizingMaskIntoConstraints = false

        setupDetailsRow(
            container: secureInfoRow,
            titleLabel: secureStatusTitleLabel,
            valueLabel: secureStatusValueLabel,
            titleKey: "chat.sidebar.item.secure_channel"
        )
        setupDetailsRow(
            container: pairInfoRow,
            titleLabel: pairStatusTitleLabel,
            valueLabel: pairStatusValueLabel,
            titleKey: "chat.sidebar.item.pair_status"
        )
        setupDetailsRow(
            container: distanceInfoRow,
            titleLabel: distanceTitleLabel,
            valueLabel: distanceValueLabel,
            titleKey: "chat.sidebar.item.distance"
        )
        setupDetailsRow(
            container: partnerMoodInfoRow,
            titleLabel: partnerMoodTitleLabel,
            valueLabel: partnerMoodValueLabel,
            titleKey: "chat.sidebar.item.partner_mood"
        )
        setupSplashPreferenceRow()
        setupMoodSectionForSidebar()

        detailsStack.addArrangedSubview(secureInfoRow)
        detailsStack.addArrangedSubview(pairInfoRow)
        detailsStack.addArrangedSubview(distanceInfoRow)
        detailsStack.addArrangedSubview(partnerMoodInfoRow)
        detailsStack.addArrangedSubview(splashPreferenceRow)
        detailsStack.addArrangedSubview(moodSectionContainer)

        secureStatusValueLabel.text = L10n.t("chat.sidebar.value.inactive")
        pairStatusValueLabel.text = L10n.t("chat.sidebar.value.unpaired")
        distanceValueLabel.text = latestDistanceDisplayValue
        partnerMoodValueLabel.text = latestPartnerMoodValue

        detailsDrawerView.addSubview(detailsTitleLabel)
        detailsDrawerView.addSubview(detailsStack)
        view.addSubview(detailsDimView)
        view.addSubview(detailsDrawerView)

        detailsDrawerTrailingConstraint = detailsDrawerView.trailingAnchor.constraint(
            equalTo: view.trailingAnchor,
            constant: detailsDrawerWidth + 20
        )

        NSLayoutConstraint.activate([
            detailsDimView.topAnchor.constraint(equalTo: view.topAnchor),
            detailsDimView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            detailsDimView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            detailsDimView.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            detailsDrawerView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 10),
            detailsDrawerView.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor, constant: -10),
            detailsDrawerView.widthAnchor.constraint(equalToConstant: detailsDrawerWidth),
            detailsDrawerTrailingConstraint,

            detailsTitleLabel.topAnchor.constraint(equalTo: detailsDrawerView.topAnchor, constant: 14),
            detailsTitleLabel.leadingAnchor.constraint(equalTo: detailsDrawerView.leadingAnchor, constant: 14),
            detailsTitleLabel.trailingAnchor.constraint(equalTo: detailsDrawerView.trailingAnchor, constant: -14),

            detailsStack.topAnchor.constraint(equalTo: detailsTitleLabel.bottomAnchor, constant: 12),
            detailsStack.leadingAnchor.constraint(equalTo: detailsDrawerView.leadingAnchor, constant: 12),
            detailsStack.trailingAnchor.constraint(equalTo: detailsDrawerView.trailingAnchor, constant: -12),
            detailsStack.bottomAnchor.constraint(lessThanOrEqualTo: detailsDrawerView.bottomAnchor, constant: -12)
        ])
    }

    private func layoutMainSections() {
        emojiContainerHeightConstraint = emojiContainer.heightAnchor.constraint(equalToConstant: 52)
        inputTopToEmojiConstraint = inputContainer.topAnchor.constraint(equalTo: emojiContainer.bottomAnchor, constant: 8)
        inputTopToTableConstraint = inputContainer.topAnchor.constraint(equalTo: tableContainer.bottomAnchor, constant: 8)

        NSLayoutConstraint.activate([
            tableContainer.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            tableContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            tableContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),

            emojiContainer.topAnchor.constraint(equalTo: tableContainer.bottomAnchor, constant: 10),
            emojiContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            emojiContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            emojiContainerHeightConstraint,

            inputContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            inputContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            inputContainer.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor, constant: -8)
        ])

        inputTopToEmojiConstraint.isActive = isQuickEmojiVisible
        inputTopToTableConstraint.isActive = !isQuickEmojiVisible
        emojiContainerHeightConstraint.constant = isQuickEmojiVisible ? 52 : 0
        emojiContainer.isHidden = !isQuickEmojiVisible
        emojiContainer.alpha = isQuickEmojiVisible ? 1 : 0
    }

    private func bindViewModel() {
        viewModel.onStateChanged = { [weak self] state in
            self?.render(state: state)
        }

        viewModel.onPairingInvalidated = { [weak self] in
            guard let self else { return }
            guard self.viewIfLoaded?.window != nil else { return }
            guard !self.hasTriggeredPairingRedirect else { return }
            self.hasTriggeredPairingRedirect = true
            self.onRequirePairing?()
        }

        viewModel.onMessagesUpdated = { [weak self] in
            guard let self else { return }
            guard self.isViewLoaded, self.view.window != nil else {
                self.needsDeferredMessageReload = true
                return
            }

            self.tableView.reloadData()
            self.updateEmptyStateVisibility()
            self.scrollToBottom(animated: true)
            self.updateVisibleGIFPlayback(isEnabled: !(self.tableView.isDragging || self.tableView.isDecelerating))
        }

        viewModel.onMessagesPrepended = { [weak self] _ in
            guard let self else { return }
            guard self.isViewLoaded, self.view.window != nil else {
                self.needsDeferredMessageReload = true
                return
            }
            self.prependMessagesAndPreservePosition()
        }

        viewModel.onPairingStatusUpdated = { [weak self] message in
            self?.pairingStatusMessage = message
            guard let self else { return }
            self.render(state: self.lastRenderedState)
        }

        viewModel.onPartnerMoodUpdated = { [weak self] mood in
            self?.latestPartnerMoodValue = mood?.title ?? L10n.t("chat.sidebar.value.unknown")
            self?.partnerMoodValueLabel.text = self?.latestPartnerMoodValue
        }

        viewModel.onDistanceUpdated = { [weak self] distance in
            let displayValue = distance?.trimmingCharacters(in: .whitespacesAndNewlines)
            self?.latestDistanceDisplayValue = (displayValue?.isEmpty == false) ? displayValue! : "--"
            self?.distanceValueLabel.text = self?.latestDistanceDisplayValue
        }

        viewModel.onHeartbeatReceived = { [weak self] in
            self?.showHeartbeatToast()
        }

        viewModel.onError = { [weak self] message in
            self?.presentError(message)
        }
    }

    private func render(state: ChatViewModel.ScreenState) {
        let previousState = lastRenderedState
        lastRenderedState = state

        switch state {
        case .idle:
            emptyStateLabel.text = L10n.t("chat.state.idle.empty")

        case .loading:
            emptyStateLabel.text = L10n.t("chat.state.loading.empty")

        case .unpaired:
            emptyStateLabel.text = pairingStatusMessage ?? L10n.t("chat.state.unpaired.empty")

        case .waitingForMutualPairing:
            let waitingText = pairingStatusMessage ?? L10n.t("chat.state.waiting.fallback")
            emptyStateLabel.text = waitingText

        case .ready:
            pairingStatusMessage = L10n.t("chat.state.ready.paired_status")
            emptyStateLabel.text = L10n.t("chat.state.ready.empty")
        }

        let ready = state == .ready
        messageTextField.isEnabled = ready
        composerSendButton.isEnabled = ready
        gifButton.isEnabled = ready
        heartButton.isEnabled = ready
        secretSwitch.isEnabled = ready

        let interactionAlpha: CGFloat = ready ? 1.0 : 0.62
        messageTextField.alpha = interactionAlpha
        composerSendButton.alpha = interactionAlpha
        gifButton.alpha = interactionAlpha
        emojiToggleButton.alpha = interactionAlpha
        heartButton.alpha = interactionAlpha
        secretSwitch.alpha = interactionAlpha
        emojiContainer.alpha = isQuickEmojiVisible ? interactionAlpha : 0

        updateDetailsSidebarValues(for: state)
        updateEmptyStateVisibility()

        if ready {
            hasTriggeredPairingRedirect = false
        } else if previousState == .ready && state == .unpaired && !hasTriggeredPairingRedirect {
            hasTriggeredPairingRedirect = true
            onRequirePairing?()
        }
    }

    private func updateEmptyStateVisibility() {
        emptyStateLabel.isHidden = viewModel.numberOfMessages() > 0
    }

    private func setupMoodButtons() {
        MoodStatus.allCases.enumerated().forEach { index, mood in
            let button = UIButton(type: .system)
            button.tag = index

            var configuration = UIButton.Configuration.plain()
            var titleAttributes = AttributeContainer()
            titleAttributes.font = UIFont(name: "AvenirNext-DemiBold", size: 13) ?? .systemFont(ofSize: 13, weight: .semibold)
            configuration.attributedTitle = AttributedString(mood.title, attributes: titleAttributes)
            configuration.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12)
            button.configuration = configuration

            button.layer.cornerRadius = 12
            button.layer.cornerCurve = .continuous
            button.layer.borderWidth = 1
            button.addTarget(self, action: #selector(moodButtonTapped(_:)), for: .touchUpInside)
            moodButtons.append(button)
            moodStack.addArrangedSubview(button)
        }
    }

    private func setupMoodSectionForSidebar() {
        moodSectionContainer.translatesAutoresizingMaskIntoConstraints = false
        moodSectionContainer.setContentCompressionResistancePriority(.required, for: .vertical)
        moodSectionContainer.setContentHuggingPriority(.required, for: .vertical)

        moodTitleLabel.text = L10n.t("chat.section.share_mood")
        moodTitleLabel.font = UIFont(name: "AvenirNext-DemiBold", size: 14) ?? .systemFont(ofSize: 14, weight: .semibold)
        moodTitleLabel.translatesAutoresizingMaskIntoConstraints = false

        moodScrollView.showsHorizontalScrollIndicator = false
        moodScrollView.translatesAutoresizingMaskIntoConstraints = false

        moodStack.axis = .horizontal
        moodStack.alignment = .fill
        moodStack.spacing = 8
        moodStack.translatesAutoresizingMaskIntoConstraints = false

        if moodButtons.isEmpty {
            setupMoodButtons()
        }

        moodScrollView.addSubview(moodStack)
        moodSectionContainer.addSubview(moodTitleLabel)
        moodSectionContainer.addSubview(moodScrollView)

        let moodTitleTopConstraint = moodTitleLabel.topAnchor.constraint(equalTo: moodSectionContainer.topAnchor, constant: 6)
        moodTitleTopConstraint.priority = .defaultHigh
        let moodScrollTopConstraint = moodScrollView.topAnchor.constraint(equalTo: moodTitleLabel.bottomAnchor, constant: 8)
        moodScrollTopConstraint.priority = .defaultHigh
        let moodScrollHeightConstraint = moodScrollView.heightAnchor.constraint(equalToConstant: 34)
        moodScrollHeightConstraint.priority = .defaultHigh
        let moodScrollBottomConstraint = moodScrollView.bottomAnchor.constraint(equalTo: moodSectionContainer.bottomAnchor, constant: -4)
        moodScrollBottomConstraint.priority = .defaultHigh

        NSLayoutConstraint.activate([
            moodTitleTopConstraint,
            moodTitleLabel.leadingAnchor.constraint(equalTo: moodSectionContainer.leadingAnchor, constant: 2),
            moodTitleLabel.trailingAnchor.constraint(equalTo: moodSectionContainer.trailingAnchor, constant: -2),

            moodScrollTopConstraint,
            moodScrollView.leadingAnchor.constraint(equalTo: moodSectionContainer.leadingAnchor),
            moodScrollView.trailingAnchor.constraint(equalTo: moodSectionContainer.trailingAnchor),
            moodScrollHeightConstraint,
            moodScrollBottomConstraint,

            moodStack.topAnchor.constraint(equalTo: moodScrollView.contentLayoutGuide.topAnchor),
            moodStack.bottomAnchor.constraint(equalTo: moodScrollView.contentLayoutGuide.bottomAnchor),
            moodStack.leadingAnchor.constraint(equalTo: moodScrollView.contentLayoutGuide.leadingAnchor),
            moodStack.trailingAnchor.constraint(equalTo: moodScrollView.contentLayoutGuide.trailingAnchor),
            moodStack.heightAnchor.constraint(equalTo: moodScrollView.frameLayoutGuide.heightAnchor)
        ])
    }

    private func setupDetailsRow(
        container: UIView,
        titleLabel: UILabel,
        valueLabel: UILabel,
        titleKey: String
    ) {
        container.layer.cornerRadius = 12
        container.layer.cornerCurve = .continuous
        container.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.text = L10n.t(titleKey)
        titleLabel.font = UIFont(name: "AvenirNext-Medium", size: 13) ?? .systemFont(ofSize: 13, weight: .medium)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        valueLabel.font = UIFont(name: "AvenirNext-DemiBold", size: 14) ?? .systemFont(ofSize: 14, weight: .semibold)
        valueLabel.textAlignment = .right
        valueLabel.translatesAutoresizingMaskIntoConstraints = false

        let rowStack = UIStackView(arrangedSubviews: [titleLabel, valueLabel])
        rowStack.axis = .horizontal
        rowStack.alignment = .center
        rowStack.spacing = 8
        rowStack.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(rowStack)

        NSLayoutConstraint.activate([
            rowStack.topAnchor.constraint(equalTo: container.topAnchor, constant: 10),
            rowStack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -10),
            rowStack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            rowStack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12)
        ])
    }

    private func setupSplashPreferenceRow() {
        splashPreferenceRow.layer.cornerRadius = 12
        splashPreferenceRow.layer.cornerCurve = .continuous
        splashPreferenceRow.translatesAutoresizingMaskIntoConstraints = false

        splashPreferenceTitleLabel.text = L10n.t("chat.sidebar.item.splash_screen")
        splashPreferenceTitleLabel.font = UIFont(name: "AvenirNext-Medium", size: 13) ?? .systemFont(ofSize: 13, weight: .medium)
        splashPreferenceTitleLabel.translatesAutoresizingMaskIntoConstraints = false

        splashPreferenceSwitch.isOn = showsSplashOnLaunch
        splashPreferenceSwitch.addTarget(self, action: #selector(splashPreferenceChanged(_:)), for: .valueChanged)
        splashPreferenceSwitch.translatesAutoresizingMaskIntoConstraints = false

        let rowStack = UIStackView(arrangedSubviews: [splashPreferenceTitleLabel, splashPreferenceSwitch])
        rowStack.axis = .horizontal
        rowStack.alignment = .center
        rowStack.spacing = 8
        rowStack.translatesAutoresizingMaskIntoConstraints = false

        splashPreferenceRow.addSubview(rowStack)

        NSLayoutConstraint.activate([
            rowStack.topAnchor.constraint(equalTo: splashPreferenceRow.topAnchor, constant: 10),
            rowStack.bottomAnchor.constraint(equalTo: splashPreferenceRow.bottomAnchor, constant: -10),
            rowStack.leadingAnchor.constraint(equalTo: splashPreferenceRow.leadingAnchor, constant: 12),
            rowStack.trailingAnchor.constraint(equalTo: splashPreferenceRow.trailingAnchor, constant: -12)
        ])
    }

    private func updateDetailsSidebarValues(for state: ChatViewModel.ScreenState) {
        let isSecureReady = state == .ready
        secureStatusValueLabel.text = isSecureReady
            ? L10n.t("chat.sidebar.value.active")
            : L10n.t("chat.sidebar.value.inactive")
        secureInfoRow.backgroundColor = isSecureReady
            ? UIColor.systemGreen.withAlphaComponent(0.28)
            : UIColor.systemRed.withAlphaComponent(0.28)

        switch state {
        case .ready:
            pairStatusValueLabel.text = L10n.t("chat.sidebar.value.paired")
        case .waitingForMutualPairing, .loading:
            pairStatusValueLabel.text = pairingStatusMessage ?? L10n.t("chat.sidebar.value.waiting")
        case .idle, .unpaired:
            pairStatusValueLabel.text = L10n.t("chat.sidebar.value.unpaired")
        }

        distanceValueLabel.text = latestDistanceDisplayValue
        partnerMoodValueLabel.text = latestPartnerMoodValue
    }

    private func setQuickEmojiVisibility(_ isVisible: Bool, animated: Bool) {
        guard isQuickEmojiVisible != isVisible else { return }
        isQuickEmojiVisible = isVisible
        UserDefaults.standard.set(isVisible, forKey: Self.quickEmojiVisibilityPreferenceKey)
        let interactionAlpha: CGFloat = lastRenderedState == .ready ? 1.0 : 0.62

        if isVisible {
            emojiContainer.isHidden = false
            inputTopToTableConstraint.isActive = false
            inputTopToEmojiConstraint.isActive = true
            emojiContainerHeightConstraint.constant = 52
        } else {
            inputTopToEmojiConstraint.isActive = false
            inputTopToTableConstraint.isActive = true
            emojiContainerHeightConstraint.constant = 0
        }

        let updateLayout = {
            self.emojiContainer.alpha = isVisible ? interactionAlpha : 0
            self.view.layoutIfNeeded()
        }

        let completion: (Bool) -> Void = { _ in
            if !isVisible {
                self.emojiContainer.isHidden = true
            }
            self.configureEmojiToggleButton()
        }

        if animated {
            UIView.animate(withDuration: 0.23, delay: 0, options: [.curveEaseInOut], animations: updateLayout, completion: completion)
        } else {
            updateLayout()
            completion(true)
        }
    }

    private func setDetailsDrawerVisibility(_ isOpen: Bool, animated: Bool) {
        guard isDetailsDrawerOpen != isOpen else { return }
        isDetailsDrawerOpen = isOpen

        if isOpen {
            detailsDimView.isHidden = false
            view.bringSubviewToFront(detailsDimView)
            view.bringSubviewToFront(detailsDrawerView)
        }

        let updates = {
            self.detailsDimView.alpha = isOpen ? 1 : 0
            self.detailsDrawerTrailingConstraint.constant = isOpen ? -12 : self.detailsDrawerWidth + 20
            self.view.layoutIfNeeded()
        }

        let completion: (Bool) -> Void = { _ in
            if !isOpen {
                self.detailsDimView.isHidden = true
            }
        }

        if animated {
            UIView.animate(withDuration: 0.25, delay: 0, options: [.curveEaseInOut], animations: updates, completion: completion)
        } else {
            updates()
            completion(true)
        }
    }

    private func setSelectedMood(at index: Int) {
        selectedMoodIndex = index

        for (idx, button) in moodButtons.enumerated() {
            let isSelected = idx == index
            button.backgroundColor = isSelected ? theme.moodSelectedBackground : theme.moodButtonBackground
            button.layer.borderColor = (isSelected ? theme.moodSelectedBorder : theme.moodButtonBorder).cgColor

            var configuration = button.configuration
            configuration?.baseForegroundColor = isSelected ? theme.moodSelectedText : theme.moodButtonText
            button.configuration = configuration
        }
    }

    private func applyTheme() {
        theme = ChatTheme.current(for: traitCollection)

        view.backgroundColor = theme.backgroundBase
        gradientLayer.colors = theme.gradient.map(\.cgColor)

        let appearance = UINavigationBarAppearance()
        appearance.configureWithTransparentBackground()
        appearance.titleTextAttributes = [
            .font: UIFont(name: "AvenirNext-Bold", size: 34) ?? UIFont.systemFont(ofSize: 34, weight: .bold),
            .foregroundColor: theme.title
        ]
        navigationController?.navigationBar.standardAppearance = appearance
        navigationController?.navigationBar.scrollEdgeAppearance = appearance
        navigationController?.navigationBar.tintColor = theme.accent

        moodTitleLabel.textColor = theme.textSecondary

        tableContainer.backgroundColor = theme.tableBackground
        tableContainer.layer.borderColor = theme.tableBorder.cgColor

        emptyStateLabel.textColor = theme.emptyStateText

        emojiContainer.backgroundColor = theme.softContainerBackground
        emojiButtons.forEach { button in
            button.backgroundColor = theme.emojiButtonBackground
            button.layer.borderWidth = 1
            button.layer.borderColor = theme.fieldBorder.cgColor
            var config = button.configuration
            config?.baseForegroundColor = theme.textPrimary
            button.configuration = config
        }

        inputContainer.backgroundColor = theme.softContainerBackground

        messageTextField.backgroundColor = theme.fieldBackground
        messageTextField.textColor = theme.textPrimary
        messageTextField.layer.borderColor = theme.fieldBorder.cgColor
        messageTextField.attributedPlaceholder = NSAttributedString(
            string: L10n.t("chat.input.placeholder"),
            attributes: [.foregroundColor: theme.placeholder]
        )

        secretLabel.textColor = theme.textSecondary
        secretSwitch.onTintColor = theme.accent
        configureComposerSendButton()

        configureActionButton(gifButton, title: L10n.t("chat.button.gif"), filled: false, color: theme.secondaryAction)
        configureEmojiToggleButton()
        configureActionButton(heartButton, title: L10n.t("chat.button.heartbeat"), filled: false, color: theme.heartbeatAction)

        heartbeatToast.backgroundColor = theme.toastBackground
        heartbeatToast.textColor = theme.toastText

        detailsDimView.backgroundColor = theme.drawerDim
        detailsDrawerView.backgroundColor = theme.drawerBackground
        detailsTitleLabel.textColor = theme.drawerTitle
        [secureInfoRow, pairInfoRow, distanceInfoRow, splashPreferenceRow].forEach { row in
            row.backgroundColor = theme.drawerRowBackground
        }
        [secureStatusTitleLabel, pairStatusTitleLabel, distanceTitleLabel, partnerMoodTitleLabel, splashPreferenceTitleLabel].forEach { label in
            label.textColor = theme.drawerRowTitle
        }
        [secureStatusValueLabel, pairStatusValueLabel, distanceValueLabel, partnerMoodValueLabel].forEach { label in
            label.textColor = theme.drawerRowValue
        }
        partnerMoodInfoRow.backgroundColor = theme.drawerRowBackground
        splashPreferenceSwitch.onTintColor = theme.accent

        if let selectedMoodIndex {
            setSelectedMood(at: selectedMoodIndex)
        } else {
            moodButtons.forEach { button in
                button.backgroundColor = theme.moodButtonBackground
                button.layer.borderColor = theme.moodButtonBorder.cgColor
                var config = button.configuration
                config?.baseForegroundColor = theme.moodButtonText
                button.configuration = config
            }
        }

        updateDetailsSidebarValues(for: lastRenderedState)
    }

    private func configureComposerSendButton() {
        let symbolConfig = UIImage.SymbolConfiguration(pointSize: 28, weight: .semibold)
        composerSendButton.setPreferredSymbolConfiguration(symbolConfig, forImageIn: .normal)
        composerSendButton.setImage(UIImage(systemName: "paperplane.circle.fill"), for: .normal)
        composerSendButton.tintColor = theme.accent
        composerSendButton.backgroundColor = .clear
        composerSendButton.accessibilityLabel = L10n.t("chat.accessibility.send")
    }

    private func configureEmojiToggleButton() {
        let iconName = isQuickEmojiVisible ? "chevron.up" : "chevron.down"
        var configuration = UIButton.Configuration.filled()
        configuration.cornerStyle = .capsule
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12)
        configuration.baseBackgroundColor = theme.secondaryAction.withAlphaComponent(0.16)
        configuration.baseForegroundColor = theme.secondaryAction
        configuration.image = UIImage(systemName: iconName)
        configuration.imagePadding = 5

        var titleAttributes = AttributeContainer()
        titleAttributes.font = UIFont(name: "AvenirNext-DemiBold", size: 14) ?? .systemFont(ofSize: 14, weight: .semibold)
        configuration.attributedTitle = AttributedString(L10n.t("chat.button.emoji"), attributes: titleAttributes)
        emojiToggleButton.configuration = configuration
        emojiToggleButton.accessibilityLabel = isQuickEmojiVisible
            ? L10n.t("chat.button.emoji_toggle.hide")
            : L10n.t("chat.button.emoji_toggle.show")
    }

    private func configureActionButton(_ button: UIButton, title: String, filled: Bool, color: UIColor) {
        var configuration = UIButton.Configuration.filled()
        configuration.cornerStyle = .capsule
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12)
        configuration.baseBackgroundColor = filled ? color : color.withAlphaComponent(0.16)
        configuration.baseForegroundColor = filled ? .white : color

        var titleAttributes = AttributeContainer()
        titleAttributes.font = UIFont(name: "AvenirNext-DemiBold", size: 14) ?? .systemFont(ofSize: 14, weight: .semibold)
        configuration.attributedTitle = AttributedString(title, attributes: titleAttributes)

        button.configuration = configuration
    }

    private func showHeartbeatToast() {
        UIView.animate(withDuration: 0.2, animations: {
            self.heartbeatToast.alpha = 1
        }) { _ in
            UIView.animate(withDuration: 0.22, delay: 1.0, options: [.curveEaseInOut], animations: {
                self.heartbeatToast.alpha = 0
            })
        }
    }

    private func markSecretMessageAsRevealed(_ messageID: String) {
        guard !messageID.isEmpty else { return }
        let insertion = revealedSecretMessageIDs.insert(messageID)
        guard insertion.inserted else { return }
        UserDefaults.standard.set(Array(revealedSecretMessageIDs), forKey: Self.revealedSecretMessagesPreferenceKey)
    }

    @discardableResult
    private func presentIfInHierarchy(_ viewController: UIViewController) -> Bool {
        guard isVisible,
              viewIfLoaded?.window != nil,
              presentedViewController == nil else {
            return false
        }

        present(viewController, animated: true)
        return true
    }

    private func presentError(_ message: String) {
        guard !message.isEmpty else { return }

        let alert = UIAlertController(title: L10n.t("common.error_title"), message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: L10n.t("common.ok"), style: .default))

        if !presentIfInHierarchy(alert) {
            pendingErrorMessage = message
        }
    }

    private func scrollToBottom(animated: Bool) {
        let count = viewModel.numberOfMessages()
        guard count > 0 else { return }
        let indexPath = IndexPath(row: count - 1, section: 0)
        tableView.scrollToRow(at: indexPath, at: .bottom, animated: animated)
    }

    private func prependMessagesAndPreservePosition() {
        guard view.window != nil else {
            needsDeferredMessageReload = true
            return
        }

        let previousContentHeight = tableView.contentSize.height
        let previousOffsetY = tableView.contentOffset.y

        tableView.reloadData()
        tableView.layoutIfNeeded()
        updateEmptyStateVisibility()

        let newContentHeight = tableView.contentSize.height
        let delta = newContentHeight - previousContentHeight
        guard delta > 0 else { return }

        tableView.setContentOffset(
            CGPoint(x: tableView.contentOffset.x, y: max(-tableView.adjustedContentInset.top, previousOffsetY + delta)),
            animated: false
        )
        updateVisibleGIFPlayback(isEnabled: !(tableView.isDragging || tableView.isDecelerating))
    }

    private func updateVisibleGIFPlayback(isEnabled: Bool) {
        let visibleRect = CGRect(origin: tableView.contentOffset, size: tableView.bounds.size)
        tableView.visibleCells
            .compactMap { $0 as? ChatMessageCell }
            .forEach { cell in
                guard isEnabled else {
                    cell.setGIFPlaybackEnabled(false)
                    return
                }

                let intersection = visibleRect.intersection(cell.frame)
                let ratio: CGFloat
                if intersection.isNull || intersection.isEmpty || cell.frame.height <= 0 {
                    ratio = 0
                } else {
                    ratio = intersection.height / cell.frame.height
                }
                cell.setGIFPlaybackEnabled(ratio >= minimumGIFVisibleRatio)
            }
    }

    private func registerForThemeChanges() {
        if #available(iOS 17.0, *) {
            registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (self: Self, _) in
                self.applyTheme()
                self.render(state: self.lastRenderedState)
            }
        }
    }

    private func configureKeyboardDismissal() {
        dismissKeyboardTapGesture.cancelsTouchesInView = false
        dismissKeyboardTapGesture.delegate = self
        view.addGestureRecognizer(dismissKeyboardTapGesture)
    }

    private func configureMemoryWarningObserver() {
        memoryWarningObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleMemoryWarning()
        }
    }

    private func handleMemoryWarning() {
        updateVisibleGIFPlayback(isEnabled: false)
        tableView.visibleCells
            .compactMap { $0 as? ChatMessageCell }
            .forEach { $0.setGIFPlaybackEnabled(false) }
        URLCache.shared.removeAllCachedResponses()

        #if canImport(SDWebImage)
        SDImageCache.shared.clearMemory()
        #endif

        viewModel.handleMemoryPressure()
    }

    private func setKeyboardMode(active: Bool, animated: Bool) {
        guard isKeyboardModeActive != active else { return }
        isKeyboardModeActive = active

        let updates = {
            self.tableMinHeightConstraint.constant = active ? 140 : 220
            self.view.layoutIfNeeded()
        }

        let completion: (Bool) -> Void = { _ in
            if active {
                self.scrollToBottom(animated: false)
            }
        }

        if animated {
            UIView.animate(withDuration: 0.22, delay: 0, options: [.curveEaseInOut], animations: updates, completion: completion)
        } else {
            updates()
            completion(true)
        }
    }

    @objc private func messageEditingDidBegin() {
        setKeyboardMode(active: true, animated: true)
    }

    @objc private func messageEditingDidEnd() {
        setKeyboardMode(active: false, animated: true)
    }

    @objc private func handleBackgroundTap() {
        view.endEditing(true)
    }

    @objc private func detailsButtonTapped() {
        setDetailsDrawerVisibility(!isDetailsDrawerOpen, animated: true)
    }

    @objc private func closeDetailsDrawer() {
        setDetailsDrawerVisibility(false, animated: true)
    }

    @objc private func splashPreferenceChanged(_ sender: UISwitch) {
        showsSplashOnLaunch = sender.isOn
        UserDefaults.standard.set(sender.isOn, forKey: AppConfiguration.UserPreferenceKey.showsSplashOnLaunch)
    }

    @objc private func emojiToggleTapped() {
        setQuickEmojiVisibility(!isQuickEmojiVisible, animated: true)
    }

    @objc private func moodButtonTapped(_ sender: UIButton) {
        let index = sender.tag
        guard index >= 0, index < MoodStatus.allCases.count else { return }
        setSelectedMood(at: index)
        viewModel.updateMood(MoodStatus.allCases[index])
    }

    @objc private func sendButtonTapped() {
        let text = messageTextField.text ?? ""
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        playSendSymbolEffect()
        viewModel.sendText(trimmed, isSecret: secretSwitch.isOn)
        messageTextField.text = nil
        messageTextField.becomeFirstResponder()
    }

    private func playSendSymbolEffect() {
        if #available(iOS 17.0, *) {
            composerSendButton.imageView?.addSymbolEffect(.bounce.up.byLayer, options: .nonRepeating)
            return
        }

        // Fallback for iOS versions without SF Symbol effects.
        UIView.animate(withDuration: 0.12, animations: {
            self.composerSendButton.transform = CGAffineTransform(scaleX: 1.12, y: 1.12)
        }) { _ in
            UIView.animate(withDuration: 0.12) {
                self.composerSendButton.transform = .identity
            }
        }
    }

    @objc private func gifButtonTapped() {
        #if canImport(GiphyUISDK)
        let controller = GiphyViewController()
        controller.delegate = self
        present(controller, animated: true)
        #else
        let alert = UIAlertController(title: L10n.t("chat.alert.gif.title"), message: L10n.t("chat.alert.gif.message"), preferredStyle: .alert)
        alert.addTextField { $0.placeholder = L10n.t("chat.alert.gif.placeholder") }
        alert.addAction(UIAlertAction(title: L10n.t("common.cancel"), style: .cancel))
        alert.addAction(UIAlertAction(title: L10n.t("chat.alert.gif.send"), style: .default, handler: { [weak self, weak alert] _ in
            let url = alert?.textFields?.first?.text ?? ""
            self?.viewModel.sendGIF(urlString: url, isSecret: self?.secretSwitch.isOn == true)
        }))
        _ = presentIfInHierarchy(alert)
        #endif
    }

    @objc private func heartLongPress(_ recognizer: UILongPressGestureRecognizer) {
        if recognizer.state == .began {
            viewModel.sendHeartbeat()
        }
    }
}

extension ChatViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        viewModel.numberOfMessages()
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(withIdentifier: ChatMessageCell.reuseIdentifier, for: indexPath) as? ChatMessageCell else {
            return UITableViewCell()
        }

        let message = viewModel.message(at: indexPath.row)
        let isOutgoing = viewModel.isFromCurrentUser(message)
        let isSecretRevealed = revealedSecretMessageIDs.contains(message.id)
        cell.configure(with: message, isOutgoing: isOutgoing, isSecretRevealed: isSecretRevealed)
        cell.onSecretRevealed = { [weak self] in
            self?.markSecretMessageAsRevealed(message.id)
        }
        return cell
    }
}

extension ChatViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        guard let chatCell = cell as? ChatMessageCell else { return }
        guard !(tableView.isDragging || tableView.isDecelerating) else {
            chatCell.setGIFPlaybackEnabled(false)
            return
        }

        let visibleRect = CGRect(origin: tableView.contentOffset, size: tableView.bounds.size)
        let intersection = visibleRect.intersection(cell.frame)
        let ratio: CGFloat
        if intersection.isNull || intersection.isEmpty || cell.frame.height <= 0 {
            ratio = 0
        } else {
            ratio = intersection.height / cell.frame.height
        }
        chatCell.setGIFPlaybackEnabled(ratio >= minimumGIFVisibleRatio)
    }

    func tableView(_ tableView: UITableView, didEndDisplaying cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        guard let chatCell = cell as? ChatMessageCell else { return }
        chatCell.setGIFPlaybackEnabled(false)
        chatCell.releaseGIFImageFromMemory()
    }

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        guard scrollView === tableView else { return }
        updateVisibleGIFPlayback(isEnabled: false)
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard scrollView === tableView else { return }
        guard let firstVisibleRow = tableView.indexPathsForVisibleRows?.map(\.row).min() else { return }

        let topOffset = tableView.contentOffset.y + tableView.adjustedContentInset.top
        if topOffset <= 48 {
            viewModel.loadOlderMessagesIfNeeded(visibleTopRow: firstVisibleRow)
        }
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        guard scrollView === tableView else { return }
        if !decelerate {
            updateVisibleGIFPlayback(isEnabled: true)
        }
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        guard scrollView === tableView else { return }
        updateVisibleGIFPlayback(isEnabled: true)
    }

    func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        guard scrollView === tableView else { return }
        updateVisibleGIFPlayback(isEnabled: true)
    }
}

extension ChatViewController: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        guard textField === messageTextField else { return true }
        sendButtonTapped()
        return false
    }
}

extension ChatViewController: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard gestureRecognizer === dismissKeyboardTapGesture else { return true }
        guard let touchedView = touch.view else { return true }

        if touchedView is UIControl {
            return false
        }

        if touchedView.isDescendant(of: inputContainer) {
            return false
        }

        if touchedView.isDescendant(of: detailsDrawerView) {
            return false
        }

        return true
    }
}

#if canImport(GiphyUISDK)
extension ChatViewController: GiphyDelegate {
    func didSelectMedia(giphyViewController: GiphyViewController, media: GPHMedia) {
        let urlString = media.url(rendition: .fixedWidth, fileType: .gif) ?? ""
        viewModel.sendGIF(urlString: urlString, isSecret: secretSwitch.isOn)
        giphyViewController.dismiss(animated: true)
    }

    func didDismiss(controller: GiphyViewController?) {
        controller?.dismiss(animated: true)
    }
}
#endif
private extension ChatViewController {
    struct ChatTheme {
        let backgroundBase: UIColor
        let gradient: [UIColor]
        let fieldBackground: UIColor
        let fieldBorder: UIColor
        let textPrimary: UIColor
        let textSecondary: UIColor
        let placeholder: UIColor
        let tableBackground: UIColor
        let tableBorder: UIColor
        let softContainerBackground: UIColor
        let emojiButtonBackground: UIColor
        let emptyStateText: UIColor
        let accent: UIColor
        let secondaryAction: UIColor
        let heartbeatAction: UIColor
        let moodButtonBackground: UIColor
        let moodButtonBorder: UIColor
        let moodButtonText: UIColor
        let moodSelectedBackground: UIColor
        let moodSelectedBorder: UIColor
        let moodSelectedText: UIColor
        let toastBackground: UIColor
        let toastText: UIColor
        let title: UIColor
        let drawerDim: UIColor
        let drawerBackground: UIColor
        let drawerTitle: UIColor
        let drawerRowBackground: UIColor
        let drawerRowTitle: UIColor
        let drawerRowValue: UIColor

        static func current(for traitCollection: UITraitCollection) -> ChatTheme {
            let isDark = traitCollection.userInterfaceStyle == .dark

            if isDark {
                return ChatTheme(
                    backgroundBase: UIColor(red: 0.05, green: 0.05, blue: 0.07, alpha: 1),
                    gradient: [
                        UIColor(red: 0.12, green: 0.08, blue: 0.12, alpha: 1),
                        UIColor(red: 0.08, green: 0.11, blue: 0.17, alpha: 1),
                        UIColor(red: 0.07, green: 0.13, blue: 0.14, alpha: 1)
                    ],
                    fieldBackground: UIColor(red: 0.15, green: 0.15, blue: 0.19, alpha: 1),
                    fieldBorder: UIColor(red: 0.36, green: 0.36, blue: 0.42, alpha: 1),
                    textPrimary: UIColor(red: 0.95, green: 0.95, blue: 0.98, alpha: 1),
                    textSecondary: UIColor(red: 0.78, green: 0.78, blue: 0.84, alpha: 1),
                    placeholder: UIColor(red: 0.54, green: 0.54, blue: 0.62, alpha: 1),
                    tableBackground: UIColor(red: 0.11, green: 0.11, blue: 0.14, alpha: 0.92),
                    tableBorder: UIColor(red: 0.28, green: 0.28, blue: 0.34, alpha: 1),
                    softContainerBackground: UIColor(red: 0.14, green: 0.14, blue: 0.18, alpha: 0.9),
                    emojiButtonBackground: UIColor(red: 0.2, green: 0.2, blue: 0.24, alpha: 1),
                    emptyStateText: UIColor(red: 0.77, green: 0.77, blue: 0.84, alpha: 1),
                    accent: UIColor(red: 0.95, green: 0.24, blue: 0.55, alpha: 1),
                    secondaryAction: UIColor(red: 0.32, green: 0.56, blue: 0.95, alpha: 1),
                    heartbeatAction: UIColor(red: 0.97, green: 0.38, blue: 0.58, alpha: 1),
                    moodButtonBackground: UIColor(red: 0.17, green: 0.17, blue: 0.21, alpha: 1),
                    moodButtonBorder: UIColor(red: 0.34, green: 0.34, blue: 0.4, alpha: 1),
                    moodButtonText: UIColor(red: 0.83, green: 0.83, blue: 0.9, alpha: 1),
                    moodSelectedBackground: UIColor(red: 0.95, green: 0.24, blue: 0.55, alpha: 0.22),
                    moodSelectedBorder: UIColor(red: 0.95, green: 0.24, blue: 0.55, alpha: 0.7),
                    moodSelectedText: UIColor(red: 1, green: 0.74, blue: 0.84, alpha: 1),
                    toastBackground: UIColor(red: 0.95, green: 0.24, blue: 0.55, alpha: 0.95),
                    toastText: .white,
                    title: UIColor(red: 0.97, green: 0.97, blue: 0.99, alpha: 1),
                    drawerDim: UIColor.black.withAlphaComponent(0.34),
                    drawerBackground: UIColor(red: 0.13, green: 0.13, blue: 0.17, alpha: 0.98),
                    drawerTitle: UIColor(red: 0.95, green: 0.95, blue: 0.98, alpha: 1),
                    drawerRowBackground: UIColor(red: 0.2, green: 0.2, blue: 0.24, alpha: 1),
                    drawerRowTitle: UIColor(red: 0.78, green: 0.78, blue: 0.84, alpha: 1),
                    drawerRowValue: UIColor(red: 0.96, green: 0.96, blue: 1, alpha: 1)
                )
            }

            return ChatTheme(
                backgroundBase: UIColor(red: 0.98, green: 0.98, blue: 1, alpha: 1),
                gradient: [
                    UIColor(red: 0.99, green: 0.95, blue: 0.95, alpha: 1),
                    UIColor(red: 0.97, green: 0.96, blue: 1, alpha: 1),
                    UIColor(red: 0.95, green: 0.98, blue: 1, alpha: 1)
                ],
                fieldBackground: UIColor.white.withAlphaComponent(0.96),
                fieldBorder: UIColor.systemGray5,
                textPrimary: UIColor(red: 0.18, green: 0.18, blue: 0.23, alpha: 1),
                textSecondary: UIColor(red: 0.44, green: 0.44, blue: 0.5, alpha: 1),
                placeholder: UIColor(red: 0.66, green: 0.66, blue: 0.72, alpha: 1),
                tableBackground: UIColor.white.withAlphaComponent(0.75),
                tableBorder: UIColor.white.withAlphaComponent(0.4),
                softContainerBackground: UIColor.white.withAlphaComponent(0.84),
                emojiButtonBackground: UIColor.white.withAlphaComponent(0.92),
                emptyStateText: UIColor(red: 0.5, green: 0.5, blue: 0.56, alpha: 1),
                accent: UIColor(red: 0.86, green: 0.18, blue: 0.44, alpha: 1),
                secondaryAction: UIColor(red: 0.2, green: 0.42, blue: 0.86, alpha: 1),
                heartbeatAction: UIColor(red: 0.9, green: 0.22, blue: 0.44, alpha: 1),
                moodButtonBackground: UIColor.white.withAlphaComponent(0.94),
                moodButtonBorder: UIColor.systemGray5,
                moodButtonText: UIColor(red: 0.46, green: 0.46, blue: 0.52, alpha: 1),
                moodSelectedBackground: UIColor(red: 0.86, green: 0.18, blue: 0.44, alpha: 0.14),
                moodSelectedBorder: UIColor(red: 0.86, green: 0.18, blue: 0.44, alpha: 0.45),
                moodSelectedText: UIColor(red: 0.68, green: 0.1, blue: 0.32, alpha: 1),
                toastBackground: UIColor(red: 0.86, green: 0.18, blue: 0.44, alpha: 0.95),
                toastText: .white,
                title: UIColor.label,
                drawerDim: UIColor.black.withAlphaComponent(0.22),
                drawerBackground: UIColor.white.withAlphaComponent(0.98),
                drawerTitle: UIColor(red: 0.2, green: 0.2, blue: 0.26, alpha: 1),
                drawerRowBackground: UIColor.white.withAlphaComponent(0.92),
                drawerRowTitle: UIColor(red: 0.45, green: 0.45, blue: 0.5, alpha: 1),
                drawerRowValue: UIColor(red: 0.23, green: 0.23, blue: 0.29, alpha: 1)
            )
        }
    }
}
