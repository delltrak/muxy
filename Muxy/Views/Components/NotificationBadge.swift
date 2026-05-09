import SwiftUI

struct NotificationBadge: View {
    let count: Int

    var body: some View {
        if count >= 1 {
            Text(count > 99 ? "99+" : "\(count)")
                .font(.caption2.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.red, in: Capsule())
                .accessibilityLabel("\(count) unread notification\(count == 1 ? "" : "s")")
        }
    }
}
