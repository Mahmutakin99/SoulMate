import WidgetKit
import SwiftUI
import Foundation

@main
struct SoulMateWidgetBundle: WidgetBundle {
    var body: some Widget {
        SoulMateWidget()
        SoulMateLiveActivityWidget()
    }
}

struct SoulMateWidget: Widget {
    private let kind = "SoulMateWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SoulMateTimelineProvider()) { entry in
            SoulMateWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("SoulMate")
        .description(NSLocalizedString("widget.description", comment: ""))
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
