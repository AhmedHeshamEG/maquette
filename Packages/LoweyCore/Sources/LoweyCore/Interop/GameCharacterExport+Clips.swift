import Foundation

/// Named clips for a game character: what its own timeline does with it (its keys, its clips, its lip sync), each clip
/// placed on it, and for a person the ten humanoid clips. Each is sampled through the Animator at the timeline's frame
/// rate, so an engine plays what the stage shows.
extension GameCharacterExport {
    static func clips(_ root: ObjectID, rig: ObjectRig, document: Document, pieces: [Piece], options: Options) -> [Clip] {
        let fps = Double(max(document.scene.timeline.fps, 1))
        var result: [Clip] = []
        let timeline = document.scene.timeline
        // Its own animation on the timeline: keys on it (turns, lip sync) and its clips, as one "Timeline" clip.
        let keyed = timeline.tracks.filter { $0.target == root && ($0.property.boneJoint != nil || $0.property == .mouthShape || $0.property == .mouth) }
        let ranges = keyed.compactMap(\.timeRange) + timeline.clipTracks.filter { $0.target == root }.flatMap { $0.segments.map { TimeRange(
            start: $0.start,
            end: $0.end
        ) } }
        if let start = ranges.map(\.start).min(), let end = ranges.map(\.end).max(), end - start > 1e-3 {
            result.append(sample("Timeline", root: root, rig: rig, document: document, pieces: pieces, from: start, to: end, fps: fps))
        }
        if options.humanoidClips, rig.standard == .humanoid {
            for name in BuiltinClips.names {
                guard let clip = BuiltinClips.rig.clips[name] else { continue }
                var playing = document
                let segment = ClipSegment(id: "export", clip: ClipRef(asset: BuiltinClips.assetID, name: name), start: 0, duration: clip.duration,
                                          loop: false, blend: 0)
                playing.scene.timeline.tracks.removeAll { $0.target == root }
                playing.scene.timeline.clipTracks = [ClipTrack(id: "export", target: root, segments: [segment])]
                result.append(sample(name, root: root, rig: rig, document: playing, pieces: pieces, from: 0, to: clip.duration, fps: fps))
            }
        }
        return result
    }

    /// One clip, frame by frame.
    static func sample(_ name: String, root: ObjectID, rig: ObjectRig, document: Document, pieces: [Piece], from start: Double, to end: Double,
                       fps: Double) -> Clip {
        let frames = max(Int(((end - start) * fps).rounded(.up)), 1)
        var clip = Clip(name: name, times: [], poses: [], weights: [:])
        let faces = pieces.enumerated().filter { !$0.element.targets.isEmpty }
        for frame in 0 ... frames {
            let time = min(start + Double(frame) / fps, end)
            let shown = Animator.evaluate(document, at: time)
            let pose = shown.poses[root] ?? RigPoses.posed(
                rig.skeleton.restPose,
                skeleton: rig.skeleton,
                by: shown.scene.objects[root] ?? SceneObject(id: root, name: "", kind: .group)
            )
            clip.times.append(time - start)
            clip.poses.append(pose.count == rig.skeleton.joints.count ? pose : rig.skeleton.restPose)
            guard let character = shown.scene.objects[root] else { continue }
            for (index, piece) in faces {
                guard let part = piece.states else { continue }
                let state = FaceStates.active(part, values: { character[$0] }).state
                let weights = piece.targets.map { $0.name == state ? Float(1) : 0 }
                clip.weights[ObjectID(raw: "\(index)"), default: []].append(weights)
            }
        }
        return clip
    }
}

/// Writing a game character: a top node in real metres, the rig's joints (named for the engine), one skinned mesh for the
/// body (and its lower-detail copies), one per face part with its blend shapes, the clips as animations, the capsule.
extension GLTFSceneWriter {
    mutating func addGameCharacter(_ object: SceneObject, rig: ObjectRig, pieces: [GameCharacterExport.Piece], clips: [GameCharacterExport.Clip],
                                   options: GameCharacterExport.Options) -> Int? {
        let name = object.name.isEmpty ? "Character" : object.name
        let scale = scene.worldTransform(of: object.id).scale
        let top = nodes.count
        nodes.append(["name": name, "scale": [scale.x, scale.y, scale.z], "extras": ["maquette": "character"]])
        let (joints, jointNodes) = addGameJoints(rig, engine: options.engine)
        let matrices = addAccessor(Self.floats(joints.modelRest.flatMap { GLTFMeshReader.columnMajor(Self.inverse($0)) }), target: nil,
                                   count: joints.joints.count, type: "MAT4")
        skins.append(["name": "\(name) skin", "joints": jointNodes, "inverseBindMatrices": matrices])
        let skin = skins.count - 1
        var meshNodes: [Int] = []
        let body = pieces.filter(\.targets.isEmpty)
        let shift = rig.skeleton.joints.count == joints.joints.count ? 0 : 1
        meshNodes.append(addRigidMesh(body, name: options.lods ? "\(name)_LOD0" : name, skin: skin, jointShift: shift))
        if options.lods {
            for (level, share) in [(1, 0.5), (2, 0.25)] {
                let lighter = body.map { piece -> GameCharacterExport.Piece in
                    var copy = piece
                    let target = max(Int(Double(piece.part.mesh.triangleCount) * share), 8)
                    copy.part.mesh = MeshSimplify.simplified(piece.part.mesh, target: target).mesh
                    return copy
                }
                meshNodes.append(addRigidMesh(lighter, name: "\(name)_LOD\(level)", skin: skin, jointShift: shift))
            }
        }
        var faceNodes: [Int] = []
        for piece in pieces where !piece.targets.isEmpty {
            faceNodes.append(addRigidMesh([piece], name: piece.part.name, skin: skin, jointShift: shift))
            meshNodes.append(faceNodes[faceNodes.count - 1])
        }
        let rootJoints = joints.joints.indices.filter { joints.joints[$0].parent == nil }.map { jointNodes[$0] }
        var children = meshNodes + rootJoints
        if options.collider, let capsule = addCapsule(pieces, name: name) { children.append(capsule) }
        nodes[top]["children"] = children
        addClips(clips, jointNodes: jointNodes, faceNodes: faceNodes, shift: shift)
        return top
    }

    /// The joints, named for the engine; Unreal's skeletons start from a `root` bone on the ground.
    mutating func addGameJoints(_ rig: ObjectRig, engine: GameEngine) -> (Skeleton, [Int]) {
        var skeleton = rig.skeleton
        if engine == .unreal, rig.standard == .humanoid, skeleton.index(of: RigMarks.rootName) == nil {
            let shifted = skeleton.joints.map { joint in
                Joint(name: joint.name, parent: joint.parent.map { $0 + 1 } ?? 0, rest: joint.rest)
            }
            skeleton = Skeleton(joints: [Joint(name: RigMarks.rootName, parent: nil, rest: .identity)] + shifted)
        }
        var made: [Int] = []
        for joint in skeleton.joints {
            made.append(nodes.count)
            let rest = joint.rest
            nodes.append(["name": engine.name(of: joint.name), "translation": [rest.position.x, rest.position.y, rest.position.z],
                          "rotation": [rest.rotation.x, rest.rotation.y, rest.rotation.z, rest.rotation.w]])
        }
        for (index, joint) in skeleton.joints.enumerated() {
            guard let parent = joint.parent else { continue }
            nodes[made[parent]]["children"] = (nodes[made[parent]]["children"] as? [Int] ?? []) + [made[index]]
        }
        return (skeleton, made)
    }

    /// One skinned mesh of rigid pieces: every corner of a piece follows its joint fully. Its blend shapes, if any, are
    /// named in `extras.targetNames` (what Godot, Unity and Unreal read).
    mutating func addRigidMesh(_ pieces: [GameCharacterExport.Piece], name: String, skin: Int, jointShift: Int) -> Int {
        let primitives = pieces.map { piece -> [String: Any] in
            var attributes = attributes(piece.part.mesh, colors: piece.part.colors)
            let count = piece.part.mesh.positions.count
            let joint = UInt16(piece.joint + jointShift)
            attributes["JOINTS_0"] = addAccessor(Self.shorts(Array(repeating: [joint, 0, 0, 0], count: count).flatMap(\.self)), target: Self.arrayBuffer,
                                                 componentType: Self.unsignedShort, count: count, type: "VEC4")
            attributes["WEIGHTS_0"] = addAccessor(Self.floats(Array(repeating: [Float(1), 0, 0, 0], count: count).flatMap(\.self)),
                                                  target: Self.arrayBuffer, count: count, type: "VEC4")
            var primitive: [String: Any] = ["attributes": attributes, "indices": indices(piece.part.mesh), "material": addMaterial(piece.part)]
            if !piece.targets.isEmpty {
                primitive["targets"] = piece.targets.map { target -> [String: Int] in
                    let flat = target.offsets.flatMap { [$0.x, $0.y, $0.z] }
                    let lows = (0 ..< 3).map { axis in target.offsets.map { $0[axis] }.min() ?? 0 }
                    let highs = (0 ..< 3).map { axis in target.offsets.map { $0[axis] }.max() ?? 0 }
                    return ["POSITION": addAccessor(Self.floats(flat), target: Self.arrayBuffer, count: target.offsets.count, type: "VEC3",
                                                    extra: ["min": lows, "max": highs])]
                }
            }
            return primitive
        }
        var mesh: [String: Any] = ["name": name, "primitives": primitives]
        if let names = pieces.first(where: { !$0.targets.isEmpty })?.targets.map(\.name) {
            mesh["extras"] = ["targetNames": names]
            mesh["weights"] = names.map { _ in 0.0 }
        }
        meshes.append(mesh)
        nodes.append(["name": name, "mesh": meshes.count - 1, "skin": skin])
        return nodes.count - 1
    }

    /// A capsule around the whole character standing, as an OMI collider (a character body for Godot).
    mutating func addCapsule(_ pieces: [GameCharacterExport.Piece], name: String) -> Int? {
        let points = pieces.flatMap { $0.part.mesh.positions.map { Vec3($0) } }
        guard let bounds = Bounds(points: points), bounds.size.y > 1e-3 else { return nil }
        let radius = max(bounds.size.x, bounds.size.z) / 2 * 0.9
        physicsShapes.append(["type": "capsule", "capsule": ["radius": radius, "height": max(bounds.size.y, radius * 2)]])
        let centre = bounds.center
        nodes.append(["name": "\(name)_collider", "translation": [centre.x, centre.y, centre.z],
                      "extensions": ["OMI_physics_body": ["collider": ["shape": physicsShapes.count - 1]]]])
        return nodes.count - 1
    }

    /// Each clip as an animation named after it: the joints' turns (and the first joint's travel), the face's weights.
    mutating func addClips(_ clips: [GameCharacterExport.Clip], jointNodes: [Int], faceNodes: [Int], shift: Int) {
        for clip in clips where clip.times.count > 1 {
            var samplers: [[String: Any]] = []
            var channels: [[String: Any]] = []
            let input = addAccessor(Self.floats(clip.times.map(Float.init)), target: nil, count: clip.times.count, type: "SCALAR",
                                    extra: ["min": [clip.times.first ?? 0], "max": [clip.times.last ?? 0]])
            let jointCount = clip.poses.first?.count ?? 0
            for joint in 0 ..< jointCount where joint + shift < jointNodes.count {
                var previous: Quat?
                let values = clip.poses.flatMap { pose -> [Float] in
                    var turn = pose[joint].rotation.normalized
                    if let before = previous, before.dot(turn) < 0 { turn = Quat(x: -turn.x, y: -turn.y, z: -turn.z, w: -turn.w) }
                    previous = turn
                    return [Float(turn.x), Float(turn.y), Float(turn.z), Float(turn.w)]
                }
                samplers.append(["input": input, "output": addAccessor(Self.floats(values), target: nil, count: clip.times.count, type: "VEC4"),
                                 "interpolation": "LINEAR"])
                channels.append(["sampler": samplers.count - 1, "target": ["node": jointNodes[joint + shift], "path": "rotation"]])
                if joint == 0 {
                    let places = clip.poses.flatMap { [Float($0[0].position.x), Float($0[0].position.y), Float($0[0].position.z)] }
                    samplers.append(["input": input, "output": addAccessor(Self.floats(places), target: nil, count: clip.times.count, type: "VEC3"),
                                     "interpolation": "LINEAR"])
                    channels.append(["sampler": samplers.count - 1, "target": ["node": jointNodes[shift], "path": "translation"]])
                }
            }
            for (index, node) in faceNodes.enumerated() {
                guard let weights = clip.weights[ObjectID(raw: "\(faceIndex(index, in: clip))")], weights.count == clip.times.count else { continue }
                samplers.append(["input": input, "output": addAccessor(Self.floats(weights.flatMap(\.self)), target: nil,
                                                                       count: weights.flatMap(\.self).count, type: "SCALAR"),
                                 "interpolation": "STEP"])
                channels.append(["sampler": samplers.count - 1, "target": ["node": node, "path": "weights"]])
            }
            animations.append(["name": clip.name, "samplers": samplers, "channels": channels])
        }
    }

    /// The key a face mesh's weights are kept under in a clip (the order the face pieces came in).
    func faceIndex(_ order: Int, in clip: GameCharacterExport.Clip) -> Int {
        clip.weights.keys.compactMap { Int($0.raw) }.sorted()[safe: order] ?? order
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
