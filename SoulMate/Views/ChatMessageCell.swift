import UIKit
#if canImport(SDWebImage)
import SDWebImage
#endif

final class ChatMessageCell: UITableViewCell {
    static let reuseIdentifier = "ChatMessageCell"
    private let defaultGIFLoopCount = 3
    private let manualReplayLoopCount = 1

    private let bubbleView = UIView()
    private let messageLabel = UILabel()
    #if canImport(SDWebImage)
    private let gifImageView = SDAnimatedImageView()
    #else
    private let gifImageView = UIImageView()
    #endif
    private let scratchRevealView = ScratchRevealView()

    private var leadingConstraint: NSLayoutConstraint!
    private var trailingConstraint: NSLayoutConstraint!
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
        messageLabel.text = nil
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
        gifImageView.isHidden = true
        gifHeightConstraint.constant = 0
        messageLabel.isHidden = false
        messageTopConstraint.isActive = true
        messageBottomConstraint.isActive = true
        gifTopConstraint.isActive = false
        gifBottomConstraint.isActive = false
        scratchRevealView.isHidden = true
        scratchRevealView.reset()
    }

    func setGIFPlaybackEnabled(_ enabled: Bool) {
        isGIFPlaybackEnabled = enabled
        updateGIFPlaybackState()
    }

    func configure(with message: ChatMessage, isOutgoing: Bool) {
        leadingConstraint.isActive = !isOutgoing
        trailingConstraint.isActive = isOutgoing

        let isDark = traitCollection.userInterfaceStyle == .dark
        bubbleView.backgroundColor = isOutgoing
            ? UIColor(red: 0.86, green: 0.18, blue: 0.44, alpha: 0.92)
            : (isDark ? UIColor(red: 0.16, green: 0.17, blue: 0.22, alpha: 0.96) : UIColor.white.withAlphaComponent(0.95))
        bubbleView.layer.borderColor = isOutgoing
            ? UIColor(red: 0.78, green: 0.12, blue: 0.36, alpha: 0.8).cgColor
            : (isDark ? UIColor(red: 0.32, green: 0.34, blue: 0.41, alpha: 1).cgColor : UIColor.systemGray5.cgColor)
        bubbleView.layer.borderWidth = 1
        messageLabel.textColor = isOutgoing ? .white : (isDark ? UIColor(red: 0.93, green: 0.93, blue: 0.97, alpha: 1) : .label)

        switch message.type {
        case .text:
            isGIFContent = false
            currentGIFURLString = nil
            hasPlayedInitialGIF = false
            messageLabel.text = message.value
            messageLabel.font = UIFont(name: "AvenirNext-Medium", size: 17) ?? .systemFont(ofSize: 17, weight: .medium)
            gifImageView.isHidden = true
            gifHeightConstraint.constant = 0
            messageLabel.isHidden = false
            messageTopConstraint.isActive = true
            messageBottomConstraint.isActive = true
            gifTopConstraint.isActive = false
            gifBottomConstraint.isActive = false

        case .emoji:
            isGIFContent = false
            currentGIFURLString = nil
            hasPlayedInitialGIF = false
            messageLabel.text = message.value
            messageLabel.font = .systemFont(ofSize: 34)
            gifImageView.isHidden = true
            gifHeightConstraint.constant = 0
            messageLabel.isHidden = false
            messageTopConstraint.isActive = true
            messageBottomConstraint.isActive = true
            gifTopConstraint.isActive = false
            gifBottomConstraint.isActive = false

        case .nudge:
            isGIFContent = false
            currentGIFURLString = nil
            hasPlayedInitialGIF = false
            messageLabel.text = "\(message.value)"
            messageLabel.font = UIFont(name: "AvenirNext-DemiBold", size: 17) ?? .systemFont(ofSize: 17, weight: .semibold)
            gifImageView.isHidden = true
            gifHeightConstraint.constant = 0
            messageLabel.isHidden = false
            messageTopConstraint.isActive = true
            messageBottomConstraint.isActive = true
            gifTopConstraint.isActive = false
            gifBottomConstraint.isActive = false

        case .gif:
            isGIFContent = true
            gifImageView.isHidden = false
            gifHeightConstraint.constant = 180
            messageLabel.isHidden = true
            messageTopConstraint.isActive = false
            messageBottomConstraint.isActive = false
            gifTopConstraint.isActive = true
            gifBottomConstraint.isActive = true

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
                gifImageView.isHidden = true
                gifHeightConstraint.constant = 0
                messageLabel.isHidden = false
                messageLabel.text = message.value
                messageLabel.font = .preferredFont(forTextStyle: .caption1)
                messageTopConstraint.isActive = true
                messageBottomConstraint.isActive = true
                gifTopConstraint.isActive = false
                gifBottomConstraint.isActive = false
            }
        }

        let shouldMask = message.isSecret && !isOutgoing
        scratchRevealView.isHidden = !shouldMask
        scratchRevealView.reset()
        updateGIFPlaybackState()
    }

    @objc private func handleGIFTap() {
        guard isGIFContent, !gifImageView.isHidden else { return }
        playGIFOnceByUserInteraction()
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

    private func setupUI() {
        bubbleView.layer.cornerRadius = 20
        bubbleView.layer.cornerCurve = .continuous
        bubbleView.layer.shadowColor = UIColor.black.cgColor
        bubbleView.layer.shadowOpacity = 0.06
        bubbleView.layer.shadowOffset = CGSize(width: 0, height: 3)
        bubbleView.layer.shadowRadius = 10
        bubbleView.translatesAutoresizingMaskIntoConstraints = false
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

        scratchRevealView.translatesAutoresizingMaskIntoConstraints = false
        scratchRevealView.isHidden = true

        bubbleView.addSubview(messageLabel)
        bubbleView.addSubview(gifImageView)
        bubbleView.addSubview(scratchRevealView)

        leadingConstraint = bubbleView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 14)
        trailingConstraint = bubbleView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -14)
        gifHeightConstraint = gifImageView.heightAnchor.constraint(equalToConstant: 0)
        messageTopConstraint = messageLabel.topAnchor.constraint(equalTo: bubbleView.topAnchor, constant: 10)
        messageBottomConstraint = messageLabel.bottomAnchor.constraint(equalTo: bubbleView.bottomAnchor, constant: -10)
        gifTopConstraint = gifImageView.topAnchor.constraint(equalTo: bubbleView.topAnchor, constant: 8)
        gifBottomConstraint = gifImageView.bottomAnchor.constraint(equalTo: bubbleView.bottomAnchor, constant: -8)

        NSLayoutConstraint.activate([
            bubbleView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 6),
            bubbleView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -6),
            bubbleView.widthAnchor.constraint(lessThanOrEqualTo: contentView.widthAnchor, multiplier: 0.78),

            messageLabel.leadingAnchor.constraint(equalTo: bubbleView.leadingAnchor, constant: 12),
            messageLabel.trailingAnchor.constraint(equalTo: bubbleView.trailingAnchor, constant: -12),
            messageTopConstraint,
            messageBottomConstraint,

            gifImageView.leadingAnchor.constraint(equalTo: bubbleView.leadingAnchor, constant: 8),
            gifImageView.trailingAnchor.constraint(equalTo: bubbleView.trailingAnchor, constant: -8),
            gifTopConstraint,
            gifBottomConstraint,
            gifHeightConstraint,

            scratchRevealView.topAnchor.constraint(equalTo: bubbleView.topAnchor),
            scratchRevealView.bottomAnchor.constraint(equalTo: bubbleView.bottomAnchor),
            scratchRevealView.leadingAnchor.constraint(equalTo: bubbleView.leadingAnchor),
            scratchRevealView.trailingAnchor.constraint(equalTo: bubbleView.trailingAnchor)
        ])

        leadingConstraint.isActive = true
        gifTopConstraint.isActive = false
        gifBottomConstraint.isActive = false
    }
}
