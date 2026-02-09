import Foundation
import UIKit
import UserNotifications

#if canImport(FirebaseAuth)
import FirebaseAuth
#endif
#if canImport(FirebaseCore)
import FirebaseCore
#endif
#if canImport(FirebaseDatabase)
import FirebaseDatabase
#endif
#if canImport(FirebaseMessaging)
import FirebaseMessaging
#endif

enum FirebaseManagerError: LocalizedError {
    case sdkMissing
    case unauthenticated
    case partnerNotFound
    case invalidPairCode
    case generic(String)

    var errorDescription: String? {
        switch self {
        case .sdkMissing:
            return L10n.t("firebase.error.sdk_missing")
        case .unauthenticated:
            return L10n.t("firebase.error.unauthenticated")
        case .partnerNotFound:
            return L10n.t("firebase.error.partner_not_found")
        case .invalidPairCode:
            return L10n.t("firebase.error.invalid_pair_code")
        case .generic(let message):
            return message
        }
    }
}

final class FirebaseObservationToken {
    private var isCancelled = false
    private let cancellation: () -> Void

    init(cancellation: @escaping () -> Void) {
        self.cancellation = cancellation
    }

    func cancel() {
        guard !isCancelled else { return }
        isCancelled = true
        cancellation()
    }

    deinit {
        cancel()
    }
}

final class FirebaseManager: NSObject {
    static let shared = FirebaseManager()
    private let configurationLock = NSLock()
    private var isCoreConfigured = false
    private var isMessagingDelegateConfigured = false
    private let pushPromptRequestedKey = "com.soulmate.push.prompt.requested"

    private override init() {
        super.init()
        #if canImport(FirebaseCore)
        isCoreConfigured = FirebaseApp.app() != nil
        #endif
    }

    func configureIfNeeded() {
        configureCoreIfNeeded()
        configureMessagingDelegateIfNeeded()
    }

    func configureCoreIfNeeded() {
        #if canImport(FirebaseCore)
        configurationLock.lock()
        defer { configurationLock.unlock() }

        if isCoreConfigured || FirebaseApp.app() != nil {
            isCoreConfigured = true
            return
        }

        FirebaseApp.configure()
        isCoreConfigured = true
        #endif
    }

    func configureMessagingDelegateIfNeeded() {
        configureCoreIfNeeded()
        #if canImport(FirebaseMessaging)
        configurationLock.lock()
        if isMessagingDelegateConfigured {
            configurationLock.unlock()
            syncFCMTokenIfPossible()
            return
        }
        isMessagingDelegateConfigured = true
        configurationLock.unlock()
        Messaging.messaging().delegate = self
        syncFCMTokenIfPossible()
        #endif
    }

    func requestPushAuthorization() {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
            if let error {
                print("Bildirim izni alınamadı: \(error.localizedDescription)")
            }
            if granted {
                DispatchQueue.main.async {
                    UIApplication.shared.registerForRemoteNotifications()
                }
            }
        }
    }

    func requestPushAuthorizationIfNeeded() {
        #if targetEnvironment(simulator)
        print("Push registration skipped on simulator.")
        return
        #else
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: pushPromptRequestedKey) {
            return
        }
        defaults.set(true, forKey: pushPromptRequestedKey)
        requestPushAuthorization()
        #endif
    }

    func updateAPNSToken(_ deviceToken: Data) {
        #if canImport(FirebaseMessaging)
        Messaging.messaging().apnsToken = deviceToken
        syncFCMTokenIfPossible()
        #endif
    }

    func syncFCMTokenIfPossible() {
        #if canImport(FirebaseMessaging)
        guard isFirebaseConfigured() else { return }
        guard let uid = currentUserID() else { return }

        Messaging.messaging().token { [weak self] token, error in
            if let error {
                print("FCM token alınamadı: \(error.localizedDescription)")
                return
            }

            guard let token, !token.isEmpty else { return }
            self?.updateFCMToken(uid: uid, token: token)
        }
        #endif
    }

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

    private func ensurePairCodeMapping(
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

    func fetchUID(for sixDigitUID: String, completion: @escaping (Result<String, Error>) -> Void) {
        guard sixDigitUID.count == 6, sixDigitUID.allSatisfy(\.isNumber) else {
            completion(.failure(FirebaseManagerError.invalidPairCode))
            return
        }

        #if canImport(FirebaseDatabase)
        guard isFirebaseConfigured() else {
            completion(.failure(FirebaseManagerError.generic(L10n.t("firebase.error.config_not_ready_restart"))))
            return
        }

        let path = "\(AppConfiguration.DatabasePath.pairCodes)/\(sixDigitUID)"
        rootRef()
            .child(AppConfiguration.DatabasePath.pairCodes)
            .child(sixDigitUID)
            .observeSingleEvent(of: .value, with: { snapshot in
                if let uid = snapshot.value as? String {
                    completion(.success(uid))
                } else {
                    completion(.failure(FirebaseManagerError.partnerNotFound))
                }
            }, withCancel: { error in
                completion(.failure(self.mapDatabaseError(error, path: path)))
            })
        #else
        completion(.failure(FirebaseManagerError.sdkMissing))
        #endif
    }

    func updatePartnerID(for uid: String, partnerUID: String, completion: @escaping (Result<Void, Error>) -> Void) {
        #if canImport(FirebaseDatabase)
        guard isFirebaseConfigured() else {
            completion(.failure(FirebaseManagerError.generic(L10n.t("firebase.error.config_not_ready_restart"))))
            return
        }

        let path = "\(AppConfiguration.DatabasePath.users)/\(uid)/partnerID"
        rootRef()
            .child(AppConfiguration.DatabasePath.users)
            .child(uid)
            .child("partnerID")
            .setValue(partnerUID) { error, _ in
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

    func clearPartnerID(uid: String, completion: @escaping (Result<Void, Error>) -> Void) {
        #if canImport(FirebaseDatabase)
        guard isFirebaseConfigured() else {
            completion(.failure(FirebaseManagerError.generic(L10n.t("firebase.error.config_not_ready_restart"))))
            return
        }

        let path = "\(AppConfiguration.DatabasePath.users)/\(uid)/partnerID"
        rootRef()
            .child(AppConfiguration.DatabasePath.users)
            .child(uid)
            .child("partnerID")
            .setValue(NSNull()) { error, _ in
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

    func observeUserProfile(uid: String, onChange: @escaping (UserPairProfile) -> Void) -> FirebaseObservationToken {
        #if canImport(FirebaseDatabase)
        guard isFirebaseConfigured() else {
            print("observeUserProfile atlandı: Firebase yapılandırılmamış.")
            return FirebaseObservationToken {}
        }

        let ref = rootRef().child(AppConfiguration.DatabasePath.users).child(uid)
        let path = "\(AppConfiguration.DatabasePath.users)/\(uid)"
        let handle = ref.observe(.value, with: { snapshot in
            guard let dictionary = snapshot.value as? [String: Any] else { return }
            onChange(UserPairProfile(uid: uid, dictionary: dictionary))
        }, withCancel: { [weak self] error in
            let mapped = self?.mapDatabaseError(error, path: path) ?? error
            print("observeUserProfile iptal edildi: \((mapped as NSError).localizedDescription)")
        })

        return FirebaseObservationToken {
            ref.removeObserver(withHandle: handle)
        }
        #else
        return FirebaseObservationToken {}
        #endif
    }

    func sendEncryptedMessage(chatID: String, envelope: EncryptedMessageEnvelope, completion: @escaping (Result<Void, Error>) -> Void) {
        #if canImport(FirebaseDatabase)
        guard isFirebaseConfigured() else {
            completion(.failure(FirebaseManagerError.generic(L10n.t("firebase.error.config_not_ready_restart"))))
            return
        }

        let path = "\(AppConfiguration.DatabasePath.chats)/\(chatID)/messages/\(envelope.id)"
        rootRef()
            .child(AppConfiguration.DatabasePath.chats)
            .child(chatID)
            .child("messages")
            .child(envelope.id)
            .setValue(envelope.dictionaryValue) { error, _ in
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

    func fetchRecentEncryptedMessages(
        chatID: String,
        limit: UInt = AppConfiguration.ChatPerformance.initialMessageWindow,
        completion: @escaping (Result<[EncryptedMessageEnvelope], Error>) -> Void
    ) {
        #if canImport(FirebaseDatabase)
        guard isFirebaseConfigured() else {
            completion(.failure(FirebaseManagerError.generic(L10n.t("firebase.error.config_not_ready_restart"))))
            return
        }

        let path = "\(AppConfiguration.DatabasePath.chats)/\(chatID)/messages"
        let ref = rootRef()
            .child(AppConfiguration.DatabasePath.chats)
            .child(chatID)
            .child("messages")

        let query = ref
            .queryOrdered(byChild: "sentAt")
            .queryLimited(toLast: max(limit, 1))

        query.observeSingleEvent(of: .value, with: { [weak self] snapshot in
            guard let self else { return }
            completion(.success(self.parseEnvelopes(from: snapshot)))
        }, withCancel: { [weak self] error in
            let mapped = self?.mapDatabaseError(error, path: path) ?? error
            completion(.failure(mapped))
        })
        #else
        completion(.failure(FirebaseManagerError.sdkMissing))
        #endif
    }

    func fetchOlderEncryptedMessages(
        chatID: String,
        endingAtOrBefore sentAt: TimeInterval,
        limit: UInt = AppConfiguration.ChatPerformance.historyPageSize,
        completion: @escaping (Result<[EncryptedMessageEnvelope], Error>) -> Void
    ) {
        #if canImport(FirebaseDatabase)
        guard isFirebaseConfigured() else {
            completion(.failure(FirebaseManagerError.generic(L10n.t("firebase.error.config_not_ready_restart"))))
            return
        }

        let pageLimit = max(limit, 1) + 1
        let path = "\(AppConfiguration.DatabasePath.chats)/\(chatID)/messages"
        let ref = rootRef()
            .child(AppConfiguration.DatabasePath.chats)
            .child(chatID)
            .child("messages")

        let query = ref
            .queryOrdered(byChild: "sentAt")
            .queryEnding(atValue: sentAt)
            .queryLimited(toLast: pageLimit)

        query.observeSingleEvent(of: .value, with: { [weak self] snapshot in
            guard let self else { return }
            completion(.success(self.parseEnvelopes(from: snapshot)))
        }, withCancel: { [weak self] error in
            let mapped = self?.mapDatabaseError(error, path: path) ?? error
            completion(.failure(mapped))
        })
        #else
        completion(.failure(FirebaseManagerError.sdkMissing))
        #endif
    }

    func observeEncryptedMessages(
        chatID: String,
        startingAt sentAt: TimeInterval? = nil,
        onMessage: @escaping (EncryptedMessageEnvelope) -> Void
    ) -> FirebaseObservationToken {
        #if canImport(FirebaseDatabase)
        guard isFirebaseConfigured() else {
            print("observeEncryptedMessages atlandı: Firebase yapılandırılmamış.")
            return FirebaseObservationToken {}
        }

        let path = "\(AppConfiguration.DatabasePath.chats)/\(chatID)/messages"
        let ref = rootRef()
            .child(AppConfiguration.DatabasePath.chats)
            .child(chatID)
            .child("messages")

        let baseQuery = ref.queryOrdered(byChild: "sentAt")
        let query = sentAt.map { baseQuery.queryStarting(atValue: $0) } ?? baseQuery

        let handle = query.observe(.childAdded, with: { snapshot in
            guard let envelope = EncryptedMessageEnvelope(snapshotValue: snapshot.value as Any) else { return }
            onMessage(envelope)
        }, withCancel: { [weak self] error in
            let mapped = self?.mapDatabaseError(error, path: path) ?? error
            print("observeEncryptedMessages iptal edildi: \((mapped as NSError).localizedDescription)")
        })

        return FirebaseObservationToken {
            query.removeObserver(withHandle: handle)
        }
        #else
        return FirebaseObservationToken {}
        #endif
    }

    func sendHeartbeat(chatID: String, senderID: String, completion: @escaping (Result<Void, Error>) -> Void) {
        #if canImport(FirebaseDatabase)
        guard isFirebaseConfigured() else {
            completion(.failure(FirebaseManagerError.generic(L10n.t("firebase.error.config_not_ready_restart"))))
            return
        }

        let heartbeatRef = rootRef()
            .child(AppConfiguration.DatabasePath.events)
            .child(chatID)
            .child("heartbeat")
            .childByAutoId()
        let path = "\(AppConfiguration.DatabasePath.events)/\(chatID)/heartbeat"

        heartbeatRef.setValue([
            "senderID": senderID,
            "sentAt": Date().timeIntervalSince1970
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

    func observeHeartbeat(chatID: String, currentUserID: String, onHeartbeat: @escaping () -> Void) -> FirebaseObservationToken {
        #if canImport(FirebaseDatabase)
        guard isFirebaseConfigured() else {
            print("observeHeartbeat atlandı: Firebase yapılandırılmamış.")
            return FirebaseObservationToken {}
        }

        let ref = rootRef()
            .child(AppConfiguration.DatabasePath.events)
            .child(chatID)
            .child("heartbeat")
        let path = "\(AppConfiguration.DatabasePath.events)/\(chatID)/heartbeat"

        let handle = ref.observe(.childAdded, with: { snapshot in
            guard let dictionary = snapshot.value as? [String: Any],
                  let senderID = dictionary["senderID"] as? String,
                  senderID != currentUserID else {
                return
            }
            onHeartbeat()
        }, withCancel: { [weak self] error in
            let mapped = self?.mapDatabaseError(error, path: path) ?? error
            print("observeHeartbeat iptal edildi: \((mapped as NSError).localizedDescription)")
        })

        return FirebaseObservationToken {
            ref.removeObserver(withHandle: handle)
        }
        #else
        return FirebaseObservationToken {}
        #endif
    }

    func updateMoodCiphertext(uid: String, ciphertext: String, completion: @escaping (Result<Void, Error>) -> Void) {
        #if canImport(FirebaseDatabase)
        guard isFirebaseConfigured() else {
            completion(.failure(FirebaseManagerError.generic(L10n.t("firebase.error.config_not_ready_restart"))))
            return
        }

        let path = "\(AppConfiguration.DatabasePath.users)/\(uid)/moodCiphertext"
        rootRef()
            .child(AppConfiguration.DatabasePath.users)
            .child(uid)
            .child("moodCiphertext")
            .setValue(ciphertext) { error, _ in
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

    func observeMoodCiphertext(uid: String, onChange: @escaping (String?) -> Void) -> FirebaseObservationToken {
        #if canImport(FirebaseDatabase)
        guard isFirebaseConfigured() else {
            print("observeMoodCiphertext atlandı: Firebase yapılandırılmamış.")
            return FirebaseObservationToken {}
        }

        let ref = rootRef().child(AppConfiguration.DatabasePath.users).child(uid).child("moodCiphertext")
        let path = "\(AppConfiguration.DatabasePath.users)/\(uid)/moodCiphertext"
        let handle = ref.observe(.value, with: { snapshot in
            onChange(snapshot.value as? String)
        }, withCancel: { [weak self] error in
            let mapped = self?.mapDatabaseError(error, path: path) ?? error
            print("observeMoodCiphertext iptal edildi: \((mapped as NSError).localizedDescription)")
        })

        return FirebaseObservationToken {
            ref.removeObserver(withHandle: handle)
        }
        #else
        return FirebaseObservationToken {}
        #endif
    }

    func updateLocationCiphertext(uid: String, ciphertext: String, completion: @escaping (Result<Void, Error>) -> Void) {
        #if canImport(FirebaseDatabase)
        guard isFirebaseConfigured() else {
            completion(.failure(FirebaseManagerError.generic(L10n.t("firebase.error.config_not_ready_restart"))))
            return
        }

        let path = "\(AppConfiguration.DatabasePath.users)/\(uid)/locationCiphertext"
        rootRef()
            .child(AppConfiguration.DatabasePath.users)
            .child(uid)
            .child("locationCiphertext")
            .setValue(ciphertext) { error, _ in
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

    func updateFCMToken(uid: String, token: String) {
        #if canImport(FirebaseDatabase)
        rootRef()
            .child(AppConfiguration.DatabasePath.users)
            .child(uid)
            .child("fcmToken")
            .setValue(token)
        #endif
    }

    static func chatID(for userA: String, and userB: String) -> String {
        [userA, userB].sorted().joined(separator: "_")
    }

    #if canImport(FirebaseDatabase)
    private func rootRef() -> DatabaseReference {
        Database.database().reference()
    }
    #endif

    private func allocatePairCode(uid: String, attemptsRemaining: Int = 8, completion: @escaping (Result<String, Error>) -> Void) {
        guard attemptsRemaining > 0 else {
            completion(.failure(FirebaseManagerError.generic(L10n.t("firebase.error.unique_pair_code_failed"))))
            return
        }

        #if canImport(FirebaseDatabase)
        guard isFirebaseConfigured() else {
            completion(.failure(FirebaseManagerError.generic(L10n.t("firebase.error.config_not_ready_restart"))))
            return
        }

        let code = Self.generateSixDigitUID()
        let codeRef = rootRef().child(AppConfiguration.DatabasePath.pairCodes).child(code)
        let path = "\(AppConfiguration.DatabasePath.pairCodes)/\(code)"

        codeRef.observeSingleEvent(of: .value, with: { [weak self] snapshot in
            if snapshot.exists() {
                self?.allocatePairCode(uid: uid, attemptsRemaining: attemptsRemaining - 1, completion: completion)
                return
            }

            codeRef.setValue(uid) { error, _ in
                if let error {
                    completion(.failure(self?.mapDatabaseError(error, path: path) ?? error))
                } else {
                    completion(.success(code))
                }
            }
        }, withCancel: { error in
            completion(.failure(self.mapDatabaseError(error, path: path)))
        })
        #else
        completion(.failure(FirebaseManagerError.sdkMissing))
        #endif
    }

    private static func generateSixDigitUID() -> String {
        String(format: "%06d", Int.random(in: 0...999_999))
    }

    #if canImport(FirebaseDatabase)
    private func parseEnvelopes(from snapshot: DataSnapshot) -> [EncryptedMessageEnvelope] {
        var envelopes: [EncryptedMessageEnvelope] = []
        for case let child as DataSnapshot in snapshot.children {
            guard let envelope = EncryptedMessageEnvelope(snapshotValue: child.value as Any) else { continue }
            envelopes.append(envelope)
        }

        envelopes.sort { lhs, rhs in
            if lhs.sentAt == rhs.sentAt {
                return lhs.id < rhs.id
            }
            return lhs.sentAt < rhs.sentAt
        }
        return envelopes
    }
    #endif

    private func isFirebaseConfigured() -> Bool {
        #if canImport(FirebaseCore)
        return FirebaseApp.app() != nil
        #else
        return false
        #endif
    }

    private func mapAuthError(_ error: Error, action: String) -> Error {
        let nsError = error as NSError
        print("FirebaseAuth \(action) hatası: domain=\(nsError.domain) code=\(nsError.code) message=\(nsError.localizedDescription)")

        #if canImport(FirebaseAuth)
        guard nsError.domain == AuthErrorDomain,
              let code = AuthErrorCode(rawValue: nsError.code) else {
            return FirebaseManagerError.generic(L10n.f("firebase.auth.error.unexpected_format", action, nsError.localizedDescription))
        }

        switch code {
        case .invalidEmail:
            return FirebaseManagerError.generic(L10n.t("firebase.auth.error.invalid_email"))
        case .emailAlreadyInUse:
            return FirebaseManagerError.generic(L10n.t("firebase.auth.error.email_in_use"))
        case .weakPassword:
            return FirebaseManagerError.generic(L10n.t("firebase.auth.error.weak_password"))
        case .wrongPassword:
            return FirebaseManagerError.generic(L10n.t("firebase.auth.error.wrong_password"))
        case .userNotFound:
            return FirebaseManagerError.generic(L10n.t("firebase.auth.error.user_not_found"))
        case .userDisabled:
            return FirebaseManagerError.generic(L10n.t("firebase.auth.error.user_disabled"))
        case .tooManyRequests:
            return FirebaseManagerError.generic(L10n.t("firebase.auth.error.too_many_requests"))
        case .networkError:
            return FirebaseManagerError.generic(L10n.t("firebase.auth.error.network"))
        case .operationNotAllowed:
            return FirebaseManagerError.generic(L10n.t("firebase.auth.error.operation_not_allowed"))
        case .appNotAuthorized:
            return FirebaseManagerError.generic(L10n.t("firebase.auth.error.app_not_authorized"))
        case .internalError:
            return FirebaseManagerError.generic(L10n.t("firebase.auth.error.internal"))
        default:
            return FirebaseManagerError.generic(L10n.f("firebase.auth.error.action_failed_format", action, nsError.localizedDescription))
        }
        #else
        return FirebaseManagerError.generic(L10n.f("firebase.auth.error.action_failed_format", action, nsError.localizedDescription))
        #endif
    }

    private func mapDatabaseError(_ error: Error, path: String) -> Error {
        let nsError = error as NSError
        print("RealtimeDatabase hatası path=\(path) domain=\(nsError.domain) code=\(nsError.code) message=\(nsError.localizedDescription)")

        let description = nsError.localizedDescription.lowercased()
        let details = (nsError.userInfo["details"] as? String)?.lowercased() ?? ""
        let combined = "\(description) \(details)"

        if combined.contains("permission_denied") || (combined.contains("permission") && combined.contains("denied")) {
            return FirebaseManagerError.generic(L10n.f("firebase.db.error.permission_denied_format", path))
        }
        if combined.contains("disconnected") {
            return FirebaseManagerError.generic(L10n.f("firebase.db.error.disconnected_format", path))
        }
        if combined.contains("network") || combined.contains("offline") || combined.contains("timed out") {
            return FirebaseManagerError.generic(L10n.f("firebase.db.error.network_format", path))
        }

        return FirebaseManagerError.generic(L10n.f("firebase.db.error.generic_format", path, nsError.localizedDescription))
    }
}

#if canImport(FirebaseMessaging)
extension FirebaseManager: MessagingDelegate {
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard let fcmToken,
              let uid = currentUserID() else { return }
        updateFCMToken(uid: uid, token: fcmToken)
    }
}
#endif
