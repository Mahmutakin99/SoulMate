import UIKit

extension ChatViewController {
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

    func applyTheme() {
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
        accountButton.tintColor = theme.accent

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
}
