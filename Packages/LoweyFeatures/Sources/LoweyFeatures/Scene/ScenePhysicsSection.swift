import HmmDesign
import LoweyCore
import SwiftUI

/// Behind the scene's name (P1): the pull everything feels, the wind, the ground, when things start to move, and
/// the run itself (how far it's worked out, Keep it).
struct ScenePhysicsSection: View {
    @Bindable var editor: EditorModel
    @State private var gesture = UUID().uuidString

    var body: some View {
        let physics = editor.scenePhysics
        PanelSection("Physics") {
            TileGrid(minimum: 84) {
                ForEach(GravityPreset.allCases) { preset in
                    TileButton(title: preset.title, systemName: preset == .none ? "circle.dotted" : "globe", identifier: "gravity-\(preset.rawValue)",
                               isOn: physics.gravity == preset && physics.customGravity == nil) {
                        editor.changeScenePhysics("Gravity") {
                            $0.gravity = preset
                            $0.customGravity = nil
                        }
                    }
                }
            }
            LabeledSlider(title: "Wind m/s", value: physics.windSpeed, range: 0 ... 30, format: { String(format: "%.1f", $0) }) { value in
                editor.changeScenePhysics("Wind", coalesce: gesture) { $0.windSpeed = value }
            } done: { finish() }
                .accessibilityIdentifier("scene-wind")
            if physics.windSpeed > 0 {
                LabeledSlider(title: "Blows toward", value: physics.windHeading, range: 0 ... 359, format: Self.compass) { value in
                    editor.changeScenePhysics("Wind", coalesce: gesture) { $0.windHeading = value }
                } done: { finish() }
                    .accessibilityIdentifier("scene-wind-heading")
                LabeledSlider(title: "Gusts", value: physics.gusts, range: 0 ... 1, format: { String(format: "%.2f", $0) }) { value in
                    editor.changeScenePhysics("Wind", coalesce: gesture) { $0.gusts = value }
                } done: { finish() }
                    .accessibilityIdentifier("scene-gusts")
            }
            Toggle("A solid ground", isOn: Binding(get: { physics.ground }, set: { value in
                editor.changeScenePhysics("Ground") { $0.ground = value }
            }))
            .font(.hmm(.body))
            .accessibilityIdentifier("scene-ground")
            HmmNumberPill("Starts at s", value: Binding(get: { physics.start }, set: { value in
                editor.changeScenePhysics("Physics start", coalesce: gesture) { $0.start = max(value, 0) }
            }), scrub: HmmScrub(fine: 0.05, range: 0 ... 3600), format: { String(format: "%.2f", $0) }, onEditingChanged: { editing in
                if !editing { finish() }
            })
            .accessibilityIdentifier("scene-physics-start")
            run
        }
    }

    @ViewBuilder
    private var run: some View {
        if let progress = editor.physicsRun.progress {
            if progress < 1 {
                ProgressView(value: progress) { Text("Working out the run").font(.hmm(.footnote)) }
                    .accessibilityIdentifier("scene-physics-progress")
            } else {
                HmmPillButton("Keep it", systemName: "key") { editor.keepRun() }
                    .accessibilityIdentifier("scene-keep")
                Hint("Keep it turns the run into keys you can change by hand.")
            }
        }
    }

    private func finish() {
        editor.endGesture()
        gesture = UUID().uuidString
    }

    /// North is -Z on the stage, east +X.
    static func compass(_ degrees: Double) -> String {
        let names = [String(localized: "north"), String(localized: "north-east"), String(localized: "east"), String(localized: "south-east"),
                     String(localized: "south"), String(localized: "south-west"), String(localized: "west"), String(localized: "north-west")]
        let index = Int(((degrees.truncatingRemainder(dividingBy: 360) + 382.5) / 45).rounded(.down)) % 8
        return "\(Int(degrees.rounded()))° \(names[index])"
    }
}
