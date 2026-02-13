//
//  ChatViewModelWidget.swift
//  SoulMate
//
//  Created by MAHMUT AKIN on 02/02/2026.
//

import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

extension ChatViewModel {
    func persistWidgetLatestMessage(_ message: String) {
        guard let defaults = UserDefaults(suiteName: AppConfiguration.appGroupIdentifier) else { return }
        defaults.set(message, forKey: AppConfiguration.SharedStoreKey.latestMessage)
        scheduleWidgetRefresh()
    }

    func persistWidgetMood(_ mood: String) {
        guard let defaults = UserDefaults(suiteName: AppConfiguration.appGroupIdentifier) else { return }
        defaults.set(mood, forKey: AppConfiguration.SharedStoreKey.latestMood)
        scheduleWidgetRefresh()
    }

    func persistWidgetDistance(_ distance: String) {
        guard let defaults = UserDefaults(suiteName: AppConfiguration.appGroupIdentifier) else { return }
        defaults.set(distance, forKey: AppConfiguration.SharedStoreKey.latestDistance)
        scheduleWidgetRefresh()
    }

    func scheduleWidgetRefresh() {
        #if canImport(WidgetKit)
        widgetRefreshWorkItem?.cancel()
        let item = DispatchWorkItem {
            WidgetCenter.shared.reloadAllTimelines()
        }
        widgetRefreshWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: item)
        #endif
    }

    func clearWidgetConversationSnapshot() {
        guard let defaults = UserDefaults(suiteName: AppConfiguration.appGroupIdentifier) else { return }
        defaults.removeObject(forKey: AppConfiguration.SharedStoreKey.latestMessage)
        defaults.removeObject(forKey: AppConfiguration.SharedStoreKey.latestMood)
        defaults.removeObject(forKey: AppConfiguration.SharedStoreKey.latestDistance)
        scheduleWidgetRefresh()
    }
}
