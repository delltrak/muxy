import SwiftUI

struct IconButton: View {
    let symbol: String
    var size: CGFloat = 13
    var color: Color = MuxyTheme.fgMuted
    var hoverColor: Color = MuxyTheme.fg
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: UIMetrics.scaled(size), weight: .semibold))
        }
        .buttonStyle(IconButtonStyle(idleColor: color, hoverColor: hoverColor))
        .accessibilityLabel(accessibilityLabel)
    }
}

struct IconButtonStyle: ButtonStyle {
    var idleColor: Color = MuxyTheme.fgMuted
    var hoverColor: Color = MuxyTheme.fg

    func makeBody(configuration: Configuration) -> some View {
        IconButtonBody(
            configuration: configuration,
            idleColor: idleColor,
            hoverColor: hoverColor
        )
    }
}

private struct IconButtonBody: View {
    let configuration: ButtonStyle.Configuration
    let idleColor: Color
    let hoverColor: Color

    @Environment(\.isEnabled) private var isEnabled
    @State private var hovered = false

    var body: some View {
        configuration.label
            .foregroundStyle(hovered ? hoverColor : idleColor)
            .frame(width: 28, height: 28)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(hovered ? MuxyTheme.hover : .clear)
            )
            .scaleEffect(configuration.isPressed ? 0.92 : 1.0)
            .opacity(opacity(for: configuration))
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .animation(.easeOut(duration: 0.12), value: hovered)
            .onHover { hovered = $0 }
    }

    private func opacity(for configuration: ButtonStyle.Configuration) -> Double {
        guard isEnabled else { return 0.4 }
        return configuration.isPressed ? 0.7 : 1.0
    }
}
