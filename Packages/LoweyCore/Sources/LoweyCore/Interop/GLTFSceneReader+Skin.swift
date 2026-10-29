import Foundation

/// Skins in (X1): a skinned mesh comes in as a rigged thing. Its joints become the rig's skeleton in the bind pose (from
/// the inverse bind matrices, parents first), the file's weights are carried onto the editable surface by the closest
/// point, and its joints' turns come back as `bone.` keys. The joint nodes themselves aren't things.
extension GLTFSceneReader.Builder {
    /// A skin read as a rig: the skeleton, its joints' nodes in its order, each of the file's joint numbers in it, and the
    /// node whose space the bind pose is in.
    struct SkinRig {
        var skeleton: Skeleton
        var order: [Int]
        var remap: [Int]
        var space: Int?
    }

    /// Every node that is a joint of some skin.
    static func jointNodes(_ file: GLTFReader.File) -> Set<Int> {
        Set(file.array("skins").flatMap { $0["joints"] as? [Int] ?? [] })
    }

    static func parents(_ file: GLTFReader.File) -> [Int: Int] {
        var parentOf: [Int: Int] = [:]
        for (index, node) in file.array("nodes").enumerated() {
            for child in node["children"] as? [Int] ?? [] {
                parentOf[child] = index
            }
        }
        return parentOf
    }

    func skinRig(_ skinIndex: Int) throws -> SkinRig? {
        let skins = file.array("skins"), nodes = file.array("nodes")
        guard skins.indices.contains(skinIndex), let joints = skins[skinIndex]["joints"] as? [Int], !joints.isEmpty,
              joints.allSatisfy(nodes.indices.contains) else { return nil }
        var binds = [Transform](repeating: .identity, count: joints.count)
        if let accessor = skins[skinIndex]["inverseBindMatrices"] as? Int {
            let values = try GLTFReader.accessor(file, accessor).values
            for joint in joints.indices where joint * 16 + 15 < values.count {
                let inverse = GLTFReader.decompose(Array(values[joint * 16 ..< joint * 16 + 16]))
                binds[joint] = Transform.relative(world: .identity, toParent: inverse)
            }
        }
        // A joint's parent is the nearest joint above it.
        let parentOf = Self.parents(file)
        let jointOf = Dictionary(joints.enumerated().map { ($1, $0) }) { first, _ in first }
        let parents = joints.map { node -> Int? in
            var above = parentOf[node]
            while let next = above {
                if let index = jointOf[next] { return index }
                above = parentOf[next]
            }
            return nil
        }
        let names = joints.map { GLTFReader.nodeName(nodes[$0], index: $0) }
        let (skeleton, remap) = SkinImport.skeleton(names: names, parents: parents, binds: binds)
        let order = joints.indices.sorted { remap[$0] < remap[$1] }
        // The bind pose's space: what holds the topmost joint.
        var top = joints[order.first ?? 0]
        while let above = parentOf[top], jointOf[above] != nil {
            top = above
        }
        return SkinRig(skeleton: skeleton, order: order.map { joints[$0] }, remap: remap, space: parentOf[top])
    }

    /// The rig on a skinned piece: the skeleton, and the file's weights carried onto the surface the app draws.
    mutating func rig(_ object: inout SceneObject, skin: SkinRig, source: ImportedPart) {
        files.merge(SkinImport.rig(&object, skeleton: skin.skeleton, remap: skin.remap, source: source)) { first, _ in first }
    }

    /// A joint's turns as `bone.` keys on each thing its skin moves (nil when the channel isn't a joint's turn). A joint's
    /// moves and sizes aren't Maquette's (its bones keep their length) and are left out.
    func boneTracks(_ channel: [String: Any], samplers: [[String: Any]], ids: inout IDFactory) throws -> (tracks: [Track], end: Double)? {
        guard let target = channel["target"] as? [String: Any], let node = target["node"] as? Int, let owners = boneTargets[node] else { return nil }
        guard target["path"] as? String == "rotation", let samplerIndex = channel["sampler"] as? Int, samplers.indices.contains(samplerIndex),
              let input = samplers[samplerIndex]["input"] as? Int, let output = samplers[samplerIndex]["output"] as? Int else { return ([], 0) }
        let times = try GLTFReader.accessor(file, input).values
        let (values, components, _) = try GLTFReader.accessor(file, output)
        let interpolation = samplers[samplerIndex]["interpolation"] as? String ?? "LINEAR"
        let cubic = interpolation == "CUBICSPLINE"
        let easing: Easing = interpolation == "STEP" ? .step : cubic ? .easeInOut : .linear
        guard components == 4 else { return ([], 0) }
        var keys: [Keyframe] = []
        for (index, time) in times.enumerated() {
            let base = (cubic ? index * 3 + 1 : index) * 4
            guard base + 4 <= values.count else { break }
            let turn = Quat(x: values[base], y: values[base + 1], z: values[base + 2], w: values[base + 3]).normalized
            keys.append(Keyframe(time: time, value: .quat(turn), easing: easing))
        }
        guard !keys.isEmpty else { return ([], 0) }
        let tracks = owners.map { Track(id: ids.next(), target: $0.object, property: .boneTurn($0.joint), keyframes: keys) }
        return (tracks, times.last ?? 0)
    }

    /// A skinned mesh node: the thing stands where the bind pose's space is, and each piece carries the rig.
    mutating func dressSkinned(_ object: inout SceneObject, mesh: Int, skin: SkinRig, index: Int, ids: inout IDFactory) throws -> [ObjectID] {
        var children: [ObjectID] = []
        // Skinned: the bind pose's space is where the thing stands; each piece carries the rig.
        let parentWorld = parentOf[index].flatMap { globals[$0] } ?? .identity
        object.transform = Transform.relative(world: skin.space.flatMap { globals[$0] } ?? .identity, toParent: parentWorld)
        let pieces = try meshPieces(mesh, skinned: true)
        for piece in pieces {
            var target = object
            if pieces.count > 1 {
                target = SceneObject(id: ids.next(), name: piece.name, kind: .mesh(piece.mesh), parent: object.id)
            } else {
                target.kind = .mesh(piece.mesh)
            }
            apply(piece.material, to: &target)
            rig(&target, skin: skin, source: piece.part)
            objectsOfMaterial[piece.index, default: []].append(target.id)
            for (joint, node) in skin.order.enumerated() {
                boneTargets[node, default: []].append((target.id, skin.skeleton.joints[joint].name))
            }
            if pieces.count > 1 {
                objects.append(target)
                children.append(target.id)
            } else {
                object = target
            }
        }
        return children
    }
}

/// What every skin reader shares: a skeleton from joints in any order, and a file's weights carried onto a thing.
enum SkinImport {
    /// The joints parents first, each at its bind place against its parent's (names made unique), and where each of the
    /// given joints went.
    static func skeleton(names: [String], parents: [Int?], binds: [Transform]) -> (Skeleton, remap: [Int]) {
        var order: [Int] = []
        var placed = Set<Int>()
        func place(_ joint: Int, depth: Int) {
            guard !placed.contains(joint), depth < 256 else { return }
            if let parent = parents[joint] { place(parent, depth: depth + 1) }
            placed.insert(joint)
            order.append(joint)
        }
        names.indices.forEach { place($0, depth: 0) }
        var remap = [Int](repeating: 0, count: names.count)
        for (index, joint) in order.enumerated() {
            remap[joint] = index
        }
        var used: Set<String> = []
        let joints = order.map { joint -> Joint in
            var name = names[joint].isEmpty ? "Joint" : names[joint]
            while used.contains(name) {
                name += " \(joint)"
            }
            used.insert(name)
            let parent = parents[joint]
            let rest = parent.map { Transform.relative(world: binds[joint], toParent: binds[$0]) } ?? binds[joint]
            return Joint(name: name, parent: parent.map { remap[$0] }, rest: rest)
        }
        return (Skeleton(joints: joints), remap)
    }

    /// Rigs `object` with `skeleton` and carries the source's weights (its joint numbers through `remap`) onto the
    /// surface the app draws, by the closest point; cut finer at the bones first, as drawing a rig does. The `.skin`
    /// file it needs comes back.
    static func rig(_ object: inout SceneObject, skeleton: Skeleton, remap: [Int], source: ImportedPart) -> [String: Data] {
        let joints = source.joints, weights = source.weights
        guard joints.count == source.mesh.positions.count, weights.count == joints.count else { return [:] }
        object.rig = ObjectRig(skeleton: skeleton)
        if let base = PaintSource.unshaped(of: object),
           let cuts = MeshDensify.cuts(for: base, bones: ObjectRig(skeleton: skeleton).segments.map { ($0.head, $0.tail) }) {
            object[.bendDetail] = .float(Double(cuts))
        }
        guard let surface = PaintSource.unshaped(of: object), !surface.isEmpty, let bounds = source.mesh.bounds else { return [:] }
        let grid = TriangleGrid(source.mesh, cell: Float(max(bounds.size.length * 0.02, 1e-4)))
        var hint: Int?
        var result = SkinWeights()
        for position in surface.positions {
            var pairs: [(joint: Int, weight: Double)] = []
            if let hit = grid.closest(to: position, within: grid.cell * 2, hint: hint) {
                hint = hit.triangle
                for corner in 0 ..< 3 {
                    let vertex = Int(source.mesh.indices[hit.triangle * 3 + corner])
                    for slot in 0 ..< 4 where weights[vertex][slot] > 0 {
                        let joint = Int(joints[vertex][slot])
                        pairs.append((remap.indices.contains(joint) ? remap[joint] : 0, Double(weights[vertex][slot] * hit.weights[corner])))
                    }
                }
            }
            let (influence, amounts) = SkinWeights.influence(pairs)
            result.joints.append(influence)
            result.weights.append(amounts)
        }
        let stored = RigOperations.stored(result, in: ObjectRig(skeleton: skeleton), object: object, mesh: surface)
        object.rig = stored.rig
        return stored.files
    }
}
