import AppKit
import SwiftUI

struct NotificationSettingsView: View {
    @AppStorage("muxy.notifications.sound") private var sound = NotificationSound.funk.rawValue
    @AppStorage("muxy.notifications.toastEnabled") private var toastEnabled = true
    @AppStorage("muxy.notifications.toastPosition") private var toastPosition = ToastPosition.topCenter.rawValue

    @Environment(\.settingsSearchQuery) private var searchQuery

    var body: some View {
        Form {
            deliverySection
            soundSection
            toastSection
            providersSection
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }

    @ViewBuilder
    private var deliverySection: some View {
        if isSectionVisible(["Toast"]) {
            Section("Delivery") {
                SettingsSearchableRow("Toast") {
                    Toggle("", isOn: $toastEnabled).labelsHidden()
                }
            }
        }
    }

    @ViewBuilder
    private var soundSection: some View {
        if isSectionVisible(["Sound"]) {
            Section("Sound") {
                SettingsSearchableRow("Sound") {
                    Picker("", selection: $sound) {
                        ForEach(NotificationSound.allCases) { option in
                            Text(option.rawValue).tag(option.rawValue)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(minWidth: 160)
                    .onChange(of: sound) { _, newValue in
                        previewSound(newValue)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var toastSection: some View {
        if isSectionVisible(["Position"], extra: ["toast"]) {
            Section("Toast") {
                SettingsSearchableRow("Position", keywords: ["toast"]) {
                    Picker("", selection: $toastPosition) {
                        ForEach(ToastPosition.allCases) { option in
                            Text(option.rawValue).tag(option.rawValue)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(minWidth: 160)
                }
            }
        }
    }

    @ViewBuilder
    private var providersSection: some View {
        let providers = AIProviderRegistry.shared.providers
        let trimmed = searchQuery.trimmingCharacters(in: .whitespaces)
        let visible = trimmed.isEmpty
            ? providers
            : providers.filter { $0.displayName.localizedCaseInsensitiveContains(trimmed) }
        let headerMatches = trimmed.isEmpty || "AI Providers".localizedCaseInsensitiveContains(trimmed)

        if !visible.isEmpty || headerMatches {
            Section("AI Providers") {
                if visible.isEmpty {
                    Text("No providers match your search.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(visible, id: \.id) { provider in
                        ProviderToggleRow(provider: provider)
                    }
                }
            }
        }
    }

    private func previewSound(_ value: String) {
        guard let sound = NotificationSound(rawValue: value), sound != .none else { return }
        NSSound(named: .init(sound.rawValue))?.play()
    }

    private func isSectionVisible(_ labels: [String], extra: [String] = []) -> Bool {
        let trimmed = searchQuery.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return true }
        let haystack = labels + extra
        return haystack.contains { $0.localizedCaseInsensitiveContains(trimmed) }
    }
}

private struct ProviderToggleRow: View {
    let provider: AIProviderIntegration
    @State private var enabled: Bool
    @State private var refreshed = false

    init(provider: AIProviderIntegration) {
        self.provider = provider
        _enabled = State(initialValue: provider.isEnabled)
    }

    var body: some View {
        LabeledContent {
            HStack(spacing: 8) {
                if enabled {
                    Button {
                        AIProviderRegistry.shared.forceInstall(provider)
                        withAnimation { refreshed = true }
                        Task {
                            try? await Task.sleep(for: .seconds(2))
                            withAnimation { refreshed = false }
                        }
                    } label: {
                        if refreshed {
                            Label("Done", systemImage: "checkmark")
                        } else {
                            Text("Refresh")
                        }
                    }
                    .controlSize(.small)
                    .disabled(refreshed)
                }
                Toggle("", isOn: $enabled)
                    .labelsHidden()
                    .onChange(of: enabled) { _, newValue in
                        provider.isEnabled = newValue
                        AIProviderRegistry.shared.installAll()
                    }
            }
        } label: {
            Label {
                Text(provider.displayName)
            } icon: {
                Image(systemName: provider.iconName)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
