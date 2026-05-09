import SwiftUI

struct AppearanceSettingsView: View {
    @State private var themeService = ThemeService.shared
    @State private var uiScale = UIScale.shared
    @State private var showLightThemePicker = false
    @State private var showDarkThemePicker = false
    @State private var currentLightTheme: String?
    @State private var currentDarkTheme: String?
    @AppStorage("muxy.vcsDisplayMode") private var vcsDisplayMode = VCSDisplayMode.attached.rawValue
    @AppStorage(SidebarCollapsedStyle.storageKey) private var sidebarCollapsedStyle = SidebarCollapsedStyle.defaultValue.rawValue
    @AppStorage(SidebarExpandedStyle.storageKey) private var sidebarExpandedStyle = SidebarExpandedStyle.defaultValue.rawValue

    @Environment(\.settingsSearchQuery) private var searchQuery

    var body: some View {
        Form {
            interfaceSection
            terminalSection
            sidebarSection
            sourceControlSection
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .task { refreshThemeNames() }
        .onReceive(NotificationCenter.default.publisher(for: .themeDidChange)) { _ in
            refreshThemeNames()
        }
    }

    @ViewBuilder
    private var interfaceSection: some View {
        if isSectionVisible(["Size"], extra: ["scale", "ui"]) {
            Section("Interface") {
                SettingsSearchableRow("Size", keywords: ["scale"]) {
                    Picker("", selection: $uiScale.preset) {
                        ForEach(UIScale.Preset.allCases) { preset in
                            Text(preset.title).tag(preset)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .fixedSize()
                }
            }
        }
    }

    @ViewBuilder
    private var terminalSection: some View {
        if isSectionVisible(["Light Theme", "Dark Theme"]) {
            Section("Terminal") {
                SettingsSearchableRow("Light Theme") {
                    themeButton(
                        title: currentLightTheme ?? "Default",
                        isPresented: $showLightThemePicker,
                        mode: .light
                    )
                }
                SettingsSearchableRow("Dark Theme") {
                    themeButton(
                        title: currentDarkTheme ?? "Default",
                        isPresented: $showDarkThemePicker,
                        mode: .dark
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var sidebarSection: some View {
        if isSectionVisible(["Collapsed Style", "Expanded Style"]) {
            Section("Sidebar") {
                SettingsSearchableRow("Collapsed Style") {
                    Picker("", selection: $sidebarCollapsedStyle) {
                        ForEach(SidebarCollapsedStyle.allCases) { style in
                            Text(style.title).tag(style.rawValue)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .fixedSize()
                }
                SettingsSearchableRow("Expanded Style") {
                    Picker("", selection: $sidebarExpandedStyle) {
                        ForEach(SidebarExpandedStyle.allCases) { style in
                            Text(style.title).tag(style.rawValue)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .fixedSize()
                }
            }
        }
    }

    @ViewBuilder
    private var sourceControlSection: some View {
        if isSectionVisible(["Display Mode"], extra: ["vcs", "git"]) {
            Section("Source Control") {
                SettingsSearchableRow("Display Mode", keywords: ["vcs", "git"]) {
                    Picker("", selection: $vcsDisplayMode) {
                        ForEach(VCSDisplayMode.allCases) { mode in
                            Text(mode.title).tag(mode.rawValue)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .fixedSize()
                }
            }
        }
    }

    private func themeButton(
        title: String,
        isPresented: Binding<Bool>,
        mode: ThemePickerMode
    ) -> some View {
        Button {
            isPresented.wrappedValue.toggle()
        } label: {
            HStack(spacing: 6) {
                Text(title).lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 10))
            }
        }
        .popover(isPresented: isPresented) {
            ThemePicker(mode: mode)
                .environment(themeService)
        }
    }

    private func refreshThemeNames() {
        currentLightTheme = themeService.currentLightThemeName()
        currentDarkTheme = themeService.currentDarkThemeName()
    }

    private func isSectionVisible(_ labels: [String], extra: [String] = []) -> Bool {
        let trimmed = searchQuery.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return true }
        let haystack = labels + extra
        return haystack.contains { $0.localizedCaseInsensitiveContains(trimmed) }
    }
}
