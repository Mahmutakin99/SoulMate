import Foundation

enum AppConfiguration {
    static let keychainService = "com.MahmutAKIN.SoulMate.secure"
    static let keychainAccessGroup = "BQH8W6X63R.com.MahmutAKIN.SoulMate.shared"
    static let appGroupIdentifier = "group.com.MahmutAKIN.SoulMate"

    enum DatabasePath {
        static let users = "users"
        static let pairCodes = "pairCodes"
        static let chats = "chats"
        static let events = "events"
    }

    enum SharedStoreKey {
        static let latestMessage = "widget.latestMessage"
        static let latestMood = "widget.latestMood"
        static let latestDistance = "widget.latestDistance"
    }

    enum NotificationPayloadKey {
        static let encryptedBody = "enc_body"
        static let senderID = "sender_id"
        static let chatID = "chat_id"
    }

    enum ChatPerformance {
        static let initialMessageWindow: UInt = 80
        static let historyPageSize: UInt = 50
        static let historyPreloadTopRowThreshold = 6
    }
}
