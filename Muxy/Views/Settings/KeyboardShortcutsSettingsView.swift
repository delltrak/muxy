import SwiftUI

struct KeyboardShortcutsSettingsView: View {
    private enum ListSection: String, CaseIterable, Identifiable {
        case app
        case custom

        var id: String { rawValue }

        var title: String {
            switch self {
            case .app: "App Shortcuts"
            case .custom: "Custom Commands"
            }
        }
    }

    @State private var section: ListSection = .app
    @State private var recordingAction: ShortcutAction?
    @State private var recordingCommandPrefix = false
    @State private var recordingCommandShortcutID: UUID?
    @State private var pendingCommandShortcutID: UUID?
    @State private var conflictWarning: (action: ShortcutAction, existing: ShortcutAction)?
    @State private var commandPrefixConflictWarning: String?
    @State private var commandConflictWarning: (id: UUID, message: String)?
    @State private var deleteAllCommandShortcutsSecondsRemaining = 0
    @State private var deleteAllCommandShortcutsTask: Task<Void, Never>?

    @Environment(\.settingsSearchQuery) private var searchText

    private var store: KeyBindingStore { KeyBindingStore.shared }
    private var commandStore: CommandShortcutStore { CommandShortcutStore.shared }

    var body: some View {
        VStack(spacing: 0) {
            sectionPicker
            Divider()
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
        .onChange(of: section) { _, _ in
            discardPendingCommandShortcut()
            recordingAction = nil
            recordingCommandPrefix = false
            recordingCommandShortcutID = nil
            conflictWarning = nil
            commandPrefixConflictWarning = nil
            commandConflictWarning = nil
            cancelDeleteAllCommandShortcutsConfirmation()
        }
    }

    private var sectionPicker: some View {
        HStack(spacing: 8) {
            Picker("", selection: $section) {
                ForEach(ListSection.allCases) { section in
                    Text(section.title).tag(section)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)

            Spacer()

            switch section {
            case .app:
                Button("Reset All") {
                    store.resetToDefaults()
                    recordingAction = nil
                    conflictWarning = nil
                }
            case .custom:
                Button {
                    discardPendingCommandShortcut()
                    let shortcut = commandStore.addShortcut()
                    pendingCommandShortcutID = shortcut.id
                    recordingCommandPrefix = false
                    recordingCommandShortcutID = shortcut.id
                } label: {
                    Label("Add", systemImage: "plus")
                }
                .help("Add Command Shortcut")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var content: some View {
        switch section {
        case .app: appShortcutsList
        case .custom: customShortcutsList
        }
    }

    private var appShortcutsList: some View {
        let visibleCategories = ShortcutAction.categories.filter { !filteredActions(for: $0).isEmpty }
        return Form {
            ForEach(visibleCategories, id: \.self) { category in
                Section(category) {
                    ForEach(filteredActions(for: category)) { action in
                        ShortcutRow(
                            action: action,
                            combo: store.combo(for: action),
                            isRecording: recordingAction == action,
                            conflictAction: conflictWarning?.action == action ? conflictWarning?.existing : nil,
                            onStartRecording: {
                                discardPendingCommandShortcut()
                                recordingAction = action
                                recordingCommandPrefix = false
                                recordingCommandShortcutID = nil
                                conflictWarning = nil
                            },
                            onRecord: { combo in handleRecord(action: action, combo: combo) },
                            onCancel: { recordingAction = nil
                                conflictWarning = nil
                            },
                            onReset: { store.resetBinding(action: action)
                                conflictWarning = nil
                            }
                        )
                    }
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }

    private var customShortcutsList: some View {
        Form {
            Section {
                CommandPrefixRow(
                    combo: commandStore.prefixCombo,
                    isRecording: recordingCommandPrefix,
                    conflictMessage: commandPrefixConflictWarning,
                    onStartRecording: {
                        discardPendingCommandShortcut()
                        recordingAction = nil
                        recordingCommandPrefix = true
                        recordingCommandShortcutID = nil
                        commandPrefixConflictWarning = nil
                        commandConflictWarning = nil
                    },
                    onRecord: handleRecord(prefixCombo:),
                    onCancel: {
                        recordingCommandPrefix = false
                        commandPrefixConflictWarning = nil
                    },
                    onReset: {
                        commandStore.resetPrefixCombo()
                        recordingCommandPrefix = false
                        commandPrefixConflictWarning = nil
                    }
                )
            } header: {
                Text("Custom Commands")
            } footer: {
                Text("Press the command layer shortcut, then a command key to open a new terminal tab.")
            }

            if !filteredCommandShortcuts.isEmpty {
                Section("Shortcuts") {
                    ForEach(filteredCommandShortcuts) { shortcut in
                        CommandShortcutRow(
                            shortcut: binding(for: shortcut),
                            prefixCombo: commandStore.prefixCombo,
                            isRecording: recordingCommandShortcutID == shortcut.id,
                            conflictMessage: commandConflictWarning?.id == shortcut.id ? commandConflictWarning?.message : nil,
                            onStartRecording: {
                                if pendingCommandShortcutID != shortcut.id {
                                    discardPendingCommandShortcut()
                                }
                                recordingAction = nil
                                recordingCommandPrefix = false
                                recordingCommandShortcutID = shortcut.id
                                commandConflictWarning = nil
                            },
                            onRecord: { combo in handleRecord(shortcutID: shortcut.id, combo: combo) },
                            onCancel: {
                                cancelCommandShortcutRecording(shortcutID: shortcut.id)
                            },
                            onDelete: {
                                commandStore.deleteShortcut(id: shortcut.id)
                                if recordingCommandShortcutID == shortcut.id {
                                    recordingCommandShortcutID = nil
                                }
                                if pendingCommandShortcutID == shortcut.id {
                                    pendingCommandShortcutID = nil
                                }
                                if commandConflictWarning?.id == shortcut.id {
                                    commandConflictWarning = nil
                                }
                            }
                        )
                    }
                }
            }

            if !commandStore.shortcuts.isEmpty {
                Section {
                    DeleteAllCommandShortcutsRow(
                        secondsRemaining: deleteAllCommandShortcutsSecondsRemaining,
                        action: handleDeleteAllCommandShortcuts
                    )
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .onDisappear {
            discardPendingCommandShortcut()
            cancelDeleteAllCommandShortcutsConfirmation()
        }
    }

    private func filteredActions(for category: String) -> [ShortcutAction] {
        let actions = ShortcutAction.allCases.filter { $0.category == category }
        let trimmed = searchText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return actions }
        return actions.filter { $0.displayName.localizedCaseInsensitiveContains(trimmed) }
    }

    private var filteredCommandShortcuts: [CommandShortcut] {
        let trimmed = searchText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return commandStore.shortcuts }
        return commandStore.shortcuts.filter {
            $0.displayName.localizedCaseInsensitiveContains(trimmed)
                || $0.command.localizedCaseInsensitiveContains(trimmed)
        }
    }

    private func handleRecord(action: ShortcutAction, combo: KeyCombo) {
        if let existing = store.conflictingAction(for: combo, excluding: action) {
            conflictWarning = (action: action, existing: existing)
            return
        }
        store.updateBinding(action: action, combo: combo)
        recordingAction = nil
        conflictWarning = nil
    }

    private func handleRecord(prefixCombo combo: KeyCombo) {
        commandStore.updatePrefixCombo(combo)
        recordingCommandPrefix = false
        commandPrefixConflictWarning = nil
    }

    private func handleRecord(shortcutID: UUID, combo: KeyCombo) {
        if let existing = commandStore.conflictingShortcut(for: combo, excluding: shortcutID) {
            commandConflictWarning = (id: shortcutID, message: "Conflicts with \"\(existing.displayName)\"")
            return
        }
        guard var shortcut = commandStore.shortcuts.first(where: { $0.id == shortcutID }) else { return }
        shortcut.combo = combo
        commandStore.updateShortcut(shortcut)
        if pendingCommandShortcutID == shortcutID {
            pendingCommandShortcutID = nil
        }
        recordingCommandShortcutID = nil
        commandConflictWarning = nil
    }

    private func cancelCommandShortcutRecording(shortcutID: UUID) {
        if pendingCommandShortcutID == shortcutID {
            commandStore.deleteShortcut(id: shortcutID)
            pendingCommandShortcutID = nil
        }
        recordingCommandShortcutID = nil
        commandConflictWarning = nil
    }

    private func discardPendingCommandShortcut() {
        guard let shortcutID = pendingCommandShortcutID else { return }
        commandStore.deleteShortcut(id: shortcutID)
        pendingCommandShortcutID = nil
        if recordingCommandShortcutID == shortcutID {
            recordingCommandShortcutID = nil
        }
        if commandConflictWarning?.id == shortcutID {
            commandConflictWarning = nil
        }
    }

    private func binding(for shortcut: CommandShortcut) -> Binding<CommandShortcut> {
        Binding {
            commandStore.shortcuts.first { $0.id == shortcut.id } ?? shortcut
        } set: { updated in
            commandStore.updateShortcut(updated)
        }
    }

    private func handleDeleteAllCommandShortcuts() {
        guard deleteAllCommandShortcutsSecondsRemaining == 0 else {
            commandStore.deleteAllShortcuts()
            pendingCommandShortcutID = nil
            recordingCommandShortcutID = nil
            commandConflictWarning = nil
            cancelDeleteAllCommandShortcutsConfirmation()
            return
        }

        startDeleteAllCommandShortcutsConfirmation()
    }

    private func startDeleteAllCommandShortcutsConfirmation() {
        deleteAllCommandShortcutsTask?.cancel()
        deleteAllCommandShortcutsTask = Task { @MainActor in
            for seconds in stride(from: 5, through: 1, by: -1) {
                deleteAllCommandShortcutsSecondsRemaining = seconds
                do {
                    try await Task.sleep(for: .seconds(1))
                } catch {
                    return
                }
            }
            deleteAllCommandShortcutsSecondsRemaining = 0
            deleteAllCommandShortcutsTask = nil
        }
    }

    private func cancelDeleteAllCommandShortcutsConfirmation() {
        deleteAllCommandShortcutsTask?.cancel()
        deleteAllCommandShortcutsTask = nil
        deleteAllCommandShortcutsSecondsRemaining = 0
    }
}

private struct ShortcutRow: View {
    let action: ShortcutAction
    let combo: KeyCombo
    let isRecording: Bool
    let conflictAction: ShortcutAction?
    let onStartRecording: () -> Void
    let onRecord: (KeyCombo) -> Void
    let onCancel: () -> Void
    let onReset: () -> Void
    @State private var hovered = false

    var body: some View {
        LabeledContent {
            if isRecording {
                ShortcutRecordingControl(
                    onRecord: onRecord,
                    onCancel: onCancel
                )
            } else {
                HStack(spacing: 6) {
                    if hovered {
                        Button(action: onReset) {
                            Image(systemName: "arrow.counterclockwise")
                        }
                        .controlSize(.small)
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Reset Shortcut")
                    }
                    Button(action: onStartRecording) {
                        Text(combo.displayString)
                            .font(.system(.callout, design: .rounded).weight(.medium))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 5))
                    }
                    .buttonStyle(.plain)
                }
            }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(action.displayName)
                if let conflictAction {
                    Text("Conflicts with \"\(conflictAction.displayName)\" — press a different shortcut or Esc to cancel")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
        .onHover { hovered = $0 }
    }
}

private struct CommandPrefixRow: View {
    let combo: KeyCombo
    let isRecording: Bool
    let conflictMessage: String?
    let onStartRecording: () -> Void
    let onRecord: (KeyCombo) -> Void
    let onCancel: () -> Void
    let onReset: () -> Void
    @State private var hovered = false

    var body: some View {
        LabeledContent {
            if isRecording {
                ShortcutRecordingControl(onRecord: onRecord, onCancel: onCancel)
            } else {
                HStack(spacing: 6) {
                    if hovered {
                        Button(action: onReset) {
                            Image(systemName: "arrow.counterclockwise")
                        }
                        .controlSize(.small)
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Reset Shortcut")
                    }
                    Button(action: onStartRecording) {
                        Text(combo.displayString)
                            .font(.system(.callout, design: .rounded).weight(.medium))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 5))
                    }
                    .buttonStyle(.plain)
                }
            }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text("Command Layer")
                if let conflictMessage {
                    Text("\(conflictMessage) — press a different shortcut or Esc to cancel")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
        .onHover { hovered = $0 }
    }
}

private struct CommandShortcutRow: View {
    @Binding var shortcut: CommandShortcut
    let prefixCombo: KeyCombo
    let isRecording: Bool
    let conflictMessage: String?
    let onStartRecording: () -> Void
    let onRecord: (KeyCombo) -> Void
    let onCancel: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                TextField("Name", text: $shortcut.name)
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 120)

                TextField("Command", text: $shortcut.command)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity)

                if isRecording {
                    ShortcutRecordingControl(
                        onRecord: onRecord,
                        onCancel: onCancel,
                        requiresModifier: false,
                        prompt: "Press key…"
                    )
                } else {
                    Button(action: onStartRecording) {
                        Text("\(prefixCombo.displayString) \(shortcut.combo.displayString)")
                            .font(.system(.callout, design: .rounded).weight(.medium))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 5))
                    }
                    .buttonStyle(.plain)
                }

                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                }
                .controlSize(.regular)
                .buttonStyle(.borderless)
                .contentShape(Rectangle())
                .accessibilityLabel("Delete Command Shortcut")
            }

            if let conflictMessage {
                Text("\(conflictMessage) — press a different shortcut or Esc to cancel")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }
}

private struct ShortcutRecordingControl: View {
    let onRecord: (KeyCombo) -> Void
    let onCancel: () -> Void
    var requiresModifier: Bool = true
    var prompt: String = "Press shortcut…"

    var body: some View {
        ZStack {
            ShortcutRecorderView(
                onRecord: onRecord,
                onCancel: onCancel,
                requiresModifier: requiresModifier
            )
            .frame(width: 0, height: 0)
            .opacity(0)

            Text(prompt)
                .font(.system(.callout, design: .rounded).weight(.medium))
                .foregroundStyle(.orange)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: 5))
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .strokeBorder(.orange.opacity(0.6), lineWidth: 1)
                )
        }
    }
}

private struct DeleteAllCommandShortcutsRow: View {
    let secondsRemaining: Int
    let action: () -> Void

    private var isConfirming: Bool {
        secondsRemaining > 0
    }

    var body: some View {
        HStack {
            Spacer()
            Button(role: .destructive, action: action) {
                Text(title)
            }
            .controlSize(.regular)
            .accessibilityLabel(title)
        }
    }

    private var title: String {
        if isConfirming {
            return "Confirm Delete All (\(secondsRemaining))"
        }
        return "Delete All"
    }
}
