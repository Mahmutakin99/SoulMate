//
//  ProfileManagementViewModel.swift
//  SoulMate
//
//  Created by MAHMUT AKIN on 14/02/2026.
//

import Foundation

final class ProfileManagementViewModel {
    var onLoadingChanged: ((Bool) -> Void)?
    var onProfileLoaded: ((String, String, String) -> Void)?
    var onError: ((String) -> Void)?
    var onNotice: ((String) -> Void)?
    var onPasswordChanged: (() -> Void)?
    var onSignedOut: (() -> Void)?
    var onAccountDeleted: (() -> Void)?

    private let firebase: FirebaseManager
    private let localMessageStore: LocalMessageStore
    private let reactionUsageStore: ReactionUsageStore
    private let encryption: EncryptionService
    private let defaults: UserDefaults

    private let noticeSeenKeyPrefix = "pairing.system_notice.last_seen"

    init(
        firebase: FirebaseManager = .shared,
        localMessageStore: LocalMessageStore = .shared,
        reactionUsageStore: ReactionUsageStore = .shared,
        encryption: EncryptionService = .shared,
        defaults: UserDefaults = .standard
    ) {
        self.firebase = firebase
        self.localMessageStore = localMessageStore
        self.reactionUsageStore = reactionUsageStore
        self.encryption = encryption
        self.defaults = defaults
    }

    func start() {
        guard let uid = firebase.currentUserID() else {
            emitError(FirebaseManagerError.unauthenticated)
            return
        }

        onLoadingChanged?(true)
        firebase.fetchUserProfile(uid: uid) { [weak self] result in
            guard let self else { return }
            self.onLoadingChanged?(false)

            switch result {
            case .failure(let error):
                self.emitError(error)
            case .success(let profile):
                let firstName = profile.firstName ?? ""
                let lastName = profile.lastName ?? ""
                let email = self.firebase.currentUserEmail() ?? L10n.t("profile.management.value.email_unknown")
                self.onProfileLoaded?(firstName, lastName, email)
            }
        }
    }

    func saveName(firstName: String, lastName: String) {
        guard let uid = firebase.currentUserID() else {
            emitError(FirebaseManagerError.unauthenticated)
            return
        }

        let cleanFirstName = firstName.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanLastName = lastName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanFirstName.isEmpty, !cleanLastName.isEmpty else {
            onError?(L10n.t("profile.error.name_required"))
            return
        }
        guard cleanFirstName.count <= 40, cleanLastName.count <= 40 else {
            onError?(L10n.t("profile.management.error.name_too_long"))
            return
        }

        onLoadingChanged?(true)
        firebase.updateNameFields(uid: uid, firstName: cleanFirstName, lastName: cleanLastName) { [weak self] result in
            guard let self else { return }
            self.onLoadingChanged?(false)

            switch result {
            case .failure(let error):
                self.emitError(error)
            case .success:
                self.onNotice?(L10n.t("profile.management.notice.saved"))
            }
        }
    }

    func changePassword(currentPassword: String, newPassword: String, confirmPassword: String) {
        let cleanCurrentPassword = currentPassword.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanNewPassword = newPassword.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanConfirmPassword = confirmPassword.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleanCurrentPassword.isEmpty else {
            onError?(L10n.t("profile.management.error.current_password_required"))
            return
        }
        guard !cleanNewPassword.isEmpty, !cleanConfirmPassword.isEmpty else {
            onError?(L10n.t("profile.management.error.password_empty"))
            return
        }
        guard cleanNewPassword == cleanConfirmPassword else {
            onError?(L10n.t("profile.management.error.password_mismatch"))
            return
        }
        guard isPasswordPolicyValid(cleanNewPassword) else {
            onError?(L10n.t("profile.management.error.password_policy"))
            return
        }

        onLoadingChanged?(true)
        firebase.reauthenticateCurrentUser(currentPassword: cleanCurrentPassword) { [weak self] reauthResult in
            guard let self else { return }

            switch reauthResult {
            case .failure(let error):
                self.onLoadingChanged?(false)
                self.emitError(error)
            case .success:
                self.firebase.changeMyPassword(newPassword: cleanNewPassword) { [weak self] result in
                    guard let self else { return }
                    self.onLoadingChanged?(false)

                    switch result {
                    case .failure(let error):
                        self.emitError(error)
                    case .success:
                        self.onNotice?(L10n.t("profile.management.notice.password_changed"))
                        self.onPasswordChanged?()
                    }
                }
            }
        }
    }

    func signOut() {
        onLoadingChanged?(true)
        firebase.signOutReleasingSession { [weak self] result in
            guard let self else { return }
            self.onLoadingChanged?(false)
            switch result {
            case .failure(let error):
                self.emitError(error)
            case .success:
                self.onSignedOut?()
            }
        }
    }

    func deleteAccount() {
        guard let uid = firebase.currentUserID() else {
            emitError(FirebaseManagerError.unauthenticated)
            return
        }

        onLoadingChanged?(true)
        firebase.deleteMyAccount { [weak self] result in
            guard let self else { return }
            self.onLoadingChanged?(false)

            switch result {
            case .failure(let error):
                self.emitError(error)
            case .success:
                self.performLocalPurge(uid: uid)
                self.firebase.forceLocalSignOutIgnoringSessionLock()
                self.onAccountDeleted?()
            }
        }
    }

    private func performLocalPurge(uid: String) {
        do {
            try localMessageStore.wipeAllData()
        } catch {
            #if DEBUG
            print("Local message purge başarısız: \(error.localizedDescription)")
            #endif
        }

        reactionUsageStore.clearUsage(uid: uid)
        encryption.clearAllKeyMaterial()

        defaults.removeObject(forKey: ChatViewController.quickEmojiVisibilityPreferenceKey)
        defaults.removeObject(forKey: ChatViewController.revealedSecretMessagesPreferenceKey)
        defaults.removeObject(forKey: "\(noticeSeenKeyPrefix).\(uid)")

        if let sharedDefaults = UserDefaults(suiteName: AppConfiguration.appGroupIdentifier) {
            sharedDefaults.removeObject(forKey: AppConfiguration.SharedStoreKey.latestMessage)
            sharedDefaults.removeObject(forKey: AppConfiguration.SharedStoreKey.latestMood)
            sharedDefaults.removeObject(forKey: AppConfiguration.SharedStoreKey.latestDistance)
        }
    }

    private func isPasswordPolicyValid(_ password: String) -> Bool {
        guard password.count >= 8, password.count <= 64 else { return false }
        let pattern = "^(?=.*[a-z])(?=.*[A-Z])(?=.*\\d).+$"
        return password.range(of: pattern, options: .regularExpression) != nil
    }

    private func emitError(_ error: Error) {
        let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        onError?(message)
    }
}
