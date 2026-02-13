import Foundation

enum ChatPayloadType: String, Codable {
    case text
    case emoji
    case gif
    case nudge
}

enum MoodStatus: String, CaseIterable, Codable {
    case happy
    case busy
    case tired
    case calm
    case missingYou

    var title: String {
        switch self {
        case .happy: return L10n.t("mood.happy")
        case .busy: return L10n.t("mood.busy")
        case .tired: return L10n.t("mood.tired")
        case .calm: return L10n.t("mood.calm")
        case .missingYou: return L10n.t("mood.missing_you")
        }
    }

    var icon: String {
        switch self {
        case .happy: return "sun.max.fill"
        case .busy: return "briefcase.fill"
        case .tired: return "moon.zzz.fill"
        case .calm: return "leaf.fill"
        case .missingYou: return "heart.fill"
        }
    }
}

enum RelationshipRequestType: String, Codable {
    case pair
    case unpair
}

enum RelationshipRequestStatus: String, Codable {
    case pending
    case accepted
    case rejected
    case expired
    case cancelled
}

enum RelationshipRequestDecision: String {
    case accept
    case reject
}

struct RelationshipRequest: Hashable {
    let id: String
    let type: RelationshipRequestType
    let status: RelationshipRequestStatus
    let fromUID: String
    let toUID: String
    let fromFirstName: String?
    let fromLastName: String?
    let fromSixDigitUID: String?
    let createdAt: Date
    let expiresAt: Date
    let resolvedAt: Date?

    init?(
        id: String,
        dictionary: [String: Any]
    ) {
        guard let typeRaw = dictionary["type"] as? String,
              let type = RelationshipRequestType(rawValue: typeRaw),
              let statusRaw = dictionary["status"] as? String,
              let status = RelationshipRequestStatus(rawValue: statusRaw),
              let fromUID = dictionary["fromUID"] as? String,
              let toUID = dictionary["toUID"] as? String,
              let createdAt = dictionary["createdAt"] as? TimeInterval,
              let expiresAt = dictionary["expiresAt"] as? TimeInterval else {
            return nil
        }

        self.id = id
        self.type = type
        self.status = status
        self.fromUID = fromUID
        self.toUID = toUID
        self.fromFirstName = dictionary["fromFirstName"] as? String
        self.fromLastName = dictionary["fromLastName"] as? String
        self.fromSixDigitUID = dictionary["fromSixDigitUID"] as? String

        self.createdAt = Date(timeIntervalSince1970: createdAt)
        self.expiresAt = Date(timeIntervalSince1970: expiresAt)

        if let resolvedAt = dictionary["resolvedAt"] as? TimeInterval {
            self.resolvedAt = Date(timeIntervalSince1970: resolvedAt)
        } else {
            self.resolvedAt = nil
        }
    }

    var isPending: Bool {
        status == .pending
    }

    var isExpired: Bool {
        Date() >= expiresAt
    }

    var senderDisplayName: String {
        let first = fromFirstName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let last = fromLastName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let fullName = "\(first) \(last)".trimmingCharacters(in: .whitespacesAndNewlines)
        if !fullName.isEmpty {
            return fullName
        }

        if let fromSixDigitUID, !fromSixDigitUID.isEmpty {
            return fromSixDigitUID
        }
        return fromUID
    }
}

struct ChatPayload: Codable {
    let type: ChatPayloadType
    let value: String
    let isSecret: Bool
    let sentAt: TimeInterval
}

struct EncryptedMessageEnvelope: Codable {
    let id: String
    let senderID: String
    let recipientID: String
    let payload: String
    let sentAt: TimeInterval
    let keyVersion: Int

    var dictionaryValue: [String: Any] {
        [
            "id": id,
            "senderID": senderID,
            "recipientID": recipientID,
            "payload": payload,
            "sentAt": sentAt,
            "keyVersion": keyVersion
        ]
    }

    init(id: String, senderID: String, recipientID: String, payload: String, sentAt: TimeInterval, keyVersion: Int = 1) {
        self.id = id
        self.senderID = senderID
        self.recipientID = recipientID
        self.payload = payload
        self.sentAt = sentAt
        self.keyVersion = keyVersion
    }

    init?(snapshotValue: Any) {
        guard let data = snapshotValue as? [String: Any],
              let id = data["id"] as? String,
              let senderID = data["senderID"] as? String,
              let recipientID = data["recipientID"] as? String,
              let payload = data["payload"] as? String,
              let sentAt = data["sentAt"] as? TimeInterval,
              let keyVersion = data["keyVersion"] as? Int else {
            return nil
        }

        self.id = id
        self.senderID = senderID
        self.recipientID = recipientID
        self.payload = payload
        self.sentAt = sentAt
        self.keyVersion = keyVersion
    }
}

struct ChatMessage: Hashable {
    let id: String
    let senderID: String
    let recipientID: String
    let sentAt: Date
    let type: ChatPayloadType
    let value: String
    let isSecret: Bool
}

struct UserPairProfile {
    let uid: String
    let sixDigitUID: String
    let firstName: String?
    let lastName: String?
    let partnerID: String?
    let publicKey: String?
    let moodCiphertext: String?
    let locationCiphertext: String?

    init(uid: String, dictionary: [String: Any]) {
        self.uid = uid
        self.sixDigitUID = dictionary["sixDigitUID"] as? String ?? ""
        self.firstName = dictionary["firstName"] as? String
        self.lastName = dictionary["lastName"] as? String
        self.partnerID = dictionary["partnerID"] as? String
        self.publicKey = dictionary["publicKey"] as? String
        self.moodCiphertext = dictionary["moodCiphertext"] as? String
        self.locationCiphertext = dictionary["locationCiphertext"] as? String
    }

    var dictionaryValue: [String: Any] {
        var dictionary: [String: Any] = [
            "sixDigitUID": sixDigitUID
        ]

        if let firstName {
            dictionary["firstName"] = firstName
        }
        if let lastName {
            dictionary["lastName"] = lastName
        }
        if let partnerID {
            dictionary["partnerID"] = partnerID
        }
        if let publicKey {
            dictionary["publicKey"] = publicKey
        }
        if let moodCiphertext {
            dictionary["moodCiphertext"] = moodCiphertext
        }
        if let locationCiphertext {
            dictionary["locationCiphertext"] = locationCiphertext
        }

        return dictionary
    }
}
