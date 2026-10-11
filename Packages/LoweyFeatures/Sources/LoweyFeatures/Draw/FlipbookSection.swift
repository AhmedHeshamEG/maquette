import HmmDesign
import LoweyCore
import SwiftUI

/// Draw ▸ Flipbook: frame-by-frame drawing on the sheet in the space (CONTEXT §10.10), or stuck to the camera as screen
/// effects. Pick or start a track; the drawings themselves are on the frame strip under the stage; a ready-made drawn
/// effect goes on the selected object or the camera.
struct FlipbookSection: View {
    @Bindable var editor: EditorModel

    var body: some View {
        VStack(alignment: .leading, spacing: HmmSpacing.s) {
            HStack(spacing: HmmSpacing.xs) {
                ForEach(FlipbookSettings.Mode.allCases) { mode in
                    ChoiceChip(title: mode.title, systemName: mode.systemImage, isOn: editor.flipbook.mode == mode) { editor.flipbook.mode = mode }
                        .accessibilityIdentifier("flipbook-\(mode.rawValue)")
                }
            }
            if editor.flipbook.mode == .draw {
                BrushRow(editor: editor, tool: .flipbook)
            }
            Toggle("Stuck to the camera", isOn: $editor.flipbook.onCamera)
                .accessibilityIdentifier("flipbook-on-camera")
            PanelSection("Tracks") {
                FlowChips(items: trackChoices, isOn: { $0 == editor.flipbook.track }) { key in
                    if key == "new" { editor.startNewFlipbook() } else { editor.flipbook.track = key }
                }
                .accessibilityIdentifier("flipbook-tracks")
                Hint(trackHint)
            }
            if let track = editor.activeFlipbook {
                trackOptions(track)
            }
            if editor.flipbook.onCamera {
                DrawingGuideControls(guide: editor.frameGuide, kinds: DrawingGuide.Kind.allCases, spacing: 0.01 ... 0.3,
                                     formatSpacing: { "\(Int(($0 * 100).rounded())) %" }) { editor.setFrameGuide($0) }
            }
            PanelSection("Drawn effects") {
                FlowChips(items: FlipbookFX.allCases.map { ($0.rawValue, $0.title) }, isOn: { _ in false }) { key in
                    if let fx = FlipbookFX(rawValue: key) { editor.addFlipbookEffect(fx) }
                }
                Hint("On the selected object, else on the camera, starting at the playhead.")
            }
            Hint("Width and opacity are the sidebar's sliders. The drawings are on the strip under the stage: + adds the next one.")
        }
        .font(.hmm(.body))
    }

    private var trackChoices: [(String, String)] {
        var choices: [(String, String)] = editor.flipbookTracks.map { track in (track.id, track.name) }
        choices.append(("new", String(localized: "New track")))
        return choices
    }

    private var trackHint: String {
        if editor.activeFlipbook == nil {
            return editor.flipbook.onCamera ? String(localized: "Your first stroke starts a flipbook on the camera.")
                : String(localized: "Your first stroke starts a flipbook on the sheet, where it stays in the space.")
        }
        return String(localized: "Strokes go into the drawing at the playhead; past the last drawing they start a new one.")
    }

    private func trackOptions(_ track: FlipbookTrack) -> some View {
        PanelSection("Track") {
            Picker("Blend", selection: Binding(get: { track.blend }, set: { blend in editor.updateFlipbook("Blend") { $0.blend = blend } })) {
                ForEach(FlipbookBlend.allCases, id: \.self) { Text(LocalizedStringKey($0.title)).tag($0) }
            }
            .pickerStyle(.segmented)
            LabeledSlider(title: "Track opacity", value: track.opacity, range: 0 ... 1, format: { "\(Int(($0 * 100).rounded())) %" },
                          set: { value in editor.updateFlipbook("Opacity", coalesceKey: "flipbook-opacity") { $0.opacity = value } },
                          done: { editor.endGesture() })
            Toggle("Loop", isOn: Binding(get: { track.loops }, set: { loops in
                editor.updateFlipbook("Loop") { $0.loops = loops }
            }))
            Stepper("New drawings hold \(editor.flipbook.hold) frames", value: $editor.flipbook.hold, in: 1 ... 8)
            HmmPillButton("Delete track", systemName: "trash", role: .destructive) { editor.deleteFlipbook() }
        }
    }
}
