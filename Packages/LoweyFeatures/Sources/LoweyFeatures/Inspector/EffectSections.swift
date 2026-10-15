import HmmDesign
import LoweyCore
import SwiftUI

/// A force's panel: how strong, how far it reaches. A fan blows where it points (turn it like any thing).
struct ForceSection: View {
    let editor: EditorModel
    let object: SceneObject
    let recipe: ForceRecipe

    var body: some View {
        PanelSection(recipe.kind.title) {
            LabeledSlider(title: recipe.kind == .fan ? "Wind m/s" : "Strength", value: recipe.strength, range: recipe.kind == .fan ? 0 ... 40 : -60 ... 60,
                          format: { String(format: "%.1f", $0) }) { value in
                editor.updateForce(object.id) { $0.strength = value }
            } done: { editor.endGesture() }
                .accessibilityIdentifier("force-strength")
            LabeledSlider(title: "Reach m", value: recipe.reach, range: 0.2 ... 20, format: { String(format: "%.1f", $0) }) { value in
                editor.updateForce(object.id) { $0.reach = value }
            } done: { editor.endGesture() }
                .accessibilityIdentifier("force-reach")
            Hint(recipe.kind == .fan ? "It blows the way it points, on real things, cloth, water and smoke."
                : recipe.kind == .pull ? "It pulls real things to its point; below zero it pushes them away." : "It turns real things around it.")
        }
    }
}

/// A fluid's panel: how much, for how long, its box and colour. It's worked out in the background and plays from there.
struct FluidSection: View {
    let editor: EditorModel
    let object: SceneObject
    let recipe: FluidRecipe

    var body: some View {
        PanelSection(recipe.kind.title) {
            LabeledSlider(title: recipe.kind == .pour ? "Litres a second" : recipe.kind == .splash ? "Litres" : "How much", value: recipe.amount,
                          range: Self.amounts(recipe.kind), format: { String(format: "%.2f", $0) }) { value in
                editor.updateFluid(object.id) { $0.amount = value }
            } done: { editor.endGesture() }
                .accessibilityIdentifier("fluid-amount")
            if recipe.kind != .splash {
                LabeledSlider(title: "Seconds", value: recipe.duration, range: 0.2 ... 30, format: { String(format: "%.1f", $0) }) { value in
                    editor.updateFluid(object.id) { $0.duration = value }
                } done: { editor.endGesture() }
                    .accessibilityIdentifier("fluid-duration")
            }
            LabeledSlider(title: "Room m", value: recipe.box.maxComponent, range: 0.2 ... 4, format: { String(format: "%.1f", $0) }) { value in
                editor.updateFluid(object.id) { $0.box = FluidRecipe.clamped($0.box * (value / max($0.box.maxComponent, 0.01))) }
            } done: { editor.endGesture() }
                .accessibilityIdentifier("fluid-box")
            ColorPicker("Colour", selection: Binding(get: { recipe.color.color }, set: { colour in
                editor.updateFluid(object.id) { $0.color = RGBA(colour) }
            }), supportsOpacity: false)
                .font(.hmm(.body))
                .accessibilityIdentifier("fluid-colour")
            if let progress = editor.physicsRun.progress, progress < 1 {
                ProgressView(value: progress) { Text("Working it out").font(.hmm(.footnote)) }
                    .accessibilityIdentifier("fluid-progress")
            }
        }
    }

    static func amounts(_ kind: FluidRecipe.Kind) -> ClosedRange<Double> {
        switch kind {
        case .pour: 0.02 ... 3
        case .splash: 0.02 ... 30
        case .smoke, .fire: 0.05 ... 1
        }
    }
}
