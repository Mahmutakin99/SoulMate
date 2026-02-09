import SwiftUI

struct SoulMateWidgetView: View {
    let entry: SoulMateWidgetEntry

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.11, green: 0.12, blue: 0.19), Color(red: 0.23, green: 0.14, blue: 0.21)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label(entry.mood, systemImage: "heart.fill")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.9))

                    Spacer()

                    Text(entry.distance)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.8))
                }

                Text(entry.lastMessage)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
            }
            .padding(14)
        }
    }
}
