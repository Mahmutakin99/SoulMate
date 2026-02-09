import UIKit

final class PairingViewController: UIViewController {
    var onPaired: (() -> Void)?
    var onBackToChat: (() -> Void)?

    private let viewModel: PairingViewModel
    private let autoOpenChatWhenPaired: Bool

    private let titleLabel = UILabel()
    private let statusLabel = UILabel()
    private let pairCodeCard = UILabel()
    private let partnerCodeField = UITextField()
    private let pairButton = UIButton(type: .system)
    private let clearPairButton = UIButton(type: .system)
    private let openChatButton = UIButton(type: .system)
    private let activity = UIActivityIndicatorView(style: .medium)

    init(viewModel: PairingViewModel = PairingViewModel(), autoOpenChatWhenPaired: Bool = true) {
        self.viewModel = viewModel
        self.autoOpenChatWhenPaired = autoOpenChatWhenPaired
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        title = L10n.t("pairing.nav_title")
        setupUI()
        bindViewModel()
        viewModel.start()
    }

    private func setupUI() {
        titleLabel.text = L10n.t("pairing.title")
        titleLabel.font = UIFont(name: "AvenirNext-Bold", size: 32) ?? .systemFont(ofSize: 32, weight: .bold)
        titleLabel.textAlignment = .center

        statusLabel.numberOfLines = 0
        statusLabel.textAlignment = .center
        statusLabel.font = UIFont(name: "AvenirNext-Medium", size: 15) ?? .systemFont(ofSize: 15, weight: .medium)
        statusLabel.textColor = .secondaryLabel
        statusLabel.text = L10n.t("pairing.status.initial_loading")

        pairCodeCard.textAlignment = .center
        pairCodeCard.font = UIFont(name: "AvenirNext-Bold", size: 28) ?? .systemFont(ofSize: 28, weight: .bold)
        pairCodeCard.layer.cornerRadius = 14
        pairCodeCard.layer.cornerCurve = .continuous
        pairCodeCard.clipsToBounds = true
        pairCodeCard.backgroundColor = UIColor.secondarySystemBackground
        pairCodeCard.text = L10n.t("pairing.pair_code.default")

        partnerCodeField.placeholder = L10n.t("pairing.partner_code.placeholder")
        partnerCodeField.borderStyle = .none
        partnerCodeField.keyboardType = .numberPad
        partnerCodeField.layer.cornerRadius = 12
        partnerCodeField.layer.cornerCurve = .continuous
        partnerCodeField.layer.borderWidth = 1
        partnerCodeField.layer.borderColor = UIColor.systemGray5.cgColor
        partnerCodeField.backgroundColor = UIColor.secondarySystemBackground
        partnerCodeField.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 12, height: 1))
        partnerCodeField.leftViewMode = .always
        partnerCodeField.translatesAutoresizingMaskIntoConstraints = false

        var pairConfig = UIButton.Configuration.filled()
        pairConfig.cornerStyle = .capsule
        pairConfig.baseBackgroundColor = UIColor(red: 0.86, green: 0.18, blue: 0.44, alpha: 1)
        pairConfig.baseForegroundColor = .white
        pairConfig.title = L10n.t("pairing.button.pair")
        pairButton.configuration = pairConfig
        pairButton.addTarget(self, action: #selector(pairTapped), for: .touchUpInside)

        var clearConfig = UIButton.Configuration.tinted()
        clearConfig.cornerStyle = .capsule
        clearConfig.baseForegroundColor = .systemRed
        clearConfig.title = L10n.t("pairing.button.unpair")
        clearPairButton.configuration = clearConfig
        clearPairButton.addTarget(self, action: #selector(clearPairTapped), for: .touchUpInside)
        clearPairButton.isHidden = true

        var openChatConfig = UIButton.Configuration.tinted()
        openChatConfig.cornerStyle = .capsule
        openChatConfig.baseForegroundColor = UIColor(red: 0.2, green: 0.42, blue: 0.86, alpha: 1)
        openChatConfig.title = L10n.t("pairing.button.back_to_chat")
        openChatButton.configuration = openChatConfig
        openChatButton.addTarget(self, action: #selector(openChatTapped), for: .touchUpInside)
        openChatButton.isHidden = true

        activity.hidesWhenStopped = true

        let stack = UIStackView(arrangedSubviews: [
            titleLabel,
            statusLabel,
            pairCodeCard,
            partnerCodeField,
            pairButton,
            clearPairButton,
            openChatButton,
            activity
        ])
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 24),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),

            pairCodeCard.heightAnchor.constraint(equalToConstant: 72),
            partnerCodeField.heightAnchor.constraint(equalToConstant: 48),
            pairButton.heightAnchor.constraint(equalToConstant: 48),
            clearPairButton.heightAnchor.constraint(equalToConstant: 44),
            openChatButton.heightAnchor.constraint(equalToConstant: 44)
        ])
    }

    private func bindViewModel() {
        viewModel.onPairCodeUpdated = { [weak self] code in
            self?.pairCodeCard.text = L10n.f("pairing.pair_code.format", code)
        }

        viewModel.onStateChanged = { [weak self] state, message in
            self?.render(state: state, message: message)
        }

        viewModel.onError = { [weak self] message in
            let alert = UIAlertController(title: L10n.t("common.error_title"), message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: L10n.t("common.ok"), style: .default))
            self?.present(alert, animated: true)
        }

        viewModel.onPaired = { [weak self] _ in
            guard let self else { return }
            if self.autoOpenChatWhenPaired {
                self.onPaired?()
            }
        }
    }

    private func render(state: PairingViewModel.State, message: String) {
        statusLabel.text = message

        switch state {
        case .loading:
            pairButton.isEnabled = false
            clearPairButton.isEnabled = false
            activity.startAnimating()

        case .notPaired:
            pairButton.isEnabled = true
            clearPairButton.isHidden = true
            openChatButton.isHidden = true
            activity.stopAnimating()

        case .waiting:
            pairButton.isEnabled = true
            clearPairButton.isHidden = false
            openChatButton.isHidden = true
            clearPairButton.isEnabled = true
            activity.stopAnimating()

        case .paired:
            pairButton.isEnabled = false
            clearPairButton.isHidden = false
            clearPairButton.isEnabled = true
            openChatButton.isHidden = autoOpenChatWhenPaired
            activity.stopAnimating()
        }
    }

    @objc private func pairTapped() {
        view.endEditing(true)
        viewModel.pair(with: partnerCodeField.text ?? "")
    }

    @objc private func clearPairTapped() {
        viewModel.clearPairing()
    }

    @objc private func openChatTapped() {
        onBackToChat?()
    }
}
