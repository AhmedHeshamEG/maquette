import Foundation
import LoweyCore

/// The Library's Motion page (CONTEXT §10.10: motion is library material): poses, clips and loops kept on this iPad,
/// dropped on anything with joints.
extension LibraryModel {
    func addMotion(_ item: MotionItem) {
        manifest.motions.append(item)
        save()
    }

    func removeMotion(_ id: String) {
        manifest.motions.removeAll { $0.id == id }
        save()
    }

    func renameMotion(_ id: String, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, let index = manifest.motions.firstIndex(where: { $0.id == id }) else { return }
        manifest.motions[index].name = trimmed
        save()
    }

    func toggleFavoriteMotion(_ id: String) {
        guard let index = manifest.motions.firstIndex(where: { $0.id == id }) else { return }
        manifest.motions[index].favorite.toggle()
        save()
    }

    func markMotionUsed(_ id: String) {
        guard let index = manifest.motions.firstIndex(where: { $0.id == id }) else { return }
        manifest.motions[index].lastUsed = Date()
        save()
    }

    /// Motions whose name holds the query (all of them for none), favourites first, then the newest.
    func motions(matching query: String) -> [MotionItem] {
        let words = query.lowercased().split(separator: " ").map(String.init)
        return manifest.motions
            .filter { item in words.allSatisfy { item.name.lowercased().contains($0) || item.kind.title.lowercased().contains($0) } }
            .sorted { lhs, rhs in lhs.favorite != rhs.favorite ? lhs.favorite : (lhs.lastUsed ?? lhs.added) > (rhs.lastUsed ?? rhs.added) }
    }

    /// Whether an item carries a skeleton (the Rigs page): a rigged model, or a saved build with a rig in it.
    static func isRigged(_ item: LibraryItem) -> Bool {
        switch item {
        case let .asset(asset): asset.rig.isRigged
        case let .prefab(prefab): prefab.fragment.objects.contains { $0.rig != nil || $0[.rigStandard] != nil }
        case .look, .script: false
        }
    }
}
