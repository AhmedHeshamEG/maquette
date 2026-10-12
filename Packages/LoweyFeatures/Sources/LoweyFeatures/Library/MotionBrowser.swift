import HmmDesign
import LoweyCore
import SwiftUI

/// The Library's Motion page: poses, clips and loops kept on this iPad. Tap one to drop it on the selected thing
/// (a pose turns its joints; a clip or a loop lays its keys at the playhead). Touch and hold to rename, favour or
/// delete. They're saved from a pose's or a row's menu.
struct MotionBrowser: View {
    let editor: EditorModel
    let query: String
    @State private var renaming: MotionItem?
    @State private var name = ""

    var body: some View {
        let items = editor.library.motions(matching: query)
        Group {
            if items.isEmpty {
                HmmEmptyState(
                    "figure.run", title: query.isEmpty ? "No motion yet" : "Nothing called “\(query)” yet",
                    message: "Save a pose, or a row's whole move as a clip or a loop, from its menu (touch and hold). Then drop it on anything with joints."
                )
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: HmmSpacing.s)], spacing: HmmSpacing.s) {
                    ForEach(items) { item in
                        TileButton(title: item.name, systemName: Self.symbol(item.kind), identifier: "motion-\(item.name)") { editor.applyMotion(item) }
                            .hmmHoldMenu(menu(for: item))
                    }
                }
            }
        }
        .alert("Name", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $name)
            Button("Save") {
                if let item = renaming { editor.library.renameMotion(item.id, to: name) }
                renaming = nil
            }
            Button("Cancel", role: .cancel) { renaming = nil }
        }
    }

    static func symbol(_ kind: MotionItem.Kind) -> String {
        switch kind {
        case .pose: "figure.stand"
        case .clip: "film"
        case .loop: "repeat"
        }
    }

    private func menu(for item: MotionItem) -> HmmHoldMenu {
        HmmHoldMenu(rename: {
            name = item.name
            renaming = item
        }, extras: [
            HmmHoldMenu.Item(item.favorite ? "Unfavourite" : "Favourite", systemName: item.favorite ? "star.slash" : "star") {
                editor.library.toggleFavoriteMotion(item.id)
            }
        ], delete: { editor.library.removeMotion(item.id) })
    }
}
