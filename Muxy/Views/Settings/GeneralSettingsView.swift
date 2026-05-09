import AppKit
import SwiftUI

struct GeneralSettingsView: View {
    @AppStorage(GeneralSettingsKeys.autoExpandWorktreesOnProjectSwitch)
    private var autoExpandWorktrees = false
    @AppStorage(GeneralSettingsKeys.defaultWorktreeParentPath)
    private var defaultWorktreeParentPath = ""
    @AppStorage(TabCloseConfirmationPreferences.confirmRunningProcessKey)
    private var confirmRunningProcess = true
    @AppStorage(ProjectLifecyclePreferences.keepOpenWhenNoTabsKey)
    private var keepProjectsOpenWhenNoTabs = false
    @AppStorage(UpdateChannel.storageKey)
    private var updateChannelRaw = UpdateChannel.stable.rawValue
    @AppStorage(QuitConfirmationPreferences.confirmQuitKey)
    private var confirmQuit = true

    @Environment(\.settingsSearchQuery) private var searchQuery

    var body: some View {
        Form {
            updatesSection
            sidebarSection
            projectsSection
            worktreesSection
            tabsSection
            quitSection
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }

    @ViewBuilder
    private var updatesSection: some View {
        let keywords = ["beta", "stable", "release"]
        if isSectionVisible(["Update channel"], extra: keywords) {
            Section {
                SettingsSearchableRow("Update channel", keywords: keywords) {
                    Picker("", selection: channelBinding) {
                        ForEach(UpdateChannel.allCases) { channel in
                            Text(channel.displayName).tag(channel)
                        }
                    }
                    .labelsHidden()
                }
            } header: {
                Text("Updates")
            } footer: {
                Text(
                    "The Beta channel ships every change merged to main and may be unstable. "
                        + "Switch back to Stable to receive only tagged releases."
                )
            }
        }
    }

    @ViewBuilder
    private var sidebarSection: some View {
        if isSectionVisible(["Auto-expand worktrees on project switch"]) {
            Section {
                SettingsSearchableRow("Auto-expand worktrees on project switch") {
                    Toggle("", isOn: $autoExpandWorktrees).labelsHidden()
                }
            } header: {
                Text("Sidebar")
            } footer: {
                Text("Automatically reveal worktrees when you switch to a project.")
            }
        }
    }

    @ViewBuilder
    private var projectsSection: some View {
        if isSectionVisible(["Keep projects open after closing the last tab"]) {
            Section {
                SettingsSearchableRow("Keep projects open after closing the last tab") {
                    Toggle("", isOn: $keepProjectsOpenWhenNoTabs).labelsHidden()
                }
            } header: {
                Text("Projects")
            } footer: {
                Text(
                    "Keep projects in the sidebar after closing their last tab. "
                        + "To remove a project afterward, use the right-click menu."
                )
            }
        }
    }

    @ViewBuilder
    private var worktreesSection: some View {
        if isSectionVisible(["Default path for new worktrees"], extra: ["folder", "location"]) {
            Section {
                LabeledContent("Default path for new worktrees") {
                    HStack(spacing: 8) {
                        pathDisplay
                        Button("Choose Folder…") { chooseDefaultWorktreeParentPath() }
                        Button("Use App Default") { defaultWorktreeParentPath = "" }
                            .disabled(defaultWorktreeParentPath.isEmpty)
                    }
                }
            } header: {
                Text("Worktrees")
            } footer: {
                Text(
                    "Muxy creates a project-named subfolder inside this folder. "
                        + "Projects can still override this from the new worktree dialog."
                )
            }
        }
    }

    @ViewBuilder
    private var tabsSection: some View {
        if isSectionVisible(["Confirm before closing a tab with a running process"]) {
            Section("Tabs") {
                SettingsSearchableRow("Confirm before closing a tab with a running process") {
                    Toggle("", isOn: $confirmRunningProcess).labelsHidden()
                }
            }
        }
    }

    @ViewBuilder
    private var quitSection: some View {
        if isSectionVisible(["Confirm before quitting Muxy"]) {
            Section("Quit") {
                SettingsSearchableRow("Confirm before quitting Muxy") {
                    Toggle("", isOn: $confirmQuit).labelsHidden()
                }
            }
        }
    }

    private var channelBinding: Binding<UpdateChannel> {
        Binding(
            get: { UpdateChannel(rawValue: updateChannelRaw) ?? .stable },
            set: { newValue in
                updateChannelRaw = newValue.rawValue
                UpdateService.shared.channel = newValue
            }
        )
    }

    private var defaultWorktreeLocationText: String {
        defaultWorktreeParentPath.isEmpty ? "Muxy App Support" : defaultWorktreeParentPath
    }

    private var pathDisplay: some View {
        HStack(spacing: 6) {
            Image(systemName: defaultWorktreeParentPath.isEmpty ? "internaldrive" : "folder")
                .foregroundStyle(.secondary)

            Text(defaultWorktreeLocationText)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(defaultWorktreeParentPath.isEmpty ? .secondary : .primary)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 5))
    }

    private func isSectionVisible(_ labels: [String], extra: [String] = []) -> Bool {
        let trimmed = searchQuery.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return true }
        let haystack = labels + extra
        return haystack.contains { $0.localizedCaseInsensitiveContains(trimmed) }
    }

    private func chooseDefaultWorktreeParentPath() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "Select the default folder for new worktrees"
        if let path = WorktreeLocationResolver.normalizedPath(defaultWorktreeParentPath) {
            panel.directoryURL = URL(fileURLWithPath: path, isDirectory: true)
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        defaultWorktreeParentPath = url.path
    }
}
