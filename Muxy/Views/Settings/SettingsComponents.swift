import AppKit
import SwiftUI

extension EnvironmentValues {
    @Entry var settingsSearchQuery: String = ""
}

struct SettingsSearchableRow<Content: View>: View {
    let label: String
    let keywords: [String]
    @ViewBuilder var content: Content
    @Environment(\.settingsSearchQuery) private var query

    init(_ label: String, keywords: [String] = [], @ViewBuilder content: () -> Content) {
        self.label = label
        self.keywords = keywords
        self.content = content()
    }

    var body: some View {
        if matches {
            LabeledContent(label) { content }
        }
    }

    private var matches: Bool {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return true }
        if label.localizedCaseInsensitiveContains(trimmed) { return true }
        return keywords.contains { $0.localizedCaseInsensitiveContains(trimmed) }
    }
}

struct SettingsSearchableSection<Header: View, Content: View, Footer: View>: View {
    let keywords: [String]
    @ViewBuilder var header: Header
    @ViewBuilder var content: Content
    @ViewBuilder var footer: Footer
    @Environment(\.settingsSearchQuery) private var query

    init(
        keywords: [String] = [],
        @ViewBuilder content: () -> Content,
        @ViewBuilder header: () -> Header,
        @ViewBuilder footer: () -> Footer
    ) {
        self.keywords = keywords
        self.content = content()
        self.header = header()
        self.footer = footer()
    }

    var body: some View {
        Section {
            content
        } header: {
            header
        } footer: {
            footer
        }
    }
}

extension View {
    func resetsSettingsFocusOnOutsideClick() -> some View {
        background(SettingsFocusResetView())
    }

    func settingsSearchQuery(_ query: String) -> some View {
        environment(\.settingsSearchQuery, query)
    }
}

private struct SettingsFocusResetView: NSViewRepresentable {
    func makeNSView(context: Context) -> SettingsFocusResetNSView {
        SettingsFocusResetNSView()
    }

    func updateNSView(_ nsView: SettingsFocusResetNSView, context: Context) {}
}

private final class SettingsFocusResetNSView: NSView {
    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(nil)
        super.mouseDown(with: event)
    }
}
