//
//  HapticEngine.swift
//  SoulMate
//
//  Created by MAHMUT AKIN on 02/02/2026.
//

import UIKit

enum HapticEngine {
    private static let impact = UIImpactFeedbackGenerator(style: .medium)

    static func playHeartbeatPattern(
        primaryIntensity: CGFloat = 0.7,
        secondaryIntensity: CGFloat = 0.52,
        interBeatDelay: TimeInterval = AppConfiguration.Heartbeat.lubDubDelaySeconds
    ) {
        let first = normalizedIntensity(primaryIntensity)
        let second = normalizedIntensity(secondaryIntensity)
        let delay = max(0.08, interBeatDelay)

        // UIFeedbackGenerator automatically respects iOS system haptic settings.
        impact.prepare()
        impact.impactOccurred(intensity: first)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            impact.prepare()
            impact.impactOccurred(intensity: second)
        }
    }

    private static func normalizedIntensity(_ value: CGFloat) -> CGFloat {
        min(max(value, 0.01), 1.0)
    }
}
