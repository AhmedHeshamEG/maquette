import Foundation
import HmmDocuments
import LoweyCore
import UIKit

/// Yours (L2, law 12): the Looks, effects and parts you made or were given, on this iPad for every project. Each keeps
/// where it came from when it arrived in a pack.
extension LibraryModel {
    // MARK: Your Looks

    /// Keeps a Look in Yours (a fresh id when one is taken) and returns it as kept.
    @discardableResult
    func saveStyle(_ preset: LookPreset) -> LookPreset {
        var kept = preset
        if manifest.style(kept.id) != nil || kept.isBuiltIn { kept.id = "yours-\(UUID().uuidString.prefix(8).lowercased())" }
        manifest.styles.insert(kept, at: 0)
        save()
        return kept
    }

    func updateStyle(_ preset: LookPreset) {
        guard let index = manifest.styles.firstIndex(where: { $0.id == preset.id }) else { return }
        manifest.styles[index] = preset
        save()
    }

    func removeStyle(_ id: String) {
        manifest.styles.removeAll { $0.id == id }
        manifest.origins[LibraryKind.look.key(id)] = nil
        save()
    }

    // MARK: Effects

    /// Keeps a particle effect in Yours under `name`.
    @discardableResult
    func saveEffect(name: String, recipe: ParticleRecipe) -> SavedEffect {
        let effect = SavedEffect(id: UUID().uuidString.lowercased(), name: name, recipe: recipe)
        manifest.effects.insert(effect, at: 0)
        save()
        return effect
    }

    func updateEffect(_ effect: SavedEffect) {
        guard let index = manifest.effects.firstIndex(where: { $0.id == effect.id }) else { return }
        manifest.effects[index] = effect
        save()
    }

    func removeEffect(_ id: String) {
        manifest.effects.removeAll { $0.id == id }
        manifest.origins[LibraryKind.effect.key(id)] = nil
        save()
    }

    // MARK: Parts

    static func partThumbnailName(_ id: String) -> String { "part-\(id).png" }

    /// Keeps a character part in Yours, with its picture.
    @discardableResult
    func savePart(name: String, job: CharacterPart.Job, fragment: SceneFragment) async -> SavedPart {
        let part = SavedPart(id: UUID().uuidString.lowercased(), name: name, job: job, fragment: fragment)
        manifest.parts.insert(part, at: 0)
        save()
        await renderThumbnail(of: fragment, named: Self.partThumbnailName(part.id))
        return part
    }

    func updatePart(_ part: SavedPart) {
        guard let index = manifest.parts.firstIndex(where: { $0.id == part.id }) else { return }
        manifest.parts[index] = part
        save()
    }

    func removePart(_ id: String) {
        manifest.parts.removeAll { $0.id == id }
        manifest.origins[LibraryKind.part.key(id)] = nil
        try? FileManager.default.removeItem(at: store.thumbnailURL(named: Self.partThumbnailName(id)))
        save()
    }

    func partThumbnail(_ id: String) -> UIImage? {
        if let cached = thumbnails[Self.partThumbnailName(id)] { return cached }
        return UIImage(contentsOfFile: store.thumbnailURL(named: Self.partThumbnailName(id)).path)
    }

    // MARK: Where things came from

    func origin(_ kind: LibraryKind, _ id: String) -> HmmPackOrigin? {
        manifest.origin(kind, id)
    }

    /// Takes a pack's things in (the brushes and materials go to their own libraries, by the app), keeping their origins.
    func adopt(_ adopted: LibraryManifest, assetFiles: [String: Data]) {
        for (key, data) in assetFiles {
            let url = store.root.appendingPathComponent(key)
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: url, options: .atomic)
        }
        replaceManifest(adopted)
    }
}
