import HmmDesign
import LoweyCore
import SwiftUI

/// The colour in the hand (U7): hmm-kit's picker (Procreate's disc, values, palettes and the colours used lately) with
/// the scene's palette first and a Materials page. One chooser for Draw ▸ Colour and the sidebar's colour well, so every
/// tool picks colour the same way. A palette slot chosen from the scene's row stays bound to the palette.
struct ColourChooser: View {
    @Bindable var editor: EditorModel

    var body: some View {
        HmmColourPicker(colour: colour, scene: editor.look.palette.swatches.map { HmmColour($0.color) }, extraTitle: "Materials",
                        extraImage: "circle.hexagongrid") {
            MaterialsPage(editor: editor)
        }
    }

    private var colour: Binding<HmmColour> {
        Binding(get: { HmmColour(editor.paintColor) }, set: { value in
            // A swatch of the scene's own palette keeps its slot (so it follows the palette); anything else is a colour.
            let chosen = RGBA(value.red, value.green, value.blue)
            if let slot = editor.look.palette.swatches.firstIndex(where: { HmmColour($0.color) == value }) {
                editor.currentColor = .palette(slot)
            } else {
                editor.currentColor = .rgba(chosen)
            }
        })
    }
}

extension HmmColour {
    init(_ rgba: RGBA) {
        self.init(red: rgba.r, green: rgba.g, blue: rgba.b)
    }
}

/// The sidebar's colour well (CONTEXT §4.1): under the two sliders while a tool that puts colour down is in the hand.
struct SidebarColourWell: View {
    @Bindable var editor: EditorModel

    var body: some View {
        // Opened by the well, or by the Pencil (its squeeze or double-tap).
        HmmColourWell(editor.paintColor.color) { editor.hands.choosingColour = true }
            .popover(isPresented: $editor.hands.choosingColour) {
                ColourPopover(editor: editor)
            }
    }
}

/// The colour picker as a pop-over.
struct ColourPopover: View {
    @Bindable var editor: EditorModel

    var body: some View {
        ScrollView {
            ColourChooser(editor: editor)
                .padding(HmmSpacing.m)
        }
        .frame(width: 340)
        .frame(maxHeight: 620)
        .presentationCompactAdaptation(.popover)
        .accessibilityIdentifier("colour-chooser")
    }
}

/// Materials (U7, D-341): the library as balls. Tap one to fill the thing being painted with it (a new layer); drag one
/// onto any thing; hold for Paint it on (a fill behind an empty mask, the brush painting the mask), the Material Studio,
/// Duplicate and Delete. Import brings a PBR set in.
struct MaterialsPage: View {
    @Bindable var editor: EditorModel
    @State private var importing = false
    @State private var editing: String?

    var body: some View {
        let materials = editor.app.materials
        VStack(alignment: .leading, spacing: HmmSpacing.s) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: HmmSpacing.xs), count: 4), spacing: HmmSpacing.xs) {
                ForEach(materials.all) { material in
                    MaterialBall(materials: materials, material: material)
                        .onTapGesture { editor.addFill(.material(material)) }
                        .draggable(MaterialDrop.prefix + material.id)
                        .hmmHoldMenu(menu(material))
                        .accessibilityAddTraits(.isButton)
                        .accessibilityHint(Text("Fills the thing being painted"))
                }
            }
            HStack(spacing: HmmSpacing.xs) {
                Button("New", systemImage: "plus") { editing = materials.makeNew() }
                    .buttonStyle(.bordered)
                Button("Import a set", systemImage: "square.and.arrow.down") { importing = true }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("material-import")
            }
            Hint("Tap to fill, drag onto any thing, hold for more. Import takes the pictures of a PBR set (colour, roughness, normal…).")
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.image], allowsMultipleSelection: true) { result in
            guard case let .success(urls) = result else { return }
            Task {
                if let made = await editor.app.materials.importSet(urls) {
                    editor.app.show("Imported \(made.name)")
                } else {
                    editor.app.show("None of those pictures is named like a map (basecolor, roughness, normal…)", kind: .error)
                }
            }
        }
        .sheet(item: Binding(get: { editing.map(MaterialEditing.init) }, set: { editing = $0?.id })) { item in
            MaterialStudioView(materials: editor.app.materials, id: item.id) { editor.addFill(.material($0)) }
        }
    }

    private func menu(_ material: PaintMaterial) -> HmmHoldMenu {
        let materials = editor.app.materials
        return HmmHoldMenu(duplicate: { editing = materials.duplicate(material.id) }, rename: nil, extras: [
            HmmHoldMenu.Item("Paint it on", systemName: "paintbrush.pointed") { editor.addFill(.material(material), masked: true) },
            HmmHoldMenu.Item("Edit", systemName: "slider.horizontal.3") { editing = material.id }
        ], delete: materials.library.isBuiltIn(material.id) && materials.library.materials[material.id] == nil ? nil : {
            materials.delete(material.id)
        })
    }
}

/// A material's id as the sheet's item.
struct MaterialEditing: Identifiable {
    let id: String
}

/// What a material dragged onto the stage carries: its id behind a prefix (a plain colour carries its hex).
enum MaterialDrop {
    static let prefix = "maquette-material:"
}

/// A material's ball and name.
struct MaterialBall: View {
    let materials: MaterialModel
    let material: PaintMaterial
    @State private var image: CGImage?
    @Environment(\.hmmTheme) private var theme

    var body: some View {
        VStack(spacing: 2) {
            Group {
                if let image {
                    Image(decorative: image, scale: 2)
                } else {
                    Circle().fill(material.color.color).padding(6)
                }
            }
            .frame(width: 48, height: 48)
            Text(material.name).font(.hmm(.caption)).lineLimit(1).foregroundStyle(theme.text2)
        }
        .frame(minWidth: HmmTarget.minimum, minHeight: HmmTarget.minimum)
        .contentShape(Rectangle())
        .task(id: "\(material.id) \(materials.revision)") { image = await materials.preview(material) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(material.name))
        .accessibilityIdentifier("material-\(material.id)")
    }
}
