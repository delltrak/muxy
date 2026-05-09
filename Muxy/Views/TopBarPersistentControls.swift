import SwiftUI

struct TopBarPersistentControls: View {
    @State private var showThemePicker = false
    @State private var showNotifications = false

    private var notificationStore: NotificationStore { NotificationStore.shared }

    private var notificationBellIcon: String {
        notificationStore.unreadCount > 0 ? "bell.badge" : "bell"
    }

    var body: some View {
        HStack(spacing: UIMetrics.spacing1) {
            IconButton(
                symbol: notificationBellIcon,
                size: 12,
                accessibilityLabel: "Notifications"
            ) {
                showNotifications.toggle()
            }
            .help("Notifications")
            .popover(isPresented: $showNotifications) {
                NotificationPanel(onDismiss: { showNotifications = false })
            }

            IconButton(
                symbol: "paintpalette",
                size: 12,
                accessibilityLabel: "Theme Picker"
            ) {
                showThemePicker.toggle()
            }
            .help("Theme Picker (\(KeyBindingStore.shared.combo(for: .toggleThemePicker).displayString))")
            .popover(isPresented: $showThemePicker) {
                ThemePicker(mode: .sidebar)
            }
        }
        .padding(.horizontal, UIMetrics.spacing2)
        .onReceive(NotificationCenter.default.publisher(for: .toggleThemePicker)) { _ in
            showThemePicker.toggle()
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleNotificationPanel)) { _ in
            showNotifications.toggle()
        }
    }
}
