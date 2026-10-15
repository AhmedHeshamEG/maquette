import HmmDesign
import LoweyCore
import PhotosUI
import SwiftUI

/// Draw ▸ Layers (U5: Sheets becomes Layers while a paint brush is over a thing): the thing being painted (made ready
/// the moment it's chosen), its layers, and a picture to project from the camera.
struct LayersPopover: View {
    @Bindable var editor: EditorModel
    @State private var photo: PhotosPickerItem?
    @State private var choosingFile = false
    @Environment(\.hmmTheme) private var theme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: HmmSpacing.m) {
                target
            }
            .padding(HmmSpacing.m)
        }
        .frame(width: 340)
        .frame(maxHeight: 520)
        .font(.hmm(.body))
        .accessibilityIdentifier("layers-popover")
        .onChange(of: photo) { _, item in load(item) }
        .fileImporter(isPresented: $choosingFile, allowedContentTypes: [.image]) { result in
            guard case let .success(url) = result else { return }
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            if let image = UIImage(contentsOfFile: url.path)?.cgImage { place(image) }
        }
    }

    @ViewBuilder private var target: some View {
        if let object = editor.paintTarget {
            if object.paint != nil {
                PaintLayersSection(editor: editor, object: object)
                picture
            } else if editor.colourPaint.preparing.contains(object.id) {
                // Being made ready since it was chosen (U1: no waiting message): its layers take this place in a moment.
                EmptyView()
            } else {
                // Only when making it ready didn't work (the reason was said): try again.
                HmmPillButton("Paint \(object.name)", systemName: "paintbrush.pointed") { editor.preparePaint(object.id) }
                    .accessibilityIdentifier("paint-start")
                Hint("Or start a stroke on it with the Pencil.")
            }
        } else {
            Hint("Tap a shape, a modelled part or a placed model to paint it.")
        }
    }

    private var picture: some View {
        PanelSection("Project a picture") {
            HStack(spacing: HmmSpacing.xs) {
                PhotosPicker(selection: $photo, matching: .images) {
                    Label("Photos", systemImage: "photo")
                }
                .buttonStyle(.bordered)
                Button("Files", systemImage: "folder") { choosingFile = true }
                    .buttonStyle(.bordered)
            }
            Hint("Place it over the model with your fingers, then Project: it lands on what the camera sees.")
        }
    }

    private func load(_ item: PhotosPickerItem?) {
        guard let item else { return }
        Task {
            if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data)?.cgImage { place(image) }
            photo = nil
        }
    }

    /// The picture over the middle of the stage, 60 % of its width.
    private func place(_ image: CGImage) {
        let stage = editor.stage?.bounds.size ?? CGSize(width: 1024, height: 768)
        let width = stage.width * 0.6
        let height = width * CGFloat(image.height) / CGFloat(max(image.width, 1))
        editor.colourPaint.picture = PaintPicture(image: image, rect: CGRect(x: (stage.width - width) / 2, y: (stage.height - height) / 2,
                                                                             width: width, height: height))
        editor.openPanel = nil
    }
}

/// An object's paint layers, top first (U7): what the brush paints (a map, or the layer's mask) and the value it lays,
/// the layers with their maps as badges, swipe for options, drag to reorder, pinch two together to merge them; a fill's
/// own controls; the chosen layer's opacity and blend; adding a layer or a fill.
struct PaintLayersSection: View {
    @Bindable var editor: EditorModel
    let object: SceneObject
    @State private var renaming: (id: String, name: String)?
    @State private var gesture = UUID().uuidString
    @State private var pinch: CGFloat = 1
    @Environment(\.hmmTheme) private var theme

    var body: some View {
        let paint = object.paint
        let current = editor.paintLayer(of: object)
        PanelSection("Layers") {
            if let current { PaintsRow(editor: editor, layer: current) }
            List {
                ForEach((paint?.layers ?? []).reversed()) { layer in
                    row(layer, isCurrent: layer.id == current?.id)
                        .listRowInsets(EdgeInsets(top: 2, leading: 0, bottom: 2, trailing: 0))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .swipeActions(edge: .trailing) { swipes(layer) }
                }
                .onMove { from, to in move(from: from, to: to, count: paint?.layers.count ?? 0) }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .environment(\.editMode, .constant(.inactive))
            .frame(height: min(CGFloat(max(paint?.layers.count ?? 1, 1)) * 52, 260))
            .simultaneousGesture(MagnifyGesture().onChanged { pinch = $0.magnification }.onEnded { _ in
                // Two fingers pinched together over the layers: the chosen one merges into the one under it (Procreate's).
                if pinch < 0.7, let current { editor.mergePaintLayerDown(current.id, of: object.id) }
                pinch = 1
            })
            .accessibilityIdentifier("paint-layers-list")
            if let current {
                if let fill = current.fill { FillControls(editor: editor, object: object, layer: current, fill: fill) }
                LabeledSlider(title: "Layer opacity", value: current.opacity, range: 0 ... 1, format: NumberFormat.percent) { value in
                    editor.updatePaintLayer(current.id, of: object.id, gesture: gesture) { $0.opacity = value }
                }
                FlowChips(items: PaintBlend.allCases.map { ($0.rawValue, $0.title) }, isOn: { $0 == current.blend.rawValue }) { key in
                    guard let blend = PaintBlend(rawValue: key) else { return }
                    editor.updatePaintLayer(current.id, of: object.id) { $0.blend = blend }
                }
                actions(current, paint: paint)
            }
        }
        .alert("Rename layer", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: Binding(get: { renaming?.name ?? "" }, set: { renaming?.name = $0 }))
            Button("Rename") {
                if let renaming { editor.updatePaintLayer(renaming.id, of: object.id) { $0.name = renaming.name } }
                renaming = nil
            }
            Button("Cancel", role: .cancel) { renaming = nil }
        }
    }

    /// The list is top first; the paint is bottom first.
    private func move(from source: IndexSet, to destination: Int, count: Int) {
        guard let from = source.first, let paint = object.paint else { return }
        let layer = paint.layers[count - 1 - from]
        let target = destination > from ? count - destination : count - 1 - destination
        editor.movePaintLayer(layer.id, of: object.id, to: target)
    }

    private func row(_ layer: PaintLayer, isCurrent: Bool) -> some View {
        HStack(spacing: HmmSpacing.xs) {
            Button {
                editor.updatePaintLayer(layer.id, of: object.id) { $0.visible.toggle() }
            } label: {
                Image(systemName: layer.visible ? "eye" : "eye.slash").frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(layer.visible ? "Hide \(layer.name)" : "Show \(layer.name)")
            VStack(alignment: .leading, spacing: 1) {
                Text(layer.name).font(.hmm(.body, weight: isCurrent ? .semibold : .regular)).lineLimit(1)
                MapBadges(layer: layer)
            }
            Spacer(minLength: 0)
            if layer.hasMask {
                Button {
                    editor.choosePaintLayer(layer.id, on: object.id)
                    editor.colourPaint.map = editor.colourPaint.map == .mask && isCurrent ? .color : .mask
                } label: {
                    Image(systemName: "circle.lefthalf.filled").frame(width: 36, height: 44)
                        .foregroundStyle(isCurrent && editor.colourPaint.map == .mask ? theme.accent : theme.text2)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Paint \(layer.name)'s mask")
            }
            if layer.blend != .normal { Text(LocalizedStringKey(layer.blend.title)).font(.hmm(.caption)).foregroundStyle(theme.text2) }
            Text("\(Int((layer.opacity * 100).rounded())) %").font(.hmm(.caption).monospacedDigit()).foregroundStyle(theme.text2)
        }
        .padding(.horizontal, HmmSpacing.xs)
        .background(isCurrent ? theme.accent.opacity(0.18) : theme.surface2, in: RoundedRectangle(cornerRadius: HmmRadius.control, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture {
            editor.choosePaintLayer(layer.id, on: object.id)
            if editor.colourPaint.map == .mask, !layer.hasMask { editor.colourPaint.map = .color }
            gesture = UUID().uuidString
        }
        .hmmHoldMenu(menu(for: layer))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
        .accessibilityIdentifier("paint-layer-\(layer.id)")
    }

    @ViewBuilder private func swipes(_ layer: PaintLayer) -> some View {
        Button(role: .destructive) { editor.deletePaintLayer(layer.id, of: object.id) } label: { Label("Delete", systemImage: "trash") }
        Button { editor.duplicatePaintLayer(layer.id, of: object.id) } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
            .tint(.gray)
        Button { editor.setMask(!layer.hasMask, layer: layer.id, of: object.id) } label: {
            Label(layer.hasMask ? "No mask" : "Mask", systemImage: "circle.lefthalf.filled")
        }
        .tint(theme.accent)
    }

    private func menu(for layer: PaintLayer) -> HmmHoldMenu {
        let isLowest = (object.paint?.layerIndex(layer.id) ?? 0) == 0
        return HmmHoldMenu(duplicate: { editor.duplicatePaintLayer(layer.id, of: object.id) }, rename: { renaming = (layer.id, layer.name) }, extras: [
            HmmHoldMenu.Item(layer.hasMask ? "Remove mask" : "Add a mask", systemName: "circle.lefthalf.filled") {
                editor.setMask(!layer.hasMask, layer: layer.id, of: object.id)
            },
            HmmHoldMenu.Item("Merge down", systemName: "square.3.layers.3d.down.right", isEnabled: !isLowest) {
                editor.mergePaintLayerDown(layer.id, of: object.id)
            },
            HmmHoldMenu.Item("Clear", systemName: "eraser") { editor.clearPaintLayer(layer.id, of: object.id) }
        ], delete: { editor.deletePaintLayer(layer.id, of: object.id) })
    }

    private func actions(_ layer: PaintLayer, paint: ObjectPaint?) -> some View {
        HStack(spacing: HmmSpacing.xs) {
            Menu {
                Button("Layer", systemImage: "square.3.layers.3d") { editor.addPaintLayer(to: object.id) }
                Button("Colour fill", systemImage: "drop.fill") { editor.addFill(.color(editor.paintColor), to: object.id) }
                Button("Dirt", systemImage: "aqi.medium") { editor.addFill(.wear(PaintWear(kind: .dirt)), to: object.id) }
                Button("Worn edges", systemImage: "square.dashed") { editor.addFill(.wear(PaintWear(kind: .edges)), to: object.id) }
            } label: {
                Label("Add", systemImage: "plus").font(.hmm(.body))
            }
            .accessibilityIdentifier("paint-layer-add")
            Spacer(minLength: 0)
            Menu {
                Button("Clear", systemImage: "eraser") { editor.clearPaintLayer(layer.id, of: object.id) }
                Button("Rename", systemImage: "pencil") { renaming = (layer.id, layer.name) }
                Divider()
                Button("Delete layer", systemImage: "trash", role: .destructive) { editor.deletePaintLayer(layer.id, of: object.id) }
                Button("Remove all paint", systemImage: "paintbrush.pointed", role: .destructive) { editor.removePaint(from: object.id) }
            } label: {
                Label("Layer", systemImage: "ellipsis.circle").font(.hmm(.body))
            }
            .accessibilityIdentifier("paint-layer-menu")
        }
    }
}

/// What the brush paints on the chosen layer: Colour, Roughness, Metal, Glow, Bumps, Fur (and Mask when it has one),
/// with the value it lays on a value map.
struct PaintsRow: View {
    @Bindable var editor: EditorModel
    let layer: PaintLayer

    var body: some View {
        let maps = PaintMap.channels + (layer.hasMask ? [.mask] : [])
        VStack(alignment: .leading, spacing: HmmSpacing.xxs) {
            FlowChips(items: maps.map { ($0.rawValue, $0.title) }, isOn: { $0 == editor.paintedMap(of: layer).rawValue }) { key in
                editor.colourPaint.map = PaintMap(rawValue: key) ?? .color
                HmmHaptics.play(.selection)
            }
            .accessibilityIdentifier("paint-map")
            if editor.colourPaint.map.isValue {
                LabeledSlider(title: valueTitle, value: editor.colourPaint.value, range: 0 ... 1, format: NumberFormat.percent) { value in
                    editor.colourPaint.value = value
                }
            } else if editor.colourPaint.map == .mask {
                Hint("Paint shows the layer, erase hides it.")
            }
        }
    }

    private var valueTitle: String {
        switch editor.colourPaint.map {
        case .roughness: "Rough"
        case .metal: "Metal"
        case .bumps: "Height"
        case .fur: "Length"
        default: "Value"
        }
    }
}

/// A layer's maps as small badges.
struct MapBadges: View {
    let layer: PaintLayer
    @Environment(\.hmmTheme) private var theme

    var body: some View {
        let maps = layer.paintedMaps
        if !maps.isEmpty || layer.fill != nil {
            Text(((layer.fill.map { [$0.kindTitle] } ?? []) + maps.map(\.title)).joined(separator: " · "))
                .font(.hmm(.caption))
                .foregroundStyle(theme.text3)
                .lineLimit(1)
        }
    }
}

/// A fill layer's own controls: wear's amount and colour, a material's name.
struct FillControls: View {
    @Bindable var editor: EditorModel
    let object: SceneObject
    let layer: PaintLayer
    let fill: PaintFill
    @State private var amount: Double?

    var body: some View {
        switch fill {
        case let .wear(wear):
            LabeledSlider(title: "Amount", value: amount ?? wear.amount, range: 0 ... 1, format: NumberFormat.percent) { amount = $0 } done: {
                var changed = wear
                changed.amount = amount ?? wear.amount
                editor.changeFill(layer.id, of: object.id, to: .wear(changed))
                amount = nil
            }
        case .color:
            Button("Use the colour in hand", systemImage: "drop.fill") { editor.changeFill(layer.id, of: object.id, to: .color(editor.paintColor)) }
                .buttonStyle(.bordered)
        case let .material(material):
            Hint("\(material.name): change it in the Material Studio, then fill again.")
        }
    }
}

extension PaintFill {
    /// What kind of fill it is, for the layer's badges.
    var kindTitle: String {
        switch self {
        case .color: "Fill"
        case .material: "Material"
        case .wear: "Wear"
        }
    }
}
