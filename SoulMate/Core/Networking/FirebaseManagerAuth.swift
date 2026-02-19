//
//  FirebaseManagerAuth.swift
//  SoulMate
//
//  Created by MAHMUT AKIN on 02/02/2026.
//

import Foundation
#if canImport(FirebaseAuth)
import FirebaseAuth
#endif
#if canImport(FirebaseFunctions)
import FirebaseFunctions
#endif
#if canImport(UIKit)
import UIKit
#endif

extension FirebaseManager {
    func currentUserID() -> String? {
        #if canImport(FirebaseAuth)
        return Auth.auth().currentUser?.uid
        #else
        return nil
        #endif
    }

    func currentUserEmail() -> String? {
        #if canImport(FirebaseAuth)
        return Auth.auth().currentUser?.email
        #else
        return nil
        #endif
    }

    func isEmailAlreadyInUse(_ email: String, completion: @escaping (Result<Bool, Error>) -> Void) {
        #if canImport(FirebaseFunctions)
        guard isFirebaseConfigured() else {
            completion(.failure(FirebaseManagerError.generic(L10n.t("firebase.error.config_missing_plist"))))
            return
        }

        let cleanEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !cleanEmail.isEmpty else {
            completion(.success(false))
            return
        }

        let callable = Functions.functions(region: "europe-west1").httpsCallable("checkEmailInUse")
        callable.call(["email": cleanEmail]) { [weak self] result, error in
            if let error {
                completion(.failure(self?.mapFunctionsError(error, action: "checkEmailInUse") ?? error))
                return
            }

            let payload = result?.data as? [String: Any]
            let inUse = payload?["inUse"] as? Bool ?? false
            completion(.success(inUse))
        }
        #else
        completion(.failure(FirebaseManagerError.sdkMissing))
        #endif
    }

    func resolveLaunchState(completion: @escaping (Result<AppLaunchState, Error>) -> Void) {
        guard let uid = currentUserID() else {
            completion(.success(.unauthenticated))
            return
        }

        fetchUserProfile(uid: uid) { [weak self] profileResult in
            guard let self else { return }

            switch profileResult {
            case .failure(let error):
                self.bootstrapUserIfNeeded(uid: uid) { bootstrapResult in
                    switch bootstrapResult {
                    case .failure:
                        completion(.failure(error))
                    case .success:
                        self.resolveLaunchState(completion: completion)
                    }
                }

            case .success(let profile):
                let hasFirstName = !(profile.firstName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
                let hasLastName = !(profile.lastName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)

                guard hasFirstName && hasLastName else {
                    completion(.success(.needsProfileCompletion(uid: uid)))
                    return
                }

                guard let partnerUID = profile.partnerID?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !partnerUID.isEmpty else {
                    completion(.success(.needsPairing(uid: uid, sixDigitUID: profile.sixDigitUID)))
                    return
                }

                self.fetchUserProfile(uid: partnerUID) { partnerResult in
                    switch partnerResult {
                    case .failure:
                        completion(.success(.needsPairing(uid: uid, sixDigitUID: profile.sixDigitUID)))
                    case .success(let partnerProfile):
                        if partnerProfile.partnerID == uid {
                            completion(.success(.readyForChat(uid: uid, partnerUID: partnerUID)))
                        } else {
                            completion(.success(.needsPairing(uid: uid, sixDigitUID: profile.sixDigitUID)))
                        }
                    }
                }
            }
        }
    }

    func createAccount(
        email: String,
        password: String,
        firstName: String,
        lastName: String,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        #if canImport(FirebaseAuth)
        guard isFirebaseConfigured() else {
            completion(.failure(FirebaseManagerError.generic(L10n.t("firebase.error.config_missing_plist"))))
            return
        }

        Auth.auth().createUser(withEmail: email, password: password) { [weak self] result, error in
            if let error {
                completion(.failure(self?.mapAuthError(error, action: L10n.t("firebase.auth.action.sign_up")) ?? error))
                return
            }
            guard let uid = result?.user.uid else {
                completion(.failure(FirebaseManagerError.generic(L10n.t("firebase.error.create_account_failed"))))
                return
            }

            self?.bootstrapUserIfNeeded(
                uid: uid,
                firstName: firstName,
                lastName: lastName,
                completion: { [weak self] bootstrapResult in
                    switch bootstrapResult {
                    case .success:
                        self?.acquireSessionLock { lockResult in
                            switch lockResult {
                            case .success:
                                completion(.success(uid))
                            case .failure(let error):
                                self?.forceLocalSignOutIgnoringSessionLock()
                                completion(.failure(error))
                            }
                        }
                    case .failure(let error):
                        self?.forceLocalSignOutIgnoringSessionLock()
                        completion(.failure(error))
                    }
                }
            )
        }
        #else
        completion(.failure(FirebaseManagerError.sdkMissing))
        #endif
    }

    func signIn(email: String, password: String, completion: @escaping (Result<String, Error>) -> Void) {
        #if canImport(FirebaseAuth)
        guard isFirebaseConfigured() else {
            completion(.failure(FirebaseManagerError.generic(L10n.t("firebase.error.config_missing_plist"))))
            return
        }

        Auth.auth().signIn(withEmail: email, password: password) { [weak self] result, error in
            if let error {
                completion(.failure(self?.mapAuthError(error, action: L10n.t("firebase.auth.action.sign_in")) ?? error))
                return
            }
            guard let uid = result?.user.uid else {
                completion(.failure(FirebaseManagerError.generic(L10n.t("firebase.error.sign_in_failed"))))
                return
            }
            self?.bootstrapUserIfNeeded(uid: uid) { [weak self] bootstrapResult in
                switch bootstrapResult {
                case .success:
                    self?.acquireSessionLock { lockResult in
                        switch lockResult {
                        case .success:
                            completion(.success(uid))
                        case .failure(let error):
                            self?.forceLocalSignOutIgnoringSessionLock()
                            completion(.failure(error))
                        }
                    }
                case .failure(let error):
                    self?.forceLocalSignOutIgnoringSessionLock()
                    completion(.failure(error))
                }
            }
        }
        #else
        completion(.failure(FirebaseManagerError.sdkMissing))
        #endif
    }

    func validateOrAcquireSessionForCurrentUser(completion: @escaping (Result<Void, Error>) -> Void) {
        guard currentUserID() != nil else {
            completion(.success(()))
            return
        }

        acquireSessionLock { [weak self] result in
            switch result {
            case .success:
                completion(.success(()))
            case .failure(let error):
                if let managerError = error as? FirebaseManagerError,
                   case .sessionLockedElsewhere = managerError {
                    self?.forceLocalSignOutIgnoringSessionLock()
                }
                completion(.failure(error))
            }
        }
    }

    func signOutReleasingSession(completion: @escaping (Result<Void, Error>) -> Void) {
        #if canImport(FirebaseAuth)
        guard currentUserID() != nil else {
            completion(.success(()))
            return
        }

        releaseSessionLock { [weak self] result in
            switch result {
            case .success(let released):
                guard released else {
                    completion(.failure(FirebaseManagerError.logoutRequiresNetwork))
                    return
                }

                do {
                    try Auth.auth().signOut()
                    completion(.success(()))
                } catch {
                    completion(.failure(self?.mapAuthError(error, action: L10n.t("chat.menu.sign_out")) ?? error))
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
        #else
        completion(.failure(FirebaseManagerError.sdkMissing))
        #endif
    }

    func reauthenticateCurrentUser(currentPassword: String, completion: @escaping (Result<Void, Error>) -> Void) {
        #if canImport(FirebaseAuth)
        guard isFirebaseConfigured() else {
            completion(.failure(FirebaseManagerError.generic(L10n.t("firebase.error.config_not_ready_restart"))))
            return
        }
        guard let user = Auth.auth().currentUser,
              let email = user.email,
              !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            completion(.failure(FirebaseManagerError.unauthenticated))
            return
        }

        let trimmedPassword = currentPassword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPassword.isEmpty else {
            completion(.failure(FirebaseManagerError.generic(L10n.t("profile.management.error.current_password_required"))))
            return
        }

        let credential = EmailAuthProvider.credential(withEmail: email, password: trimmedPassword)
        user.reauthenticate(with: credential) { [weak self] _, error in
            if let error {
                completion(.failure(self?.mapAuthError(error, action: L10n.t("profile.management.button.change_password")) ?? error))
            } else {
                completion(.success(()))
            }
        }
        #else
        completion(.failure(FirebaseManagerError.sdkMissing))
        #endif
    }

    func changeMyPassword(newPassword: String, completion: @escaping (Result<Void, Error>) -> Void) {
        #if canImport(FirebaseFunctions)
        guard isFirebaseConfigured() else {
            completion(.failure(FirebaseManagerError.generic(L10n.t("firebase.error.config_not_ready_restart"))))
            return
        }
        guard currentUserID() != nil else {
            completion(.failure(FirebaseManagerError.unauthenticated))
            return
        }

        let trimmedPassword = newPassword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPassword.isEmpty else {
            completion(.failure(FirebaseManagerError.generic(L10n.t("profile.management.error.password_empty"))))
            return
        }

        let callable = Functions.functions(region: "europe-west1").httpsCallable("changeMyPassword")
        callable.call(["newPassword": trimmedPassword]) { [weak self] _, error in
            if let error {
                completion(.failure(self?.mapFunctionsError(error, action: "changeMyPassword") ?? error))
            } else {
                completion(.success(()))
            }
        }
        #else
        completion(.failure(FirebaseManagerError.sdkMissing))
        #endif
    }

    func deleteMyAccount(
        installationID: String = InstallationIDProvider.shared.installationID(),
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        #if canImport(FirebaseFunctions)
        guard isFirebaseConfigured() else {
            completion(.failure(FirebaseManagerError.generic(L10n.t("firebase.error.config_not_ready_restart"))))
            return
        }
        guard currentUserID() != nil else {
            completion(.failure(FirebaseManagerError.unauthenticated))
            return
        }

        let callable = Functions.functions(region: "europe-west1").httpsCallable("deleteMyAccount")
        callable.call([
            "installationID": installationID
        ]) { [weak self] _, error in
            if let error {
                completion(.failure(self?.mapFunctionsError(error, action: "deleteMyAccount") ?? error))
            } else {
                completion(.success(()))
            }
        }
        #else
        completion(.failure(FirebaseManagerError.sdkMissing))
        #endif
    }

    func forceLocalSignOutIgnoringSessionLock() {
        #if canImport(FirebaseAuth)
        try? Auth.auth().signOut()
        #endif
    }

    func signOut() throws {
        #if canImport(FirebaseAuth)
        try Auth.auth().signOut()
        #else
        throw FirebaseManagerError.sdkMissing
        #endif
    }

    private func acquireSessionLock(completion: @escaping (Result<Void, Error>) -> Void) {
        #if canImport(FirebaseFunctions)
        guard isFirebaseConfigured() else {
            completion(.failure(FirebaseManagerError.sessionValidationFailed))
            return
        }
        guard currentUserID() != nil else {
            completion(.failure(FirebaseManagerError.unauthenticated))
            return
        }

        let timeout = AppConfiguration.Session.lockCallTimeoutSeconds
        let callbackLock = NSLock()
        var didComplete = false
        let finish: (Result<Void, Error>) -> Void = { result in
            callbackLock.lock()
            defer { callbackLock.unlock() }
            guard !didComplete else { return }
            didComplete = true
            completion(result)
        }

        let timeoutWorkItem = DispatchWorkItem {
            #if DEBUG
            print("LAUNCH_VALIDATION_TIMEOUT action=acquireSessionLock timeout=\(timeout)s")
            #endif
            finish(.failure(FirebaseManagerError.sessionValidationFailed))
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout, execute: timeoutWorkItem)

        let callable = Functions.functions(region: "europe-west1").httpsCallable("acquireSessionLock")
        callable.call(sessionLockPayload()) { [weak self] _, error in
            timeoutWorkItem.cancel()
            if let error {
                finish(.failure(self?.mapFunctionsError(error, action: "acquireSessionLock") ?? error))
            } else {
                finish(.success(()))
            }
        }
        #else
        completion(.failure(FirebaseManagerError.sessionValidationFailed))
        #endif
    }

    private func releaseSessionLock(completion: @escaping (Result<Bool, Error>) -> Void) {
        #if canImport(FirebaseFunctions)
        guard isFirebaseConfigured() else {
            completion(.failure(FirebaseManagerError.logoutRequiresNetwork))
            return
        }
        guard currentUserID() != nil else {
            completion(.success(true))
            return
        }

        let timeout = AppConfiguration.Session.lockCallTimeoutSeconds
        let callbackLock = NSLock()
        var didComplete = false
        let finish: (Result<Bool, Error>) -> Void = { result in
            callbackLock.lock()
            defer { callbackLock.unlock() }
            guard !didComplete else { return }
            didComplete = true
            completion(result)
        }

        let timeoutWorkItem = DispatchWorkItem {
            #if DEBUG
            print("LAUNCH_VALIDATION_TIMEOUT action=releaseSessionLock timeout=\(timeout)s")
            #endif
            finish(.failure(FirebaseManagerError.logoutRequiresNetwork))
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout, execute: timeoutWorkItem)

        let callable = Functions.functions(region: "europe-west1").httpsCallable("releaseSessionLock")
        callable.call(["installationID": InstallationIDProvider.shared.installationID()]) { [weak self] result, error in
            timeoutWorkItem.cancel()
            if let error {
                finish(.failure(self?.mapFunctionsError(error, action: "releaseSessionLock") ?? error))
                return
            }

            let payload = result?.data as? [String: Any]
            let released = payload?["released"] as? Bool ?? false
            finish(.success(released))
        }
        #else
        completion(.failure(FirebaseManagerError.logoutRequiresNetwork))
        #endif
    }

    private func sessionLockPayload() -> [String: Any] {
        [
            "installationID": InstallationIDProvider.shared.installationID(),
            "platform": "ios",
            "deviceName": currentDeviceName(),
            "appVersion": currentAppVersion()
        ]
    }

    private func currentDeviceName() -> String {
        #if canImport(UIKit)
        return UIDevice.current.name
        #else
        return "unknown-device"
        #endif
    }

    private func currentAppVersion() -> String {
        let shortVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String

        switch (shortVersion, build) {
        case let (version?, build?) where !version.isEmpty && !build.isEmpty:
            return "\(version) (\(build))"
        case let (version?, _) where !version.isEmpty:
            return version
        case let (_, build?) where !build.isEmpty:
            return build
        default:
            return "unknown"
        }
    }
}
