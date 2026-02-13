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
    private let submitButton = UIButton(type: .system)
    private let activity = UIActivityIndicatorView(style: .medium)
    private let gradientLayer = CAGradientLayer()

    init(viewModel: AuthViewModel = AuthViewModel()) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        AppVisualTheme.applyBackground(to: view, gradientLayer: gradientLayer)
        title = L10n.t("auth.nav_title")
        setupUI()
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

        configureField(passwordField, placeholder: L10n.t("auth.field.password"), secure: true)
        passwordField.textContentType = .password

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

    private func bindViewModel() {
        viewModel.onLoadingChanged = { [weak self] loading in
            self?.submitButton.isEnabled = !loading
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

        var configuration = submitButton.configuration
        configuration?.title = isSignUp ? L10n.t("auth.button.sign_up") : L10n.t("auth.button.sign_in")
        submitButton.configuration = configuration
    }

    @objc private func modeChanged() {
        updateModeUI()
    }

    @objc private func submitTapped() {
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
}
