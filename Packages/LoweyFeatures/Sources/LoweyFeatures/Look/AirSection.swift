import HmmDesign
import LoweyCore
import SwiftUI
import UniformTypeIdentifiers

/// Look ▸ World (F1): an HDRI as the world's sky and light, and the air (haze, god rays).
struct AirSection: View {
    let editor: EditorModel
    @State private var importing = false

    var body: some View {
        VStack(alignment: .leading, spacing: HmmSpacing.m) {
            PanelSection("Sky from a picture") {
                if editor.look.sky.environment != nil {
                    LabeledSlider(title: "Turn", value: editor.look.sky.environmentTurn ?? 0, range: -180 ... 180, format: { "\(Int($0.rounded()))°" },
                                  set: { editor.turnEnvironment($0, gesture: "hdri-turn") }, done: editor.endGesture)
                    LabeledSlider(title: "Brightness", value: editor.look.sky.environmentExposure ?? 0, range: -4 ... 4,
                                  format: { String(format: "%+.1f", $0) }, set: { editor.setEnvironmentExposure($0, gesture: "hdri-exposure") },
                                  done: editor.endGesture)
                    HStack(spacing: HmmSpacing.xs) {
                        HmmPillButton("Another HDRI", systemName: "photo.on.rectangle") { importing = true }
                        HmmPillButton("Back to the mood's sky", systemName: "arrow.uturn.backward") { editor.removeEnvironment() }
                    }
                } else {
                    HmmPillButton("Choose an HDRI…", systemName: "photo.on.rectangle", prominent: true) { importing = true }
                        .accessibilityIdentifier("choose-hdri")
                    Hint("A Radiance .hdr panorama shows behind everything and lights the world: its sun, its sky.")
                }
            }
            PanelSection("Air") {
                LabeledSlider(title: "Haze", value: editor.atmosphere.haze, range: 0 ... 1, format: NumberFormat.percent,
                              set: { editor.setAir(haze: $0, gesture: "haze") }, done: editor.endGesture)
                LabeledSlider(title: "God rays", value: editor.atmosphere.godRays, range: 0 ... 1, format: NumberFormat.percent,
                              set: { editor.setAir(godRays: $0, gesture: "rays") }, done: editor.endGesture)
                Hint("God rays stream from the sun past what stands in front of it: turn the camera toward the sun to see them.")
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.radianceHDR]) { result in
            guard case let .success(url) = result else { return }
            Task { await editor.importEnvironment(url) }
        }
    }
}
