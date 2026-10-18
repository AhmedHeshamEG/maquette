import HmmDesign
import HmmMedia
import LoweyCore
import LoweyEngine
import SwiftUI

/// The options beside a preset (A1): Final, a transparent background, only the selection, every scene or every shot,
/// only the loop, a glTF's painted colour, and the custom size, frame rate and quality one step deeper.
struct ExportOptions: Equatable {
    var final = false
    var transparent = false
    var onlySelection = false
    var everyScene = false
    var everyShot = false
    var onlyLoop = false
    var custom = false
    var paintColors: PaintColorOutput = .texture

    func job(_ preset: ExportPreset, settings: ExportSettings) -> ExportJob {
        var settings = settings
        settings.final = final && Self.renders(preset)
        if Self.moves(preset) || preset.kind == .still {
            settings.transparent = transparent
            if transparent, !settings.codec.hasAlpha, preset.kind == .video { settings.codec = .hevcAlpha }
            if !transparent, settings.codec == .hevcAlpha { settings.codec = .hevc }
        }
        return ExportJob(preset: preset, settings: settings, everyScene: everyScene, everyShot: everyShot && Self.moves(preset),
                         onlySelection: onlySelection, paintColors: paintColors)
    }

    /// Video, GIF, frames and passes: things that play over time.
    static func moves(_ preset: ExportPreset) -> Bool {
        [.video, .gif, .frames, .passes].contains(preset.kind)
    }

    /// Everything drawn by the renderer (Final applies).
    static func renders(_ preset: ExportPreset) -> Bool {
        moves(preset) || [.still, .stillPasses, .paper].contains(preset.kind)
    }
}

struct ExportOptionsView: View {
    @Bindable var editor: EditorModel
    let preset: ExportPreset
    @Binding var settings: ExportSettings
    @Binding var options: ExportOptions
    @Environment(\.hmmTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: HmmSpacing.s) {
            if ExportOptions.renders(preset) {
                Toggle(isOn: $options.final) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Final")
                        Text("Motion blur, the best shadows, water and edges. Slower; it carries on in the background.")
                            .font(.hmm(.footnote)).foregroundStyle(theme.text2)
                    }
                }
                .accessibilityIdentifier("export-final")
            }
            if ExportOptions.moves(preset) || preset.kind == .still {
                Toggle("Transparent background", isOn: $options.transparent).accessibilityIdentifier("export-transparent")
            }
            if !editor.selection.isEmpty, preset.kind != .lookShader, preset.kind != .captions {
                Toggle("Only the selection", isOn: $options.onlySelection).accessibilityIdentifier("export-only-selection")
            }
            if editor.sceneList.count > 1, preset.kind != .model, preset.kind != .lookShader, preset.kind != .captions {
                Toggle("Every scene, one file each", isOn: $options.everyScene).accessibilityIdentifier("export-every-scene")
            }
            if ExportOptions.moves(preset), !editor.timeline.cuts.isEmpty {
                Toggle("Every shot, one file each", isOn: $options.everyShot).accessibilityIdentifier("export-every-shot")
            }
            if ExportOptions.moves(preset), editor.timeline.loop != nil { Toggle("Only the loop", isOn: $options.onlyLoop) }
            if preset.format == .gltf, preset != .gltfWeb, editor.hasPaintedThings {
                Picker("Painted colour", selection: $options.paintColors) {
                    ForEach(PaintColorOutput.allCases, id: \.self) { Text(LocalizedStringKey($0.title)).tag($0) }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("model-colours")
            }
            if ExportOptions.moves(preset) {
                Toggle("Custom size, frame rate and quality", isOn: $options.custom)
                if options.custom { customControls }
            }
        }
    }

    private var customControls: some View {
        VStack(alignment: .leading, spacing: HmmSpacing.s) {
            Picker("Shape", selection: $settings.framing) {
                ForEach(Framing.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            Picker("Size", selection: $settings.longSide) {
                Text("720p").tag(1280)
                Text("1080p").tag(1920)
                Text("4K").tag(3840)
            }
            .pickerStyle(.segmented)
            Picker("Frame rate", selection: $settings.fps) {
                ForEach(ExportSettings.frameRates, id: \.self) { Text("\($0) fps").tag($0) }
            }
            .pickerStyle(.segmented)
            if preset.kind == .video, !settings.codec.hasAlpha {
                Picker("Codec", selection: $settings.codec) {
                    Text("H.264").tag(VideoCodecKind.h264)
                    Text("HEVC").tag(VideoCodecKind.hevc)
                }
                .pickerStyle(.segmented)
            }
            if preset.kind == .video, settings.codec != .prores4444 {
                LabeledSlider(title: "Quality", value: settings.quality, range: 0.1 ... 1, format: NumberFormat.percent) { settings.quality = $0 }
            }
        }
    }
}
