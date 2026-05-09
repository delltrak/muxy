import SwiftUI

enum ThemePickerMode {
    case light
    case dark
    case currentAppearance

    static var sidebar: ThemePickerMode { .currentAppearance }
}

struct ThemePicker: View {
    var mode: ThemePickerMode = .currentAppearance
    @Environment(ThemeService.self) private var themeService
    @State private var themes: [ThemePreview] = []
    @State private var currentTheme: String?

    var body: some View {
        SearchableListPicker(
            items: themes,
            filterKey: \.name,
            placeholder: "Search themes",
            emptyLabel: "No themes found",
            onSelect: { selectTheme($0) },
            row: { theme, isHighlighted in
                ThemeRow(
                    theme: theme,
                    isActive: theme.name == currentTheme,
                    isHighlighted: isHighlighted
                )
            }
        )
        .frame(width: UIMetrics.scaled(360), height: UIMetrics.scaled(480))
        .task {
            themes = await themeService.loadThemes()
            currentTheme = currentName()
        }
    }

    private func currentName() -> String? {
        isDarkMode() ? themeService.currentDarkThemeName() : themeService.currentLightThemeName()
    }

    private func isDarkMode() -> Bool {
        switch mode {
        case .light: false
        case .dark: true
        case .currentAppearance: themeService.activeAppearance() == .dark
        }
    }

    private func selectTheme(_ theme: ThemePreview) {
        currentTheme = theme.name
        if isDarkMode() {
            themeService.applyDarkTheme(theme.name)
        } else {
            themeService.applyLightTheme(theme.name)
        }
    }
}

private struct ThemeRow: View {
    let theme: ThemePreview
    let isActive: Bool
    let isHighlighted: Bool
    @State private var hovered = false

    private var paletteAccents: [NSColor] {
        let count = theme.palette.count
        guard count > 0 else { return [] }
        let indices = [1, 2, 3, 4, 5].filter { $0 < count }
        return indices.map { theme.palette[$0] }
    }

    var body: some View {
        HStack(spacing: UIMetrics.spacing4) {
            ZStack {
                RoundedRectangle(cornerRadius: UIMetrics.scaled(6), style: .continuous)
                    .fill(Color(nsColor: theme.background))
                Text("Aa")
                    .font(.system(size: UIMetrics.fontFootnote, weight: .medium, design: .default))
                    .foregroundStyle(Color(nsColor: theme.foreground))
            }
            .frame(width: UIMetrics.scaled(36), height: UIMetrics.scaled(28))
            .overlay(
                RoundedRectangle(cornerRadius: UIMetrics.scaled(6), style: .continuous)
                    .strokeBorder(MuxyTheme.border.opacity(0.5), lineWidth: 0.5)
            )

            Text(theme.name)
                .font(.system(size: UIMetrics.fontBody, weight: isActive ? .semibold : .regular))
                .foregroundStyle(MuxyTheme.fg)
                .lineLimit(1)

            Spacer(minLength: UIMetrics.spacing3)

            HStack(spacing: UIMetrics.scaled(3)) {
                ForEach(Array(paletteAccents.enumerated()), id: \.offset) { _, color in
                    Circle()
                        .fill(Color(nsColor: color))
                        .frame(width: UIMetrics.scaled(8), height: UIMetrics.scaled(8))
                }
            }

            Image(systemName: "checkmark")
                .font(.system(size: UIMetrics.fontFootnote, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: UIMetrics.scaled(14))
                .opacity(isActive ? 1 : 0)
        }
        .padding(.horizontal, UIMetrics.spacing5)
        .padding(.vertical, UIMetrics.scaled(7))
        .background(rowBackground)
        .clipShape(RoundedRectangle(cornerRadius: UIMetrics.radiusMD, style: .continuous))
        .padding(.horizontal, UIMetrics.spacing3)
        .onHover { hovered = $0 }
    }

    private var rowBackground: Color {
        if isHighlighted { return MuxyTheme.accent.opacity(0.18) }
        if hovered { return MuxyTheme.hover }
        return .clear
    }
}
