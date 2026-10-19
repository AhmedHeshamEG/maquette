import HmmDesign
import HmmDocuments
import LoweyCore
import SwiftUI
import UIKit

/// The Look Studio (L2, D-484), in the Studio grammar every made thing shares: the Look on its check scene at the top,
/// changing as you go; its settings in pages (Light, Lines, Paint, Print, Motion); About last. It edits one of the
/// project's own Looks; "Save to Yours" keeps it for every project, the share button sends it as a pack.
struct LookStudioView: View {
    let editor: EditorModel
    let id: String
    @State private var page: LookStudioPage = .light
    @State private var mood: LightingPreset = .day
    @State private var picture: UIImage?
    @State private var sharing: IdentifiedURL?
    @Environment(\.dismiss) private var dismiss

    private var preset: LookPreset {
        editor.document.project.customLooks.first { $0.id == id } ?? .ink
    }

    var body: some View {
        HmmStudio(preset.name, page: $page, identifier: "look-studio", previewHeight: 220) {
            ZStack(alignment: .bottomTrailing) {
                if let picture {
                    Image(uiImage: picture).resizable().scaledToFill()
                }
                Picker("Mood", selection: $mood) {
                    Text("Day").tag(LightingPreset.day)
                    Text("Night").tag(LightingPreset.night)
                }
                .pickerStyle(.segmented)
                .frame(width: 160)
                .padding(HmmSpacing.s)
            }
            .accessibilityLabel(Text("\(preset.name) on its check scene"))
        } content: { page in
            LookStudioPageView(editor: editor, preset: preset, page: page)
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
            ToolbarItemGroup(placement: .primaryAction) {
                Button("Save to Yours", systemImage: "tray.and.arrow.down") { editor.saveLookToYours(preset) }
                    .accessibilityIdentifier("look-studio-save")
                Button("Share as a pack", systemImage: "square.and.arrow.up") {
                    sharing = editor.app.writePack([.look(id)], name: preset.name, author: editor.app.packAuthor, licence: editor.app.packLicence,
                                                   looks: editor.document.project.customLooks).map(IdentifiedURL.init)
                }
            }
        }
        .sheet(item: $sharing) { ShareSheet(items: [$0.url]) }
        .task(id: "\(preset.hashValue)-\(mood.rawValue)") {
            try? await Task.sleep(for: .milliseconds(80))
            picture = await LookSwatches.shared.swatch(preset, mood: mood, width: 640, height: 360)
        }
    }
}

/// The Look Studio's pages.
enum LookStudioPage: String, CaseIterable, HmmStudioPage {
    case light, lines, paint, print, motion, about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .light: "Light"
        case .lines: "Lines"
        case .paint: "Paint"
        case .print: "Print"
        case .motion: "Motion"
        case .about: "About"
        }
    }
}

/// One page of the Look Studio. Every change is the project's Look changing (one undo step a drag).
struct LookStudioPageView: View {
    let editor: EditorModel
    let preset: LookPreset
    let page: LookStudioPage

    var body: some View {
        VStack(alignment: .leading, spacing: HmmSpacing.s) {
            switch page {
            case .light: light
            case .lines: lines
            case .paint: paint
            case .print: printing
            case .motion: motion
            case .about: about
            }
        }
        .font(.hmm(.body))
    }

    @ViewBuilder private var light: some View {
        Picker("Shading", selection: binding(\.shading.model)) {
            Text("Bands").tag(LookModel.toon)
            Text("Soft").tag(LookModel.clay)
        }
        .pickerStyle(.segmented)
        Picker("Bands", selection: binding(\.shading.bands)) {
            Text("2 bands").tag(2)
            Text("3 bands").tag(3)
        }
        .pickerStyle(.segmented)
        slider("Shadow edge", \.shading.edgeSoftness, 0.002 ... 0.08)
        slider("Shadow depth", \.shading.shadowValue, 0 ... 0.7)
        slider("Shadow hue", \.shading.shadowHueShift, 0 ... 0.6)
        slider("Shadow tint", tintAmount, 0 ... 1)
        slider("Rim light", \.shading.rim, 0 ... 1)
        slider("Contact shading", \.shading.contactShading, 0 ... 1)
        slider("Shape smoothing", \.shading.smoothing, 0 ... 1)
        slider("Reflection", reflection, 0 ... 1)
        Hint("Bands are cel shading; soft is light as in a photograph. A shadow tint lays one colour over every shadow.")
    }

    @ViewBuilder private var lines: some View {
        Toggle("Lines", isOn: binding(\.lines.enabled))
        if preset.lines.enabled {
            slider("Line width", \.lines.width, 0.5 ... 6)
            slider("Boil", \.lines.boil, 0 ... 1)
            Toggle("Pencil lines", isOn: binding(\.lines.pencil))
            Picker("Line colour", selection: binding(\.lines.colorMode)) {
                Text("Darkened colour").tag(LineParams.ColorMode.darkened)
                Text("Ink").tag(LineParams.ColorMode.ink)
            }
            .pickerStyle(.segmented)
        }
    }

    @ViewBuilder private var paint: some View {
        slider("Brush strokes", paintValue(\.strokes), 0 ... 1)
        slider("Stroke size", paintValue(\.size), 2 ... 16)
        slider("Wet edges", paintValue(\.wetEdges), 0 ... 1)
        slider("Granulation", paintValue(\.granulation), 0 ... 1)
        slider("Paper shows through", paintValue(\.paper), 0 ... 1)
        Hint("Strokes follow the forms, as a painter's do. Wet edges, granulation and paper make it watercolour.")
    }

    @ViewBuilder private var printing: some View {
        slider("Halftone", \.comic.halftone, 0 ... 1)
        slider("Hatching", \.comic.hatching, 0 ... 1)
        Toggle("Colour misregistration", isOn: binding(\.comic.misregistration))
        slider("Paper grain", \.finish.paperGrain, 0 ... 1)
        slider("Saturation", \.finish.saturation, -1 ... 1)
        Toggle("Accents keep their colour", isOn: binding(\.finish.accentKeepsColor))
        Toggle("Pixels", isOn: Binding(get: { preset.pixel != nil }, set: { on in change { $0.pixel = on ? PixelStyle() : nil } }))
        if let pixel = preset.pixel {
            LabeledSlider(title: "Pixel size", value: pixel.size, range: 2 ... 16, set: { value in
                change(coalesce: "pixel-size") { $0.pixel?.size = value }
            }, done: editor.endGesture)
            LabeledSlider(title: "Colours", value: Double(pixel.colors), range: 2 ... 32, format: { "\(Int($0))" }, set: { value in
                change(coalesce: "pixel-colours") { $0.pixel?.colors = Int(value.rounded()) }
            }, done: editor.endGesture)
        }
    }

    private var motion: some View {
        Picker("Animation", selection: binding(\.stepping)) {
            Text("On ones").tag(Stepping.onOnes)
            Text("On twos").tag(Stepping.onTwos)
            Text("On threes").tag(Stepping.onThrees)
            Text("On fours").tag(Stepping.onFours)
        }
        .pickerStyle(.segmented)
    }

    private var about: some View {
        HmmStudioAbout(name: Binding(get: { preset.name }, set: { editor.renameCustomLook(preset.id, to: $0) }),
                       origin: editor.library.origin(.look, preset.id),
                       note: "A Look is how everything is drawn. Things that use it change with it; built-in Looks stay as they came.")
    }

    // MARK: Values

    private func change(coalesce: String? = nil, _ edit: (inout LookPreset) -> Void) {
        editor.updateCustomLook(preset.id, coalesce: coalesce, edit)
    }

    private func binding<Value: Equatable>(_ path: WritableKeyPath<LookPreset, Value>) -> Binding<Value> {
        Binding(get: { preset[keyPath: path] }, set: { value in change { $0[keyPath: path] = value } })
    }

    private func slider(_ title: String, _ path: WritableKeyPath<LookPreset, Double>, _ range: ClosedRange<Double>) -> some View {
        LabeledSlider(title: title, value: preset[keyPath: path], range: range, set: { value in
            change(coalesce: "look-studio-\(title)") { $0[keyPath: path] = value }
        }, done: editor.endGesture)
    }

    /// A value the Look may not have yet (its paint, its tint, its reflection): reading gives 0, writing makes it.
    private func slider(_ title: String, _ value: (get: (LookPreset) -> Double, set: (inout LookPreset, Double) -> Void),
                        _ range: ClosedRange<Double>) -> some View {
        LabeledSlider(title: title, value: value.get(preset), range: range, set: { number in
            change(coalesce: "look-studio-\(title)") { value.set(&$0, number) }
        }, done: editor.endGesture)
    }

    private func paintValue(_ path: WritableKeyPath<PaintStyle, Double>) -> (get: (LookPreset) -> Double, set: (inout LookPreset, Double) -> Void) {
        ({ $0.paint?[keyPath: path] ?? (path == \.size ? 6 : 0) }, { preset, value in
            var paint = preset.paint ?? PaintStyle(strokes: 0)
            paint[keyPath: path] = value
            preset.paint = paint.isOff ? nil : paint
        })
    }

    private var tintAmount: (get: (LookPreset) -> Double, set: (inout LookPreset, Double) -> Void) {
        ({ $0.shading.shadowTint?.a ?? 0 }, { preset, value in
            var tint = preset.shading.shadowTint ?? RGBA(0.62, 0.58, 0.82)
            tint.a = value
            preset.shading.shadowTint = value > 0.001 ? tint : nil
        })
    }

    private var reflection: (get: (LookPreset) -> Double, set: (inout LookPreset, Double) -> Void) {
        ({ $0.shading.reflection ?? 0 }, { preset, value in preset.shading.reflection = value > 0.001 ? value : nil })
    }
}
