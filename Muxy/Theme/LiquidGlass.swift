import SwiftUI

enum MuxyGlassVariant {
    case regular
    case interactive
    case tinted(Color)
    case interactiveTinted(Color)

    var fallbackMaterial: Material {
        switch self {
        case .regular,
             .interactive: .regularMaterial
        case .tinted,
             .interactiveTinted: .ultraThinMaterial
        }
    }
}

extension View {
    @ViewBuilder
    func muxyGlass(
        _ variant: MuxyGlassVariant = .regular,
        in shape: some Shape = RoundedRectangle(cornerRadius: 0)
    ) -> some View {
        if #available(macOS 26.0, *) {
            LiquidGlassApplier.apply(view: self, variant: variant, shape: shape)
        } else {
            background(variant.fallbackMaterial, in: shape)
        }
    }
}

@available(macOS 26.0, *)
private enum LiquidGlassApplier {
    @ViewBuilder
    static func apply(
        view: some View,
        variant: MuxyGlassVariant,
        shape: some Shape
    ) -> some View {
        switch variant {
        case .regular:
            view.glassEffect(.regular, in: shape)
        case .interactive:
            view.glassEffect(.regular.interactive(), in: shape)
        case let .tinted(color):
            view.glassEffect(.regular.tint(color), in: shape)
        case let .interactiveTinted(color):
            view.glassEffect(.regular.tint(color).interactive(), in: shape)
        }
    }
}
