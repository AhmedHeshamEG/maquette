import HmmDesign
import LoweyCore
import SwiftUI

/// The Library (top left): everything ready to place. **Things**: the characters (a Blob, Me, a Puppet) and the Kit by
/// set. **Motion**: poses, clips and loops to drop on anything with joints. **Rigs**: everything with a skeleton.
/// **Yours**: what you imported, built and saved, your favourites and what you used last. One search across them.
/// Tap to place, drag onto the stage, touch and hold for the item's menu. While swapping a shape for a model, a tap
/// swaps it.
struct LibraryPanel: View {
    @Bindable var editor: EditorModel

    var body: some View {
        HmmPanel(isSwapping ? "Swap for…" : "Library", width: 380, sizing: HmmPanelSizing(id: "library"), movable: true, close: close) {
            VStack(alignment: .leading, spacing: HmmSpacing.m) {
                if !isSwapping { pages }
                LibraryBrowser(editor: editor, page: isSwapping ? .yours : editor.libraryPage)
            }
        }
    }

    private var pages: some View {
        HStack(spacing: HmmSpacing.xs) {
            ForEach(LibraryPage.allCases) { page in
                ChoiceChip(title: page.title, systemName: page.systemImage, isOn: editor.libraryPage == page) {
                    withHmmAnimation(.snappy) { editor.libraryPage = page }
                }
                .accessibilityIdentifier("library-\(page.rawValue)")
            }
        }
    }

    private var isSwapping: Bool {
        if case .swap = editor.libraryPurpose { return true }
        return false
    }

    private func close() {
        editor.openPanel = nil
        editor.libraryPurpose = .place
    }
}

/// Things' first row: the ready-made characters. A Blob is built in its own sheet; Me lands at once; a Puppet is
/// built from parts.
struct CharacterRow: View {
    let editor: EditorModel

    var body: some View {
        PanelSection("Characters") {
            TileGrid {
                TileButton(title: "Blob", systemName: "face.smiling", identifier: "add-blob") { openSheet(.blobBuilder) }
                TileButton(title: "Me", systemName: "person.crop.circle", identifier: "add-me") {
                    editor.openPanel = nil
                    editor.buildBlob(.hesham)
                }
                TileButton(title: "Puppet", systemName: "figure.stand", identifier: "add-character") {
                    editor.characterBuilderTarget = nil
                    openSheet(.characterBuilder)
                }
            }
        }
    }

    private func openSheet(_ sheet: EditorSheet) {
        editor.openPanel = nil
        editor.sheet = sheet
    }
}
