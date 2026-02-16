//
//  PairingViewController.swift
//  SoulMate
//
//  Created by MAHMUT AKIN on 02/02/2026.
//

import UIKit

final class PairingViewController: UIViewController {
    var onPaired: (() -> Void)?
    var onBackToChat: (() -> Void)?
    var onRequestSignOut: (() -> Void)?

    private let viewModel: PairingViewModel
    private let autoOpenChatWhenPaired: Bool

    private let titleLabel = UILabel()
    private let statusLabel = UILabel()
    private let partnerInfoCard = UIView()
    private let partnerInfoTitleLabel = UILabel()
    private let partnerNameCaptionLabel = UILabel()
    private let partnerNameValueLabel = UILabel()
    private let partnerCodeCaptionLabel = UILabel()
    private let partnerCodeValueLabel = UILabel()
    private let partnerStateCaptionLabel = UILabel()
    private let partnerStateValueLabel = UILabel()
    private let pairCodeCard = UILabel()
    private let partnerCodeField = UITextField()
    private let pairButton = UIButton(type: .system)
    private let clearPairButton = UIButton(type: .system)
    private let openChatButton = UIButton(type: .system)
    private let requestsTitleLabel = UILabel()
    private let emptyRequestsLabel = UILabel()
    private let requestsTableView = UITableView(frame: .zero, style: .insetGrouped)
    private let activity = UIActivityIndicatorView(style: .medium)
    private let gradientLayer = CAGradientLayer()

    private let relativeDateFormatter = RelativeDateTimeFormatter()
    private var incomingRequests: [RelationshipRequest] = []
    private var pendingAlerts: [UIAlertController] = []
    private var isPresentingQueuedAlert = false

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
        AppVisualTheme.applyBackground(to: view, gradientLayer: gradientLayer)
        title = L10n.t("pairing.nav_title")
        configureNavigationItems()
        setupUI()
        bindViewModel()
        viewModel.start()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        gradientLayer.frame = view.bounds
    }

    private func configureNavigationItems() {
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: L10n.t("pairing.nav.sign_out"),
            style: .plain,
            target: self,
            action: #selector(signOutTapped)
        )
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        presentNextAlertIfPossible()
    }

    private func setupUI() {
        titleLabel.text = L10n.t("pairing.title")
        titleLabel.font = UIFont(name: "AvenirNext-Bold", size: 32) ?? .systemFont(ofSize: 32, weight: .bold)
        titleLabel.textAlignment = .center
        titleLabel.textColor = AppVisualTheme.textPrimary

        statusLabel.numberOfLines = 0
        statusLabel.textAlignment = .center
        statusLabel.font = UIFont(name: "AvenirNext-Medium", size: 15) ?? .systemFont(ofSize: 15, weight: .medium)
        statusLabel.textColor = AppVisualTheme.textSecondary
        statusLabel.text = L10n.t("pairing.status.initial_loading")

        configurePartnerInfoCard()

        pairCodeCard.textAlignment = .center
        pairCodeCard.font = UIFont(name: "AvenirNext-Bold", size: 28) ?? .systemFont(ofSize: 28, weight: .bold)
        pairCodeCard.layer.cornerRadius = 14
        pairCodeCard.layer.cornerCurve = .continuous
        pairCodeCard.clipsToBounds = true
        pairCodeCard.backgroundColor = AppVisualTheme.softCardBackground
        pairCodeCard.textColor = AppVisualTheme.textPrimary
        pairCodeCard.text = L10n.t("pairing.pair_code.default")

        partnerCodeField.placeholder = L10n.t("pairing.partner_code.placeholder")
        partnerCodeField.borderStyle = .none
        partnerCodeField.keyboardType = .numberPad
        partnerCodeField.layer.cornerRadius = 12
        partnerCodeField.layer.cornerCurve = .continuous
        partnerCodeField.layer.borderWidth = 1
        partnerCodeField.layer.borderColor = AppVisualTheme.fieldBorder.cgColor
        partnerCodeField.backgroundColor = AppVisualTheme.fieldBackground
        partnerCodeField.textColor = AppVisualTheme.textPrimary
        partnerCodeField.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 12, height: 1))
        partnerCodeField.leftViewMode = .always
        partnerCodeField.translatesAutoresizingMaskIntoConstraints = false

        var pairConfig = UIButton.Configuration.filled()
        pairConfig.cornerStyle = .capsule
        pairConfig.baseBackgroundColor = AppVisualTheme.accent
        pairConfig.baseForegroundColor = .white
        pairConfig.title = L10n.t("pairing.button.send_pair_request")
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

        requestsTitleLabel.text = L10n.t("pairing.requests.title")
        requestsTitleLabel.font = UIFont(name: "AvenirNext-DemiBold", size: 18) ?? .systemFont(ofSize: 18, weight: .semibold)
        requestsTitleLabel.textColor = AppVisualTheme.textPrimary

        emptyRequestsLabel.text = L10n.t("pairing.requests.empty")
        emptyRequestsLabel.font = UIFont(name: "AvenirNext-Medium", size: 14) ?? .systemFont(ofSize: 14, weight: .medium)
        emptyRequestsLabel.textColor = AppVisualTheme.textSecondary
        emptyRequestsLabel.textAlignment = .center
        emptyRequestsLabel.numberOfLines = 0

        requestsTableView.register(UITableViewCell.self, forCellReuseIdentifier: "requestCell")
        requestsTableView.dataSource = self
        requestsTableView.delegate = self
        requestsTableView.backgroundColor = .clear
        requestsTableView.separatorStyle = .none
        requestsTableView.rowHeight = 64
        requestsTableView.showsVerticalScrollIndicator = false
        requestsTableView.translatesAutoresizingMaskIntoConstraints = false

        activity.hidesWhenStopped = true

        let headerStack = UIStackView(arrangedSubviews: [
            titleLabel,
            statusLabel,
            partnerInfoCard,
            pairCodeCard,
            partnerCodeField,
            pairButton,
            clearPairButton,
            openChatButton,
            requestsTitleLabel,
            emptyRequestsLabel,
            activity
        ])
        headerStack.axis = .vertical
        headerStack.spacing = 12
        headerStack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(headerStack)
        view.addSubview(requestsTableView)

        NSLayoutConstraint.activate([
            headerStack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            headerStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            headerStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),

            pairCodeCard.heightAnchor.constraint(equalToConstant: 72),
            partnerCodeField.heightAnchor.constraint(equalToConstant: 48),
            pairButton.heightAnchor.constraint(equalToConstant: 48),
            clearPairButton.heightAnchor.constraint(equalToConstant: 44),
            openChatButton.heightAnchor.constraint(equalToConstant: 44),

            requestsTableView.topAnchor.constraint(equalTo: headerStack.bottomAnchor, constant: 8),
            requestsTableView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            requestsTableView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            requestsTableView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -8)
        ])
    }

    private func configurePartnerInfoCard() {
        partnerInfoCard.backgroundColor = AppVisualTheme.softCardBackground
        partnerInfoCard.layer.cornerRadius = 14
        partnerInfoCard.layer.cornerCurve = .continuous
        partnerInfoCard.layer.borderWidth = 1
        partnerInfoCard.layer.borderColor = AppVisualTheme.fieldBorder.cgColor
        partnerInfoCard.isHidden = true

        partnerInfoTitleLabel.text = isTurkishLanguage ? "Eşleşilen Kişi" : "Paired Partner"
        partnerInfoTitleLabel.font = UIFont(name: "AvenirNext-DemiBold", size: 15) ?? .systemFont(ofSize: 15, weight: .semibold)
        partnerInfoTitleLabel.textColor = AppVisualTheme.textPrimary

        configurePartnerCaptionLabel(partnerNameCaptionLabel, text: isTurkishLanguage ? "Ad" : "Name")
        configurePartnerCaptionLabel(partnerCodeCaptionLabel, text: isTurkishLanguage ? "Kod" : "Code")
        configurePartnerCaptionLabel(partnerStateCaptionLabel, text: isTurkishLanguage ? "Durum" : "Status")

        configurePartnerValueLabel(partnerNameValueLabel)
        configurePartnerValueLabel(partnerCodeValueLabel)
        configurePartnerValueLabel(partnerStateValueLabel)

        partnerCodeValueLabel.font = UIFont.monospacedDigitSystemFont(ofSize: 14, weight: .medium)

        partnerNameValueLabel.text = isTurkishLanguage ? "Bilinmiyor" : "Unknown"
        partnerCodeValueLabel.text = "------"
        partnerStateValueLabel.text = isTurkishLanguage ? "Bekliyor" : "Pending"

        let contentStack = UIStackView(arrangedSubviews: [
            partnerInfoTitleLabel,
            makePartnerInfoRow(caption: partnerNameCaptionLabel, value: partnerNameValueLabel),
            makePartnerInfoRow(caption: partnerCodeCaptionLabel, value: partnerCodeValueLabel),
            makePartnerInfoRow(caption: partnerStateCaptionLabel, value: partnerStateValueLabel)
        ])
        contentStack.axis = .vertical
        contentStack.spacing = 8
        contentStack.translatesAutoresizingMaskIntoConstraints = false

        partnerInfoCard.addSubview(contentStack)
        NSLayoutConstraint.activate([
            contentStack.topAnchor.constraint(equalTo: partnerInfoCard.topAnchor, constant: 12),
            contentStack.leadingAnchor.constraint(equalTo: partnerInfoCard.leadingAnchor, constant: 12),
            contentStack.trailingAnchor.constraint(equalTo: partnerInfoCard.trailingAnchor, constant: -12),
            contentStack.bottomAnchor.constraint(equalTo: partnerInfoCard.bottomAnchor, constant: -12)
        ])
    }

    private func configurePartnerCaptionLabel(_ label: UILabel, text: String) {
        label.text = text
        label.font = UIFont(name: "AvenirNext-Medium", size: 12) ?? .systemFont(ofSize: 12, weight: .medium)
        label.textColor = AppVisualTheme.textSecondary
    }

    private func configurePartnerValueLabel(_ label: UILabel) {
        label.font = UIFont(name: "AvenirNext-DemiBold", size: 14) ?? .systemFont(ofSize: 14, weight: .semibold)
        label.textColor = AppVisualTheme.textPrimary
        label.textAlignment = .right
        label.numberOfLines = 1
    }

    private func makePartnerInfoRow(caption: UILabel, value: UILabel) -> UIStackView {
        let row = UIStackView(arrangedSubviews: [caption, value])
        row.axis = .horizontal
        row.alignment = .center
        row.distribution = .fill
        row.spacing = 10
        caption.setContentHuggingPriority(.required, for: .horizontal)
        value.setContentCompressionResistancePriority(.required, for: .horizontal)
        return row
    }

    private var isTurkishLanguage: Bool {
        Locale.preferredLanguages.first?.lowercased().hasPrefix("tr") == true
    }

    private func renderPartnerInfo(_ info: PairingViewModel.PartnerInfo?) {
        guard let info else {
            partnerInfoCard.isHidden = true
            return
        }

        partnerInfoCard.isHidden = false
        partnerNameValueLabel.text = info.displayName
        partnerCodeValueLabel.text = info.pairCode
        partnerStateValueLabel.text = info.isMutuallyPaired
            ? (isTurkishLanguage ? "Eşleşti" : "Paired")
            : (isTurkishLanguage ? "Beklemede" : "Pending")
        partnerStateValueLabel.textColor = info.isMutuallyPaired
            ? UIColor(red: 0.31, green: 0.78, blue: 0.48, alpha: 1)
            : AppVisualTheme.textSecondary
    }

    private func bindViewModel() {
        viewModel.onPairCodeUpdated = { [weak self] code in
            self?.pairCodeCard.text = L10n.f("pairing.pair_code.format", code)
        }

        viewModel.onStateChanged = { [weak self] state, message in
            self?.render(state: state, message: message)
        }

        viewModel.onPartnerInfoUpdated = { [weak self] info in
            self?.renderPartnerInfo(info)
        }

        viewModel.onIncomingRequestsUpdated = { [weak self] requests in
            self?.incomingRequests = requests
            self?.emptyRequestsLabel.isHidden = !requests.isEmpty
            self?.requestsTableView.reloadData()
        }

        viewModel.onError = { [weak self] message in
            self?.presentSimpleAlert(title: L10n.t("common.error_title"), message: message)
        }

        viewModel.onNotice = { [weak self] message in
            self?.presentSimpleAlert(title: L10n.t("app.name"), message: message)
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
            clearPairButton.isEnabled = false
            openChatButton.isHidden = true
            partnerInfoCard.isHidden = true
            activity.stopAnimating()

        case .waiting:
            pairButton.isEnabled = false
            clearPairButton.isHidden = true
            clearPairButton.isEnabled = false
            openChatButton.isHidden = true
            activity.stopAnimating()

        case .paired:
            pairButton.isEnabled = false
            clearPairButton.isHidden = false
            clearPairButton.isEnabled = !viewModel.isUnpairRequestPending
            openChatButton.isHidden = autoOpenChatWhenPaired
            activity.stopAnimating()
        }
    }

    @objc private func pairTapped() {
        view.endEditing(true)
        viewModel.sendPairRequest(code: partnerCodeField.text ?? "")
    }

    @objc private func clearPairTapped() {
        let alert = UIAlertController(
            title: L10n.t("pairing.unpair.confirm.title"),
            message: L10n.t("pairing.unpair.confirm.message"),
            preferredStyle: .alert
        )

        alert.addAction(makeAlertAction(
            title: L10n.t("pairing.unpair.action.delete_and_unpair"),
            style: .destructive
        ) { [weak self] in
            self?.viewModel.sendUnpairRequest()
        })

        alert.addAction(makeAlertAction(title: L10n.t("common.cancel"), style: .cancel))
        presentAlertSafely(alert)
    }

    @objc private func openChatTapped() {
        onBackToChat?()
    }

    @objc private func signOutTapped() {
        let alert = UIAlertController(
            title: L10n.t("pairing.sign_out.confirm.title"),
            message: L10n.t("pairing.sign_out.confirm.message"),
            preferredStyle: .alert
        )
        alert.addAction(makeAlertAction(
            title: L10n.t("pairing.sign_out.confirm.action"),
            style: .destructive
        ) { [weak self] in
            self?.onRequestSignOut?()
        })
        alert.addAction(makeAlertAction(title: L10n.t("common.cancel"), style: .cancel))
        presentAlertSafely(alert)
    }

    private func presentActions(for request: RelationshipRequest) {
        let senderName = request.senderDisplayName

        switch request.type {
        case .pair:
            let title = L10n.f("pairing.request.alert.pair.title_format", senderName)
            let pairCode = request.fromSixDigitUID ?? "------"
            let message = L10n.f("pairing.request.alert.pair.message_format", pairCode)

            let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
            alert.addAction(makeAlertAction(title: L10n.t("pairing.request.action.accept"), style: .default) { [weak self] in
                self?.viewModel.respondToRequest(request: request, decision: .accept)
            })
            alert.addAction(makeAlertAction(title: L10n.t("pairing.request.action.reject"), style: .destructive) { [weak self] in
                self?.viewModel.respondToRequest(request: request, decision: .reject)
            })
            alert.addAction(makeAlertAction(title: L10n.t("common.cancel"), style: .cancel))
            presentAlertSafely(alert)

        case .unpair:
            let title = L10n.f("pairing.request.alert.unpair.title_format", senderName)
            let message = L10n.t("pairing.unpair.confirm.message")

            let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
            alert.addAction(makeAlertAction(title: L10n.t("pairing.request.action.accept_delete"), style: .default) { [weak self] in
                self?.viewModel.respondToRequest(
                    request: request,
                    decision: .accept
                )
            })
            alert.addAction(makeAlertAction(title: L10n.t("pairing.request.action.reject"), style: .destructive) { [weak self] in
                self?.viewModel.respondToRequest(request: request, decision: .reject)
            })
            alert.addAction(makeAlertAction(title: L10n.t("common.cancel"), style: .cancel))
            presentAlertSafely(alert)
        }
    }

    private func requestTypeTitle(_ type: RelationshipRequestType) -> String {
        switch type {
        case .pair:
            return L10n.t("pairing.request.type.pair")
        case .unpair:
            return L10n.t("pairing.request.type.unpair")
        }
    }

    private func requestSubtitle(for request: RelationshipRequest) -> String {
        let type = requestTypeTitle(request.type)
        let fromCode = request.fromSixDigitUID ?? "------"
        let relative = relativeDateFormatter.localizedString(for: request.createdAt, relativeTo: Date())
        return L10n.f("pairing.request.cell.subtitle_format", type, fromCode, relative)
    }

    private func presentSimpleAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(makeAlertAction(title: L10n.t("common.ok"), style: .default))
        presentAlertSafely(alert)
    }

    private func makeAlertAction(
        title: String,
        style: UIAlertAction.Style,
        handler: (() -> Void)? = nil
    ) -> UIAlertAction {
        UIAlertAction(title: title, style: style) { [weak self] _ in
            handler?()
            self?.didDismissPresentedAlert()
        }
    }

    private func presentAlertSafely(_ alert: UIAlertController) {
        pendingAlerts.append(alert)
        presentNextAlertIfPossible()
    }

    private func presentNextAlertIfPossible() {
        guard !isPresentingQueuedAlert else { return }
        guard isViewLoaded, view.window != nil else { return }
        guard presentedViewController == nil else { return }
        guard let nextAlert = pendingAlerts.first else { return }

        pendingAlerts.removeFirst()
        isPresentingQueuedAlert = true
        present(nextAlert, animated: true)
    }

    private func didDismissPresentedAlert() {
        isPresentingQueuedAlert = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.presentNextAlertIfPossible()
        }
    }
}

extension PairingViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        incomingRequests.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let request = incomingRequests[indexPath.row]
        let cell = tableView.dequeueReusableCell(withIdentifier: "requestCell", for: indexPath)
        cell.accessoryType = .disclosureIndicator
        cell.selectionStyle = .default
        cell.backgroundColor = .clear
        cell.layer.cornerRadius = 12
        cell.layer.cornerCurve = .continuous
        cell.layer.borderWidth = 1

        let isUnpair = request.type == .unpair
        let accentColor = isUnpair
            ? UIColor.systemRed.withAlphaComponent(0.85)
            : UIColor.systemGreen.withAlphaComponent(0.82)
        let softTint = isUnpair
            ? UIColor.systemRed.withAlphaComponent(0.14)
            : UIColor.systemGreen.withAlphaComponent(0.14)
        cell.layer.borderColor = accentColor.cgColor
        cell.contentView.backgroundColor = softTint
        cell.contentView.layer.cornerRadius = 12
        cell.contentView.layer.cornerCurve = .continuous

        var config = cell.defaultContentConfiguration()
        config.text = request.senderDisplayName
        config.secondaryText = requestSubtitle(for: request)
        config.textProperties.font = UIFont(name: "AvenirNext-DemiBold", size: 16) ?? .systemFont(ofSize: 16, weight: .semibold)
        config.textProperties.color = AppVisualTheme.textPrimary
        config.secondaryTextProperties.font = UIFont(name: "AvenirNext-Medium", size: 13) ?? .systemFont(ofSize: 13, weight: .medium)
        config.secondaryTextProperties.color = AppVisualTheme.textSecondary
        config.image = UIImage(systemName: isUnpair ? "link.badge.minus" : "link")
        config.imageProperties.tintColor = accentColor
        cell.contentConfiguration = config
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let request = incomingRequests[indexPath.row]
        presentActions(for: request)
    }
}
