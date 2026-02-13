//
//  SoulMateActivityAttributes.swift
//  SoulMate
//
//  Created by MAHMUT AKIN on 02/02/2026.
//

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
