import HmmDesign
import LoweyCore
import SwiftUI
import UIKit

/// The Library's pages. Search first, browse second: Things (the characters and the Kit by set) and Yours (your
/// models, builds, worlds and scripts). Tap to place, drag onto the stage, touch and hold for options. While swapping,
/// tapping a model swaps the selection for it.
struct LibraryBrowser: View {
    @Bindable var editor: EditorModel
    let page: LibraryPage
    @State private var query = ""
    @State private var filter: LibraryFilter = .all
    @State private var kitSet: String?
    @State private var expanded: Set<String> = []
    @State private var importing = false
    @State private var editingItem: LibraryItem?
    @State private var editName = ""
    @State private var editTags = ""
    @Environment(\.hmmTheme) private var theme

    private var library: LibraryModel { editor.library }

    var body: some View {
        VStack(alignment: .leading, spacing: HmmSpacing.s) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(theme.text2)
                TextField("Search: tree, desk, robot…", text: $query)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("library-search")
                HmmButton("square.and.arrow.down", label: "Import models", size: 36) { importing = true }
            }
            .padding(.horizontal, HmmSpacing.s)
            .frame(height: 44)
            .background(RoundedRectangle(cornerRadius: HmmRadius.control, style: .continuous).fill(theme.surface2))
            if page == .yours {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: HmmSpacing.xs) {
                        ForEach(isSwapping ? [.models, .favorites, .recent] : Self.yoursFilters, id: \.self) { item in
                            ChoiceChip(title: item.displayName, isOn: filter == item) { filter = item }
                        }
                    }
                }
            }
            if library.importing > 0 {
                Label("Importing \(library.importing)…", systemImage: "arrow.down.circle").font(.hmm(.footnote)).foregroundStyle(theme.text2)
            }
            if page == .motion, !isSwapping {
                MotionBrowser(editor: editor, query: query)
            } else if page == .things, query.isEmpty, !isSwapping {
                GroundsRow(editor: editor)
                HouseKitBrowser(editor: editor)
                MoreSets(editor: editor, selectedSet: $kitSet, expanded: $expanded)
            } else if page == .characters, results.isEmpty {
                if query.isEmpty {
                    CharacterRow(editor: editor)
                    Text("Rigged things you save to the library land here too, with their bones.")
                        .font(.hmm(.footnote)).foregroundStyle(theme.text2)
                } else {
                    HmmEmptyState("figure.stand", title: "No character called “\(query)”",
                                  message: "Make one with New, or rig something and Save to library from its menu.",
                                  actionTitle: "Import models") { importing = true }
                }
            } else if results.isEmpty {
                if page == .yours, query.isEmpty, !isSwapping { YoursSections(editor: editor) }
                HmmEmptyState(query.isEmpty ? "shippingbox" : "questionmark.folder",
                              title: query.isEmpty ? "Your library is empty" : "Nothing called “\(query)” yet",
                              message: "Import USDZ, glTF, GLB or OBJ models (a whole folder works), or build something and Save to library.",
                              actionTitle: "Import models") { importing = true }
            } else {
                if page == .characters, query.isEmpty, !isSwapping { CharacterRow(editor: editor) }
                if page == .yours, query.isEmpty, !isSwapping { YoursSections(editor: editor) }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: HmmSpacing.s)], spacing: HmmSpacing.s) {
                    ForEach(results) { item in
                        LibraryTile(item: item, thumbnail: library.thumbnail(for: item))
                            .onAppear { library.requestThumbnail(for: item) }
                            .onTapGesture {
                                HmmHaptics.play(.commit)
                                editor.place(item)
                            }
                            .accessibilityAddTraits(.isButton)
                            .draggable(item.id)
                            .hmmHoldMenu(menu(for: item))
                    }
                }
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: LibraryModel.importTypes, allowsMultipleSelection: true) { result in
            guard case let .success(chosen) = result else { return }
            // three.js work (a scene file, a project folder or zip, a page) comes into the scene itself; models go to the library.
            for url in chosen where EditorModel.isThreeJSON(url) {
                editor.bringInThreeJSON(url)
            }
            let projects = chosen.filter { !EditorModel.isThreeJSON($0) && EditorModel.isWebProject($0) }
            for url in projects {
                editor.bringInThreeProject(url)
            }
            let urls = chosen.filter { !EditorModel.isThreeJSON($0) && !projects.contains($0) }
            guard !urls.isEmpty else { return }
            Task {
                let count = await library.importFiles(urls)
                editor.app.show(count == 0 ? "No models there (USDZ, glTF, GLB, OBJ)" : "Imported \(count) model\(count == 1 ? "" : "s")")
                if count > 0 {
                    filter = .models
                    editor.libraryPage = .yours
                }
            }
        }
        .alert("Edit", isPresented: Binding(get: { editingItem != nil }, set: { if !$0 { editingItem = nil } })) {
            TextField("Name", text: $editName)
            TextField("Tags, comma separated", text: $editTags)
            Button("Save") {
                if let item = editingItem {
                    library.rename(item, to: editName)
                    library.setTags(item, editTags.split(separator: ",").map(String.init))
                }
                editingItem = nil
            }
            Button("Cancel", role: .cancel) { editingItem = nil }
        }
        .onAppear { if isSwapping { filter = .models } }
    }

    /// Yours: everything but the Kit's sets (those are Things).
    private static let yoursFilters: [LibraryFilter] = [.all, .favorites, .recent, .models, .prefabs, .looks, .scripts]

    private var isSwapping: Bool {
        if case .swap = editor.libraryPurpose { return true }
        return false
    }

    private var results: [LibraryItem] {
        // Searching Things looks through everything, the Kit included.
        var items = LibrarySearch.search(query, in: library.manifest, filter: page == .things || page == .characters ? .all : filter)
        // Characters: everything with a skeleton, the Kit's characters included.
        if page == .characters { return items.filter(LibraryModel.isRigged) }
        // Yours holds your own things; the Kit is on Things (a favourite or a recent Kit model still shows).
        if page == .yours, !isSwapping, filter == .all || filter == .models { items = items.filter { !$0.isKit } }
        guard isSwapping else { return items }
        return items.filter {
            if case .asset = $0 {
                true
            } else {
                false
            }
        }
    }

    private func menu(for item: LibraryItem) -> HmmHoldMenu {
        var extras = [HmmHoldMenu.Item(item.favorite ? "Unfavourite" : "Favourite", systemName: item.favorite ? "star.slash" : "star") {
            library.toggleFavorite(item)
        }]
        if case let .prefab(prefab) = item, !editor.selection.isEmpty, editor.singleSelection?.kind.prefabID != prefab.id {
            extras.append(HmmHoldMenu.Item("Replace with the selection", systemName: "arrow.triangle.2.circlepath") { editor.updatePrefab(prefab.id) })
        }
        return HmmHoldMenu(rename: {
            editName = item.name
            editTags = item.tags.joined(separator: ", ")
            editingItem = item
        }, extras: extras, delete: holdAction(if: !item.isKit) { library.remove(item) })
    }
}

struct LibraryTile: View {
    let item: LibraryItem
    let thumbnail: UIImage?
    @Environment(\.hmmTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: HmmSpacing.xxs) {
            ZStack(alignment: .topTrailing) {
                Group {
                    if let thumbnail {
                        Image(uiImage: thumbnail).resizable().scaledToFill()
                    } else {
                        ZStack {
                            theme.surface2
                            Image(systemName: placeholder).font(.system(size: 28)).foregroundStyle(theme.text3)
                        }
                    }
                }
                .frame(minWidth: 0, maxWidth: .infinity)
                .aspectRatio(1, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: HmmRadius.card, style: .continuous))
                HStack(spacing: 4) {
                    if case let .asset(asset) = item, asset.rig.isRigged { Badge(text: "RIGGED") }
                    if item.favorite { Image(systemName: "star.fill").font(.system(size: 11)).foregroundStyle(theme.accent) }
                }
                .padding(6)
            }
            Text(item.name).font(.hmm(.footnote, weight: .semibold)).lineLimit(2).foregroundStyle(theme.text)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("library-item-\(item.name)")
        .hoverEffect(.lift)
    }

    private var placeholder: String {
        switch item {
        case .asset: "shippingbox"
        case .prefab: "hammer"
        case .look: "paintpalette"
        case .script: "curlybraces"
        }
    }
}
