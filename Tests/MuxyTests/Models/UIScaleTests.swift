import Foundation
import SwiftUI
import Testing

@testable import Muxy

@Suite("UIScale")
@MainActor
struct UIScaleTests {
    @Test("Each preset returns a distinct, ordered multiplier")
    func presetMultipliersAreOrdered() {
        let presets = UIScale.Preset.allCases
        #expect(presets == [.regular, .large, .extraLarge])

        let multipliers = presets.map(\.multiplier)
        #expect(multipliers == multipliers.sorted())
        #expect(Set(multipliers).count == multipliers.count)
        #expect(UIScale.Preset.regular.multiplier == 1.0)
    }

    @Test("UIMetrics.scaled multiplies by the active preset multiplier")
    func metricsScaleWithPreset() {
        let scale = UIScale.shared
        let original = scale.preset
        defer { scale.preset = original }

        scale.preset = .regular
        let baseline = UIMetrics.fontBody
        #expect(baseline == 12.0)

        scale.preset = .large
        #expect(UIMetrics.fontBody == 12.0 * UIScale.Preset.large.multiplier)
        #expect(UIMetrics.scaled(10) == 10 * UIScale.Preset.large.multiplier)

        scale.preset = .extraLarge
        #expect(UIMetrics.iconLG == 16 * UIScale.Preset.extraLarge.multiplier)
    }

    @Test("Preset is round-trip codable")
    func presetIsCodable() throws {
        for preset in UIScale.Preset.allCases {
            let data = try JSONEncoder().encode(preset)
            let decoded = try JSONDecoder().decode(UIScale.Preset.self, from: data)
            #expect(decoded == preset)
        }
    }

    @Test("Dynamic Type multiplier is monotonic across all sizes")
    func dynamicTypeMultiplierIsMonotonic() {
        let ordered: [DynamicTypeSize] = [
            .xSmall, .small, .medium, .large, .xLarge, .xxLarge, .xxxLarge,
            .accessibility1, .accessibility2, .accessibility3, .accessibility4, .accessibility5,
        ]
        let multipliers = ordered.map { UIScale.dynamicTypeMultiplier($0) }
        #expect(multipliers == multipliers.sorted())
        #expect(UIScale.dynamicTypeMultiplier(.medium) == 1.0)
    }

    @Test("Combined preset and Dynamic Type multiplier compounds")
    func combinedMultiplierCompounds() {
        let combined = UIScale.multiplier(for: .large, dynamicType: .xLarge)
        let expected = UIScale.Preset.large.multiplier * UIScale.dynamicTypeMultiplier(.xLarge)
        #expect(combined == expected)
    }
}
