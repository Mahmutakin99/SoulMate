//
//  ReactionUsageStore.swift
//  SoulMate
//
//  Created by MAHMUT AKIN on 14/02/2026.
//

import Foundation

final class ReactionUsageStore {
    static let shared = ReactionUsageStore()

    private struct UsageEntry: Codable {
        var score: Double
        var lastUsedAt: TimeInterval
        var useCount: Int
    }

    private typealias UserUsageMap = [String: [String: UsageEntry]]

    private let storageKey = "chat.reaction.usage.v1"
    private let decayHours: Double = 72
    private let queue = DispatchQueue(label: "com.soulmate.reactionusage.store", qos: .utility)
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func recordUsage(emoji: String, uid: String, at date: Date = Date()) {
        let trimmedEmoji = emoji.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedUID = uid.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedEmoji.isEmpty, !trimmedUID.isEmpty else { return }

        queue.sync {
            var store = loadStore()
            var usageMap = store[trimmedUID] ?? [:]
            var entry = usageMap[trimmedEmoji] ?? UsageEntry(
                score: 0,
                lastUsedAt: date.timeIntervalSince1970,
                useCount: 0
            )

            let deltaHours = max(0, (date.timeIntervalSince1970 - entry.lastUsedAt) / 3600)
            let decayedScore = entry.score * exp(-deltaHours / decayHours)

            entry.score = decayedScore + 1
            entry.lastUsedAt = date.timeIntervalSince1970
            entry.useCount += 1

            usageMap[trimmedEmoji] = entry
            store[trimmedUID] = usageMap
            saveStore(store)
        }
    }

    func topEmojis(uid: String, maxCount: Int, fallback: [String]) -> [String] {
        let trimmedUID = uid.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedUID.isEmpty, maxCount > 0 else { return [] }

        return queue.sync {
            let store = loadStore()
            let usageMap = store[trimmedUID] ?? [:]
            let rankedUsage = rankedEmojis(from: usageMap)
            return mergedUnique(
                primary: rankedUsage,
                secondary: fallback,
                limit: maxCount
            )
        }
    }

    private func rankedEmojis(from map: [String: UsageEntry]) -> [String] {
        map
            .filter { !$0.key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted { lhs, rhs in
                if lhs.value.score != rhs.value.score {
                    return lhs.value.score > rhs.value.score
                }
                if lhs.value.lastUsedAt != rhs.value.lastUsedAt {
                    return lhs.value.lastUsedAt > rhs.value.lastUsedAt
                }
                return lhs.key < rhs.key
            }
            .map(\.key)
    }

    private func mergedUnique(primary: [String], secondary: [String], limit: Int) -> [String] {
        var output: [String] = []
        output.reserveCapacity(limit)

        func appendIfNeeded(_ emoji: String) {
            guard !emoji.isEmpty else { return }
            guard !output.contains(emoji) else { return }
            guard output.count < limit else { return }
            output.append(emoji)
        }

        primary.forEach(appendIfNeeded)
        secondary.forEach(appendIfNeeded)

        return output
    }

    private func loadStore() -> UserUsageMap {
        guard let data = defaults.data(forKey: storageKey) else {
            return [:]
        }

        do {
            return try JSONDecoder().decode(UserUsageMap.self, from: data)
        } catch {
            return [:]
        }
    }

    private func saveStore(_ store: UserUsageMap) {
        do {
            let data = try JSONEncoder().encode(store)
            defaults.set(data, forKey: storageKey)
        } catch {
            #if DEBUG
            print("ReactionUsageStore kaydedilemedi: \(error.localizedDescription)")
            #endif
        }
    }
}
