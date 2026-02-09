import ActivityKit
import WidgetKit
import SwiftUI

struct SoulMateActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var text: String
        var mood: String
    }

    var partnerName: String
}

@available(iOSApplicationExtension 16.1, *)
struct SoulMateLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SoulMateActivityAttributes.self) { context in
            VStack(alignment: .leading) {
                Text(context.attributes.partnerName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(context.state.text)
                    .font(.headline)
                Text(context.state.mood)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text("💞")
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.state.text)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.mood)
                }
            } compactLeading: {
                Text("💞")
            } compactTrailing: {
                Text("•")
            } minimal: {
                Text("💞")
            }
            .widgetURL(URL(string: "soulmate://chat"))
        }
    }
}
