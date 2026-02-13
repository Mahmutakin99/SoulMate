//
//  ChatViewControllerUI.swift
//  SoulMate
//
//  Created by MAHMUT AKIN on 02/02/2026.
//

import UIKit
#if canImport(SDWebImage)
import SDWebImage
#endif

extension ChatViewController {
    func configureNavigationBar() {
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
        let accountItem = makeAccountBarButtonItem(menu: menu)
        let detailsItem = UIBarButtonItem(
            image: UIImage(systemName: "sidebar.right"),
            style: .plain,
            target: self,
            action: #selector(detailsButtonTapped)
        )
        navigationItem.rightBarButtonItems = [accountItem, detailsItem]
    }

    private func makeAccountBarButtonItem(menu: UIMenu) -> UIBarButtonItem {
        accountButtonContainer.frame = CGRect(x: 0, y: 0, width: 32, height: 32)

        if accountButtonContainer.subviews.isEmpty {
            accountButtonContainer.translatesAutoresizingMaskIntoConstraints = false

            accountButton.setImage(UIImage(systemName: "person.crop.circle"), for: .normal)
            accountButton.menu = menu
            accountButton.showsMenuAsPrimaryAction = true
            accountButton.accessibilityTraits = .button
            accountButton.translatesAutoresizingMaskIntoConstraints = false

            accountBadgeLabel.backgroundColor = .systemRed
            accountBadgeLabel.textColor = .white
            accountBadgeLabel.font = UIFont.monospacedDigitSystemFont(ofSize: 11, weight: .bold)
            accountBadgeLabel.textAlignment = .center
            accountBadgeLabel.layer.cornerRadius = 9
            accountBadgeLabel.layer.cornerCurve = .continuous
            accountBadgeLabel.clipsToBounds = true
            accountBadgeLabel.isHidden = true
            accountBadgeLabel.translatesAutoresizingMaskIntoConstraints = false

            accountButtonContainer.addSubview(accountButton)
            accountButtonContainer.addSubview(accountBadgeLabel)

            NSLayoutConstraint.activate([
                accountButtonContainer.widthAnchor.constraint(equalToConstant: 32),
                accountButtonContainer.heightAnchor.constraint(equalToConstant: 32),

                accountButton.topAnchor.constraint(equalTo: accountButtonContainer.topAnchor),
                accountButton.bottomAnchor.constraint(equalTo: accountButtonContainer.bottomAnchor),
                accountButton.leadingAnchor.constraint(equalTo: accountButtonContainer.leadingAnchor),
                accountButton.trailingAnchor.constraint(equalTo: accountButtonContainer.trailingAnchor),

                accountBadgeLabel.topAnchor.constraint(equalTo: accountButtonContainer.topAnchor, constant: -2),
                accountBadgeLabel.trailingAnchor.constraint(equalTo: accountButtonContainer.trailingAnchor, constant: 2),
                accountBadgeLabel.heightAnchor.constraint(equalToConstant: 18),
                accountBadgeLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 18)
            ])
        }

        accountButton.tintColor = theme.accent
        updateDetailsBadge(count: 0)
        return UIBarButtonItem(customView: accountButtonContainer)
    }

    func setupBackground() {
        view.backgroundColor = .systemBackground
        gradientLayer.startPoint = CGPoint(x: 0, y: 0)
        gradientLayer.endPoint = CGPoint(x: 1, y: 1)
        view.layer.insertSublayer(gradientLayer, at: 0)
    }

    func setupUI() {
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

    func registerForThemeChanges() {
        if #available(iOS 17.0, *) {
            registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (self: Self, _) in
                self.applyTheme()
                self.render(state: self.lastRenderedState)
            }
        }
    }

    func configureMemoryWarningObserver() {
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
}
