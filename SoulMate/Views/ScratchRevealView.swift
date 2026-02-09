import UIKit

final class ScratchRevealView: UIView {
    private let coverView = UIView()
    private let hintLabel = UILabel()

    private let maskLayer = CAShapeLayer()
    private let revealPath = UIBezierPath()

    private var scratchHits = 0
    private let maxHitsToReveal = 42

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        refreshMaskPathIfNeeded()
    }

    func reset() {
        scratchHits = 0
        revealPath.removeAllPoints()
        refreshMaskPathIfNeeded()
        coverView.alpha = 1.0
    }

    private func setupUI() {
        backgroundColor = .clear
        isUserInteractionEnabled = true

        coverView.backgroundColor = UIColor.black.withAlphaComponent(0.88)
        coverView.translatesAutoresizingMaskIntoConstraints = false
        coverView.layer.cornerRadius = 20
        addSubview(coverView)

        hintLabel.text = L10n.t("scratch.hint")
        hintLabel.font = .preferredFont(forTextStyle: .caption1)
        hintLabel.textColor = .white
        hintLabel.textAlignment = .center
        hintLabel.translatesAutoresizingMaskIntoConstraints = false
        coverView.addSubview(hintLabel)

        NSLayoutConstraint.activate([
            coverView.topAnchor.constraint(equalTo: topAnchor),
            coverView.bottomAnchor.constraint(equalTo: bottomAnchor),
            coverView.leadingAnchor.constraint(equalTo: leadingAnchor),
            coverView.trailingAnchor.constraint(equalTo: trailingAnchor),

            hintLabel.centerXAnchor.constraint(equalTo: coverView.centerXAnchor),
            hintLabel.centerYAnchor.constraint(equalTo: coverView.centerYAnchor)
        ])

        maskLayer.fillRule = .evenOdd
        coverView.layer.mask = maskLayer
    }

    private func refreshMaskPathIfNeeded() {
        let fullRect = UIBezierPath(rect: bounds)
        fullRect.append(revealPath)
        maskLayer.path = fullRect.cgPath
    }

    private func scratch(at point: CGPoint) {
        let radius: CGFloat = 17
        let ovalRect = CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)
        revealPath.append(UIBezierPath(ovalIn: ovalRect))
        scratchHits += 1
        refreshMaskPathIfNeeded()

        if scratchHits >= maxHitsToReveal {
            UIView.animate(withDuration: 0.2) {
                self.coverView.alpha = 0
            }
        }
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let point = touches.first?.location(in: self) else { return }
        scratch(at: point)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let point = touches.first?.location(in: self) else { return }
        scratch(at: point)
    }
}
