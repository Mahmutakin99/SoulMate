import Foundation

struct MessageSyncPolicy {
    static func shouldBootstrap(
        syncState: SyncStateRecord?,
        localMessageCount: Int,
        currentSchemaVersion: Int,
        currentAppVersion: String,
        featureEnabled: Bool
    ) -> MessageSyncPolicyDecision {
        guard featureEnabled else { return .skip }

        guard let syncState else {
            return .bootstrap(reason: "missing_cursor")
        }

        if syncState.lastSyncedTimestampMs == nil || syncState.lastSyncedMessageID == nil {
            return .bootstrap(reason: "missing_cursor")
        }

        if localMessageCount == 0 {
            return .bootstrap(reason: "local_empty")
        }

        if syncState.gapDetected {
            return .bootstrap(reason: "gap_detected")
        }

        if syncState.bootstrapIncomplete {
            return .bootstrap(reason: "bootstrap_incomplete")
        }

        if syncState.schemaVersion < currentSchemaVersion {
            return .bootstrap(reason: "schema_upgrade")
        }

        if syncState.appVersion != currentAppVersion {
            return .bootstrap(reason: "app_upgrade")
        }

        return .skip
    }
}
