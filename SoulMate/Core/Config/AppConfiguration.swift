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
        static let relationshipRequests = "relationshipRequests"
    }

    enum SharedStoreKey {
        static let latestMessage = "widget.latestMessage"
        static let latestMood = "widget.latestMood"
        static let latestDistance = "widget.latestDistance"
    }

    enum UserPreferenceKey {
        static let showsSplashOnLaunch = "userpref.showsSplashOnLaunch"
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
        static let maxInMemoryMessages = 350
        static let maxInMemoryMessagesOnPressure = 180
    }

    enum ImageCache {
        static let maxMemoryCostBytes: UInt = 36 * 1024 * 1024
        static let maxDiskSizeBytes: UInt = 220 * 1024 * 1024
        static let maxDiskAgeSeconds: TimeInterval = 60 * 60 * 24 * 7
    }

    enum Archive {
        static let maxLocalMessages: UInt = 2000
        static let directoryName = "ArchivedConversations"
    }

    enum Request {
        static let expirySeconds: TimeInterval = 24 * 60 * 60
        static let maxInboxItems: UInt = 50
    }
}
