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
