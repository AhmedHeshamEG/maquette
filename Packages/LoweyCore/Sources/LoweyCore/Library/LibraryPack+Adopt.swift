import Foundation
import HmmDocuments

public extension LibraryPack {
    /// What a pack brought, for the app to file: its brushes go into a new set named after the pack; pictures and
    /// models are written into their stores first, by these keys.
    struct Adopted: Sendable {
        public var brushSet: (id: String, name: String, brushes: [Brush])?
        public var brushPictures: [String: Data] = [:]
        public var materialPictures: [String: Data] = [:]
        /// A thing's models, by their place in the library (`assets/<id>/<file>`).
        public var assetFiles: [String: Data] = [:]
        /// How many things came in, by kind.
        public var counts: [LibraryKind: Int] = [:]

        public var total: Int { counts.values.reduce(0, +) }
    }

    /// Takes a pack's things into this iPad's libraries (Yours): a fresh id wherever one is taken, pictures filed under
    /// what they are, models that are already here left as they are, and where each came from kept beside it.
    static func adopt(_ contents: Contents, into library: inout LibraryManifest, brushes: inout BrushLibrary, materials: inout MaterialLibrary,
                      newID: () -> String) -> Adopted {
        var adopted = Adopted()
        var newBrushes: [Brush] = []
        for entry in contents.entries {
            var id = entry.item.id
            switch entry.item {
            case var .brush(brush):
                if brushes.brush(brush.id) != nil { brush.id = newID() }
                brush.about.origin = .shared
                brush.shape.source = refiled(brush.shape.source, contents: contents, into: &adopted.brushPictures)
                brush.grain.source = brush.grain.source.map { refiled($0, contents: contents, into: &adopted.brushPictures) }
                newBrushes.append(brush)
                id = brush.id
            case var .material(material):
                if materials.material(material.id) != nil { material.id = newID() }
                material.pictures = material.pictures.map { refiled($0, contents: contents, into: &adopted.materialPictures) }
                materials.update(material)
                id = material.id
            case var .look(look):
                if library.style(look.id) != nil || LookPreset.builtIns.contains(where: { $0.id == look.id }) { look.id = newID() }
                library.styles.insert(look, at: 0)
                id = look.id
            case var .effect(effect):
                if library.effect(effect.id) != nil { effect.id = newID() }
                library.effects.insert(effect, at: 0)
                id = effect.id
            case var .part(part):
                if library.part(part.id) != nil { part.id = newID() }
                library.parts.insert(part, at: 0)
                id = part.id
            case var .motion(motion):
                if library.motions.contains(where: { $0.id == motion.id }) { motion.id = newID() }
                library.motions.insert(motion, at: 0)
                id = motion.id
            case .thing(var prefab, let assets):
                if library.prefab(prefab.id) != nil { prefab.id = PrefabID(raw: newID()) }
                for asset in assets where asset.kit == nil && library.asset(asset.id) == nil {
                    library.assets.append(asset)
                    let folder = "\(LibraryStore.assetsFolder)/\(asset.id.raw)/"
                    for (key, data) in contents.files where key.hasPrefix(folder) {
                        adopted.assetFiles[key] = data
                    }
                }
                library.prefabs.insert(prefab, at: 0)
                id = prefab.id.raw
            }
            library.origins[entry.item.kind.key(id)] = entry.origin
            adopted.counts[entry.item.kind, default: 0] += 1
        }
        if !newBrushes.isEmpty {
            let set = (id: newID(), name: contents.manifest.name, brushes: newBrushes)
            brushes.add(newBrushes, toSet: set.id, named: set.name)
            adopted.brushSet = set
        }
        return adopted
    }

    /// A brush picture filed under what it is (its content), so a name that doesn't match never misleads.
    private static func refiled(_ source: BrushImageSource, contents: Contents, into pictures: inout [String: Data]) -> BrushImageSource {
        guard case let .image(key) = source, let data = contents.files[key] else { return source }
        let filed = BrushKey.imageKey(for: data)
        pictures[filed] = data
        return .image(filed)
    }

    private static func refiled(_ set: MaterialPictures, contents: Contents, into pictures: inout [String: Data]) -> MaterialPictures {
        func file(_ key: String?) -> String? {
            guard let key, let data = contents.files[key] else { return key }
            let filed = MaterialLibraryStore.imageKey(for: data)
            pictures[filed] = data
            return filed
        }
        return MaterialPictures(color: file(set.color), roughness: file(set.roughness), metal: file(set.metal), height: file(set.height),
                                normal: file(set.normal), glow: file(set.glow), occlusion: file(set.occlusion))
    }
}
