//
//  ChatMessageCell.swift
//  SoulMate
//
//  Created by MAHMUT AKIN on 02/02/2026.
//

import UIKit
#if canImport(SDWebImage)
import SDWebImage
#endif

final class ChatMessageCell: UITableViewCell {
    static let reuseIdentifier = "ChatMessageCell"

    private static let outgoingBubble = UIColor(red: 0.86, green: 0.18, blue: 0.44, alpha: 0.92)
    private static let incomingBubbleDark = UIColor(red: 0.16, green: 0.17, blue: 0.22, alpha: 0.96)
    private static let outgoingBorder = UIColor(red: 0.78, green: 0.12, blue: 0.36, alpha: 0.8)
    private static let incomingBorderDark = UIColor(red: 0.32, green: 0.34, blue: 0.41, alpha: 1)
    private static let incomingTextDark = UIColor(red: 0.93, green: 0.93, blue: 0.97, alpha: 1)
    private static let metaOutgoing = UIColor.white.withAlphaComponent(0.86)
    private static let metaIncomingDark = UIColor(red: 0.75, green: 0.76, blue: 0.84, alpha: 1)
    private static let readTickColor = UIColor(red: 0.56, green: 0.93, blue: 1.0, alpha: 1)

    private static let textFont = UIFont(name: "AvenirNext-Medium", size: 17) ?? .systemFont(ofSize: 17, weight: .medium)
    private static let nudgeFont = UIFont(name: "AvenirNext-DemiBold", size: 17) ?? .systemFont(ofSize: 17, weight: .semibold)
    private static let emojiFont = UIFont.systemFont(ofSize: 34)
    private static let metaFont = UIFont(name: "AvenirNext-Medium", size: 11) ?? .systemFont(ofSize: 11, weight: .medium)
    private static let reactionFont = UIFont.systemFont(ofSize: 14)
    private static let fallbackTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private let defaultGIFLoopCount = 3
    private let manualReplayLoopCount = 1
    var onSecretRevealed: (() -> Void)?
    var onReactionLongPress: ((UIView) -> Void)?

    private let bubbleView = UIView()
    private let messageLabel = UILabel()
    #if canImport(SDWebImage)
    private let gifImageView = SDAnimatedImageView()
    #else
    private let gifImageView = UIImageView()
    #endif
    private let scratchRevealView = ScratchRevealView()
    private let metaLabel = UILabel()
    private let reactionChipLabel = UILabel()

    private var minLeadingConstraint: NSLayoutConstraint!
    private var maxTrailingConstraint: NSLayoutConstraint!
    private var incomingAlignmentConstraint: NSLayoutConstraint!
    private var outgoingAlignmentConstraint: NSLayoutConstraint!
    private var reactionIncomingAlignmentConstraint: NSLayoutConstraint!
    private var reactionOutgoingAlignmentConstraint: NSLayoutConstraint!
    private var bubbleBottomConstraint: NSLayoutConstraint!
    private var reactionHeightConstraint: NSLayoutConstraint!
    private var gifHeightConstraint: NSLayoutConstraint!
    private var gifTopConstraint: NSLayoutConstraint!
    private var gifBottomConstraint: NSLayoutConstraint!
    private var messageTopConstraint: NSLayoutConstraint!
    private var messageBottomConstraint: NSLayoutConstraint!

    private var isGIFContent = false
    private var isGIFPlaybackEnabled = true
    private var currentGIFURLString: String?
    private var hasPlayedInitialGIF = false

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        backgroundColor = .clear
        contentView.backgroundColor = .clear
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        onSecretRevealed = nil
        onReactionLongPress = nil
        messageLabel.text = nil
        metaLabel.text = nil
        reactionChipLabel.text = nil
        reactionChipLabel.isHidden = true
        currentGIFURLString = nil
        isGIFContent = false
        isGIFPlaybackEnabled = true
        hasPlayedInitialGIF = false
        #if canImport(SDWebImage)
        gifImageView.sd_cancelCurrentImageLoad()
        #endif
        resetGIFLoopMode(loopCount: defaultGIFLoopCount)
        gifImageView.stopAnimating()
        gifImageView.image = nil
        setContentLayout(messageVisible: true, gifVisible: false, gifHeight: 0)
        setReactionVisibility(false)
        outgoingAlignmentConstraint.isActive = false
        incomingAlignmentConstraint.isActive = true
        reactionOutgoingAlignmentConstraint.isActive = false
        reactionIncomingAlignmentConstraint.isActive = true
        scratchRevealView.isHidden = true
        scratchRevealView.onFullyRevealed = nil
        scratchRevealView.reset()
    }

    func setGIFPlaybackEnabled(_ enabled: Bool) {
        isGIFPlaybackEnabled = enabled
        updateGIFPlaybackState()
    }

    func releaseGIFImageFromMemory() {
        guard isGIFContent else { return }
        gifImageView.stopAnimating()
        #if canImport(SDWebImage)
        gifImageView.sd_cancelCurrentImageLoad()
        #endif
        gifImageView.image = nil
        currentGIFURLString = nil
        hasPlayedInitialGIF = false
    }

    func configure(
        with message: ChatMessage,
        isOutgoing: Bool,
        isSecretRevealed: Bool = false,
        meta: ChatMessageMeta?
    ) {
        setBubbleAlignment(isOutgoing: isOutgoing)

        bubbleView.backgroundColor = isOutgoing
            ? Self.outgoingBubble
            : Self.incomingBubbleDark
        bubbleView.layer.borderColor = isOutgoing
            ? Self.outgoingBorder.cgColor
            : Self.incomingBorderDark.cgColor
        bubbleView.layer.borderWidth = 1
        messageLabel.textColor = isOutgoing ? .white : Self.incomingTextDark

        configureMeta(meta: meta, fallbackDate: message.sentAt, isOutgoing: isOutgoing)
        configureReactionChip(meta: meta, isOutgoing: isOutgoing)

        switch message.type {
        case .text:
            isGIFContent = false
            currentGIFURLString = nil
            hasPlayedInitialGIF = false
            messageLabel.text = message.value
            messageLabel.font = Self.textFont
            setContentLayout(messageVisible: true, gifVisible: false, gifHeight: 0)

        case .emoji:
            isGIFContent = false
            currentGIFURLString = nil
            hasPlayedInitialGIF = false
            messageLabel.text = message.value
            messageLabel.font = Self.emojiFont
            setContentLayout(messageVisible: true, gifVisible: false, gifHeight: 0)

        case .nudge:
            isGIFContent = false
            currentGIFURLString = nil
            hasPlayedInitialGIF = false
            messageLabel.text = message.value
            messageLabel.font = Self.nudgeFont
            setContentLayout(messageVisible: true, gifVisible: false, gifHeight: 0)

        case .gif:
            isGIFContent = true
            setContentLayout(messageVisible: false, gifVisible: true, gifHeight: 180)

            if let url = URL(string: message.value) {
                #if canImport(SDWebImage)
                if currentGIFURLString != message.value {
                    currentGIFURLString = message.value
                    hasPlayedInitialGIF = false
                    resetGIFLoopMode(loopCount: defaultGIFLoopCount)
                    gifImageView.sd_setImage(with: url, placeholderImage: nil, options: [.scaleDownLargeImages]) { [weak self] _, _, _, _ in
                        self?.updateGIFPlaybackState()
                    }
                }
                #else
                messageLabel.isHidden = false
                messageLabel.text = message.value
                messageLabel.font = .preferredFont(forTextStyle: .caption1)
                gifImageView.isHidden = true
                #endif
            } else {
                isGIFContent = false
                currentGIFURLString = nil
                hasPlayedInitialGIF = false
                messageLabel.text = message.value
                messageLabel.font = .preferredFont(forTextStyle: .caption1)
                setContentLayout(messageVisible: true, gifVisible: false, gifHeight: 0)
            }
        }

        let shouldMask = message.isSecret && !isOutgoing && !isSecretRevealed
        if shouldMask {
            scratchRevealView.reset()
            scratchRevealView.isHidden = false
            scratchRevealView.onFullyRevealed = { [weak self] in
                self?.scratchRevealView.isHidden = true
                self?.onSecretRevealed?()
            }
        } else {
            scratchRevealView.onFullyRevealed = nil
            scratchRevealView.isHidden = true
            if message.isSecret && !isOutgoing && isSecretRevealed {
                scratchRevealView.revealPermanently(animated: false)
            } else {
                scratchRevealView.reset()
            }
        }
        updateGIFPlaybackState()
    }

    @objc private func handleBubbleLongPress(_ recognizer: UILongPressGestureRecognizer) {
        guard recognizer.state == .began else { return }
        onReactionLongPress?(bubbleView)
    }

    @objc private func handleGIFTap() {
        guard isGIFContent, !gifImageView.isHidden else { return }
        playGIFOnceByUserInteraction()
    }

    private func configureMeta(meta: ChatMessageMeta?, fallbackDate: Date, isOutgoing: Bool) {
        metaLabel.textAlignment = isOutgoing ? .right : .left
        let timeText = meta?.timeText ?? Self.fallbackTimeFormatter.string(from: fallbackDate)
        if isOutgoing, let deliveryState = meta?.deliveryState {
            switch deliveryState {
            case .sent:
                metaLabel.text = "\(timeText)  ✓"
                metaLabel.textColor = Self.metaOutgoing
            case .delivered:
                metaLabel.text = "\(timeText)  ✓✓"
                metaLabel.textColor = Self.metaOutgoing
            case .read:
                metaLabel.text = "\(timeText)  ✓✓"
                metaLabel.textColor = Self.readTickColor
            }
        } else {
            metaLabel.text = timeText
            metaLabel.textColor = isOutgoing ? Self.metaOutgoing : Self.metaIncomingDark
        }
    }

    private func configureReactionChip(meta: ChatMessageMeta?, isOutgoing: Bool) {
        let reactions = (meta?.reactions ?? []).sorted {
            if $0.updatedAt == $1.updatedAt {
                return $0.reactorUID < $1.reactorUID
            }
            return $0.updatedAt < $1.updatedAt
        }

        if reactions.isEmpty {
            reactionChipLabel.text = nil
            setReactionVisibility(false)
            return
        }

        reactionChipLabel.text = reactions.map(\.emoji).joined(separator: " ")
        reactionChipLabel.backgroundColor = isOutgoing
            ? UIColor.white.withAlphaComponent(0.2)
            : UIColor.white.withAlphaComponent(0.12)
        reactionChipLabel.textColor = isOutgoing ? .white : Self.incomingTextDark
        setReactionVisibility(true)
    }

    private func updateGIFPlaybackState() {
        guard isGIFContent, !gifImageView.isHidden else {
            gifImageView.stopAnimating()
            return
        }

        guard isGIFPlaybackEnabled else {
            gifImageView.stopAnimating()
            return
        }

        guard gifImageView.image != nil else { return }

        #if canImport(SDWebImage)
        if !hasPlayedInitialGIF {
            hasPlayedInitialGIF = true
            resetGIFLoopMode(loopCount: defaultGIFLoopCount)
            gifImageView.startAnimating()
            return
        }

        if gifImageView.animationRepeatCount == defaultGIFLoopCount,
           gifImageView.currentLoopCount < defaultGIFLoopCount,
           !gifImageView.isAnimating {
            gifImageView.startAnimating()
        }
        #else
        if !hasPlayedInitialGIF {
            hasPlayedInitialGIF = true
            gifImageView.startAnimating()
        }
        #endif
    }

    private func playGIFOnceByUserInteraction() {
        guard isGIFPlaybackEnabled else { return }
        guard gifImageView.image != nil else { return }

        #if canImport(SDWebImage)
        gifImageView.shouldCustomLoopCount = true
        gifImageView.animationRepeatCount = manualReplayLoopCount
        gifImageView.resetFrameIndexWhenStopped = true
        gifImageView.stopAnimating()
        gifImageView.resetFrameIndexWhenStopped = false
        gifImageView.startAnimating()
        #else
        gifImageView.stopAnimating()
        gifImageView.startAnimating()
        #endif
    }

    private func resetGIFLoopMode(loopCount: Int) {
        #if canImport(SDWebImage)
        gifImageView.shouldCustomLoopCount = true
        gifImageView.animationRepeatCount = loopCount
        gifImageView.clearBufferWhenStopped = true
        gifImageView.resetFrameIndexWhenStopped = false
        gifImageView.autoPlayAnimatedImage = false
        #else
        _ = loopCount
        #endif
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        bubbleView.layer.shadowPath = UIBezierPath(
            roundedRect: bubbleView.bounds,
            cornerRadius: bubbleView.layer.cornerRadius
        ).cgPath
    }

    private func setupUI() {
        bubbleView.layer.cornerRadius = 20
        bubbleView.layer.cornerCurve = .continuous
        bubbleView.layer.shadowColor = UIColor.black.cgColor
        bubbleView.layer.shadowOpacity = 0.06
        bubbleView.layer.shadowOffset = CGSize(width: 0, height: 3)
        bubbleView.layer.shadowRadius = 10
        bubbleView.translatesAutoresizingMaskIntoConstraints = false
        bubbleView.addGestureRecognizer(UILongPressGestureRecognizer(target: self, action: #selector(handleBubbleLongPress(_:))))
        contentView.addSubview(bubbleView)

        messageLabel.numberOfLines = 0
        messageLabel.translatesAutoresizingMaskIntoConstraints = false

        gifImageView.contentMode = .scaleAspectFill
        gifImageView.clipsToBounds = true
        gifImageView.layer.cornerRadius = 14
        gifImageView.isUserInteractionEnabled = true
        gifImageView.translatesAutoresizingMaskIntoConstraints = false
        gifImageView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handleGIFTap)))
        resetGIFLoopMode(loopCount: defaultGIFLoopCount)

        metaLabel.font = Self.metaFont
        metaLabel.textAlignment = .right
        metaLabel.translatesAutoresizingMaskIntoConstraints = false

        reactionChipLabel.font = Self.reactionFont
        reactionChipLabel.layer.cornerRadius = 11
        reactionChipLabel.layer.cornerCurve = .continuous
        reactionChipLabel.clipsToBounds = true
        reactionChipLabel.textAlignment = .center
        reactionChipLabel.translatesAutoresizingMaskIntoConstraints = false
        reactionChipLabel.isHidden = true

        scratchRevealView.translatesAutoresizingMaskIntoConstraints = false
        scratchRevealView.isHidden = true

        bubbleView.addSubview(messageLabel)
        bubbleView.addSubview(gifImageView)
        bubbleView.addSubview(metaLabel)
        bubbleView.addSubview(scratchRevealView)
        contentView.addSubview(reactionChipLabel)

        minLeadingConstraint = bubbleView.leadingAnchor.constraint(greaterThanOrEqualTo: contentView.leadingAnchor, constant: 14)
        maxTrailingConstraint = bubbleView.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -14)
        incomingAlignmentConstraint = bubbleView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 14)
        outgoingAlignmentConstraint = bubbleView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -14)
        bubbleBottomConstraint = bubbleView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8)
        reactionIncomingAlignmentConstraint = reactionChipLabel.leadingAnchor.constraint(equalTo: bubbleView.leadingAnchor, constant: 4)
        reactionOutgoingAlignmentConstraint = reactionChipLabel.trailingAnchor.constraint(equalTo: bubbleView.trailingAnchor, constant: -4)
        reactionHeightConstraint = reactionChipLabel.heightAnchor.constraint(equalToConstant: 0)

        gifHeightConstraint = gifImageView.heightAnchor.constraint(equalToConstant: 0)
        messageTopConstraint = messageLabel.topAnchor.constraint(equalTo: bubbleView.topAnchor, constant: 10)
        messageBottomConstraint = messageLabel.bottomAnchor.constraint(equalTo: metaLabel.topAnchor, constant: -6)
        gifTopConstraint = gifImageView.topAnchor.constraint(equalTo: bubbleView.topAnchor, constant: 8)
        gifBottomConstraint = gifImageView.bottomAnchor.constraint(equalTo: metaLabel.topAnchor, constant: -6)

        NSLayoutConstraint.activate([
            bubbleView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 6),
            bubbleView.widthAnchor.constraint(lessThanOrEqualTo: contentView.widthAnchor, multiplier: 0.78),
            minLeadingConstraint,
            maxTrailingConstraint,
            incomingAlignmentConstraint,
            bubbleBottomConstraint,

            messageLabel.leadingAnchor.constraint(equalTo: bubbleView.leadingAnchor, constant: 12),
            messageLabel.trailingAnchor.constraint(equalTo: bubbleView.trailingAnchor, constant: -12),
            messageTopConstraint,
            messageBottomConstraint,

            gifImageView.leadingAnchor.constraint(equalTo: bubbleView.leadingAnchor, constant: 8),
            gifImageView.trailingAnchor.constraint(equalTo: bubbleView.trailingAnchor, constant: -8),
            gifHeightConstraint,

            metaLabel.leadingAnchor.constraint(greaterThanOrEqualTo: bubbleView.leadingAnchor, constant: 12),
            metaLabel.trailingAnchor.constraint(equalTo: bubbleView.trailingAnchor, constant: -12),
            metaLabel.bottomAnchor.constraint(equalTo: bubbleView.bottomAnchor, constant: -8),

            reactionChipLabel.topAnchor.constraint(equalTo: bubbleView.bottomAnchor, constant: 4),
            reactionChipLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -4),
            reactionHeightConstraint,
            reactionChipLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 24),
            reactionIncomingAlignmentConstraint,

            scratchRevealView.topAnchor.constraint(equalTo: bubbleView.topAnchor),
            scratchRevealView.bottomAnchor.constraint(equalTo: bubbleView.bottomAnchor),
            scratchRevealView.leadingAnchor.constraint(equalTo: bubbleView.leadingAnchor),
            scratchRevealView.trailingAnchor.constraint(equalTo: bubbleView.trailingAnchor)
        ])
    }

    private func setBubbleAlignment(isOutgoing: Bool) {
        incomingAlignmentConstraint.isActive = false
        outgoingAlignmentConstraint.isActive = false
        reactionIncomingAlignmentConstraint.isActive = false
        reactionOutgoingAlignmentConstraint.isActive = false

        if isOutgoing {
            outgoingAlignmentConstraint.isActive = true
            reactionOutgoingAlignmentConstraint.isActive = true
        } else {
            incomingAlignmentConstraint.isActive = true
            reactionIncomingAlignmentConstraint.isActive = true
        }
    }

    private func setContentLayout(messageVisible: Bool, gifVisible: Bool, gifHeight: CGFloat) {
        messageTopConstraint.isActive = false
        messageBottomConstraint.isActive = false
        gifTopConstraint.isActive = false
        gifBottomConstraint.isActive = false

        messageLabel.isHidden = !messageVisible
        gifImageView.isHidden = !gifVisible
        gifHeightConstraint.constant = gifHeight

        if messageVisible {
            messageTopConstraint.isActive = true
            messageBottomConstraint.isActive = true
        }

        if gifVisible {
            gifTopConstraint.isActive = true
            gifBottomConstraint.isActive = true
        }
    }

    private func setReactionVisibility(_ visible: Bool) {
        reactionChipLabel.isHidden = !visible
        reactionHeightConstraint.constant = visible ? 22 : 0
        bubbleBottomConstraint.isActive = !visible
    }
}
