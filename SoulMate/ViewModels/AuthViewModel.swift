//
//  AuthViewModel.swift
//  SoulMate
//
//  Created by MAHMUT AKIN on 02/02/2026.
//

import Foundation

final class AuthViewModel {
    enum Mode {
        case signIn
        case signUp
    }

    var onLoadingChanged: ((Bool) -> Void)?
    var onSuccess: (() -> Void)?
    var onError: ((String) -> Void)?

    private let firebase: FirebaseManager

    init(firebase: FirebaseManager = .shared) {
        self.firebase = firebase
    }

    func submit(
        mode: Mode,
        firstName: String?,
        lastName: String?,
        email: String,
        password: String
    ) {
        let cleanEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let cleanPassword = password.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleanEmail.isEmpty, !cleanPassword.isEmpty else {
            onError?(L10n.t("auth.error.empty_credentials"))
            return
        }

        guard cleanEmail.contains("@"), cleanEmail.contains(".") else {
            onError?(L10n.t("auth.error.invalid_email"))
            return
        }

        onLoadingChanged?(true)

        switch mode {
        case .signIn:
            firebase.signIn(email: cleanEmail, password: cleanPassword) { [weak self] result in
                self?.onLoadingChanged?(false)
                switch result {
                case .success:
                    self?.onSuccess?()
                case .failure(let error):
                    self?.emitError(error)
                }
            }

        case .signUp:
            let cleanFirstName = (firstName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let cleanLastName = (lastName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

            guard !cleanFirstName.isEmpty, !cleanLastName.isEmpty else {
                onLoadingChanged?(false)
                onError?(L10n.t("auth.error.signup_name_required"))
                return
            }

            guard cleanPassword.count >= 6 else {
                onLoadingChanged?(false)
                onError?(L10n.t("auth.error.password_min_length"))
                return
            }

            firebase.createAccount(
                email: cleanEmail,
                password: cleanPassword,
                firstName: cleanFirstName,
                lastName: cleanLastName
            ) { [weak self] result in
                self?.onLoadingChanged?(false)
                switch result {
                case .success:
                    self?.onSuccess?()
                case .failure(let error):
                    self?.emitError(error)
                }
            }
        }
    }

    private func emitError(_ error: Error) {
        let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        onError?(message)
    }
}
