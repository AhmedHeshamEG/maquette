import Foundation

/// Clones in glTF (X1): the copies where they stand at the first frame as GPU instances of the thing's mesh
/// (`EXT_mesh_gpu_instancing`, which three.js plays as an `InstancedMesh`), and the recipe in the node's extras, so a round
/// trip through Maquette gives back the layout and its effects.
extension GLTFSceneWriter {
    mutating func addClones(of object: SceneObject, to node: inout [String: Any], extras: inout [String: Any]) {
        guard let clones = object.motionDesign?.clones, node["mesh"] != nil, clones.count > 1 else { return }
        if let data = try? JSONEncoder().encode(clones), let recipe = try? JSONSerialization.jsonObject(with: data) {
            extras["clones"] = recipe
        }
        let places = Self.clonePlaces(of: object, clones: clones, in: scene)
        let translations = places.flatMap { [Float($0.position.x), Float($0.position.y), Float($0.position.z)] }
        let rotations = places.flatMap { [Float($0.rotation.x), Float($0.rotation.y), Float($0.rotation.z), Float($0.rotation.w)] }
        let scales = places.flatMap { [Float($0.scale.x), Float($0.scale.y), Float($0.scale.z)] }
        let attributes = [
            "TRANSLATION": addAccessor(Self.floats(translations), target: nil, count: places.count, type: "VEC3"),
            "ROTATION": addAccessor(Self.floats(rotations), target: nil, count: places.count, type: "VEC4"),
            "SCALE": addAccessor(Self.floats(scales), target: nil, count: places.count, type: "VEC3")
        ]
        var extensions = node["extensions"] as? [String: Any] ?? [:]
        extensions["EXT_mesh_gpu_instancing"] = ["attributes": attributes]
        node["extensions"] = extensions
        extensionsUsed.insert("EXT_mesh_gpu_instancing")
    }

    /// Each copy at the first frame in the thing's own space (the first is the thing: no change).
    static func clonePlaces(of object: SceneObject, clones: ObjectClones, in scene: Scene) -> [Transform] {
        let base = object.transform
        let strength = object[.effectStrength]?.floatValue ?? 1
        let slots = ClonePlayback.slots(clones.layout, count: clones.count, base: base, parent: object.parent, in: scene)
        return slots.enumerated().map { index, slot in
            let place = ClonePlayback.transform(slot: slot, index: index, clones: clones, base: base, moved: base, time: 0, strength: strength)
            return Transform.relative(world: place, toParent: base)
        }
    }
}

extension GLTFSceneReader.Builder {
    /// A node's clones: Maquette's own recipe when the file kept it, else its GPU instances as copies placed against the
    /// first (which the caller makes the thing's own place).
    func clones(of node: [String: Any]) throws -> (clones: ObjectClones, first: Transform)? {
        if let recipe = ((node["extras"] as? [String: Any])?["maquette"] as? [String: Any])?["clones"],
           let data = try? JSONSerialization.data(withJSONObject: recipe), let clones = try? JSONDecoder().decode(ObjectClones.self, from: data) {
            return (clones, .identity)
        }
        guard let attributes = ((node["extensions"] as? [String: Any])?["EXT_mesh_gpu_instancing"] as? [String: Any])?["attributes"]
            as? [String: Any] else { return nil }
        func values(_ name: String, _ components: Int) throws -> [[Double]]? {
            guard let index = attributes[name] as? Int else { return nil }
            let read = try GLTFReader.accessor(file, index)
            guard read.components == components else { return nil }
            return stride(from: 0, to: read.values.count - components + 1, by: components).map { Array(read.values[$0 ..< $0 + components]) }
        }
        let translations = try values("TRANSLATION", 3), rotations = try values("ROTATION", 4), scales = try values("SCALE", 3)
        let count = min([translations?.count, rotations?.count, scales?.count].compactMap { $0 }.min() ?? 0, ObjectClones.maximumCount)
        guard count > 1 else { return nil }
        let places = (0 ..< count).map { index in
            Transform(position: translations.map { Vec3($0[index][0], $0[index][1], $0[index][2]) } ?? .zero,
                      rotation: rotations.map { Quat(x: $0[index][0], y: $0[index][1], z: $0[index][2], w: $0[index][3]).normalized } ?? .identity,
                      scale: scales.map { Vec3($0[index][0], $0[index][1], $0[index][2]) } ?? Vec3(1, 1, 1))
        }
        let first = places[0]
        return (ObjectClones(layout: .placed(places.map { Transform.relative(world: $0, toParent: first) })), first)
    }
}
