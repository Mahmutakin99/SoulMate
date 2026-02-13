//
//  FirebaseManagerMessages.swift
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

        let path = "\(AppConfiguration.DatabasePath.chats)/\(chatID)/messages"
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

    func markMessageRead(chatID: String, messageID: String, completion: @escaping (Result<Void, Error>) -> Void) {
        #if canImport(FirebaseFunctions)
        guard isFirebaseConfigured() else {
            completion(.failure(FirebaseManagerError.generic(L10n.t("firebase.error.config_not_ready_restart"))))
            return
        }

        let trimmedChatID = chatID.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedMessageID = messageID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedChatID.isEmpty, !trimmedMessageID.isEmpty else {
            completion(.failure(FirebaseManagerError.generic(L10n.t("pairing.request.error.generic_invalid"))))
            return
        }

        let callable = Functions.functions(region: "europe-west1").httpsCallable("markMessageRead")
        callable.call([
            "chatID": trimmedChatID,
            "messageID": trimmedMessageID
        ]) { [weak self] _, error in
            if let error {
                completion(.failure(self?.mapFunctionsError(error, action: "markMessageRead") ?? error))
            } else {
                completion(.success(()))
            }
        }
        #else
        completion(.failure(FirebaseManagerError.sdkMissing))
        #endif
    }

    func setMessageReaction(
        chatID: String,
        messageID: String,
        ciphertext: String,
        keyVersion: Int,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        #if canImport(FirebaseFunctions)
        guard isFirebaseConfigured() else {
            completion(.failure(FirebaseManagerError.generic(L10n.t("firebase.error.config_not_ready_restart"))))
            return
        }

        let trimmedChatID = chatID.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedMessageID = messageID.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCiphertext = ciphertext.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedChatID.isEmpty,
              !trimmedMessageID.isEmpty,
              !trimmedCiphertext.isEmpty else {
            completion(.failure(FirebaseManagerError.generic(L10n.t("pairing.request.error.generic_invalid"))))
            return
        }

        let callable = Functions.functions(region: "europe-west1").httpsCallable("setMessageReaction")
        callable.call([
            "chatID": trimmedChatID,
            "messageID": trimmedMessageID,
            "ciphertext": trimmedCiphertext,
            "keyVersion": keyVersion
        ]) { [weak self] _, error in
            if let error {
                completion(.failure(self?.mapFunctionsError(error, action: "setMessageReaction") ?? error))
            } else {
                completion(.success(()))
            }
        }
        #else
        completion(.failure(FirebaseManagerError.sdkMissing))
        #endif
    }

    func clearMessageReaction(
        chatID: String,
        messageID: String,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        #if canImport(FirebaseFunctions)
        guard isFirebaseConfigured() else {
            completion(.failure(FirebaseManagerError.generic(L10n.t("firebase.error.config_not_ready_restart"))))
            return
        }

        let trimmedChatID = chatID.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedMessageID = messageID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedChatID.isEmpty, !trimmedMessageID.isEmpty else {
            completion(.failure(FirebaseManagerError.generic(L10n.t("pairing.request.error.generic_invalid"))))
            return
        }

        let callable = Functions.functions(region: "europe-west1").httpsCallable("clearMessageReaction")
        callable.call([
            "chatID": trimmedChatID,
            "messageID": trimmedMessageID
        ]) { [weak self] _, error in
            if let error {
                completion(.failure(self?.mapFunctionsError(error, action: "clearMessageReaction") ?? error))
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
            if self?.shouldLogObserverCancellation(mapped) ?? true {
                print("observeEncryptedMessages iptal edildi: \((mapped as NSError).localizedDescription)")
            }
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
            if self?.shouldLogObserverCancellation(mapped) ?? true {
                print("observeHeartbeat iptal edildi: \((mapped as NSError).localizedDescription)")
            }
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
            if self?.shouldLogObserverCancellation(mapped) ?? true {
                print("observeMoodCiphertext iptal edildi: \((mapped as NSError).localizedDescription)")
            }
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

    func observeMessageReceipts(
        chatID: String,
        onChange: @escaping ([MessageReceipt]) -> Void,
        onCancelled: ((Error) -> Void)? = nil
    ) -> FirebaseObservationToken {
        #if canImport(FirebaseDatabase)
        guard isFirebaseConfigured() else {
            #if DEBUG
            print("observeMessageReceipts atlandı: Firebase yapılandırılmamış.")
            #endif
            return FirebaseObservationToken {}
        }

        let ref = rootRef()
            .child(AppConfiguration.DatabasePath.events)
            .child(chatID)
            .child("messageReceipts")
        let path = "\(AppConfiguration.DatabasePath.events)/\(chatID)/messageReceipts"

        let handle = ref.observe(.value, with: { snapshot in
            var receipts: [MessageReceipt] = []
            for case let child as DataSnapshot in snapshot.children {
                guard let dictionary = child.value as? [String: Any],
                      let receipt = MessageReceipt(messageID: child.key, dictionary: dictionary) else {
                    continue
                }
                receipts.append(receipt)
            }
            onChange(receipts)
        }, withCancel: { [weak self] error in
            let mapped = self?.mapDatabaseError(error, path: path) ?? error
            #if DEBUG
            if self?.shouldLogObserverCancellation(mapped) ?? true {
                print("observeMessageReceipts iptal edildi: \((mapped as NSError).localizedDescription)")
            }
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

    func observeMessageReactions(
        chatID: String,
        onChange: @escaping ([(messageID: String, reactorUID: String, envelope: MessageReactionEnvelope)]) -> Void,
        onCancelled: ((Error) -> Void)? = nil
    ) -> FirebaseObservationToken {
        #if canImport(FirebaseDatabase)
        guard isFirebaseConfigured() else {
            #if DEBUG
            print("observeMessageReactions atlandı: Firebase yapılandırılmamış.")
            #endif
            return FirebaseObservationToken {}
        }

        let ref = rootRef()
            .child(AppConfiguration.DatabasePath.events)
            .child(chatID)
            .child("messageReactions")
        let path = "\(AppConfiguration.DatabasePath.events)/\(chatID)/messageReactions"

        let handle = ref.observe(.value, with: { snapshot in
            var rows: [(messageID: String, reactorUID: String, envelope: MessageReactionEnvelope)] = []
            for case let messageSnapshot as DataSnapshot in snapshot.children {
                for case let reactorSnapshot as DataSnapshot in messageSnapshot.children {
                    guard let envelope = MessageReactionEnvelope(snapshotValue: reactorSnapshot.value as Any) else {
                        continue
                    }
                    rows.append((
                        messageID: messageSnapshot.key,
                        reactorUID: reactorSnapshot.key,
                        envelope: envelope
                    ))
                }
            }
            onChange(rows)
        }, withCancel: { [weak self] error in
            let mapped = self?.mapDatabaseError(error, path: path) ?? error
            #if DEBUG
            if self?.shouldLogObserverCancellation(mapped) ?? true {
                print("observeMessageReactions iptal edildi: \((mapped as NSError).localizedDescription)")
            }
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
