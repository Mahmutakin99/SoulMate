import Foundation
#if canImport(FirebaseAuth)
import FirebaseAuth
#endif

extension FirebaseManager {
    func currentUserID() -> String? {
        #if canImport(FirebaseAuth)
        return Auth.auth().currentUser?.uid
        #else
        return nil
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
                completion: completion
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
            self?.bootstrapUserIfNeeded(uid: uid, completion: completion)
        }
        #else
        completion(.failure(FirebaseManagerError.sdkMissing))
        #endif
    }

    func signOut() throws {
        #if canImport(FirebaseAuth)
        try Auth.auth().signOut()
        #else
        throw FirebaseManagerError.sdkMissing
        #endif
    }
}
