//
//  ProfileCompletionViewController.swift
//  SoulMate
//
//  Created by MAHMUT AKIN on 02/02/2026.
//

import UIKit

final class ProfileCompletionViewController: UIViewController {
    var onProfileCompleted: (() -> Void)?

    private let viewModel: ProfileCompletionViewModel

    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let firstNameField = UITextField()
    private let lastNameField = UITextField()
    private let continueButton = UIButton(type: .system)
    private let activity = UIActivityIndicatorView(style: .medium)

    init(viewModel: ProfileCompletionViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        title = L10n.t("profile.nav_title")
        setupUI()
        bindViewModel()
    }

    private func setupUI() {
        titleLabel.text = L10n.t("profile.title")
        titleLabel.font = UIFont(name: "AvenirNext-Bold", size: 32) ?? .systemFont(ofSize: 32, weight: .bold)
        titleLabel.textAlignment = .center

        subtitleLabel.text = L10n.t("profile.subtitle")
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.font = UIFont(name: "AvenirNext-Medium", size: 15) ?? .systemFont(ofSize: 15, weight: .medium)
        subtitleLabel.textAlignment = .center

        configureField(firstNameField, placeholder: L10n.t("auth.field.first_name"))
        configureField(lastNameField, placeholder: L10n.t("auth.field.last_name"))

        var configuration = UIButton.Configuration.filled()
        configuration.cornerStyle = .capsule
        configuration.title = L10n.t("profile.button.continue")
        configuration.baseBackgroundColor = UIColor(red: 0.86, green: 0.18, blue: 0.44, alpha: 1)
        continueButton.configuration = configuration
        continueButton.addTarget(self, action: #selector(continueTapped), for: .touchUpInside)

        activity.hidesWhenStopped = true

        let stack = UIStackView(arrangedSubviews: [
            titleLabel,
            subtitleLabel,
            firstNameField,
            lastNameField,
            continueButton,
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
            continueButton.heightAnchor.constraint(equalToConstant: 48)
        ])
    }

    private func configureField(_ field: UITextField, placeholder: String) {
        field.placeholder = placeholder
        field.borderStyle = .none
        field.layer.cornerRadius = 12
        field.layer.cornerCurve = .continuous
        field.layer.borderWidth = 1
        field.layer.borderColor = UIColor.systemGray5.cgColor
        field.backgroundColor = UIColor.secondarySystemBackground
        field.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 12, height: 1))
        field.leftViewMode = .always
    }

    private func bindViewModel() {
        viewModel.onLoadingChanged = { [weak self] loading in
            self?.continueButton.isEnabled = !loading
            if loading {
                self?.activity.startAnimating()
            } else {
                self?.activity.stopAnimating()
            }
        }

        viewModel.onSuccess = { [weak self] in
            self?.onProfileCompleted?()
        }

        viewModel.onError = { [weak self] message in
            let alert = UIAlertController(title: L10n.t("common.error_title"), message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: L10n.t("common.ok"), style: .default))
            self?.present(alert, animated: true)
        }
    }

    @objc private func continueTapped() {
        viewModel.save(
            firstName: firstNameField.text ?? "",
            lastName: lastNameField.text ?? ""
        )
    }
}
