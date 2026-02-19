//
//  AppConfiguration.swift
//  SoulMate
//
//  Created by MAHMUT AKIN on 02/02/2026.
//

import Foundation
import CoreGraphics

enum AppConfiguration {
    static let keychainService = "com.MahmutAKIN.SoulMate.secure"
    static let keychainAccessGroup = "BQH8W6X63R.com.MahmutAKIN.SoulMate.shared"
    static let appGroupIdentifier = "group.com.MahmutAKIN.SoulMate"

    enum DatabasePath {
        static let users = "users"
        static let pairCodes = "pairCodes"
        static let sessionLocks = "sessionLocks"
        static let chats = "chats"
        static let events = "events"
        static let relationshipRequests = "relationshipRequests"
        static let systemNotices = "systemNotices"
    }

    enum SharedStoreKey {
        static let latestMessage = "widget.latestMessage"
        static let latestMood = "widget.latestMood"
        static let latestDistance = "widget.latestDistance"
    }

    enum UserPreferenceKey {
        static let showsSplashOnLaunch = "userpref.showsSplashOnLaunch"
        static let heartbeatTempoPreset = "userpref.heartbeatTempoPreset"
        static let heartbeatIntensityPreset = "userpref.heartbeatIntensityPreset"
    }

    enum NotificationPayloadKey {
        static let encryptedBody = "enc_body"
        static let senderID = "sender_id"
        static let chatID = "chat_id"
    }

    enum ChatPerformance {
        static let initialMessageWindow: UInt = 60
        static let historyPageSize: UInt = 60
        static let historyPreloadTopRowThreshold = 6
        static let maxInMemoryMessages = 350
        static let maxInMemoryMessagesOnPressure = 180
    }

    enum MessageQueue {
        static let cloudTTLSeconds: TimeInterval = 7 * 24 * 60 * 60
        static let initialCloudSyncWindow: UInt = 60
        static let localPageSize: UInt = 60
    }

    enum Performance {
        static let initialLocalWindow: UInt = 60
        static let historyPageSize: UInt = 60
        static let bootstrapCloudWindow: UInt = 60
        static let firstPaintLogEnabled = true
    }

    enum FeatureFlags {
        static let localFirstEphemeralMessaging = true
        static let enableHybridSnapshotLaunch = true
        static let enableDeltaOnlyChatObservers = true
        static let enableConditionalBootstrap = true
        static let enableDeltaCoalescing = true
        static let enableScopedMetadataFetch = true
        static let enableBalancedLaunchFallback = true
    }

    enum ImageCache {
        static let maxMemoryCostBytes: UInt = 36 * 1024 * 1024
        static let maxDiskSizeBytes: UInt = 220 * 1024 * 1024
        static let maxDiskAgeSeconds: TimeInterval = 60 * 60 * 24 * 7
    }

    enum Request {
        static let expirySeconds: TimeInterval = 24 * 60 * 60
        static let maxInboxItems: UInt = 50
    }

    enum Session {
        static let installationIDAccount = "session.installation_id"
        static let lockCallTimeoutSeconds: TimeInterval = 12
    }

    enum Heartbeat {
        static let longPressStartDelaySeconds: TimeInterval = 0.26
        static let longPressAllowableMovement: CGFloat = 36
        static let maxHoldDurationSeconds: TimeInterval = 12
        static let minSendIntervalSeconds: TimeInterval = 1
        static let lubDubDelaySeconds: TimeInterval = 0.16
    }
}
