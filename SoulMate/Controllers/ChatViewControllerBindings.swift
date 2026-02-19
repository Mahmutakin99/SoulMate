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
            guard self.isViewLoaded, self.view.window != nil else {
                self.needsDeferredMessageReload = true
                return
            }

            let shouldStickToBottom = self.isNearBottom() || self.previousMessageCount == 0
            let currentCount = self.viewModel.messages.count
            if AppConfiguration.FeatureFlags.enableDeltaCoalescing {
                self.scheduleCoalescedSnapshotApply(
                    needsFullReload: true,
                    shouldStickToBottom: shouldStickToBottom,
                    currentCount: currentCount
                )
            } else {
                self.dismissReactionQuickPicker()
                self.applyMessageSnapshot(animatingDifferences: true)
                self.previousMessageCount = currentCount
                self.previousLastMessageID = currentCount > 0 ? self.viewModel.message(at: currentCount - 1).id : nil
                self.updateEmptyStateVisibility()
                if shouldStickToBottom {
                    self.scrollToBottom(animated: true)
                }
                self.scheduleVisibleGIFPlaybackUpdate(isEnabled: !(self.tableView.isDragging || self.tableView.isDecelerating), delay: 0.08)
                self.markVisibleIncomingMessagesAsRead()
            }
        }

        viewModel.onMessagesPrepended = { [weak self] insertedCount in
            guard let self else { return }
            self.dismissReactionQuickPicker()
            guard self.isViewLoaded, self.view.window != nil else {
                self.needsDeferredMessageReload = true
                return
            }
            self.coalescedSnapshotApplyWorkItem?.cancel()
            self.coalescedSnapshotApplyWorkItem = nil
            self.pendingSnapshotNeedsFullReload = false
            self.pendingSnapshotShouldStickToBottom = false
            self.pendingSnapshotCurrentCount = nil
            self.pendingSnapshotReconfigureIDs.removeAll(keepingCapacity: true)
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
            if AppConfiguration.FeatureFlags.enableDeltaCoalescing {
                self.scheduleCoalescedSnapshotApply(
                    needsFullReload: false,
                    reconfigureMessageIDs: changedIDs
                )
            } else {
                self.applyMessageSnapshot(animatingDifferences: false, reconfigureMessageIDs: changedIDs)
            }
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

    private func scheduleCoalescedSnapshotApply(
        needsFullReload: Bool,
        shouldStickToBottom: Bool = false,
        currentCount: Int? = nil,
        reconfigureMessageIDs: Set<String> = []
    ) {
        if needsFullReload {
            dismissReactionQuickPicker()
            pendingSnapshotNeedsFullReload = true
            pendingSnapshotShouldStickToBottom = pendingSnapshotShouldStickToBottom || shouldStickToBottom
            if let currentCount {
                pendingSnapshotCurrentCount = currentCount
            }
        }
        pendingSnapshotReconfigureIDs.formUnion(reconfigureMessageIDs)

        guard coalescedSnapshotApplyWorkItem == nil else { return }
        let workItem = DispatchWorkItem { [weak self] in
            self?.performCoalescedSnapshotApply()
        }
        coalescedSnapshotApplyWorkItem = workItem
        DispatchQueue.main.async(execute: workItem)
    }

    private func performCoalescedSnapshotApply() {
        coalescedSnapshotApplyWorkItem = nil

        let needsFullReload = pendingSnapshotNeedsFullReload
        let shouldStickToBottom = pendingSnapshotShouldStickToBottom
        let currentCount = pendingSnapshotCurrentCount ?? viewModel.messages.count
        let reconfigureIDs = pendingSnapshotReconfigureIDs

        pendingSnapshotNeedsFullReload = false
        pendingSnapshotShouldStickToBottom = false
        pendingSnapshotCurrentCount = nil
        pendingSnapshotReconfigureIDs.removeAll(keepingCapacity: true)

        applyMessageSnapshot(
            animatingDifferences: needsFullReload,
            reconfigureMessageIDs: reconfigureIDs
        ) { [weak self] in
            guard let self else { return }
            if needsFullReload {
                self.previousMessageCount = currentCount
                self.previousLastMessageID = currentCount > 0 ? self.viewModel.message(at: currentCount - 1).id : nil
                self.updateEmptyStateVisibility()
                if shouldStickToBottom {
                    self.scrollToBottom(animated: true)
                }
                self.markVisibleIncomingMessagesAsRead()
            }
            self.scheduleVisibleGIFPlaybackUpdate(
                isEnabled: !(self.tableView.isDragging || self.tableView.isDecelerating),
                delay: 0.08
            )
        }
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
