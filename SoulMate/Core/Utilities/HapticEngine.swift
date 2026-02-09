import UIKit

enum HapticEngine {
    static func playHeartbeatPattern() {
        let impact = UIImpactFeedbackGenerator(style: .medium)
        let notification = UINotificationFeedbackGenerator()

        impact.prepare()
        notification.prepare()

        impact.impactOccurred(intensity: 1.0)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) {
            impact.impactOccurred(intensity: 0.75)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) {
            notification.notificationOccurred(.success)
        }
    }
}
