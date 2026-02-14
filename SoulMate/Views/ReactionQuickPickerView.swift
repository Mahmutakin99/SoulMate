//
//  ReactionQuickPickerView.swift
//  SoulMate
//
//  Created by MAHMUT AKIN on 14/02/2026.
//

import UIKit

final class ReactionQuickPickerView: UIView {
    struct Appearance {
        let backgroundColor: UIColor
        let borderColor: UIColor
        let chipBackgroundColor: UIColor
        let chipSelectedBackgroundColor: UIColor
        let chipTextColor: UIColor
        let plusBackgroundColor: UIColor
        let plusTintColor: UIColor
    }

    var onEmojiSelected: ((String) -> Void)?
    var onMoreSelected: (() -> Void)?

    private let stackView = UIStackView()
    private var currentAppearance: Appearance?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(
        emojis: [String],
        selectedEmoji: String?,
        appearance: Appearance
    ) {
        currentAppearance = appearance
        backgroundColor = appearance.backgroundColor
        layer.borderColor = appearance.borderColor.cgColor

        stackView.arrangedSubviews.forEach {
            stackView.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }

        emojis.forEach { emoji in
            let button = makeEmojiButton(
                emoji: emoji,
                selected: selectedEmoji == emoji,
                appearance: appearance
            )
            stackView.addArrangedSubview(button)
        }

        let plusButton = makePlusButton(appearance: appearance)
        stackView.addArrangedSubview(plusButton)
    }

    private func setupUI() {
        layer.cornerRadius = 22
        layer.cornerCurve = .continuous
        layer.borderWidth = 1
        clipsToBounds = true

        stackView.axis = .horizontal
        stackView.alignment = .center
        stackView.spacing = 8
        stackView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10)
        ])

        accessibilityLabel = L10n.t("chat.reaction.quick_picker.accessibility")
    }

    private func makeEmojiButton(
        emoji: String,
        selected: Bool,
        appearance: Appearance
    ) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(emoji, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 28)
        button.backgroundColor = selected ? appearance.chipSelectedBackgroundColor : appearance.chipBackgroundColor
        button.tintColor = appearance.chipTextColor
        button.layer.cornerRadius = 16
        button.layer.cornerCurve = .continuous
        button.clipsToBounds = true
        button.accessibilityLabel = "Reaksiyon: \(emoji)"
        button.translatesAutoresizingMaskIntoConstraints = false
        button.widthAnchor.constraint(equalToConstant: 40).isActive = true
        button.heightAnchor.constraint(equalToConstant: 32).isActive = true
        button.addAction(UIAction { [weak self] _ in
            self?.onEmojiSelected?(emoji)
        }, for: .touchUpInside)
        return button
    }

    private func makePlusButton(appearance: Appearance) -> UIButton {
        let button = UIButton(type: .system)
        let config = UIImage.SymbolConfiguration(pointSize: 15, weight: .bold)
        button.setImage(UIImage(systemName: "plus", withConfiguration: config), for: .normal)
        button.tintColor = appearance.plusTintColor
        button.backgroundColor = appearance.plusBackgroundColor
        button.layer.cornerRadius = 16
        button.layer.cornerCurve = .continuous
        button.clipsToBounds = true
        button.accessibilityLabel = L10n.t("chat.reaction.more")
        button.translatesAutoresizingMaskIntoConstraints = false
        button.widthAnchor.constraint(equalToConstant: 32).isActive = true
        button.heightAnchor.constraint(equalToConstant: 32).isActive = true
        button.addAction(UIAction { [weak self] _ in
            self?.onMoreSelected?()
        }, for: .touchUpInside)
        return button
    }
}
