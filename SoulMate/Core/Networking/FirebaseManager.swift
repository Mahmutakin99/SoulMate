import Foundation

#if canImport(FirebaseDatabase)
import FirebaseDatabase
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
    let configurationLock = NSLock()
    var isCoreConfigured = false
    var isMessagingDelegateConfigured = false
    var hasAPNSToken = false
    var isSyncingFCMToken = false
    var lastFCMTokenSyncAt: Date?
    let minimumFCMTokenSyncInterval: TimeInterval = 5
    let pushPromptRequestedKey = "com.soulmate.push.prompt.requested"

    private override init() {
        super.init()
    }

    static func chatID(for userA: String, and userB: String) -> String {
        [userA, userB].sorted().joined(separator: "_")
    }

    #if canImport(FirebaseDatabase)
    func rootRef() -> DatabaseReference {
        Database.database().reference()
    }
    #endif

    func allocatePairCode(uid: String, attemptsRemaining: Int = 8, completion: @escaping (Result<String, Error>) -> Void) {
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
    func parseEnvelopes(from snapshot: DataSnapshot) -> [EncryptedMessageEnvelope] {
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

    func isFirebaseConfigured() -> Bool {
        #if canImport(FirebaseCore)
        return isCoreConfigured
        #else
        return false
        #endif
    }

    #if canImport(FirebaseDatabase)
    func parseRelationshipRequests(from snapshot: DataSnapshot) -> [RelationshipRequest] {
        var requests: [RelationshipRequest] = []
        for case let child as DataSnapshot in snapshot.children {
            guard let dictionary = child.value as? [String: Any],
                  let request = RelationshipRequest(id: child.key, dictionary: dictionary) else {
                continue
            }
            requests.append(request)
        }

        requests.sort { lhs, rhs in
            if lhs.createdAt == rhs.createdAt {
                return lhs.id > rhs.id
            }
            return lhs.createdAt > rhs.createdAt
        }
        return requests
    }
    #endif
}
