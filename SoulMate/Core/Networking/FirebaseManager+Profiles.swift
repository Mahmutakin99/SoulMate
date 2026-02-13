import Foundation
#if canImport(FirebaseDatabase)
import FirebaseDatabase
#endif

extension FirebaseManager {
    func bootstrapUserIfNeeded(
        uid: String,
        firstName: String? = nil,
        lastName: String? = nil,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        let publicKey: String
        do {
            publicKey = try EncryptionService.shared.identityPublicKeyBase64()
        } catch {
            completion(.failure(error))
            return
        }

        ensureUserProfile(uid: uid, publicKey: publicKey, firstName: firstName, lastName: lastName) { result in
            switch result {
            case .success:
                completion(.success(uid))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    func syncIdentityPublicKeyIfNeeded(uid: String, completion: ((Result<Void, Error>) -> Void)? = nil) {
        #if canImport(FirebaseDatabase)
        guard isFirebaseConfigured() else {
            completion?(.failure(FirebaseManagerError.generic(L10n.t("firebase.error.config_not_ready_restart"))))
            return
        }

        let publicKey: String
        do {
            publicKey = try EncryptionService.shared.identityPublicKeyBase64()
        } catch {
            completion?(.failure(error))
            return
        }

        let path = "\(AppConfiguration.DatabasePath.users)/\(uid)/publicKey"
        rootRef()
            .child(AppConfiguration.DatabasePath.users)
            .child(uid)
            .child("publicKey")
            .setValue(publicKey) { [weak self] error, _ in
                if let error {
                    completion?(.failure(self?.mapDatabaseError(error, path: path) ?? error))
                } else {
                    completion?(.success(()))
                }
            }
        #else
        completion?(.failure(FirebaseManagerError.sdkMissing))
        #endif
    }

    func ensureUserProfile(
        uid: String,
        publicKey: String,
        firstName: String? = nil,
        lastName: String? = nil,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        #if canImport(FirebaseDatabase)
        guard isFirebaseConfigured() else {
            completion(.failure(FirebaseManagerError.generic(L10n.t("firebase.error.config_not_ready_restart"))))
            return
        }

        let userRef = rootRef().child(AppConfiguration.DatabasePath.users).child(uid)

        userRef.observeSingleEvent(of: .value, with: { [weak self] snapshot in
            var payload = snapshot.value as? [String: Any] ?? [:]
            let existingCode = payload["sixDigitUID"] as? String

            let finishWrite: (String) -> Void = { code in
                payload["sixDigitUID"] = code
                payload["publicKey"] = publicKey
                if let firstName = firstName?.trimmingCharacters(in: .whitespacesAndNewlines), !firstName.isEmpty {
                    payload["firstName"] = firstName
                }
                if let lastName = lastName?.trimmingCharacters(in: .whitespacesAndNewlines), !lastName.isEmpty {
                    payload["lastName"] = lastName
                }

                userRef.updateChildValues(payload) { error, _ in
                    if let error {
                        completion(.failure(self?.mapDatabaseError(error, path: "\(AppConfiguration.DatabasePath.users)/\(uid)") ?? error))
                        return
                    }

                    self?.ensurePairCodeMapping(uid: uid, code: code, completion: completion)
                }
            }

            if let existingCode {
                finishWrite(existingCode)
                return
            }

            guard let self else {
                completion(.failure(FirebaseManagerError.generic(L10n.t("firebase.error.pair_code_generation_unexpected"))))
                return
            }

            self.allocatePairCode(uid: uid) { result in
                switch result {
                case .success(let code):
                    finishWrite(code)
                case .failure(let error):
                    completion(.failure(error))
                }
            }
        }, withCancel: { error in
            completion(.failure(self.mapDatabaseError(error, path: "\(AppConfiguration.DatabasePath.users)/\(uid)")))
        })
        #else
        completion(.failure(FirebaseManagerError.sdkMissing))
        #endif
    }

    func ensurePairCodeMapping(
        uid: String,
        code: String,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        #if canImport(FirebaseDatabase)
        guard isFirebaseConfigured() else {
            completion(.failure(FirebaseManagerError.generic(L10n.t("firebase.error.config_not_ready_restart"))))
            return
        }

        let path = "\(AppConfiguration.DatabasePath.pairCodes)/\(code)"
        let pairCodeRef = rootRef()
            .child(AppConfiguration.DatabasePath.pairCodes)
            .child(code)

        pairCodeRef.observeSingleEvent(of: .value, with: { snapshot in
            if let mappedUID = snapshot.value as? String {
                if mappedUID == uid {
                    completion(.success(()))
                } else {
                    completion(.failure(FirebaseManagerError.generic(L10n.t("firebase.error.pair_id_other_account"))))
                }
                return
            }

            pairCodeRef.setValue(uid) { mapError, _ in
                if let mapError {
                    completion(.failure(self.mapDatabaseError(mapError, path: path)))
                } else {
                    completion(.success(()))
                }
            }
        }, withCancel: { error in
            completion(.failure(self.mapDatabaseError(error, path: path)))
        })
        #else
        completion(.failure(FirebaseManagerError.sdkMissing))
        #endif
    }

    func updateNameFields(uid: String, firstName: String, lastName: String, completion: @escaping (Result<Void, Error>) -> Void) {
        #if canImport(FirebaseDatabase)
        guard isFirebaseConfigured() else {
            completion(.failure(FirebaseManagerError.generic(L10n.t("firebase.error.config_not_ready_restart"))))
            return
        }

        let path = "\(AppConfiguration.DatabasePath.users)/\(uid)"
        rootRef()
            .child(AppConfiguration.DatabasePath.users)
            .child(uid)
            .updateChildValues([
                "firstName": firstName,
                "lastName": lastName
            ]) { error, _ in
                if let error {
                    completion(.failure(self.mapDatabaseError(error, path: path)))
                } else {
                    completion(.success(()))
                }
            }
        #else
        completion(.failure(FirebaseManagerError.sdkMissing))
        #endif
    }

    func fetchUserProfile(uid: String, completion: @escaping (Result<UserPairProfile, Error>) -> Void) {
        #if canImport(FirebaseDatabase)
        guard isFirebaseConfigured() else {
            completion(.failure(FirebaseManagerError.generic(L10n.t("firebase.error.config_not_ready_restart"))))
            return
        }

        let path = "\(AppConfiguration.DatabasePath.users)/\(uid)"
        rootRef()
            .child(AppConfiguration.DatabasePath.users)
            .child(uid)
            .observeSingleEvent(of: .value, with: { snapshot in
                guard let dictionary = snapshot.value as? [String: Any] else {
                    completion(.failure(FirebaseManagerError.generic(L10n.t("firebase.error.user_profile_not_found"))))
                    return
                }
                completion(.success(UserPairProfile(uid: uid, dictionary: dictionary)))
            }, withCancel: { error in
                completion(.failure(self.mapDatabaseError(error, path: path)))
            })
        #else
        completion(.failure(FirebaseManagerError.sdkMissing))
        #endif
    }

    func observeUserProfile(
        uid: String,
        onChange: @escaping (UserPairProfile) -> Void,
        onCancelled: ((Error) -> Void)? = nil
    ) -> FirebaseObservationToken {
        #if canImport(FirebaseDatabase)
        guard isFirebaseConfigured() else {
            #if DEBUG
            print("observeUserProfile atlandı: Firebase yapılandırılmamış.")
            #endif
            return FirebaseObservationToken {}
        }

        let ref = rootRef().child(AppConfiguration.DatabasePath.users).child(uid)
        let path = "\(AppConfiguration.DatabasePath.users)/\(uid)"
        let handle = ref.observe(.value, with: { snapshot in
            guard let dictionary = snapshot.value as? [String: Any] else { return }
            onChange(UserPairProfile(uid: uid, dictionary: dictionary))
        }, withCancel: { [weak self] error in
            let mapped = self?.mapDatabaseError(error, path: path) ?? error
            #if DEBUG
            print("observeUserProfile iptal edildi: \((mapped as NSError).localizedDescription)")
            #endif
            onCancelled?(mapped)
        })

        return FirebaseObservationToken {
            ref.removeObserver(withHandle: handle)
        }
        #else
        return FirebaseObservationToken {}
        #endif
    }
}
