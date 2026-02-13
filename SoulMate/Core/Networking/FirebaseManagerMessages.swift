//
//  AuthViewController.swift
//  SoulMate
//
//  Created by MAHMUT AKIN on 02/02/2026.
//

import Foundation
#if canImport(FirebaseDatabase)
import FirebaseDatabase
#endif
#if canImport(FirebaseFunctions)
import FirebaseFunctions
#endif

extension FirebaseManager {
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

    func ackMessageStored(chatID: String, messageID: String, completion: @escaping (Result<Void, Error>) -> Void) {
        #if canImport(FirebaseFunctions)
        guard isFirebaseConfigured() else {
            completion(.failure(FirebaseManagerError.generic(L10n.t("firebase.error.config_not_ready_restart"))))
            return
        }

        let trimmedChatID = chatID.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedMessageID = messageID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedChatID.isEmpty, !trimmedMessageID.isEmpty else {
            completion(.failure(FirebaseManagerError.generic(L10n.t("chat.local.error.invalid_ack_input"))))
            return
        }

        let callable = Functions.functions(region: "europe-west1").httpsCallable("ackMessageStored")
        callable.call([
            "chatID": trimmedChatID,
            "messageID": trimmedMessageID
        ]) { [weak self] _, error in
            if let error {
                completion(.failure(self?.mapFunctionsError(error, action: "ackMessageStored") ?? error))
            } else {
                completion(.success(()))
            }
        }
        #else
        completion(.failure(FirebaseManagerError.sdkMissing))
        #endif
    }

    func syncRecentCloudMessages(
        chatID: String,
        limit: UInt = AppConfiguration.MessageQueue.initialCloudSyncWindow,
        completion: @escaping (Result<[EncryptedMessageEnvelope], Error>) -> Void
    ) {
        fetchRecentEncryptedMessages(chatID: chatID, limit: limit, completion: completion)
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
        onMessage: @escaping (EncryptedMessageEnvelope) -> Void,
        onCancelled: ((Error) -> Void)? = nil
    ) -> FirebaseObservationToken {
        #if canImport(FirebaseDatabase)
        guard isFirebaseConfigured() else {
            #if DEBUG
            print("observeEncryptedMessages atlandı: Firebase yapılandırılmamış.")
            #endif
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
            #if DEBUG
            print("observeEncryptedMessages iptal edildi: \((mapped as NSError).localizedDescription)")
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

    func observeHeartbeat(
        chatID: String,
        currentUserID: String,
        onHeartbeat: @escaping () -> Void,
        onCancelled: ((Error) -> Void)? = nil
    ) -> FirebaseObservationToken {
        #if canImport(FirebaseDatabase)
        guard isFirebaseConfigured() else {
            #if DEBUG
            print("observeHeartbeat atlandı: Firebase yapılandırılmamış.")
            #endif
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
            #if DEBUG
            print("observeHeartbeat iptal edildi: \((mapped as NSError).localizedDescription)")
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

    func observeMoodCiphertext(
        uid: String,
        onChange: @escaping (String?) -> Void,
        onCancelled: ((Error) -> Void)? = nil
    ) -> FirebaseObservationToken {
        #if canImport(FirebaseDatabase)
        guard isFirebaseConfigured() else {
            #if DEBUG
            print("observeMoodCiphertext atlandı: Firebase yapılandırılmamış.")
            #endif
            return FirebaseObservationToken {}
        }

        let ref = rootRef().child(AppConfiguration.DatabasePath.users).child(uid).child("moodCiphertext")
        let path = "\(AppConfiguration.DatabasePath.users)/\(uid)/moodCiphertext"
        let handle = ref.observe(.value, with: { snapshot in
            onChange(snapshot.value as? String)
        }, withCancel: { [weak self] error in
            let mapped = self?.mapDatabaseError(error, path: path) ?? error
            #if DEBUG
            print("observeMoodCiphertext iptal edildi: \((mapped as NSError).localizedDescription)")
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
}
