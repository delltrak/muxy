import SwiftUI

struct AIUsageSettingsView: View {
    private let usageService = AIUsageService.shared
    @AppStorage(AIUsageSettingsStore.usageEnabledKey) private var usageEnabled = false
    @AppStorage(AIUsageSettingsStore.showSecondaryLimitsKey) private var showSecondaryLimits = AIUsageSettingsStore
        .defaultShowSecondaryLimits
    @State private var usageDisplayMode = AIUsageSettingsStore.usageDisplayMode()
    @State private var autoRefreshInterval = AIUsageSettingsStore.autoRefreshInterval()

    @Environment(\.settingsSearchQuery) private var searchQuery

    private var providers: [AIUsageProviderCatalogEntry] {
        AIUsageProviderCatalog.providers
    }

    var body: some View {
        Form {
            usageEnabledSection
            if usageEnabled {
                displaySection
                providersSection
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .onChange(of: usageEnabled) { _, enabled in
            AIUsageSettingsStore.setUsageEnabled(enabled)
            if enabled {
                refreshUsage()
            }
        }
        .onChange(of: usageDisplayMode) { _, newValue in
            AIUsageSettingsStore.setUsageDisplayMode(newValue)
        }
        .onChange(of: autoRefreshInterval) { _, newValue in
            AIUsageSettingsStore.setAutoRefreshInterval(newValue)
        }
        .onChange(of: showSecondaryLimits) { _, _ in
            usageService.recomposeSnapshots()
        }
    }

    @ViewBuilder
    private var usageEnabledSection: some View {
        if isSectionVisible(["Enable AI Usage"], extra: ["sidebar", "usage"]) {
            Section {
                SettingsSearchableRow("Enable AI Usage", keywords: ["sidebar", "board"]) {
                    Toggle("", isOn: $usageEnabled).labelsHidden()
                }
            } header: {
                Text("AI Usage")
            } footer: {
                if !usageEnabled {
                    Text("Enable AI Usage to show the usage board in the sidebar.")
                }
            }
        }
    }

    @ViewBuilder
    private var displaySection: some View {
        let labels = ["Show", "Auto Refresh", "Show Secondary Limits"]
        if isSectionVisible(labels) {
            Section {
                SettingsSearchableRow("Show", keywords: ["display", "mode"]) {
                    Picker("", selection: $usageDisplayMode) {
                        ForEach(AIUsageDisplayMode.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .fixedSize()
                }

                SettingsSearchableRow("Auto Refresh", keywords: ["interval", "refresh"]) {
                    Picker("", selection: $autoRefreshInterval) {
                        ForEach(AIUsageAutoRefreshInterval.allCases) { interval in
                            Text(interval.label).tag(interval)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(minWidth: 110)
                }

                SettingsSearchableRow(
                    "Show Secondary Limits",
                    keywords: ["weekly", "monthly", "quota"]
                ) {
                    Toggle("", isOn: $showSecondaryLimits).labelsHidden()
                }
            } header: {
                Text("Display")
            } footer: {
                Text("Display weekly and monthly quotas alongside the primary session usage.")
            }
        }
    }

    @ViewBuilder
    private var providersSection: some View {
        let trimmed = searchQuery.trimmingCharacters(in: .whitespaces)
        let visible = trimmed.isEmpty
            ? providers
            : providers.filter { $0.displayName.localizedCaseInsensitiveContains(trimmed) }
        let headerMatches = trimmed.isEmpty || "Providers".localizedCaseInsensitiveContains(trimmed)

        if !visible.isEmpty || headerMatches {
            Section {
                if visible.isEmpty {
                    Text("No providers match your search.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(visible) { provider in
                        providerRow(provider)
                    }
                }
                HStack {
                    Spacer()
                    Button {
                        refreshUsage()
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .controlSize(.regular)
                    .disabled(usageService.isRefreshing)
                }
            } header: {
                Text("Providers")
            } footer: {
                Text("Choose which providers appear on the usage board.")
            }
        }
    }

    private func providerRow(_ provider: AIUsageProviderCatalogEntry) -> some View {
        LabeledContent {
            Toggle("", isOn: providerToggleBinding(for: provider))
                .labelsHidden()
        } label: {
            HStack(spacing: 8) {
                ProviderIconView(iconName: provider.iconName, size: 16, style: .monochrome(.primary))
                VStack(alignment: .leading, spacing: 2) {
                    Text(provider.displayName)
                    if provider.hasNotificationIntegration {
                        Text("Integrated")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func providerToggleBinding(for provider: AIUsageProviderCatalogEntry) -> Binding<Bool> {
        Binding(
            get: {
                AIUsageProviderTrackingStore.isTracked(providerID: provider.id)
            },
            set: { isOn in
                AIUsageProviderTrackingStore.setTracked(isOn, providerID: provider.id)
                usageService.recomposeSnapshots()
            }
        )
    }

    private func refreshUsage() {
        Task {
            await usageService.refresh(force: true)
        }
    }

    private func isSectionVisible(_ labels: [String], extra: [String] = []) -> Bool {
        let trimmed = searchQuery.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return true }
        let haystack = labels + extra
        return haystack.contains { $0.localizedCaseInsensitiveContains(trimmed) }
    }
}
