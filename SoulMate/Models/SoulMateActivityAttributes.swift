#if canImport(ActivityKit)
import ActivityKit

struct SoulMateActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var text: String
        var mood: String
    }

    var partnerName: String
}
#endif
