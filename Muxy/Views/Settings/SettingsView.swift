import SwiftUI

enum SettingsTab: String, CaseIterable, Identifiable, Hashable {
    case general
    case appearance
    case editor
    case shortcuts
    case notifications
    case mobile
    case aiUsage

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General"
        case .appearance: "Appearance"
        case .editor: "Editor"
        case .shortcuts: "Shortcuts"
        case .notifications: "Notifications"
        case .mobile: "Mobile"
        case .aiUsage: "AI Usage"
        }
    }

    var systemImage: String {
        switch self {
        case .general: "gearshape"
        case .appearance: "paintbrush"
        case .editor: "pencil.line"
        case .shortcuts: "keyboard"
        case .notifications: "bell"
        case .mobile: "iphone"
        case .aiUsage: "chart.bar"
        }
    }

    var searchPlaceholder: String { "Search \(title)" }
}

struct SettingsView: View {
    @State private var tab: SettingsTab = .general
    @State private var searchText = ""
    @State private var showRestoreConfirmation = false

    var body: some View {
        TabView(selection: $tab) {
            ForEach(SettingsTab.allCases) { tab in
                tabContent(for: tab)
                    .tabItem { Label(tab.title, systemImage: tab.systemImage) }
                    .tag(tab)
            }
        }
        .frame(minWidth: 480, idealWidth: 600, minHeight: 400, idealHeight: 520)
        .toolbarRole(.editor)
        .searchable(text: $searchText, placement: .toolbar, prompt: tab.searchPlaceholder)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Restore Defaults…") {
                    showRestoreConfirmation = true
                }
            }
        }
        .confirmationDialog(
            "Restore \(tab.title) defaults?",
            isPresented: $showRestoreConfirmation,
            titleVisibility: .visible
        ) {
            Button("Restore Defaults", role: .destructive) {
                SettingsDefaultsRestorer.restore(tab: tab)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This resets the \(tab.title) settings to their original values. Other tabs are not affected.")
        }
        .onChange(of: tab) { _, _ in searchText = "" }
        .resetsSettingsFocusOnOutsideClick()
    }

    @ViewBuilder
    private func tabContent(for tab: SettingsTab) -> some View {
        switch tab {
        case .general:
            GeneralSettingsView().settingsSearchQuery(searchText)
        case .appearance:
            AppearanceSettingsView().settingsSearchQuery(searchText)
        case .editor:
            EditorSettingsView().settingsSearchQuery(searchText)
        case .shortcuts:
            KeyboardShortcutsSettingsView().settingsSearchQuery(searchText)
        case .notifications:
            NotificationSettingsView().settingsSearchQuery(searchText)
        case .mobile:
            MobileSettingsView().settingsSearchQuery(searchText)
        case .aiUsage:
            AIUsageSettingsView().settingsSearchQuery(searchText)
        }
    }
}
