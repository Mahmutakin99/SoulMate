//
//  ChatViewControllerBindings.swift
//  SoulMate
//
//  Created by MAHMUT AKIN on 02/02/2026.
//

import UIKit

extension ChatViewController {
    func bindViewModel() {
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

        viewModel.onIncomingPendingRequestBadgeChanged = { [weak self] badgeState in
            self?.updateDetailsBadge(state: badgeState)
        }

        viewModel.onMessagesUpdated = { [weak self] in
            guard let self else { return }
            self.dismissReactionQuickPicker()
            guard self.isViewLoaded, self.view.window != nil else {
                self.needsDeferredMessageReload = true
                return
            }

            let currentCount = self.viewModel.messages.count
            let previousCount = self.previousMessageCount
            let canAppendAtBottom = currentCount > previousCount &&
                previousCount > 0 &&
                self.tableView.numberOfRows(inSection: 0) == previousCount &&
                self.previousLastMessageID == self.viewModel.message(at: previousCount - 1).id

            if canAppendAtBottom {
                let newIndexPaths = (previousCount..<currentCount).map {
                    IndexPath(row: $0, section: 0)
                }
                self.tableView.insertRows(at: newIndexPaths, with: .automatic)
            } else {
                self.tableView.reloadData()
            }

            self.previousMessageCount = currentCount
            self.previousLastMessageID = currentCount > 0 ? self.viewModel.message(at: currentCount - 1).id : nil

            self.updateEmptyStateVisibility()
            self.scrollToBottom(animated: true)
            self.scheduleVisibleGIFPlaybackUpdate(isEnabled: !(self.tableView.isDragging || self.tableView.isDecelerating), delay: 0.08)
            self.markVisibleIncomingMessagesAsRead()
        }

        viewModel.onMessagesPrepended = { [weak self] insertedCount in
            guard let self else { return }
            self.dismissReactionQuickPicker()
            guard self.isViewLoaded, self.view.window != nil else {
                self.needsDeferredMessageReload = true
                return
            }
            self.prependMessagesAndPreservePosition(insertedCount: insertedCount)
            self.markVisibleIncomingMessagesAsRead()
        }

        viewModel.onMessageMetaUpdated = { [weak self] changedIDs in
            guard let self else { return }
            guard !changedIDs.isEmpty else { return }
            guard self.isViewLoaded, self.view.window != nil else {
                self.needsDeferredMessageReload = true
                return
            }
            guard self.tableView.numberOfRows(inSection: 0) == self.viewModel.numberOfMessages() else {
                return
            }

            let changedRows = self.viewModel.messages.enumerated().compactMap { index, message in
                changedIDs.contains(message.id) ? IndexPath(row: index, section: 0) : nil
            }
            guard !changedRows.isEmpty else { return }
            self.tableView.reloadRows(at: changedRows, with: .none)
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

    func render(state: ChatViewModel.ScreenState) {
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
        heartButton.isEnabled = ready
        secretSwitch.isEnabled = ready

        let interactionAlpha: CGFloat = ready ? 1.0 : 0.62
        messageTextField.alpha = interactionAlpha
        composerSendButton.alpha = interactionAlpha
        emojiToggleButton.alpha = interactionAlpha
        heartButton.alpha = interactionAlpha
        secretSwitch.alpha = interactionAlpha
        emojiContainer.alpha = isQuickEmojiVisible ? interactionAlpha : 0

        updateDetailsSidebarValues(for: state)
        updateEmptyStateVisibility()

        if !ready {
            stopHeartbeatHoldSession()
        }

        if ready {
            hasTriggeredPairingRedirect = false
        } else if previousState == .ready && state == .unpaired && !hasTriggeredPairingRedirect {
            hasTriggeredPairingRedirect = true
            onRequirePairing?()
        }
    }

    func updateEmptyStateVisibility() {
        emptyStateLabel.isHidden = viewModel.numberOfMessages() > 0
    }

    @discardableResult
    func presentIfInHierarchy(_ viewController: UIViewController) -> Bool {
        guard isVisible,
              viewIfLoaded?.window != nil,
              presentedViewController == nil else {
            return false
        }

        present(viewController, animated: true)
        return true
    }

    func presentError(_ message: String) {
        guard !message.isEmpty else { return }

        let alert = UIAlertController(title: L10n.t("common.error_title"), message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: L10n.t("common.ok"), style: .default))

        if !presentIfInHierarchy(alert) {
            pendingErrorMessage = message
        }
    }
}
