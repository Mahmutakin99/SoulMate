import WidgetKit
import SwiftUI
import Foundation

struct SoulMateWidgetEntry: TimelineEntry {
    let date: Date
    let lastMessage: String
    let mood: String
    let distance: String
}

struct SoulMateTimelineProvider: TimelineProvider {
    private let appGroupIdentifier = "group.com.MahmutAKIN.SoulMate"

    func placeholder(in context: Context) -> SoulMateWidgetEntry {
        SoulMateWidgetEntry(
            date: Date(),
            lastMessage: NSLocalizedString("widget.placeholder.last_message", comment: ""),
            mood: NSLocalizedString("widget.placeholder.mood", comment: ""),
            distance: "5.0 km"
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (SoulMateWidgetEntry) -> Void) {
        completion(makeEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SoulMateWidgetEntry>) -> Void) {
        let entry = makeEntry()
        let refreshDate = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date().addingTimeInterval(900)
        completion(Timeline(entries: [entry], policy: .after(refreshDate)))
    }

    private func makeEntry() -> SoulMateWidgetEntry {
        let store = UserDefaults(suiteName: appGroupIdentifier)

        return SoulMateWidgetEntry(
            date: Date(),
            lastMessage: store?.string(forKey: "widget.latestMessage") ?? NSLocalizedString("widget.timeline.no_message", comment: ""),
            mood: store?.string(forKey: "widget.latestMood") ?? NSLocalizedString("widget.timeline.unknown_mood", comment: ""),
            distance: store?.string(forKey: "widget.latestDistance") ?? "--"
        )
    }
}
