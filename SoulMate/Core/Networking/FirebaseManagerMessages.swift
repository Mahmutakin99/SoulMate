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
        limit: UInt = AppConfiguration.Performance.bootstrapCloudWindow,
        completion: @escaping (Result<[EncryptedMessageEnvelope], Error>) -> Void
    ) {
        fetchRecentEncryptedMessages(chatID: chatID, limit: limit, completion: completion)
    }

    func fetchRecentEncryptedMessages(
        chatID: String,
        limit: UInt = AppConfiguration.Performance.initialLocalWindow,
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
            .queryOrdered(byChild: "timestamp")
            .queryLimited(toLast: max(limit, 1))

        query.getData(completion: { [weak self] error, snapshot in
            if let error {
                let mapped = self?.mapDatabaseError(error, path: path) ?? error
                completion(.failure(mapped))
                return
            }
            guard let snapshot else {
                completion(.success([]))
                return
            }
            completion(.success(self?.parseEnvelopes(from: snapshot) ?? []))
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
        let cursor = ChatSyncCursor(
            timestampMs: Int64(sentAt * 1000),
            messageID: String(repeating: "z", count: 32)
        )
        fetchOlderEncryptedMessages(chatID: chatID, before: cursor, limit: limit, completion: completion)
    }

    func fetchOlderEncryptedMessages(
        chatID: String,
        before cursor: ChatSyncCursor,
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

        let cursorTimestampSeconds = TimeInterval(cursor.timestampMs) / 1000
        let orderedQuery = ref.queryOrdered(byChild: "timestamp")
        let query: DatabaseQuery
        if cursor.messageID.isEmpty {
            query = orderedQuery
                .queryEnding(atValue: cursorTimestampSeconds)
                .queryLimited(toLast: pageLimit)
        } else {
            query = orderedQuery
                .queryEnding(atValue: cursorTimestampSeconds, childKey: cursor.messageID)
                .queryLimited(toLast: pageLimit)
        }

        query.getData(completion: { [weak self] error, snapshot in
            if let error {
                let mapped = self?.mapDatabaseError(error, path: path) ?? error
                completion(.failure(mapped))
                return
            }
            guard let snapshot else {
                completion(.success([]))
                return
            }
            let parsed = self?.parseEnvelopes(from: snapshot) ?? []
            let filtered = parsed.filter { envelope in
                !(envelope.id == cursor.messageID && Int64(envelope.timestamp * 1000) == cursor.timestampMs)
            }
            completion(.success(filtered))
        })
        #else
        completion(.failure(FirebaseManagerError.sdkMissing))
        #endif
    }

    func observeEncryptedMessages(
        chatID: String,
        startingAt sentAt: TimeInterval? = nil,
        startingAfterMessageID: String? = nil,
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

        let baseQuery = ref.queryOrdered(byChild: "timestamp")
        let query: DatabaseQuery
        if let sentAt {
            if let startingAfterMessageID {
                query = baseQuery.queryStarting(atValue: sentAt, childKey: startingAfterMessageID)
            } else {
                query = baseQuery.queryStarting(atValue: sentAt)
            }
        } else {
            query = baseQuery
        }

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
        onEvent: @escaping (MessageReceiptDeltaEvent) -> Void,
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

        let cancellationHandler: (Error) -> Void = { [weak self] error in
            let mapped = self?.mapDatabaseError(error, path: path) ?? error
            #if DEBUG
            if self?.shouldLogObserverCancellation(mapped) ?? true {
                print("observeMessageReceipts iptal edildi: \((mapped as NSError).localizedDescription)")
            }
            #endif
            onCancelled?(mapped)
        }

        let childAddedHandle = ref.observe(.childAdded, with: { snapshot in
            guard let dictionary = snapshot.value as? [String: Any],
                  let receipt = MessageReceipt(messageID: snapshot.key, dictionary: dictionary) else {
                return
            }
            onEvent(.upsert(receipt))
        }, withCancel: cancellationHandler)

        let childChangedHandle = ref.observe(.childChanged, with: { snapshot in
            guard let dictionary = snapshot.value as? [String: Any],
                  let receipt = MessageReceipt(messageID: snapshot.key, dictionary: dictionary) else {
                return
            }
            onEvent(.upsert(receipt))
        }, withCancel: cancellationHandler)

        let childRemovedHandle = ref.observe(.childRemoved, with: { snapshot in
            onEvent(.remove(messageID: snapshot.key))
        }, withCancel: cancellationHandler)

        return FirebaseObservationToken {
            ref.removeObserver(withHandle: childAddedHandle)
            ref.removeObserver(withHandle: childChangedHandle)
            ref.removeObserver(withHandle: childRemovedHandle)
        }
        #else
        return FirebaseObservationToken {}
        #endif
    }

    func observeMessageReactions(
        chatID: String,
        onEvent: @escaping (MessageReactionDeltaEvent) -> Void,
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

        let cancellationHandler: (Error) -> Void = { [weak self] error in
            let mapped = self?.mapDatabaseError(error, path: path) ?? error
            #if DEBUG
            if self?.shouldLogObserverCancellation(mapped) ?? true {
                print("observeMessageReactions iptal edildi: \((mapped as NSError).localizedDescription)")
            }
            #endif
            onCancelled?(mapped)
        }

        let childAddedHandle = ref.observe(.childAdded, with: { [weak self] messageSnapshot in
            guard let self else { return }
            let reactors = self.parseReactionRows(messageSnapshot: messageSnapshot)
            onEvent(.replace(messageID: messageSnapshot.key, reactors: reactors))
        }, withCancel: cancellationHandler)

        let childChangedHandle = ref.observe(.childChanged, with: { [weak self] messageSnapshot in
            guard let self else { return }
            let reactors = self.parseReactionRows(messageSnapshot: messageSnapshot)
            onEvent(.replace(messageID: messageSnapshot.key, reactors: reactors))
        }, withCancel: cancellationHandler)

        let childRemovedHandle = ref.observe(.childRemoved, with: { messageSnapshot in
            onEvent(.removeMessage(messageID: messageSnapshot.key))
        }, withCancel: cancellationHandler)

        return FirebaseObservationToken {
            ref.removeObserver(withHandle: childAddedHandle)
            ref.removeObserver(withHandle: childChangedHandle)
            ref.removeObserver(withHandle: childRemovedHandle)
        }
        #else
        return FirebaseObservationToken {}
        #endif
    }

    #if canImport(FirebaseDatabase)
    private func parseReactionRows(
        messageSnapshot: DataSnapshot
    ) -> [(reactorUID: String, envelope: MessageReactionEnvelope)] {
        var rows: [(reactorUID: String, envelope: MessageReactionEnvelope)] = []
        for case let reactorSnapshot as DataSnapshot in messageSnapshot.children {
            guard let envelope = MessageReactionEnvelope(snapshotValue: reactorSnapshot.value as Any) else {
                continue
            }
            rows.append((reactorUID: reactorSnapshot.key, envelope: envelope))
        }
        return rows
    }
    #endif
}
