import HmmDesign
import LoweyCore
import SwiftUI
import UniformTypeIdentifiers

/// Library ▸ Yours, the made things (L2, law 12): your Looks, effects and parts, each opened in its Studio from its menu,
/// and packs: share some of Yours as one file, or bring one in. Models, builds and worlds follow in the grid below.
struct YoursSections: View {
    let editor: EditorModel
    @State private var effectStudio: SavedEffect?
    @State private var partStudio: SavedPart?
    @State private var packing = false
    @State private var bringing = false
    @State private var sharing: IdentifiedURL?
    @Environment(\.hmmTheme) private var theme

    private var library: LibraryModel { editor.library }

    static let packTypes: [UTType] = [UTType("studio.h.maquette.pack"), UTType(filenameExtension: ProjectPackage.fileExtension)].compactMap(\.self)

    var body: some View {
        VStack(alignment: .leading, spacing: HmmSpacing.m) {
            HStack(spacing: HmmSpacing.xs) {
                HmmPillButton("Share a pack", systemName: "shippingbox") { packing = true }
                    .accessibilityIdentifier("share-pack")
                HmmPillButton("Bring in a pack", systemName: "square.and.arrow.down") { bringing = true }
                    .accessibilityIdentifier("bring-pack")
            }
            if !library.manifest.styles.isEmpty { looks }
            if !library.manifest.effects.isEmpty { effects }
            if !library.manifest.parts.isEmpty { parts }
        }
        .sheet(item: $effectStudio) { effect in
            NavigationStack { EffectStudioView(editor: editor, id: effect.id) }
        }
        .sheet(item: $partStudio) { part in
            NavigationStack { PartStudioView(editor: editor, id: part.id) }
        }
        .sheet(isPresented: $packing) { NavigationStack { PackSheet(editor: editor) } }
        .sheet(item: $sharing) { ShareSheet(items: [$0.url]) }
        .fileImporter(isPresented: $bringing, allowedContentTypes: Self.packTypes) { result in
            guard case let .success(url) = result else { return }
            editor.app.openPackage(url)
        }
    }

    private var looks: some View {
        PanelSection("Your Looks") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: HmmSpacing.s) {
                    ForEach(library.manifest.styles) { preset in
                        Button {
                            editor.useStyle(preset)
                        } label: {
                            LookCard(preset: preset, selected: editor.look.presetID == preset.id, mood: editor.look.lightingPreset ?? .day)
                        }
                        .buttonStyle(.plain)
                        .hmmHoldMenu(HmmHoldMenu(extras: [share(.look(preset.id), named: preset.name)], delete: { library.removeStyle(preset.id) }))
                    }
                }
            }
        }
    }

    private var effects: some View {
        PanelSection("Effects") {
            TileGrid {
                ForEach(library.manifest.effects) { effect in
                    TileButton(title: effect.name, systemName: effect.recipe.preset.systemImage, identifier: "yours-effect-\(effect.name)") {
                        editor.openPanel = nil
                        editor.addSavedEffect(effect)
                    }
                    .hmmHoldMenu(HmmHoldMenu(extras: [
                        HmmHoldMenu.Item("Open in the Effect Studio", systemName: "slider.horizontal.3") { effectStudio = effect },
                        share(.effect(effect.id), named: effect.name)
                    ], delete: { library.removeEffect(effect.id) }))
                }
            }
        }
    }

    private var parts: some View {
        PanelSection("Parts") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: HmmSpacing.s)], spacing: HmmSpacing.s) {
                ForEach(library.manifest.parts) { part in
                    Button {
                        editor.addSavedPart(part)
                    } label: {
                        VStack(spacing: HmmSpacing.xxs) {
                            ZStack {
                                theme.surface2
                                if let picture = library.partThumbnail(part.id) {
                                    Image(uiImage: picture).resizable().scaledToFill()
                                } else {
                                    Image(systemName: "puzzlepiece").font(.system(size: 22)).foregroundStyle(theme.text3)
                                }
                            }
                            .aspectRatio(1, contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: HmmRadius.card, style: .continuous))
                            Text(part.name).font(.hmm(.caption, weight: .semibold)).lineLimit(2).foregroundStyle(theme.text)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("yours-part-\(part.name)")
                    .hmmHoldMenu(HmmHoldMenu(extras: [
                        HmmHoldMenu.Item("Open in the Part Studio", systemName: "slider.horizontal.3") { partStudio = part },
                        share(.part(part.id), named: part.name)
                    ], delete: { library.removePart(part.id) }))
                }
            }
            Hint("Tap a part with a character selected and it goes on, rigged with the rest.")
        }
    }

    private func share(_ choice: PackChoice, named name: String) -> HmmHoldMenu.Item {
        HmmHoldMenu.Item("Share as a pack", systemName: "square.and.arrow.up") {
            sharing = editor.app.writePack([choice], name: name, author: editor.app.packAuthor, licence: editor.app.packLicence,
                                           looks: editor.document.project.customLooks).map(IdentifiedURL.init)
        }
    }
}
