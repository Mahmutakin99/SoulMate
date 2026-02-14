//
//  ChatViewControllerTable.swift
//  SoulMate
//
//  Created by MAHMUT AKIN on 02/02/2026.
//

import UIKit

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
        let metadata = viewModel.messageMeta(for: message.id)
        cell.configure(
            with: message,
            isOutgoing: isOutgoing,
            isSecretRevealed: isSecretRevealed,
            meta: metadata
        )
        cell.onSecretRevealed = { [weak self] in
            self?.markSecretMessageAsRevealed(message.id)
        }
        cell.onReactionLongPress = { [weak self] anchorView in
            self?.presentReactionQuickPicker(for: message, sourceView: anchorView)
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
        markVisibleIncomingMessagesAsRead()
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
        scheduleVisibleGIFPlaybackUpdate(isEnabled: !(tableView.isDragging || tableView.isDecelerating), delay: 0.1)
        guard let firstVisibleRow = tableView.indexPathsForVisibleRows?.map(\.row).min() else { return }

        let topOffset = tableView.contentOffset.y + tableView.adjustedContentInset.top
        if topOffset <= 48 {
            viewModel.loadOlderMessagesIfNeeded(visibleTopRow: firstVisibleRow)
        }
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        guard scrollView === tableView else { return }
        if !decelerate {
            scheduleVisibleGIFPlaybackUpdate(isEnabled: true, delay: 0.08)
            markVisibleIncomingMessagesAsRead()
        }
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        guard scrollView === tableView else { return }
        scheduleVisibleGIFPlaybackUpdate(isEnabled: true, delay: 0.08)
        markVisibleIncomingMessagesAsRead()
    }

    func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        guard scrollView === tableView else { return }
        scheduleVisibleGIFPlaybackUpdate(isEnabled: true, delay: 0.08)
        markVisibleIncomingMessagesAsRead()
    }
}

extension ChatViewController {
    func scrollToBottom(animated: Bool) {
        let modelCount = viewModel.numberOfMessages()
        guard modelCount > 0 else { return }

        tableView.layoutIfNeeded()
        let tableRowCount = tableView.numberOfRows(inSection: 0)
        guard tableRowCount > 0 else { return }

        let targetOffsetY = max(
            -tableView.adjustedContentInset.top,
            tableView.contentSize.height - tableView.bounds.height + tableView.adjustedContentInset.bottom
        )
        tableView.setContentOffset(
            CGPoint(x: tableView.contentOffset.x, y: targetOffsetY),
            animated: animated
        )
    }

    func prependMessagesAndPreservePosition(insertedCount: Int) {
        guard view.window != nil else {
            needsDeferredMessageReload = true
            return
        }
        guard insertedCount > 0 else { return }

        let previousContentHeight = tableView.contentSize.height
        let previousOffsetY = tableView.contentOffset.y

        let expectedPreviousRows = viewModel.numberOfMessages() - insertedCount
        guard tableView.numberOfRows(inSection: 0) == expectedPreviousRows else {
            tableView.reloadData()
            tableView.layoutIfNeeded()
            updateEmptyStateVisibility()
            previousMessageCount = viewModel.numberOfMessages()
            previousLastMessageID = previousMessageCount > 0 ? viewModel.message(at: previousMessageCount - 1).id : nil
            scheduleVisibleGIFPlaybackUpdate(isEnabled: !(tableView.isDragging || tableView.isDecelerating), delay: 0.08)
            return
        }

        let indexPaths = (0..<insertedCount).map { IndexPath(row: $0, section: 0) }
        tableView.performBatchUpdates({
            tableView.insertRows(at: indexPaths, with: .none)
        })
        tableView.layoutIfNeeded()
        updateEmptyStateVisibility()

        let newContentHeight = tableView.contentSize.height
        let delta = newContentHeight - previousContentHeight
        guard delta > 0 else {
            previousMessageCount = viewModel.numberOfMessages()
            previousLastMessageID = previousMessageCount > 0 ? viewModel.message(at: previousMessageCount - 1).id : nil
            scheduleVisibleGIFPlaybackUpdate(isEnabled: !(tableView.isDragging || tableView.isDecelerating), delay: 0.08)
            return
        }

        tableView.setContentOffset(
            CGPoint(x: tableView.contentOffset.x, y: max(-tableView.adjustedContentInset.top, previousOffsetY + delta)),
            animated: false
        )
        previousMessageCount = viewModel.numberOfMessages()
        previousLastMessageID = previousMessageCount > 0 ? viewModel.message(at: previousMessageCount - 1).id : nil
        scheduleVisibleGIFPlaybackUpdate(isEnabled: !(tableView.isDragging || tableView.isDecelerating), delay: 0.08)
    }

    func scheduleVisibleGIFPlaybackUpdate(isEnabled: Bool, delay: TimeInterval = 0.1) {
        gifPlaybackUpdateWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.updateVisibleGIFPlayback(isEnabled: isEnabled)
        }
        gifPlaybackUpdateWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    func updateVisibleGIFPlayback(isEnabled: Bool) {
        let chatCells = tableView.visibleCells.compactMap { $0 as? ChatMessageCell }
        guard !chatCells.isEmpty else { return }

        let visibleRect = CGRect(origin: tableView.contentOffset, size: tableView.bounds.size)
        chatCells.forEach { cell in
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

    func markVisibleIncomingMessagesAsRead() {
        guard view.window != nil else { return }
        guard let visibleRows = tableView.indexPathsForVisibleRows, !visibleRows.isEmpty else { return }

        let incomingIDs = visibleRows.compactMap { indexPath -> String? in
            guard indexPath.row < viewModel.numberOfMessages() else { return nil }
            let message = viewModel.message(at: indexPath.row)
            return viewModel.isIncomingMessageForCurrentUser(message) ? message.id : nil
        }
        guard !incomingIDs.isEmpty else { return }
        viewModel.markVisibleIncomingMessagesAsRead(incomingIDs)
    }

}
