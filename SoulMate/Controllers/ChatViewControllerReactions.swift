//
//  ChatViewControllerReactions.swift
//  SoulMate
//
//  Created by MAHMUT AKIN on 14/02/2026.
//

import UIKit

extension ChatViewController {
    func presentReactionQuickPicker(for message: ChatMessage, sourceView: UIView) {
        guard view.window != nil else { return }
        guard !message.id.isEmpty else { return }

        dismissReactionQuickPicker()

        let overlay = UIControl()
        overlay.backgroundColor = .clear
        overlay.frame = view.bounds
        overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        overlay.addAction(UIAction { [weak self] _ in
            self?.dismissReactionQuickPicker()
        }, for: .touchUpInside)

        let quickPicker = ReactionQuickPickerView()
        quickPicker.translatesAutoresizingMaskIntoConstraints = true
        quickPicker.onEmojiSelected = { [weak self] emoji in
            guard let self, let messageID = self.activeReactionMessageID else { return }
            self.viewModel.toggleReaction(messageID: messageID, emoji: emoji)
            self.dismissReactionQuickPicker()
        }
        quickPicker.onMoreSelected = { [weak self] in
            guard let self, let messageID = self.activeReactionMessageID else { return }
            self.dismissReactionQuickPicker()
            self.presentReactionEmojiPanel(for: messageID)
        }

        let quickEmojis = viewModel.quickReactionEmojis(maxCount: 5)
        let selectedEmoji = viewModel.currentUserReactionEmoji(for: message.id)
        quickPicker.configure(
            emojis: quickEmojis,
            selectedEmoji: selectedEmoji,
            appearance: reactionQuickPickerAppearance()
        )

        overlay.addSubview(quickPicker)
        view.addSubview(overlay)

        let anchorRect = sourceView.convert(sourceView.bounds, to: view)
        let pickerFrame = calculateReactionPickerFrame(
            anchorRect: anchorRect,
            picker: quickPicker,
            maxWidth: view.bounds.width - 24
        )
        quickPicker.frame = pickerFrame

        quickPicker.alpha = 0
        quickPicker.transform = CGAffineTransform(scaleX: 0.94, y: 0.94)
        UIView.animate(withDuration: 0.16, delay: 0, options: [.curveEaseOut]) {
            quickPicker.alpha = 1
            quickPicker.transform = .identity
        }

        reactionPickerOverlay = overlay
        reactionQuickPickerView = quickPicker
        activeReactionMessageID = message.id
    }

    func dismissReactionQuickPicker() {
        guard let overlay = reactionPickerOverlay else { return }
        reactionPickerOverlay = nil
        reactionQuickPickerView = nil
        activeReactionMessageID = nil

        UIView.animate(withDuration: 0.14, delay: 0, options: [.curveEaseInOut]) {
            overlay.alpha = 0
        } completion: { _ in
            overlay.removeFromSuperview()
        }
    }

    private func presentReactionEmojiPanel(for messageID: String) {
        guard view.window != nil else { return }
        guard presentedViewController == nil else { return }

        let panel = ReactionEmojiPanelViewController(
            frequentEmojis: viewModel.frequentReactionEmojis(maxCount: 12),
            appearance: reactionEmojiPanelAppearance()
        )
        panel.onEmojiSelected = { [weak self] emoji in
            self?.viewModel.toggleReaction(messageID: messageID, emoji: emoji)
        }
        present(panel, animated: true)
    }

    private func reactionQuickPickerAppearance() -> ReactionQuickPickerView.Appearance {
        ReactionQuickPickerView.Appearance(
            backgroundColor: theme.reactionPickerBackground,
            borderColor: theme.reactionPickerBorder,
            chipBackgroundColor: theme.reactionChipBackground,
            chipSelectedBackgroundColor: theme.reactionChipSelectedBackground,
            chipTextColor: theme.reactionChipText,
            plusBackgroundColor: theme.reactionPlusBackground,
            plusTintColor: theme.reactionPlusTint
        )
    }

    private func reactionEmojiPanelAppearance() -> ReactionEmojiPanelViewController.Appearance {
        ReactionEmojiPanelViewController.Appearance(
            backgroundColor: theme.reactionPanelBackground,
            sectionTitleColor: theme.reactionPanelSectionTitle,
            emojiBackgroundColor: theme.reactionPanelEmojiBackground,
            emojiTextColor: theme.reactionPanelEmojiText
        )
    }

    private func calculateReactionPickerFrame(
        anchorRect: CGRect,
        picker: ReactionQuickPickerView,
        maxWidth: CGFloat
    ) -> CGRect {
        let targetSize = picker.systemLayoutSizeFitting(
            CGSize(width: maxWidth, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .fittingSizeLevel,
            verticalFittingPriority: .required
        )

        let width = min(maxWidth, max(188, targetSize.width))
        let height = max(48, targetSize.height)

        let minimumX: CGFloat = 12
        let maximumX = max(minimumX, view.bounds.width - width - 12)
        let x = min(max(anchorRect.midX - (width / 2), minimumX), maximumX)

        let safeTop = view.safeAreaInsets.top + 8
        let safeBottom = view.bounds.height - view.safeAreaInsets.bottom - height - 8
        let preferredAboveY = anchorRect.minY - height - 8
        let y: CGFloat
        if preferredAboveY >= safeTop {
            y = preferredAboveY
        } else {
            y = min(max(anchorRect.maxY + 8, safeTop), safeBottom)
        }

        return CGRect(x: x, y: y, width: width, height: height)
    }
}
