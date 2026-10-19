import HmmDesign
import LoweyCore
import SwiftUI

/// A selected light: its colour, strength and reach, a spot's cone, a soft panel's size, and the setups (F1): three-point,
/// golden hour, moonlight and neon one tap away, placed around the selection as the shot camera sees it.
struct LightSection: View {
    let editor: EditorModel
    let object: SceneObject
    let type: LightType
    @State private var showsMoreSetups = false

    var body: some View {
        VStack(alignment: .leading, spacing: HmmSpacing.m) {
            PanelSection(type.title) {
                ColorPicker("Colour", selection: Binding(get: { (object[.lightColor]?.colorValue?.resolved(in: editor.look.palette) ?? .white).color },
                                                         set: { editor.setProperty(.lightColor, .color(.rgba(RGBA($0))), coalesce: "lightcolor") }),
                            supportsOpacity: false)
                slider("Strength", .lightIntensity, 0 ... 6, 1)
                if type != .directional { slider("Reach", .lightRange, 0.5 ... 30, 6) }
                if type == .spot { slider("Cone", .spotAngle, 5 ... 120, 40) }
                if type == .area {
                    slider("Width", .lightWidth, 0.1 ... 6, 1, unit: true)
                    slider("Height", .lightHeight, 0.1 ... 6, 0.6, unit: true)
                    Hint("A soft panel lights the way it faces, like a softbox or a window. Turn it to aim it.")
                }
                if type == .directional {
                    Hint("Only the sun casts shadows; bulbs, spots and panels light without them.")
                }
            }
            setups
        }
        .font(.hmm(.body))
    }

    private var setups: some View {
        PanelSection("Setups") {
            TileGrid(minimum: 96) {
                ForEach([LightRecipe.threePoint, .goldenHour, .moonlit, .neon]) { recipe in
                    TileButton(title: recipe.title, systemName: Self.icon(for: recipe), identifier: "setup-\(recipe.rawValue)") {
                        editor.applyLightSetup(recipe)
                    }
                    .accessibilityHint(Text(LocalizedStringKey(recipe.reason)))
                }
            }
            DisclosureGroup("More setups", isExpanded: $showsMoreSetups) {
                TileGrid(minimum: 96) {
                    ForEach(LightRecipe.allCases.filter { ![.threePoint, .goldenHour, .moonlit, .neon].contains($0) }) { recipe in
                        TileButton(title: recipe.title, systemName: Self.icon(for: recipe), identifier: "setup-\(recipe.rawValue)") {
                            editor.applyLightSetup(recipe)
                        }
                    }
                }
                .padding(.top, HmmSpacing.xs)
            }
            Hint("Lights the selection as the shot camera sees it; the last setup's lights are replaced.")
        }
    }

    static func icon(for recipe: LightRecipe) -> String {
        switch recipe {
        case .threePoint: "light.ribbon"
        case .goldenHour: "sunset.fill"
        case .moonlit: "moon.stars.fill"
        case .neon: "lightspectrum.horizontal"
        case .keyWarmWorldCool: "thermometer.sun"
        case .noirSingleSource: "light.min"
        case .goldenRim: "circle.dashed"
        case .monitorGlow: "display"
        case .studioSoft: "camera.aperture"
        }
    }

    private func slider(_ title: String, _ key: PropertyKey, _ range: ClosedRange<Double>, _ fallback: Double, unit: Bool = false) -> some View {
        LabeledSlider(title: title, value: object[key]?.floatValue ?? fallback, range: range,
                      format: unit ? { editor.units.format($0) } : { NumberFormat.short($0) }, set: {
                          editor.setProperty(key, .float($0), coalesce: "\(key.rawValue)-\(object.id.raw)")
                      }, done: editor.endGesture)
    }
}
