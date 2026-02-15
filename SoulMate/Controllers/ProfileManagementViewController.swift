//
//  ProfileManagementViewController.swift
//  SoulMate
//
//  Created by MAHMUT AKIN on 14/02/2026.
//

import UIKit

final class ProfileManagementViewController: UIViewController, UIGestureRecognizerDelegate {
    var onSignedOut: (() -> Void)?
    var onAccountDeleted: (() -> Void)?

    private let viewModel: ProfileManagementViewModel
    private let gradientLayer = CAGradientLayer()

    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()

    private let headingLabel = UILabel()
    private let subheadingLabel = UILabel()

    private let nameCard = UIView()
    private let firstNameField = UITextField()
    private let lastNameField = UITextField()
    private let emailTitleLabel = UILabel()
    private let emailValueLabel = UILabel()
    private let saveNameButton = UIButton(type: .system)

    private let securityCard = UIView()
    private let passwordTitleLabel = UILabel()
    private let passwordSecurityInfoLabel = UILabel()
    private let passwordToggleButton = UIButton(type: .system)
    private let passwordPanelContainer = UIView()
    private let passwordPolicyLabel = UILabel()
    private let currentPasswordField = UITextField()
    private let newPasswordField = UITextField()
    private let confirmPasswordField = UITextField()
    private let changePasswordButton = UIButton(type: .system)

    private let actionsCard = UIView()
    private let signOutButton = UIButton(type: .system)
    private let deleteAccountButton = UIButton(type: .system)

    private let activityIndicator = UIActivityIndicatorView(style: .medium)

    private var isPasswordPanelVisible = false
    private var isCurrentPasswordVisible = false
    private lazy var dismissKeyboardTapGesture: UITapGestureRecognizer = {
        let gesture = UITapGestureRecognizer(target: self, action: #selector(handleBackgroundTap))
        gesture.cancelsTouchesInView = false
        gesture.delegate = self
        return gesture
    }()

    init(viewModel: ProfileManagementViewModel = ProfileManagementViewModel()) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L10n.t("profile.management.nav_title")
        AppVisualTheme.applyBackground(to: view, gradientLayer: gradientLayer)
        setupUI()
        configureInteractions()
        bindViewModel()
        viewModel.start()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        gradientLayer.frame = view.bounds
    }

    private func setupUI() {
        navigationItem.largeTitleDisplayMode = .never
        view.backgroundColor = AppVisualTheme.backgroundBase

        scrollView.alwaysBounceVertical = true
        scrollView.keyboardDismissMode = .interactive
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        contentStack.axis = .vertical
        contentStack.spacing = 14
        contentStack.translatesAutoresizingMaskIntoConstraints = false

        headingLabel.text = L10n.t("profile.management.title")
        headingLabel.font = UIFont(name: "AvenirNext-Bold", size: 30) ?? .systemFont(ofSize: 30, weight: .bold)
        headingLabel.textColor = AppVisualTheme.textPrimary

        subheadingLabel.text = L10n.t("profile.management.subtitle")
        subheadingLabel.font = UIFont(name: "AvenirNext-Medium", size: 15) ?? .systemFont(ofSize: 15, weight: .medium)
        subheadingLabel.textColor = AppVisualTheme.textSecondary
        subheadingLabel.numberOfLines = 0

        view.addSubview(scrollView)
        scrollView.addSubview(contentStack)
        contentStack.addArrangedSubview(headingLabel)
        contentStack.addArrangedSubview(subheadingLabel)

        setupNameCard()
        setupSecurityCard()
        setupActionsCard()
        setupActivityIndicator()

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 20),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 20),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -20),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -24),
            contentStack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -40)
        ])
    }

    private func setupNameCard() {
        configureCard(nameCard)
        contentStack.addArrangedSubview(nameCard)

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        nameCard.addSubview(stack)

        let nameSectionTitle = UILabel()
        nameSectionTitle.text = L10n.t("profile.management.section.identity")
        nameSectionTitle.font = UIFont(name: "AvenirNext-DemiBold", size: 15) ?? .systemFont(ofSize: 15, weight: .semibold)
        nameSectionTitle.textColor = AppVisualTheme.textPrimary

        configureField(firstNameField, placeholder: L10n.t("auth.field.first_name"))
        configureField(lastNameField, placeholder: L10n.t("auth.field.last_name"))

        emailTitleLabel.text = L10n.t("profile.management.field.email")
        emailTitleLabel.font = UIFont(name: "AvenirNext-Medium", size: 13) ?? .systemFont(ofSize: 13, weight: .medium)
        emailTitleLabel.textColor = AppVisualTheme.textSecondary

        emailValueLabel.font = UIFont(name: "AvenirNext-DemiBold", size: 15) ?? .systemFont(ofSize: 15, weight: .semibold)
        emailValueLabel.textColor = AppVisualTheme.textPrimary
        emailValueLabel.numberOfLines = 0
        emailValueLabel.text = L10n.t("profile.management.value.email_unknown")

        var saveConfig = UIButton.Configuration.filled()
        saveConfig.cornerStyle = .capsule
        saveConfig.baseBackgroundColor = AppVisualTheme.accent
        saveConfig.baseForegroundColor = .white
        saveConfig.title = L10n.t("profile.management.button.save")
        saveNameButton.configuration = saveConfig
        saveNameButton.addTarget(self, action: #selector(saveNameTapped), for: .touchUpInside)

        stack.addArrangedSubview(nameSectionTitle)
        stack.addArrangedSubview(firstNameField)
        stack.addArrangedSubview(lastNameField)
        stack.addArrangedSubview(emailTitleLabel)
        stack.addArrangedSubview(emailValueLabel)
        stack.addArrangedSubview(saveNameButton)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: nameCard.topAnchor, constant: 14),
            stack.leadingAnchor.constraint(equalTo: nameCard.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: nameCard.trailingAnchor, constant: -14),
            stack.bottomAnchor.constraint(equalTo: nameCard.bottomAnchor, constant: -14),

            firstNameField.heightAnchor.constraint(equalToConstant: 48),
            lastNameField.heightAnchor.constraint(equalToConstant: 48),
            saveNameButton.heightAnchor.constraint(equalToConstant: 46)
        ])
    }

    private func setupSecurityCard() {
        configureCard(securityCard)
        contentStack.addArrangedSubview(securityCard)

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        securityCard.addSubview(stack)

        let titleRow = UIStackView()
        titleRow.axis = .horizontal
        titleRow.spacing = 8
        titleRow.alignment = .center

        passwordTitleLabel.text = L10n.t("profile.management.field.password")
        passwordTitleLabel.font = UIFont(name: "AvenirNext-DemiBold", size: 15) ?? .systemFont(ofSize: 15, weight: .semibold)
        passwordTitleLabel.textColor = AppVisualTheme.textPrimary

        passwordSecurityInfoLabel.text = L10n.t("profile.management.password.info")
        passwordSecurityInfoLabel.font = UIFont(name: "AvenirNext-Medium", size: 13) ?? .systemFont(ofSize: 13, weight: .medium)
        passwordSecurityInfoLabel.textColor = AppVisualTheme.textSecondary
        passwordSecurityInfoLabel.numberOfLines = 0

        titleRow.addArrangedSubview(passwordTitleLabel)
        titleRow.addArrangedSubview(UIView())

        var toggleConfig = UIButton.Configuration.tinted()
        toggleConfig.cornerStyle = .capsule
        toggleConfig.baseForegroundColor = AppVisualTheme.secondaryAction
        toggleConfig.title = L10n.t("profile.management.button.change_password")
        passwordToggleButton.configuration = toggleConfig
        passwordToggleButton.addTarget(self, action: #selector(togglePasswordPanelTapped), for: .touchUpInside)

        passwordPanelContainer.isHidden = true
        passwordPanelContainer.alpha = 0

        let panelStack = UIStackView()
        panelStack.axis = .vertical
        panelStack.spacing = 8
        panelStack.translatesAutoresizingMaskIntoConstraints = false
        passwordPanelContainer.addSubview(panelStack)

        passwordPolicyLabel.text = L10n.t("profile.management.password.policy")
        passwordPolicyLabel.font = UIFont(name: "AvenirNext-Medium", size: 13) ?? .systemFont(ofSize: 13, weight: .medium)
        passwordPolicyLabel.textColor = AppVisualTheme.textSecondary
        passwordPolicyLabel.numberOfLines = 0

        configureSecureField(currentPasswordField, placeholder: L10n.t("profile.management.field.current_password"))
        currentPasswordField.textContentType = .password
        configureCurrentPasswordVisibilityButton()

        configureSecureField(newPasswordField, placeholder: L10n.t("profile.management.field.new_password"))
        configureSecureField(confirmPasswordField, placeholder: L10n.t("profile.management.field.new_password_repeat"))

        var changeConfig = UIButton.Configuration.filled()
        changeConfig.cornerStyle = .capsule
        changeConfig.baseBackgroundColor = AppVisualTheme.secondaryAction
        changeConfig.baseForegroundColor = .white
        changeConfig.title = L10n.t("profile.management.button.apply_password")
        changePasswordButton.configuration = changeConfig
        changePasswordButton.addTarget(self, action: #selector(changePasswordTapped), for: .touchUpInside)

        panelStack.addArrangedSubview(currentPasswordField)
        panelStack.addArrangedSubview(passwordPolicyLabel)
        panelStack.addArrangedSubview(newPasswordField)
        panelStack.addArrangedSubview(confirmPasswordField)
        panelStack.addArrangedSubview(changePasswordButton)

        stack.addArrangedSubview(titleRow)
        stack.addArrangedSubview(passwordSecurityInfoLabel)
        stack.addArrangedSubview(passwordToggleButton)
        stack.addArrangedSubview(passwordPanelContainer)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: securityCard.topAnchor, constant: 14),
            stack.leadingAnchor.constraint(equalTo: securityCard.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: securityCard.trailingAnchor, constant: -14),
            stack.bottomAnchor.constraint(equalTo: securityCard.bottomAnchor, constant: -14),

            panelStack.topAnchor.constraint(equalTo: passwordPanelContainer.topAnchor),
            panelStack.leadingAnchor.constraint(equalTo: passwordPanelContainer.leadingAnchor),
            panelStack.trailingAnchor.constraint(equalTo: passwordPanelContainer.trailingAnchor),
            panelStack.bottomAnchor.constraint(equalTo: passwordPanelContainer.bottomAnchor),

            currentPasswordField.heightAnchor.constraint(equalToConstant: 48),
            newPasswordField.heightAnchor.constraint(equalToConstant: 48),
            confirmPasswordField.heightAnchor.constraint(equalToConstant: 48),
            changePasswordButton.heightAnchor.constraint(equalToConstant: 46)
        ])
    }

    private func setupActionsCard() {
        configureCard(actionsCard)
        contentStack.addArrangedSubview(actionsCard)

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        actionsCard.addSubview(stack)

        var signOutConfig = UIButton.Configuration.tinted()
        signOutConfig.cornerStyle = .capsule
        signOutConfig.baseForegroundColor = AppVisualTheme.textPrimary
        signOutConfig.title = L10n.t("profile.management.button.sign_out")
        signOutButton.configuration = signOutConfig
        signOutButton.backgroundColor = AppVisualTheme.fieldBackground
        signOutButton.layer.cornerRadius = 20
        signOutButton.layer.cornerCurve = .continuous
        signOutButton.layer.borderWidth = 1
        signOutButton.layer.borderColor = AppVisualTheme.fieldBorder.cgColor
        signOutButton.addTarget(self, action: #selector(signOutTapped), for: .touchUpInside)

        var deleteConfig = UIButton.Configuration.tinted()
        deleteConfig.cornerStyle = .capsule
        deleteConfig.baseForegroundColor = UIColor(red: 0.93, green: 0.32, blue: 0.34, alpha: 1)
        deleteConfig.title = L10n.t("profile.management.button.delete_account")
        deleteAccountButton.configuration = deleteConfig
        deleteAccountButton.backgroundColor = UIColor(red: 0.4, green: 0.12, blue: 0.14, alpha: 0.35)
        deleteAccountButton.layer.cornerRadius = 20
        deleteAccountButton.layer.cornerCurve = .continuous
        deleteAccountButton.layer.borderWidth = 1
        deleteAccountButton.layer.borderColor = UIColor(red: 0.74, green: 0.24, blue: 0.28, alpha: 0.65).cgColor
        deleteAccountButton.addTarget(self, action: #selector(deleteAccountTapped), for: .touchUpInside)

        stack.addArrangedSubview(signOutButton)
        stack.addArrangedSubview(deleteAccountButton)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: actionsCard.topAnchor, constant: 14),
            stack.leadingAnchor.constraint(equalTo: actionsCard.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: actionsCard.trailingAnchor, constant: -14),
            stack.bottomAnchor.constraint(equalTo: actionsCard.bottomAnchor, constant: -14),

            signOutButton.heightAnchor.constraint(equalToConstant: 44),
            deleteAccountButton.heightAnchor.constraint(equalToConstant: 44)
        ])
    }

    private func setupActivityIndicator() {
        activityIndicator.hidesWhenStopped = true
        activityIndicator.color = AppVisualTheme.textPrimary
        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(activityIndicator)

        NSLayoutConstraint.activate([
            activityIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            activityIndicator.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16)
        ])
    }

    private func bindViewModel() {
        viewModel.onLoadingChanged = { [weak self] isLoading in
            guard let self else { return }
            self.setInteractionEnabled(!isLoading)
            if isLoading {
                self.activityIndicator.startAnimating()
            } else {
                self.activityIndicator.stopAnimating()
            }
        }

        viewModel.onProfileLoaded = { [weak self] firstName, lastName, email in
            self?.firstNameField.text = firstName
            self?.lastNameField.text = lastName
            self?.emailValueLabel.text = email
        }

        viewModel.onError = { [weak self] message in
            self?.presentAlert(title: L10n.t("common.error_title"), message: message)
        }

        viewModel.onNotice = { [weak self] message in
            self?.presentAlert(title: L10n.t("app.name"), message: message)
        }

        viewModel.onPasswordChanged = { [weak self] in
            self?.currentPasswordField.text = nil
            self?.newPasswordField.text = nil
            self?.confirmPasswordField.text = nil
            self?.setCurrentPasswordVisibility(false)
            self?.setPasswordPanelVisible(false, animated: true)
        }

        viewModel.onSignedOut = { [weak self] in
            self?.onSignedOut?()
        }

        viewModel.onAccountDeleted = { [weak self] in
            self?.onAccountDeleted?()
        }
    }

    private func configureCard(_ card: UIView) {
        card.backgroundColor = AppVisualTheme.softCardBackground
        card.layer.cornerRadius = 16
        card.layer.cornerCurve = .continuous
        card.layer.borderWidth = 1
        card.layer.borderColor = AppVisualTheme.fieldBorder.cgColor
    }

    private func configureField(_ field: UITextField, placeholder: String) {
        field.placeholder = placeholder
        field.borderStyle = .none
        field.layer.cornerRadius = 12
        field.layer.cornerCurve = .continuous
        field.layer.borderWidth = 1
        field.layer.borderColor = AppVisualTheme.fieldBorder.cgColor
        field.backgroundColor = AppVisualTheme.fieldBackground
        field.textColor = AppVisualTheme.textPrimary
        field.attributedPlaceholder = NSAttributedString(
            string: placeholder,
            attributes: [.foregroundColor: AppVisualTheme.textSecondary]
        )
        field.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 12, height: 1))
        field.leftViewMode = .always
        field.autocorrectionType = .no
        field.autocapitalizationType = .words
    }

    private func configureSecureField(_ field: UITextField, placeholder: String) {
        configureField(field, placeholder: placeholder)
        field.textContentType = .newPassword
        field.isSecureTextEntry = true
        field.autocapitalizationType = .none
        field.autocorrectionType = .no
    }

    private func configureInteractions() {
        view.addGestureRecognizer(dismissKeyboardTapGesture)
    }

    private func setInteractionEnabled(_ isEnabled: Bool) {
        [saveNameButton, passwordToggleButton, changePasswordButton, signOutButton, deleteAccountButton].forEach {
            $0.isEnabled = isEnabled
            $0.alpha = isEnabled ? 1 : 0.7
        }
        view.isUserInteractionEnabled = true
        if isEnabled {
            firstNameField.isEnabled = true
            lastNameField.isEnabled = true
            currentPasswordField.isEnabled = true
            newPasswordField.isEnabled = true
            confirmPasswordField.isEnabled = true
        } else {
            firstNameField.isEnabled = false
            lastNameField.isEnabled = false
            currentPasswordField.isEnabled = false
            newPasswordField.isEnabled = false
            confirmPasswordField.isEnabled = false
        }
    }

    private func configureCurrentPasswordVisibilityButton() {
        let button = UIButton(type: .system)
        button.tintColor = AppVisualTheme.textSecondary
        button.addTarget(self, action: #selector(toggleCurrentPasswordVisibilityTapped), for: .touchUpInside)
        button.frame = CGRect(x: 6, y: 0, width: 30, height: 30)

        let rightContainer = UIView(frame: CGRect(x: 0, y: 0, width: 42, height: 30))
        rightContainer.backgroundColor = .clear
        rightContainer.addSubview(button)

        currentPasswordField.rightView = rightContainer
        currentPasswordField.rightViewMode = .always
        updateCurrentPasswordVisibilityButtonIcon()
    }

    private func setPasswordPanelVisible(_ visible: Bool, animated: Bool) {
        guard isPasswordPanelVisible != visible else { return }
        isPasswordPanelVisible = visible

        var config = passwordToggleButton.configuration
        config?.title = visible
            ? L10n.t("profile.management.button.cancel_password_change")
            : L10n.t("profile.management.button.change_password")
        passwordToggleButton.configuration = config

        if visible {
            passwordPanelContainer.isHidden = false
            if animated {
                passwordPanelContainer.alpha = 0
                UIView.animate(withDuration: 0.24) {
                    self.passwordPanelContainer.alpha = 1
                    self.view.layoutIfNeeded()
                }
            } else {
                passwordPanelContainer.alpha = 1
            }
            return
        }

        let hidePanel = {
            self.passwordPanelContainer.alpha = 0
            self.view.layoutIfNeeded()
        }

        let completion: (Bool) -> Void = { _ in
            self.passwordPanelContainer.isHidden = true
            self.passwordPanelContainer.alpha = 0
        }

        if animated {
            UIView.animate(withDuration: 0.2, animations: hidePanel, completion: completion)
        } else {
            hidePanel()
            completion(true)
        }
    }

    private func presentAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: L10n.t("common.ok"), style: .default))
        present(alert, animated: true)
    }

    private func setCurrentPasswordVisibility(_ isVisible: Bool) {
        guard isCurrentPasswordVisible != isVisible else { return }
        isCurrentPasswordVisible = isVisible
        setSecureEntry(!isVisible, for: currentPasswordField)
        updateCurrentPasswordVisibilityButtonIcon()
    }

    private func setSecureEntry(_ secure: Bool, for field: UITextField) {
        let existingText = field.text
        let wasFirstResponder = field.isFirstResponder
        field.isSecureTextEntry = secure
        field.text = existingText
        if wasFirstResponder {
            field.becomeFirstResponder()
        }
    }

    private func updateCurrentPasswordVisibilityButtonIcon() {
        guard let button = currentPasswordField.rightView?.subviews.compactMap({ $0 as? UIButton }).first else { return }
        let symbolName = isCurrentPasswordVisible ? "eye.slash" : "eye"
        button.setImage(UIImage(systemName: symbolName), for: .normal)
    }

    @objc private func saveNameTapped() {
        view.endEditing(true)
        viewModel.saveName(
            firstName: firstNameField.text ?? "",
            lastName: lastNameField.text ?? ""
        )
    }

    @objc private func togglePasswordPanelTapped() {
        setPasswordPanelVisible(!isPasswordPanelVisible, animated: true)
    }

    @objc private func toggleCurrentPasswordVisibilityTapped() {
        setCurrentPasswordVisibility(!isCurrentPasswordVisible)
    }

    @objc private func handleBackgroundTap() {
        view.endEditing(true)
    }

    @objc private func changePasswordTapped() {
        view.endEditing(true)
        viewModel.changePassword(
            currentPassword: currentPasswordField.text ?? "",
            newPassword: newPasswordField.text ?? "",
            confirmPassword: confirmPasswordField.text ?? ""
        )
    }

    @objc private func signOutTapped() {
        let alert = UIAlertController(
            title: L10n.t("profile.management.sign_out.confirm.title"),
            message: L10n.t("profile.management.sign_out.confirm.message"),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(
            title: L10n.t("profile.management.button.sign_out"),
            style: .destructive,
            handler: { [weak self] _ in
                self?.viewModel.signOut()
            }
        ))
        alert.addAction(UIAlertAction(title: L10n.t("common.cancel"), style: .cancel))
        present(alert, animated: true)
    }

    @objc private func deleteAccountTapped() {
        let alert = UIAlertController(
            title: L10n.t("profile.management.delete.confirm.title"),
            message: L10n.t("profile.management.delete.confirm.message"),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(
            title: L10n.t("profile.management.delete.confirm.action"),
            style: .destructive,
            handler: { [weak self] _ in
                self?.viewModel.deleteAccount()
            }
        ))
        alert.addAction(UIAlertAction(title: L10n.t("common.cancel"), style: .cancel))
        present(alert, animated: true)
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard gestureRecognizer === dismissKeyboardTapGesture else { return true }

        if touch.view is UIControl || touch.view is UITextField || touch.view is UITextView {
            return false
        }

        return true
    }
}
