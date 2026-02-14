//
//  ReactionEmojiPanelViewController.swift
//  SoulMate
//
//  Created by MAHMUT AKIN on 14/02/2026.
//

import UIKit

final class ReactionEmojiPanelViewController: UIViewController {
    enum Section: Int, CaseIterable {
        case frequent
        case all
    }

    struct Appearance {
        let backgroundColor: UIColor
        let sectionTitleColor: UIColor
        let emojiBackgroundColor: UIColor
        let emojiTextColor: UIColor
    }

    static let curatedEmojiList: [String] = [
        "❤️", "😂", "🥰", "🔥", "😮", "😢", "👍", "🙏", "👏", "🤝",
        "😘", "😍", "🤣", "😁", "😅", "🙂", "🙃", "😉", "🤗", "😎",
        "🤔", "🥳", "🤩", "😴", "😤", "😡", "😭", "🤯", "🙌", "👌",
        "💪", "👀", "✅", "❌", "🎉", "💯", "✨", "🌟", "🌈", "☀️",
        "🌙", "⚡️", "☕️", "🍀", "🍕", "🍰", "🎂", "🎁", "🎵", "🎶",
        "🚀", "🏆", "⚽️", "🏀", "🎮", "📸", "🫶", "🤍", "💙", "💜",
        "🧠", "😇", "🤍", "😬", "🙈", "🙉", "🙊", "😌", "😋", "🤤",
        "🤞", "✌️", "🤌", "🫡", "😓", "🤕", "🤒", "🤠", "🥲", "🫠"
    ]

    var onEmojiSelected: ((String) -> Void)?

    private let frequentEmojis: [String]
    private let allEmojis: [String]
    private let appearance: Appearance

    private lazy var collectionViewLayout: UICollectionViewFlowLayout = {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .vertical
        layout.minimumInteritemSpacing = 10
        layout.minimumLineSpacing = 12
        layout.sectionInset = UIEdgeInsets(top: 12, left: 14, bottom: 16, right: 14)
        layout.headerReferenceSize = CGSize(width: 100, height: 30)
        return layout
    }()

    private lazy var collectionView: UICollectionView = {
        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: collectionViewLayout)
        collectionView.backgroundColor = .clear
        collectionView.showsVerticalScrollIndicator = true
        collectionView.alwaysBounceVertical = true
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.register(ReactionEmojiCell.self, forCellWithReuseIdentifier: ReactionEmojiCell.reuseIdentifier)
        collectionView.register(
            ReactionEmojiSectionHeaderView.self,
            forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader,
            withReuseIdentifier: ReactionEmojiSectionHeaderView.reuseIdentifier
        )
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        return collectionView
    }()

    init(
        frequentEmojis: [String],
        allEmojis: [String] = ReactionEmojiPanelViewController.curatedEmojiList,
        appearance: Appearance
    ) {
        self.frequentEmojis = Array(NSOrderedSet(array: frequentEmojis).array as? [String] ?? [])
        self.allEmojis = Array(NSOrderedSet(array: allEmojis).array as? [String] ?? [])
        self.appearance = appearance
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .pageSheet
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = appearance.backgroundColor
        setupUI()
        configureSheetIfAvailable()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateItemSize()
    }

    private func setupUI() {
        let titleLabel = UILabel()
        titleLabel.text = L10n.t("chat.reaction.panel.title")
        titleLabel.textColor = appearance.sectionTitleColor
        titleLabel.font = UIFont(name: "AvenirNext-DemiBold", size: 16) ?? .systemFont(ofSize: 16, weight: .semibold)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(titleLabel)
        view.addSubview(collectionView)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 10),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 18),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -18),

            collectionView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 6),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        ])
    }

    private func configureSheetIfAvailable() {
        if let sheet = sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
            sheet.preferredCornerRadius = 20
        }
    }

    private func updateItemSize() {
        let columns: CGFloat = 8
        let horizontalInsets = collectionViewLayout.sectionInset.left + collectionViewLayout.sectionInset.right
        let totalSpacing = (columns - 1) * collectionViewLayout.minimumInteritemSpacing
        let availableWidth = max(0, collectionView.bounds.width - horizontalInsets - totalSpacing)
        let side = max(34, floor(availableWidth / columns))
        collectionViewLayout.itemSize = CGSize(width: side, height: 38)
    }
}

extension ReactionEmojiPanelViewController: UICollectionViewDataSource {
    func numberOfSections(in _: UICollectionView) -> Int {
        Section.allCases.count
    }

    func collectionView(_: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        guard let sectionKind = Section(rawValue: section) else { return 0 }
        switch sectionKind {
        case .frequent:
            return frequentEmojis.count
        case .all:
            return allEmojis.count
        }
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        guard let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: ReactionEmojiCell.reuseIdentifier,
            for: indexPath
        ) as? ReactionEmojiCell else {
            return UICollectionViewCell()
        }

        guard let sectionKind = Section(rawValue: indexPath.section) else {
            return UICollectionViewCell()
        }

        let emoji: String
        switch sectionKind {
        case .frequent:
            emoji = frequentEmojis[indexPath.item]
        case .all:
            emoji = allEmojis[indexPath.item]
        }

        cell.configure(emoji: emoji, appearance: appearance)
        return cell
    }

    func collectionView(
        _ collectionView: UICollectionView,
        viewForSupplementaryElementOfKind kind: String,
        at indexPath: IndexPath
    ) -> UICollectionReusableView {
        guard kind == UICollectionView.elementKindSectionHeader else {
            return UICollectionReusableView()
        }
        guard let header = collectionView.dequeueReusableSupplementaryView(
            ofKind: kind,
            withReuseIdentifier: ReactionEmojiSectionHeaderView.reuseIdentifier,
            for: indexPath
        ) as? ReactionEmojiSectionHeaderView else {
            return UICollectionReusableView()
        }

        if indexPath.section == Section.frequent.rawValue {
            header.configure(title: L10n.t("chat.reaction.panel.section.frequent"), color: appearance.sectionTitleColor)
        } else {
            header.configure(title: L10n.t("chat.reaction.panel.section.all"), color: appearance.sectionTitleColor)
        }
        return header
    }
}

extension ReactionEmojiPanelViewController: UICollectionViewDelegate {
    func collectionView(_: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard let sectionKind = Section(rawValue: indexPath.section) else { return }
        let emoji: String
        switch sectionKind {
        case .frequent:
            emoji = frequentEmojis[indexPath.item]
        case .all:
            emoji = allEmojis[indexPath.item]
        }

        dismiss(animated: true) { [weak self] in
            self?.onEmojiSelected?(emoji)
        }
    }
}

private final class ReactionEmojiCell: UICollectionViewCell {
    static let reuseIdentifier = "ReactionEmojiCell"

    private let emojiLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.layer.cornerRadius = 12
        contentView.layer.cornerCurve = .continuous
        contentView.clipsToBounds = true

        emojiLabel.font = .systemFont(ofSize: 26)
        emojiLabel.textAlignment = .center
        emojiLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(emojiLabel)

        NSLayoutConstraint.activate([
            emojiLabel.topAnchor.constraint(equalTo: contentView.topAnchor),
            emojiLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            emojiLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            emojiLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(emoji: String, appearance: ReactionEmojiPanelViewController.Appearance) {
        emojiLabel.text = emoji
        emojiLabel.textColor = appearance.emojiTextColor
        contentView.backgroundColor = appearance.emojiBackgroundColor
        accessibilityLabel = "Reaksiyon: \(emoji)"
    }
}

private final class ReactionEmojiSectionHeaderView: UICollectionReusableView {
    static let reuseIdentifier = "ReactionEmojiSectionHeaderView"

    private let titleLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        titleLabel.font = UIFont(name: "AvenirNext-DemiBold", size: 13) ?? .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)
        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -16),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(title: String, color: UIColor) {
        titleLabel.text = title
        titleLabel.textColor = color
    }
}
