//
//  AuthViewController.swift
//  SoulMate
//
//  Created by MAHMUT AKIN on 02/02/2026.
//

import UIKit

final class AuthViewController: UIViewController {
    var onAuthSuccess: (() -> Void)?
    var initialNoticeMessage: String?

    private let viewModel: AuthViewModel
    private var hasPresentedInitialNotice = false

    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let modeControl = UISegmentedControl(items: [L10n.t("auth.mode.sign_in"), L10n.t("auth.mode.sign_up")])

    private let firstNameField = UITextField()
    private let lastNameField = UITextField()
    private let emailField = UITextField()
    private let passwordField = UITextField()
    private let formValidationLabel = UILabel()
    private let submitButton = UIButton(type: .system)
    private let activity = UIActivityIndicatorView(style: .medium)
    private let gradientLayer = CAGradientLayer()
    private lazy var dismissKeyboardTapGesture: UITapGestureRecognizer = {
        let gesture = UITapGestureRecognizer(target: self, action: #selector(handleBackgroundTap))
        gesture.cancelsTouchesInView = false
        gesture.delegate = self
        return gesture
    }()

    private var isLoading = false
    private var isCheckingEmailInUse = false
    private var isEmailInUse = false
    private var lastCheckedEmail: String?
    private var emailCheckWorkItem: DispatchWorkItem?

    init(viewModel: AuthViewModel = AuthViewModel()) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        emailCheckWorkItem?.cancel()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        AppVisualTheme.applyBackground(to: view, gradientLayer: gradientLayer)
        title = L10n.t("auth.nav_title")
        setupUI()
        configureInteractions()
        bindViewModel()
        updateModeUI()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        gradientLayer.frame = view.bounds
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        presentInitialNoticeIfNeeded()
    }

    private func setupUI() {
        titleLabel.text = L10n.t("auth.title")
        titleLabel.font = UIFont(name: "AvenirNext-Bold", size: 36) ?? .systemFont(ofSize: 36, weight: .bold)
        titleLabel.textAlignment = .center
        titleLabel.textColor = AppVisualTheme.textPrimary

        subtitleLabel.text = L10n.t("auth.subtitle")
        subtitleLabel.font = UIFont(name: "AvenirNext-Medium", size: 15) ?? .systemFont(ofSize: 15, weight: .medium)
        subtitleLabel.textColor = AppVisualTheme.textSecondary
        subtitleLabel.textAlignment = .center

        modeControl.selectedSegmentIndex = 0
        modeControl.addTarget(self, action: #selector(modeChanged), for: .valueChanged)

        configureField(firstNameField, placeholder: L10n.t("auth.field.first_name"), secure: false)
        configureField(lastNameField, placeholder: L10n.t("auth.field.last_name"), secure: false)
        configureField(emailField, placeholder: L10n.t("auth.field.email"), secure: false)
        emailField.keyboardType = .emailAddress
        emailField.autocapitalizationType = .none
        emailField.textContentType = .username
        emailField.addTarget(self, action: #selector(textFieldChanged), for: .editingChanged)

        configureField(passwordField, placeholder: L10n.t("auth.field.password"), secure: true)
        passwordField.textContentType = .password
        passwordField.addTarget(self, action: #selector(textFieldChanged), for: .editingChanged)
        firstNameField.addTarget(self, action: #selector(textFieldChanged), for: .editingChanged)
        lastNameField.addTarget(self, action: #selector(textFieldChanged), for: .editingChanged)

        formValidationLabel.font = UIFont(name: "AvenirNext-Medium", size: 12) ?? .systemFont(ofSize: 12, weight: .medium)
        formValidationLabel.textColor = UIColor(red: 0.92, green: 0.34, blue: 0.41, alpha: 1)
        formValidationLabel.numberOfLines = 0
        formValidationLabel.isHidden = true

        var configuration = UIButton.Configuration.filled()
        configuration.cornerStyle = .capsule
        configuration.baseBackgroundColor = AppVisualTheme.accent
        configuration.baseForegroundColor = .white
        configuration.title = L10n.t("auth.button.sign_in")
        submitButton.configuration = configuration
        submitButton.addTarget(self, action: #selector(submitTapped), for: .touchUpInside)

        activity.hidesWhenStopped = true

        let stack = UIStackView(arrangedSubviews: [
            titleLabel,
            subtitleLabel,
            modeControl,
            firstNameField,
            lastNameField,
            emailField,
            passwordField,
            formValidationLabel,
            submitButton,
            activity
        ])
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 28),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),

            firstNameField.heightAnchor.constraint(equalToConstant: 48),
            lastNameField.heightAnchor.constraint(equalToConstant: 48),
            emailField.heightAnchor.constraint(equalToConstant: 48),
            passwordField.heightAnchor.constraint(equalToConstant: 48),
            submitButton.heightAnchor.constraint(equalToConstant: 48)
        ])
    }

    private func configureField(_ field: UITextField, placeholder: String, secure: Bool) {
        field.placeholder = placeholder
        field.isSecureTextEntry = secure
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
    }

    private func configureInteractions() {
        view.addGestureRecognizer(dismissKeyboardTapGesture)
    }

    private func bindViewModel() {
        viewModel.onLoadingChanged = { [weak self] loading in
            self?.isLoading = loading
            self?.updateSubmitAvailability()
            if loading {
                self?.activity.startAnimating()
            } else {
                self?.activity.stopAnimating()
            }
        }

        viewModel.onSuccess = { [weak self] in
            self?.onAuthSuccess?()
        }

        viewModel.onError = { [weak self] message in
            let alert = UIAlertController(title: L10n.t("common.error_title"), message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: L10n.t("common.ok"), style: .default))
            self?.present(alert, animated: true)
        }
    }

    private func updateModeUI() {
        let isSignUp = modeControl.selectedSegmentIndex == 1
        firstNameField.isHidden = !isSignUp
        lastNameField.isHidden = !isSignUp

        if !isSignUp {
            isCheckingEmailInUse = false
            isEmailInUse = false
            lastCheckedEmail = nil
            emailCheckWorkItem?.cancel()
            emailCheckWorkItem = nil
        } else {
            scheduleEmailInUseCheckIfNeeded()
        }

        var configuration = submitButton.configuration
        configuration?.title = isSignUp ? L10n.t("auth.button.sign_up") : L10n.t("auth.button.sign_in")
        submitButton.configuration = configuration
        updateSubmitAvailability()
    }

    @objc private func modeChanged() {
        updateModeUI()
    }

    @objc private func textFieldChanged() {
        if modeControl.selectedSegmentIndex == 1 {
            scheduleEmailInUseCheckIfNeeded()
        }
        updateSubmitAvailability()
    }

    @objc private func handleBackgroundTap() {
        view.endEditing(true)
    }

    @objc private func submitTapped() {
        guard submitButton.isEnabled else {
            if let message = currentValidationMessage() {
                let alert = UIAlertController(title: L10n.t("common.error_title"), message: message, preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: L10n.t("common.ok"), style: .default))
                present(alert, animated: true)
            }
            return
        }

        let isSignUp = modeControl.selectedSegmentIndex == 1
        viewModel.submit(
            mode: isSignUp ? .signUp : .signIn,
            firstName: firstNameField.text,
            lastName: lastNameField.text,
            email: emailField.text ?? "",
            password: passwordField.text ?? ""
        )
    }

    private func presentInitialNoticeIfNeeded() {
        guard !hasPresentedInitialNotice else { return }
        guard let message = initialNoticeMessage?.trimmingCharacters(in: .whitespacesAndNewlines),
              !message.isEmpty else {
            return
        }
        guard presentedViewController == nil else { return }

        hasPresentedInitialNotice = true
        let alert = UIAlertController(
            title: L10n.t("app.name"),
            message: message,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: L10n.t("common.ok"), style: .default))
        present(alert, animated: true)
    }

    private func scheduleEmailInUseCheckIfNeeded() {
        guard modeControl.selectedSegmentIndex == 1 else { return }

        let email = normalizedEmail()
        guard isEmailFormatValid(email) else {
            isCheckingEmailInUse = false
            isEmailInUse = false
            lastCheckedEmail = nil
            emailCheckWorkItem?.cancel()
            emailCheckWorkItem = nil
            return
        }

        if lastCheckedEmail == email {
            return
        }

        emailCheckWorkItem?.cancel()
        isCheckingEmailInUse = true
        isEmailInUse = false
        updateSubmitAvailability()

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.viewModel.checkEmailInUse(email) { [weak self] result in
                DispatchQueue.main.async {
                    guard let self else { return }
                    guard self.modeControl.selectedSegmentIndex == 1 else { return }
                    guard self.normalizedEmail() == email else { return }

                    self.isCheckingEmailInUse = false
                    self.lastCheckedEmail = email

                    switch result {
                    case .success(let inUse):
                        self.isEmailInUse = inUse
                    case .failure:
                        self.isEmailInUse = false
                    }

                    self.updateSubmitAvailability()
                }
            }
        }

        emailCheckWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: workItem)
    }

    private func updateSubmitAvailability() {
        let message = currentValidationMessage()
        let canSubmit = message == nil && !isLoading

        submitButton.isEnabled = canSubmit
        submitButton.alpha = canSubmit ? 1 : 0.7

        formValidationLabel.text = message
        formValidationLabel.isHidden = message == nil
    }

    private func currentValidationMessage() -> String? {
        let isSignUp = modeControl.selectedSegmentIndex == 1
        let cleanEmail = normalizedEmail()
        let cleanPassword = passwordField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if isSignUp {
            let cleanFirstName = firstNameField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let cleanLastName = lastNameField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if cleanFirstName.isEmpty || cleanLastName.isEmpty {
                return L10n.t("auth.error.signup_name_required")
            }
        }

        if cleanEmail.isEmpty || cleanPassword.isEmpty {
            return L10n.t("auth.error.empty_credentials")
        }

        guard isEmailFormatValid(cleanEmail) else {
            return L10n.t("auth.error.invalid_email")
        }

        if isSignUp {
            guard viewModel.isStrongPassword(cleanPassword) else {
                return L10n.t("auth.error.password_policy")
            }
            if isCheckingEmailInUse {
                return L10n.t("auth.validation.email_checking")
            }
            if isEmailInUse {
                return L10n.t("auth.error.email_in_use")
            }
        }

        return nil
    }

    private func normalizedEmail() -> String {
        (emailField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func isEmailFormatValid(_ email: String) -> Bool {
        email.contains("@") && email.contains(".")
    }
}

extension AuthViewController: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard gestureRecognizer === dismissKeyboardTapGesture else { return true }

        if touch.view is UIControl || touch.view is UITextField || touch.view is UITextView {
            return false
        }

        return true
    }
}
