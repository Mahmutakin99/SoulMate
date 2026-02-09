import Foundation
#if canImport(ActivityKit)
import ActivityKit
#endif

final class LiveActivityManager {
    static let shared = LiveActivityManager()

    private init() {}

    func startIfNeeded(partnerName: String) {
        #if canImport(ActivityKit)
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        guard Activity<SoulMateActivityAttributes>.activities.isEmpty else { return }

        let attributes = SoulMateActivityAttributes(partnerName: partnerName)
        let state = SoulMateActivityAttributes.ContentState(text: L10n.t("live.state.secure_active"), mood: L10n.t("live.state.calm"))
        let content = ActivityContent(state: state, staleDate: nil)

        do {
            _ = try Activity<SoulMateActivityAttributes>.request(attributes: attributes, content: content)
        } catch {
            print("Canlı Etkinlik başlatılamadı: \(error.localizedDescription)")
        }
        #endif
    }

    func update(text: String, mood: String) {
        #if canImport(ActivityKit)
        let contentState = SoulMateActivityAttributes.ContentState(text: text, mood: mood)
        let content = ActivityContent(state: contentState, staleDate: nil)
        Task {
            for activity in Activity<SoulMateActivityAttributes>.activities {
                await activity.update(content)
            }
        }
        #endif
    }

    func endAll() {
        #if canImport(ActivityKit)
        Task {
            for activity in Activity<SoulMateActivityAttributes>.activities {
                let finalState = SoulMateActivityAttributes.ContentState(text: L10n.t("live.state.session_ended"), mood: L10n.t("live.state.neutral"))
                let finalContent = ActivityContent(state: finalState, staleDate: nil)
                await activity.end(finalContent, dismissalPolicy: .immediate)
            }
        }
        #endif
    }
}
