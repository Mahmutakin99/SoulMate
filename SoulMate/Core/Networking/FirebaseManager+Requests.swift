import Foundation
#if canImport(FirebaseDatabase)
import FirebaseDatabase
#endif
#if canImport(FirebaseFunctions)
import FirebaseFunctions
#endif

extension FirebaseManager {
    func createPairRequest(partnerCode: String, completion: @escaping (Result<Void, Error>) -> Void) {
        #if canImport(FirebaseFunctions)
        guard isFirebaseConfigured() else {
            completion(.failure(FirebaseManagerError.generic(L10n.t("firebase.error.config_not_ready_restart"))))
            return
        }

        let trimmedCode = partnerCode.trimmingCharacters(in: .whitespacesAndNewlines)
        let callable = Functions.functions(region: "europe-west1").httpsCallable("createPairRequest")
        callable.call(["partnerCode": trimmedCode]) { [weak self] _, error in
            if let error {
                completion(.failure(self?.mapFunctionsError(error, action: "createPairRequest") ?? error))
            } else {
                completion(.success(()))
            }
        }
        #else
        completion(.failure(FirebaseManagerError.sdkMissing))
        #endif
    }

    func respondPairRequest(
        requestID: String,
        decision: RelationshipRequestDecision,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        #if canImport(FirebaseFunctions)
        guard isFirebaseConfigured() else {
            completion(.failure(FirebaseManagerError.generic(L10n.t("firebase.error.config_not_ready_restart"))))
            return
        }

        let trimmedRequestID = requestID.trimmingCharacters(in: .whitespacesAndNewlines)
        let callable = Functions.functions(region: "europe-west1").httpsCallable("respondPairRequest")
        callable.call([
            "requestID": trimmedRequestID,
            "decision": decision.rawValue
        ]) { [weak self] _, error in
            if let error {
                completion(.failure(self?.mapFunctionsError(error, action: "respondPairRequest") ?? error))
            } else {
                completion(.success(()))
            }
        }
        #else
        completion(.failure(FirebaseManagerError.sdkMissing))
        #endif
    }

    func createUnpairRequest(completion: @escaping (Result<Void, Error>) -> Void) {
        #if canImport(FirebaseFunctions)
        guard isFirebaseConfigured() else {
            completion(.failure(FirebaseManagerError.generic(L10n.t("firebase.error.config_not_ready_restart"))))
            return
        }

        let callable = Functions.functions(region: "europe-west1").httpsCallable("createUnpairRequest")
        callable.call([:]) { [weak self] _, error in
            if let error {
                completion(.failure(self?.mapFunctionsError(error, action: "createUnpairRequest") ?? error))
            } else {
                completion(.success(()))
            }
        }
        #else
        completion(.failure(FirebaseManagerError.sdkMissing))
        #endif
    }

    func respondUnpairRequest(
        requestID: String,
        decision: RelationshipRequestDecision,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        #if canImport(FirebaseFunctions)
        guard isFirebaseConfigured() else {
            completion(.failure(FirebaseManagerError.generic(L10n.t("firebase.error.config_not_ready_restart"))))
            return
        }

        let trimmedRequestID = requestID.trimmingCharacters(in: .whitespacesAndNewlines)
        let payload: [String: Any] = [
            "requestID": trimmedRequestID,
            "decision": decision.rawValue
        ]

        let callable = Functions.functions(region: "europe-west1").httpsCallable("respondUnpairRequest")
        callable.call(payload) { [weak self] _, error in
            if let error {
                completion(.failure(self?.mapFunctionsError(error, action: "respondUnpairRequest") ?? error))
            } else {
                completion(.success(()))
            }
        }
        #else
        completion(.failure(FirebaseManagerError.sdkMissing))
        #endif
    }

    func observeIncomingRequests(
        uid: String,
        onChange: @escaping ([RelationshipRequest]) -> Void,
        onCancelled: ((Error) -> Void)? = nil
    ) -> FirebaseObservationToken {
        #if canImport(FirebaseDatabase)
        guard isFirebaseConfigured() else {
            #if DEBUG
            print("observeIncomingRequests atlandı: Firebase yapılandırılmamış.")
            #endif
            return FirebaseObservationToken {}
        }

        let baseRef = rootRef().child(AppConfiguration.DatabasePath.relationshipRequests)
        let limit = AppConfiguration.Request.maxInboxItems > 0 ? AppConfiguration.Request.maxInboxItems : 1
        let query = baseRef
            .queryOrdered(byChild: "toUID")
            .queryEqual(toValue: uid)
            .queryLimited(toLast: limit)

        let path = "\(AppConfiguration.DatabasePath.relationshipRequests)?toUID=\(uid)"
        let handle = query.observe(.value, with: { [weak self] snapshot in
            guard let self else { return }
            onChange(self.parseRelationshipRequests(from: snapshot))
        }, withCancel: { [weak self] error in
            let mapped = self?.mapDatabaseError(error, path: path) ?? error
            #if DEBUG
            print("observeIncomingRequests iptal edildi: \((mapped as NSError).localizedDescription)")
            #endif
            onCancelled?(mapped)
        })

        return FirebaseObservationToken {
            query.removeObserver(withHandle: handle)
        }
        #else
        return FirebaseObservationToken {}
        #endif
    }

    func observeOutgoingRequests(
        uid: String,
        onChange: @escaping ([RelationshipRequest]) -> Void,
        onCancelled: ((Error) -> Void)? = nil
    ) -> FirebaseObservationToken {
        #if canImport(FirebaseDatabase)
        guard isFirebaseConfigured() else {
            #if DEBUG
            print("observeOutgoingRequests atlandı: Firebase yapılandırılmamış.")
            #endif
            return FirebaseObservationToken {}
        }

        let baseRef = rootRef().child(AppConfiguration.DatabasePath.relationshipRequests)
        let limit = AppConfiguration.Request.maxInboxItems > 0 ? AppConfiguration.Request.maxInboxItems : 1
        let query = baseRef
            .queryOrdered(byChild: "fromUID")
            .queryEqual(toValue: uid)
            .queryLimited(toLast: limit)

        let path = "\(AppConfiguration.DatabasePath.relationshipRequests)?fromUID=\(uid)"
        let handle = query.observe(.value, with: { [weak self] snapshot in
            guard let self else { return }
            onChange(self.parseRelationshipRequests(from: snapshot))
        }, withCancel: { [weak self] error in
            let mapped = self?.mapDatabaseError(error, path: path) ?? error
            #if DEBUG
            print("observeOutgoingRequests iptal edildi: \((mapped as NSError).localizedDescription)")
            #endif
            onCancelled?(mapped)
        })

        return FirebaseObservationToken {
            query.removeObserver(withHandle: handle)
        }
        #else
        return FirebaseObservationToken {}
        #endif
    }
}
