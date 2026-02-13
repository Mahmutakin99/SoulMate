//
//  ChatViewControllerSidebar.swift
//  SoulMate
//
//  Created by MAHMUT AKIN on 02/02/2026.
//

import UIKit

extension ChatViewController {
    func setupDetailsSidebar() {
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

    func updateDetailsBadge(count: Int) {
        let normalizedCount = max(0, count)
        let badgeText: String?
        if normalizedCount <= 0 {
            badgeText = nil
        } else if normalizedCount >= 100 {
            badgeText = "99+"
        } else {
            badgeText = "\(normalizedCount)"
        }

        accountBadgeLabel.text = badgeText
        accountBadgeLabel.isHidden = badgeText == nil

        if let badgeText {
            accountButton.accessibilityLabel = L10n.f("chat.account.badge.accessibility_format", badgeText)
        } else {
            accountButton.accessibilityLabel = L10n.t("chat.account.accessibility")
        }
    }

    func updateDetailsSidebarValues(for state: ChatViewModel.ScreenState) {
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

    func setDetailsDrawerVisibility(_ isOpen: Bool, animated: Bool) {
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

    func setSelectedMood(at index: Int) {
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

    @objc func detailsButtonTapped() {
        setDetailsDrawerVisibility(!isDetailsDrawerOpen, animated: true)
    }

    @objc func closeDetailsDrawer() {
        setDetailsDrawerVisibility(false, animated: true)
    }

    @objc func splashPreferenceChanged(_ sender: UISwitch) {
        showsSplashOnLaunch = sender.isOn
        UserDefaults.standard.set(sender.isOn, forKey: AppConfiguration.UserPreferenceKey.showsSplashOnLaunch)
    }

    @objc func moodButtonTapped(_ sender: UIButton) {
        let index = sender.tag
        guard index >= 0, index < MoodStatus.allCases.count else { return }
        setSelectedMood(at: index)
        viewModel.updateMood(MoodStatus.allCases[index])
    }
}
