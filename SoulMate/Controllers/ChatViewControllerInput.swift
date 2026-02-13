//
//  ChatViewControllerInput.swift
//  SoulMate
//
//  Created by MAHMUT AKIN on 02/02/2026.
//

import UIKit
#if canImport(GiphyUISDK)
import GiphyUISDK
#endif

extension ChatViewController {
    func setupInputSection() {
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

    func setQuickEmojiVisibility(_ isVisible: Bool, animated: Bool) {
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

    func configureComposerSendButton() {
        let symbolConfig = UIImage.SymbolConfiguration(pointSize: 28, weight: .semibold)
        composerSendButton.setPreferredSymbolConfiguration(symbolConfig, forImageIn: .normal)
        composerSendButton.setImage(UIImage(systemName: "paperplane.circle.fill"), for: .normal)
        composerSendButton.tintColor = theme.accent
        composerSendButton.backgroundColor = .clear
        composerSendButton.accessibilityLabel = L10n.t("chat.accessibility.send")
    }

    func configureEmojiToggleButton() {
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

    func configureActionButton(_ button: UIButton, title: String, filled: Bool, color: UIColor) {
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

    func showHeartbeatToast() {
        UIView.animate(withDuration: 0.2, animations: {
            self.heartbeatToast.alpha = 1
        }) { _ in
            UIView.animate(withDuration: 0.22, delay: 1.0, options: [.curveEaseInOut], animations: {
                self.heartbeatToast.alpha = 0
            })
        }
    }

    func markSecretMessageAsRevealed(_ messageID: String) {
        guard !messageID.isEmpty else { return }
        let insertion = revealedSecretMessageIDs.insert(messageID)
        guard insertion.inserted else { return }
        UserDefaults.standard.set(Array(revealedSecretMessageIDs), forKey: Self.revealedSecretMessagesPreferenceKey)
    }

    func configureKeyboardDismissal() {
        dismissKeyboardTapGesture.cancelsTouchesInView = false
        dismissKeyboardTapGesture.delegate = self
        view.addGestureRecognizer(dismissKeyboardTapGesture)
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

    @objc func messageEditingDidBegin() {
        setKeyboardMode(active: true, animated: true)
    }

    @objc func messageEditingDidEnd() {
        setKeyboardMode(active: false, animated: true)
    }

    @objc func handleBackgroundTap() {
        view.endEditing(true)
    }

    @objc func emojiToggleTapped() {
        setQuickEmojiVisibility(!isQuickEmojiVisible, animated: true)
    }

    @objc func sendButtonTapped() {
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

        UIView.animate(withDuration: 0.12, animations: {
            self.composerSendButton.transform = CGAffineTransform(scaleX: 1.12, y: 1.12)
        }) { _ in
            UIView.animate(withDuration: 0.12) {
                self.composerSendButton.transform = .identity
            }
        }
    }

    @objc func gifButtonTapped() {
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

    @objc func heartLongPress(_ recognizer: UILongPressGestureRecognizer) {
        if recognizer.state == .began {
            viewModel.sendHeartbeat()
        }
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
