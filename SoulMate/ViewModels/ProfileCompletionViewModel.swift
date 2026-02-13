//
//  AuthViewController.swift
//  SoulMate
//
//  Created by MAHMUT AKIN on 02/02/2026.
//

import Foundation

final class ProfileCompletionViewModel {
    var onLoadingChanged: ((Bool) -> Void)?
    var onSuccess: (() -> Void)?
    var onError: ((String) -> Void)?

    private let firebase: FirebaseManager
    private let uid: String

    init(uid: String, firebase: FirebaseManager = .shared) {
        self.uid = uid
        self.firebase = firebase
    }

    func save(firstName: String, lastName: String) {
        let cleanFirstName = firstName.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanLastName = lastName.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleanFirstName.isEmpty, !cleanLastName.isEmpty else {
            onError?(L10n.t("profile.error.name_required"))
            return
        }

        onLoadingChanged?(true)
        firebase.updateNameFields(uid: uid, firstName: cleanFirstName, lastName: cleanLastName) { [weak self] result in
            self?.onLoadingChanged?(false)
            switch result {
            case .success:
                self?.onSuccess?()
            case .failure(let error):
                let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                self?.onError?(message)
            }
        }
    }
}
