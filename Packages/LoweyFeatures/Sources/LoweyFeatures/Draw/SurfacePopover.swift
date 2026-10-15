import HmmDesign
import LoweyCore
import LoweyEngine
import PhotosUI
import SwiftUI

/// Draw ▸ Surface (U7): everything about the painted thing's surface beside its layers. The faces brush and seams, wear,
/// a decal, painting mirrored, the texture's size, the flat view, normals baked from a detailed copy, and fur. One
/// deliberate step deeper than the layers (progressive disclosure), each row in plain words.
struct SurfacePopover: View {
    @Bindable var editor: EditorModel
    @State private var photo: PhotosPickerItem?
    @State private var choosingFile = false
    @State private var furGesture = UUID().uuidString
    @Environment(\.hmmTheme) private var theme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: HmmSpacing.m) {
                if let object = editor.paintTarget {
                    tools
                    if object.paint != nil {
                        wear
                        decal
                        mirror(object)
                        size(object)
                        flat
                        normals(object)
                    }
                    fur(object)
                } else {
                    Hint("Tap a shape, a modelled part or a placed model to work on its surface.")
                }
            }
            .padding(HmmSpacing.m)
        }
        .frame(width: 340)
        .frame(maxHeight: 560)
        .font(.hmm(.body))
        .accessibilityIdentifier("surface-popover")
        .onChange(of: photo) { _, item in loadPhoto(item) }
        .fileImporter(isPresented: $choosingFile, allowedContentTypes: [.image]) { result in
            guard case let .success(url) = result else { return }
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            if let data = try? Data(contentsOf: url) { holdDecal(data) }
        }
    }

    private var tools: some View {
        PanelSection("Brushes") {
            FlowChips(items: [ColourPaintSettings.Mode.faces, .seams].map { ($0.rawValue, $0.title) },
                      isOn: { $0 == editor.colourPaint.mode.rawValue }) { key in
                let mode = ColourPaintSettings.Mode(rawValue: key) ?? .paint
                editor.colourPaint.mode = editor.colourPaint.mode == mode ? .paint : mode
                editor.tool = .paint
                editor.refreshSeamOverlay()
            }
            .accessibilityIdentifier("surface-brushes")
            if editor.colourPaint.mode == .faces {
                Hint("Tap a face: it fills edge to edge with the colour in hand, the low-poly way.")
            }
            if editor.colourPaint.mode == .seams {
                Hint("Tap edges to mark where the surface is cut open when it's laid flat. Close a loop, then Cut.")
                HStack(spacing: HmmSpacing.xs) {
                    HmmPillButton("Cut \(editor.colourPaint.pendingSeams.count)", systemName: "scissors") { editor.applySeams() }
                        .disabled(editor.colourPaint.pendingSeams.isEmpty)
                        .accessibilityIdentifier("seams-cut")
                    Button("Automatic") { editor.applySeams(clear: true) }
                        .buttonStyle(.bordered)
                }
            }
        }
    }

    private var wear: some View {
        PanelSection("Wear") {
            HStack(spacing: HmmSpacing.xs) {
                Button("Dirt", systemImage: "aqi.medium") { editor.addFill(.wear(PaintWear(kind: .dirt))) }
                Button("Worn edges", systemImage: "square.dashed") { editor.addFill(.wear(PaintWear(kind: .edges))) }
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("surface-wear")
            Hint("Grime gathers in the creases, paint rubs off the edges. Each is a layer: its amount is in Layers.")
        }
    }

    private var decal: some View {
        PanelSection("Decal") {
            HStack(spacing: HmmSpacing.xs) {
                PhotosPicker(selection: $photo, matching: .images) { Label("Photos", systemImage: "photo") }
                    .buttonStyle(.bordered)
                Button("Files", systemImage: "folder") { choosingFile = true }
                    .buttonStyle(.bordered)
            }
            if editor.colourPaint.decalWaiting {
                LabeledSlider(title: "Decal size", value: editor.colourPaint.decalSize, range: 0.02 ... 2, format: { String(format: "%.2f m", $0) }) {
                    editor.colourPaint.decalSize = $0
                }
                Hint("Now tap the thing where the picture goes: it's pressed on like a sticker.")
            } else {
                Hint("A picture pressed onto the surface: a logo, a label, a sign.")
            }
        }
    }

    private func mirror(_ object: SceneObject) -> some View {
        PanelSection("Mirror") {
            let current = object.paint?.mirror
            FlowChips(items: [("off", "Off")] + PaintMirror.allCases.map { ($0.rawValue, $0.title) },
                      isOn: { $0 == (current?.rawValue ?? "off") }) { key in
                editor.setPaintMirror(PaintMirror(rawValue: key))
            }
            .accessibilityIdentifier("surface-mirror")
        }
    }

    private func size(_ object: SceneObject) -> some View {
        PanelSection("Texture size") {
            let current = object.paint?.surface.size ?? PaintSurface.defaultSize
            FlowChips(items: PaintSurface.sizes.map { (String($0), "\($0)") }, isOn: { $0 == String(current) }) { key in
                if let size = Int(key) { editor.setTextureSize(size) }
            }
            .accessibilityIdentifier("surface-size")
            Hint("More pixels for fine detail, fewer for a light file. Every layer is kept.")
        }
    }

    private var flat: some View {
        PanelSection("Flat view") {
            Button("Paint it flat", systemImage: "square.grid.3x3.square") { editor.colourPaint.flatView = true }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("surface-flat")
            Hint("The surface laid out flat, as the texture is: paint it in 2D.")
        }
    }

    private func normals(_ object: SceneObject) -> some View {
        PanelSection("Detail from a sculpt") {
            let candidates = editor.displayed.scene.objects.values.filter { $0.id != object.id && $0.isPaintable }.sorted { $0.name < $1.name }
            Menu {
                ForEach(candidates) { candidate in
                    Button(candidate.name) { editor.bakeNormals(from: candidate.id) }
                }
            } label: {
                Label("Bake normals from…", systemImage: "wand.and.rays")
            }
            .disabled(candidates.isEmpty)
            .accessibilityIdentifier("surface-bake")
            if let from = object.paint?.normalsFrom {
                HStack {
                    Text("From \(from)").foregroundStyle(theme.text2)
                    Spacer()
                    Button("Remove") { editor.removeBakedNormals() }
                }
            }
            Hint("A detailed sculpt's bumps and creases, given to its light copy as light and shade.")
        }
    }

    private func fur(_ object: SceneObject) -> some View {
        PanelSection("Fur") {
            let fur = FurSettings(object) ?? FurSettings(length: 0)
            LabeledSlider(title: "Fur length", value: fur.length * 100, range: 0 ... 15, format: { String(format: "%.1f cm", $0) }) { value in
                editor.setFur({ $0.length = value / 100 }, gesture: furGesture)
            } done: { furGesture = UUID().uuidString }
            if fur.length > 0 {
                LabeledSlider(title: "Density", value: fur.density, range: 0 ... 1, format: NumberFormat.percent) { value in
                    editor.setFur({ $0.density = value }, gesture: furGesture)
                } done: { furGesture = UUID().uuidString }
                LabeledSlider(title: "Droop", value: fur.droop, range: 0 ... 1, format: NumberFormat.percent) { value in
                    editor.setFur({ $0.droop = value }, gesture: furGesture)
                } done: { furGesture = UUID().uuidString }
                FlowChips(items: FurSettings.Style.allCases.map { ($0.rawValue, $0.title) }, isOn: { $0 == fur.style.rawValue }) { key in
                    editor.setFur { $0.style = FurSettings.Style(rawValue: key) ?? .shells }
                }
                Hint("Paint the Fur map in Layers: white grows it long, black leaves it bare.")
            }
        }
        .accessibilityIdentifier("surface-fur")
    }

    private func loadPhoto(_ item: PhotosPickerItem?) {
        guard let item else { return }
        Task {
            if let data = try? await item.loadTransferable(type: Data.self) { holdDecal(data) }
            photo = nil
        }
    }

    private func holdDecal(_ data: Data) {
        guard let picture = PaintPixels.decode(data) else {
            editor.app.show("That picture couldn't be read", kind: .error)
            return
        }
        editor.texture.decal = picture
        editor.colourPaint.decalWaiting = true
        editor.colourPaint.mode = .paint
        editor.tool = .paint
    }
}
