import SwiftUI

struct EditorSettingsView: View {
    @State private var settings = EditorSettings.shared
    @State private var monoFonts: [String] = []
    @State private var markdownFonts: [String] = []
    @State private var allowMarkdownRemoteImages = MarkdownPreviewPreferences.allowRemoteImages

    @Environment(\.settingsSearchQuery) private var searchQuery

    private var showsAppearanceSection: Bool { settings.defaultEditor == .builtIn }

    var body: some View {
        Form {
            editorSection
            markdownSection
            richInputSection
            if showsAppearanceSection {
                appearanceSection
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .task {
            monoFonts = EditorSettings.availableMonospacedFonts
            markdownFonts = EditorSettings.availableMarkdownPreviewFonts
        }
    }

    @ViewBuilder
    private var editorSection: some View {
        let labels: [String] = settings.defaultEditor == .terminalCommand
            ? ["Default Editor", "Editor Command"]
            : ["Default Editor"]
        if isSectionVisible(labels) {
            Section("Editor") {
                SettingsSearchableRow("Default Editor") {
                    Picker("", selection: $settings.defaultEditor) {
                        ForEach(EditorSettings.DefaultEditor.allCases) { editor in
                            Text(editor.displayName).tag(editor)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }

                if settings.defaultEditor == .terminalCommand {
                    SettingsSearchableRow("Editor Command") {
                        TextField("vim", text: $settings.externalEditorCommand)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                            .frame(minWidth: 180)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var markdownSection: some View {
        if isSectionVisible(["Allow Remote Images", "Font Family", "Zoom"], extra: ["markdown"]) {
            Section {
                SettingsSearchableRow("Allow Remote Images", keywords: ["markdown", "https"]) {
                    Toggle("", isOn: $allowMarkdownRemoteImages)
                        .labelsHidden()
                        .onChange(of: allowMarkdownRemoteImages) { _, newValue in
                            MarkdownPreviewPreferences.allowRemoteImages = newValue
                        }
                }

                SettingsSearchableRow("Font Family", keywords: ["markdown", "font"]) {
                    Picker("", selection: $settings.markdownPreviewFontFamily) {
                        ForEach(markdownFonts, id: \.self) { family in
                            if family == EditorSettings.systemFontFamilyToken {
                                Text(family).tag(family)
                            } else {
                                Text(family)
                                    .font(.custom(family, size: 12))
                                    .tag(family)
                            }
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }

                SettingsSearchableRow("Zoom", keywords: ["markdown", "scale"]) {
                    Stepper(
                        value: $settings.markdownPreviewFontScale,
                        in: EditorSettings.minMarkdownPreviewFontScale ... EditorSettings.maxMarkdownPreviewFontScale,
                        step: EditorSettings.markdownPreviewZoomStep
                    ) {
                        Text("\(Int((settings.markdownPreviewFontScale * 100).rounded()))%")
                            .font(.system(.body, design: .monospaced))
                            .frame(minWidth: 48, alignment: .trailing)
                    }
                }
            } header: {
                Text("Markdown Preview")
            } footer: {
                Text("Remote images are fetched over HTTPS only. Plain HTTP and other schemes are blocked.")
            }
        }
    }

    @ViewBuilder
    private var richInputSection: some View {
        if isSectionVisible(["Image Submission"], extra: ["paste", "image"]) {
            Section {
                SettingsSearchableRow("Image Submission", keywords: ["paste", "image"]) {
                    Picker("", selection: $settings.richInputImageStrategy) {
                        ForEach(RichInputImageStrategy.allCases) { strategy in
                            Text(strategy.displayName).tag(strategy)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }
            } header: {
                Text("Rich Input")
            } footer: {
                Text(
                    "Inline File Path keeps multiple images perfectly ordered with text and Enter. "
                        + "Use Clipboard Paste if your TUI doesn't recognize image paths."
                )
            }
        }
    }

    @ViewBuilder
    private var appearanceSection: some View {
        let labels = ["Highlight Current Line", "Show Line Numbers", "Wrap Lines", "Font Family", "Font Size"]
        if isSectionVisible(labels) {
            Section("Appearance") {
                SettingsSearchableRow("Highlight Current Line") {
                    Toggle("", isOn: $settings.highlightCurrentLine).labelsHidden()
                }
                SettingsSearchableRow("Show Line Numbers") {
                    Toggle("", isOn: $settings.showLineNumbers).labelsHidden()
                }
                SettingsSearchableRow("Wrap Lines") {
                    Toggle("", isOn: $settings.lineWrapping).labelsHidden()
                }
                SettingsSearchableRow("Font Family") {
                    Picker("", selection: $settings.fontFamily) {
                        ForEach(monoFonts, id: \.self) { family in
                            Text(family)
                                .font(.custom(family, size: 12))
                                .tag(family)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }
                SettingsSearchableRow("Font Size") {
                    Stepper(value: $settings.fontSize, in: 8 ... 36, step: 1) {
                        Text("\(Int(settings.fontSize)) pt")
                            .font(.system(.body, design: .monospaced))
                            .frame(minWidth: 48, alignment: .trailing)
                    }
                }
            }
        }
    }

    private func isSectionVisible(_ labels: [String], extra: [String] = []) -> Bool {
        let trimmed = searchQuery.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return true }
        let haystack = labels + extra
        return haystack.contains { $0.localizedCaseInsensitiveContains(trimmed) }
    }
}
