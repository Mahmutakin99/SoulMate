//
//  ChatViewControllerTable.swift
//  SoulMate
//
//  Created by MAHMUT AKIN on 02/02/2026.
//

import UIKit

extension ChatViewController {
    func configureMessageDataSource() {
        messageDataSource = UITableViewDiffableDataSource<Int, String>(tableView: tableView) { [weak self] tableView, indexPath, messageID in
            guard let self,
                  let message = self.viewModel.message(for: messageID),
                  let cell = tableView.dequeueReusableCell(
                    withIdentifier: ChatMessageCell.reuseIdentifier,
                    for: indexPath
                  ) as? ChatMessageCell else {
                return UITableViewCell()
            }

            let isOutgoing = self.viewModel.isFromCurrentUser(message)
            let isSecretRevealed = self.revealedSecretMessageIDs.contains(message.id)
            let metadata = self.viewModel.messageMeta(for: message.id)
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

    func applyMessageSnapshot(
        animatingDifferences: Bool,
        reconfigureMessageIDs: Set<String> = [],
        completion: (() -> Void)? = nil
    ) {
        var snapshot = NSDiffableDataSourceSnapshot<Int, String>()
        snapshot.appendSections([0])
        let allIDs = viewModel.messages.map(\.id)
        snapshot.appendItems(allIDs, toSection: 0)

        if !reconfigureMessageIDs.isEmpty {
            let validIDs = reconfigureMessageIDs.filter { snapshot.indexOfItem($0) != nil }
            if !validIDs.isEmpty {
                if #available(iOS 15.0, *) {
                    snapshot.reconfigureItems(Array(validIDs))
                } else {
                    snapshot.reloadItems(Array(validIDs))
                }
            }
        }

        let shouldAnimate = animatingDifferences && isVisible
        messageDataSource?.apply(snapshot, animatingDifferences: shouldAnimate, completion: completion)
    }

    func isNearBottom(threshold: CGFloat = 36) -> Bool {
        let contentHeight = tableView.contentSize.height
        let visibleBottom = tableView.contentOffset.y + tableView.bounds.height - tableView.adjustedContentInset.bottom
        return contentHeight - visibleBottom <= threshold
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

        let topVisibleIndexPath = tableView.indexPathsForVisibleRows?.min()
        let topMessageID = topVisibleIndexPath.flatMap { messageDataSource?.itemIdentifier(for: $0) }
        let topAnchorOffset: CGFloat = {
            guard let topVisibleIndexPath else { return 0 }
            return tableView.rectForRow(at: topVisibleIndexPath).minY - tableView.contentOffset.y
        }()

        applyMessageSnapshot(animatingDifferences: false) { [weak self] in
            guard let self else { return }
            self.tableView.layoutIfNeeded()
            if let topMessageID,
               let newRow = self.viewModel.messages.firstIndex(where: { $0.id == topMessageID }) {
                let indexPath = IndexPath(row: newRow, section: 0)
                let targetY = self.tableView.rectForRow(at: indexPath).minY - topAnchorOffset
                self.tableView.setContentOffset(
                    CGPoint(x: self.tableView.contentOffset.x, y: max(-self.tableView.adjustedContentInset.top, targetY)),
                    animated: false
                )
            }
            self.updateEmptyStateVisibility()
            self.previousMessageCount = self.viewModel.numberOfMessages()
            self.previousLastMessageID = self.previousMessageCount > 0 ? self.viewModel.message(at: self.previousMessageCount - 1).id : nil
            self.scheduleVisibleGIFPlaybackUpdate(isEnabled: !(self.tableView.isDragging || self.tableView.isDecelerating), delay: 0.08)
        }
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
