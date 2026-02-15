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

    private let passwordPolicyPattern = "^(?=.*[a-z])(?=.*[A-Z])(?=.*\\d).+$"

    init(firebase: FirebaseManager = .shared) {
        self.firebase = firebase
    }

    func isStrongPassword(_ password: String) -> Bool {
        let clean = password.trimmingCharacters(in: .whitespacesAndNewlines)
        guard clean.count >= 8, clean.count <= 64 else { return false }
        return clean.range(of: passwordPolicyPattern, options: .regularExpression) != nil
    }

    func checkEmailInUse(_ email: String, completion: @escaping (Result<Bool, Error>) -> Void) {
        let cleanEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !cleanEmail.isEmpty else {
            completion(.success(false))
            return
        }

        firebase.isEmailAlreadyInUse(cleanEmail) { result in
            completion(result)
        }
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

            guard isStrongPassword(cleanPassword) else {
                onLoadingChanged?(false)
                onError?(L10n.t("auth.error.password_policy"))
                return
            }

            firebase.isEmailAlreadyInUse(cleanEmail) { [weak self] availabilityResult in
                guard let self else { return }

                switch availabilityResult {
                case .success(let inUse):
                    if inUse {
                        self.onLoadingChanged?(false)
                        self.onError?(L10n.t("auth.error.email_in_use"))
                        return
                    }
                    self.createAccount(
                        email: cleanEmail,
                        password: cleanPassword,
                        firstName: cleanFirstName,
                        lastName: cleanLastName
                    )
                case .failure:
                    // If proactive lookup fails, continue with create flow and rely on backend/Auth validation.
                    self.createAccount(
                        email: cleanEmail,
                        password: cleanPassword,
                        firstName: cleanFirstName,
                        lastName: cleanLastName
                    )
                }
            }
        }
    }

    private func createAccount(email: String, password: String, firstName: String, lastName: String) {
        firebase.createAccount(
            email: email,
            password: password,
            firstName: firstName,
            lastName: lastName
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

    private func emitError(_ error: Error) {
        let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        onError?(message)
    }
}
