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
        // Parents first: a joint's parent is the nearest joint above it.
        let parentOf = Self.parents(file)
        let jointOf = Dictionary(joints.enumerated().map { ($1, $0) }) { first, _ in first }
        func parentJoint(_ joint: Int) -> Int? {
            var node = parentOf[joints[joint]]
            while let above = node {
                if let index = jointOf[above] { return index }
                node = parentOf[above]
            }
            return nil
        }
        var order: [Int] = []
        var placed = Set<Int>()
        func place(_ joint: Int, depth: Int) {
            guard !placed.contains(joint), depth < 256 else { return }
            if let parent = parentJoint(joint) { place(parent, depth: depth + 1) }
            placed.insert(joint)
            order.append(joint)
        }
        joints.indices.forEach { place($0, depth: 0) }
        let newIndex = Dictionary(order.enumerated().map { ($1, $0) }) { first, _ in first }
        var used: Set<String> = []
        let skeletonJoints = order.map { joint -> Joint in
            var name = GLTFReader.nodeName(nodes[joints[joint]], index: joints[joint])
            while used.contains(name) {
                name += " \(joint)"
            }
            used.insert(name)
            let parent = parentJoint(joint)
            let rest = parent.map { Transform.relative(world: binds[joint], toParent: binds[$0]) } ?? binds[joint]
            return Joint(name: name, parent: parent.flatMap { newIndex[$0] }, rest: rest)
        }
        // The bind pose's space: what holds the topmost joint.
        var top = joints[order[0]]
        while let above = parentOf[top], jointOf[above] != nil {
            top = above
        }
        return SkinRig(skeleton: Skeleton(joints: skeletonJoints), order: order.map { joints[$0] }, remap: joints.indices.map { newIndex[$0] ?? 0 },
                       space: parentOf[top])
    }

    /// The rig on a skinned piece: the skeleton, and the file's weights carried onto the surface the app draws.
    mutating func rig(_ object: inout SceneObject, skin: SkinRig, source: ImportedPart) {
        let joints = source.joints, weights = source.weights, remap = skin.remap
        guard joints.count == source.mesh.positions.count, weights.count == joints.count else { return }
        object.rig = ObjectRig(skeleton: skin.skeleton)
        // Faces made whole again are too big to bend: cut them finer at the bones, as drawing a rig does.
        if let base = PaintSource.unshaped(of: object),
           let cuts = MeshDensify.cuts(for: base, bones: ObjectRig(skeleton: skin.skeleton).segments.map { ($0.head, $0.tail) }) {
            object[.bendDetail] = .float(Double(cuts))
        }
        guard let surface = PaintSource.unshaped(of: object), !surface.isEmpty, let bounds = source.mesh.bounds else { return }
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
        let stored = RigOperations.stored(result, in: ObjectRig(skeleton: skin.skeleton), object: object, mesh: surface)
        object.rig = stored.rig
        files.merge(stored.files) { first, _ in first }
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
