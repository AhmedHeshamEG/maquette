import Foundation

/// three.js skins in (X1): a `SkinnedMesh` comes in rigged as a glTF's does (`SkinImport`). Its skeleton's bones in the
/// bind pose (their inverses, seen from the mesh through its bind matrix), the geometry's `skinIndex` and `skinWeight`
/// carried onto the surface, and the bones' `quaternion` tracks as `bone.` keys. Bones aren't things.
extension ThreeReaderBuilder {
    /// Every object's parent, by uuid, and the bones.
    static func tree(_ json: [String: Any]) -> (parents: [String: String], bones: Set<String>, names: [String: String]) {
        var parents: [String: String] = [:], bones = Set<String>(), names: [String: String] = [:]
        func walk(_ object: [String: Any], parent: String?) {
            let uuid = object["uuid"] as? String ?? ""
            if let parent { parents[uuid] = parent }
            if object["type"] as? String == "Bone" { bones.insert(uuid) }
            names[uuid] = object["name"] as? String ?? ""
            for child in object["children"] as? [[String: Any]] ?? [] {
                walk(child, parent: uuid)
            }
        }
        if let root = json["object"] as? [String: Any] { walk(root, parent: nil) }
        return (parents, bones, names)
    }

    /// Rigs a skinned mesh from its skeleton; false when the file doesn't hold one it can read.
    mutating func skin(_ object: inout SceneObject, source: [String: Any]) -> Bool {
        guard let skeletonID = source["skeleton"] as? String, let skeleton = Self.byUUID(json["skeletons"])[skeletonID],
              let bones = skeleton["bones"] as? [String], !bones.isEmpty, let geometryID = source["geometry"] as? String,
              let data = geometries[geometryID]?["data"] as? [String: Any], let mesh = buffer(data) else { return false }
        let attributes = data["attributes"] as? [String: Any] ?? [:]
        guard let indices = GLTFReader.numbers((attributes["skinIndex"] as? [String: Any])?["array"]),
              let amounts = GLTFReader.numbers((attributes["skinWeight"] as? [String: Any])?["array"]),
              indices.count >= mesh.positions.count * 4, amounts.count >= mesh.positions.count * 4 else { return false }
        let inverses = (skeleton["boneInverses"] as? [Any] ?? []).map { GLTFReader.numbers($0) ?? [] }
        let bind = GLTFReader.decompose(GLTFReader.numbers(source["bindMatrix"]) ?? ThreeMatrix.identity)
        let binds = bones.indices.map { index -> Transform in
            let world = index < inverses.count && inverses[index].count == 16
                ? Transform.relative(world: .identity, toParent: GLTFReader.decompose(inverses[index])) : .identity
            return Transform.relative(world: world, toParent: bind)
        }
        let boneIndex = Dictionary(bones.enumerated().map { ($1, $0) }) { first, _ in first }
        let parents = bones.map { bone -> Int? in
            var above = tree.parents[bone]
            while let next = above {
                if let index = boneIndex[next] { return index }
                above = tree.parents[next]
            }
            return nil
        }
        let names = bones.enumerated().map { index, bone in tree.names[bone].flatMap { $0.isEmpty ? nil : $0 } ?? "Bone \(index + 1)" }
        let (rig, remap) = SkinImport.skeleton(names: names, parents: parents, binds: binds)
        let count = mesh.positions.count
        let part = ImportedPart(name: object.name, mesh: mesh, material: 0,
                                joints: (0 ..< count).map { vertex in SIMD4<UInt16>((0 ..< 4).map { UInt16(clamping: Int(indices[vertex * 4 + $0])) }) },
                                weights: (0 ..< count).map { vertex in SIMD4<Float>((0 ..< 4).map { Float(amounts[vertex * 4 + $0]) }) })
        files.merge(SkinImport.rig(&object, skeleton: rig, remap: remap, source: part)) { first, _ in first }
        for (index, bone) in bones.enumerated() {
            let owner = (object: object.id, joint: rig.joints[remap[index]].name)
            boneTargets[bone, default: []].append(owner)
            if let name = tree.names[bone], !name.isEmpty { boneTargets[name, default: []].append(owner) }
        }
        return true
    }

    /// A bone's `quaternion` track as `bone.` keys on each thing it moves (nil when the track isn't a bone's).
    func boneTracks(_ source: [String: Any], ids: inout IDFactory) -> [Track]? {
        guard let name = source["name"] as? String, let dot = name.lastIndex(of: "."), let owners = boneTargets[String(name[..<dot])] else { return nil }
        guard name[name.index(after: dot)...] == "quaternion", let times = GLTFReader.numbers(source["times"]),
              let values = GLTFReader.numbers(source["values"]) else { return [] }
        let easing: Easing = source["interpolation"] as? Int == 2300 ? .step : .linear
        let keys = times.enumerated().compactMap { index, time -> Keyframe? in
            guard index * 4 + 4 <= values.count else { return nil }
            let turn = Quat(x: values[index * 4], y: values[index * 4 + 1], z: values[index * 4 + 2], w: values[index * 4 + 3]).normalized
            return Keyframe(time: time, value: .quat(turn), easing: easing)
        }
        guard !keys.isEmpty else { return [] }
        return owners.map { Track(id: ids.next(), target: $0.object, property: .boneTurn($0.joint), keyframes: keys) }
    }
}
