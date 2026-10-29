import HmmDesign
import LoweyCore
import SwiftUI
import UIKit

/// Things opens on the house kit (CONTEXT §10.9, Q2): Maquette's own things by category, tap to place; the free CC0
/// packs wait behind More sets.
struct HouseKitBrowser: View {
    @Bindable var editor: EditorModel
    @State private var category: HouseKit.Category = .home

    private var library: LibraryModel { editor.library }

    var body: some View {
        VStack(alignment: .leading, spacing: HmmSpacing.s) {
            FlowChips(items: HouseKit.Category.allCases.map { ($0.rawValue, $0.title) }, isOn: { $0 == category.rawValue }) { raw in
                if let chosen = HouseKit.Category(rawValue: raw) { category = chosen }
            }
            .accessibilityIdentifier("house-kit-categories")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 88), spacing: HmmSpacing.s)], spacing: HmmSpacing.s) {
                ForEach(HouseKit.items(in: category)) { item in
                    HouseKitTile(item: item, thumbnail: library.houseThumbnail(item))
                        .onAppear { library.requestHouseThumbnail(item) }
                        .onTapGesture {
                            HmmHaptics.play(.commit)
                            editor.placeHouseKit(item)
                        }
                        .accessibilityAddTraits(.isButton)
                        .draggable(item.libraryID)
                }
            }
        }
    }
}

/// One of the house kit's things: its picture and its name.
struct HouseKitTile: View {
    let item: HouseKit.Item
    let thumbnail: UIImage?
    @Environment(\.hmmTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: HmmSpacing.xxs) {
            Group {
                if let thumbnail {
                    Image(uiImage: thumbnail).resizable().scaledToFill()
                } else {
                    ZStack {
                        theme.surface2
                        Image(systemName: "cube").font(.system(size: 28)).foregroundStyle(theme.text3)
                    }
                }
            }
            .frame(minWidth: 0, maxWidth: .infinity)
            .aspectRatio(1, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: HmmRadius.card, style: .continuous))
            Text(LocalizedStringKey(item.title)).font(.hmm(.footnote, weight: .semibold)).lineLimit(2).foregroundStyle(theme.text)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("house-kit-\(item.rawValue)")
        .hoverEffect(.lift)
    }
}

/// The CC0 packs, folded under More sets once the house kit leads.
struct MoreSets: View {
    @Bindable var editor: EditorModel
    @Binding var selectedSet: String?
    @Binding var expanded: Set<String>
    @State private var open = false

    var body: some View {
        VStack(alignment: .leading, spacing: HmmSpacing.s) {
            Group {
                if open {
                    HmmPillButton("Fewer sets", systemName: "chevron.up") { open.toggle() }
                } else {
                    HmmPillButton("More sets", systemName: "chevron.down") { open.toggle() }
                }
            }
            .accessibilityIdentifier("more-sets")
            if open {
                KitBrowser(editor: editor, selectedSet: $selectedSet, expanded: $expanded)
            }
        }
    }
}

extension EditorModel {
    /// Places a house kit thing where the view looks (or where it's dropped), selected, as one undo step.
    func placeHouseKit(_ item: HouseKit.Item, at screenPoint: CGPoint? = nil) {
        var fragment = HouseKit.build(item)
        guard !fragment.objects.isEmpty else { return }
        fragment.objects[0].name = ObjectFactory.uniqueName(item.title, in: scene)
        var transform = fragment.objects[0].transform
        transform.position = dropPoint(at: screenPoint)
        fragment.objects[0].transform = transform
        let root = fragment.objects[0].id
        guard perform(.insert(fragment, parent: nil, index: nil)) else { return }
        select(root)
        if AppIdentity.isUITesting { trail("placed=\(item.rawValue)") }
    }
}
