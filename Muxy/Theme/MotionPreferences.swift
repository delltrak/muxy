import SwiftUI

@MainActor
struct ReduceMotionAware: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let animation: Animation?

    func body(content: Content) -> some View {
        content.animation(reduceMotion ? nil : animation, value: UUID())
    }
}

extension View {
    func reduceMotionAware(_ animation: Animation?) -> some View {
        modifier(ReduceMotionAware(animation: animation))
    }
}

extension Animation {
    static func reducible(_ base: Animation, reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : base
    }
}
