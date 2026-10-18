import Foundation

/// The engine a character is exported for (K1 step 6): its skeleton named the way that engine's humanoid retargeting
/// reads it, everything else the same.
public enum GameEngine: String, CaseIterable, Sendable, Identifiable {
    case godot, unity, unreal

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .godot: "Godot"
        case .unity: "Unity"
        case .unreal: "Unreal"
        }
    }

    /// A joint's name for this engine. Godot's humanoid profile and Unity's Mecanim read "Hips", "LeftUpperArm"…;
    /// Unreal's mannequin reads "pelvis", "upperarm_l"…. Joints outside the humanoid keep their names.
    public func name(of joint: String) -> String {
        switch self {
        case .godot, .unity:
            return joint.prefix(1).uppercased() + joint.dropFirst()
        case .unreal:
            return Self.unrealNames[joint] ?? joint
        }
    }

    static let unrealNames: [String: String] = {
        var names = ["hips": "pelvis", "spine": "spine_01", "chest": "spine_02", "neck": "neck_01", "head": "head"]
        for (side, suffix) in [("left", "l"), ("right", "r")] {
            for (joint, bone) in [("Shoulder", "clavicle"), ("UpperArm", "upperarm"), ("LowerArm", "lowerarm"), ("Hand", "hand"),
                                  ("UpperLeg", "thigh"), ("LowerLeg", "calf"), ("Foot", "foot"), ("Toes", "ball")] {
                names[side + joint] = "\(bone)_\(suffix)"
            }
        }
        return names
    }()
}

/// A made character for a game engine: one skinned character in real metres (each part riding its joint), face states
/// as blend shapes, named clips (its own clips and keys, and for a person the ten humanoid clips), lower-detail copies
/// named `_LOD1` and `_LOD2`, and a collision capsule in the form Godot reads. GLB, which Godot, Unity (glTFast) and
/// Unreal (Interchange) open.
public enum GameCharacterExport {
    public struct Options: Sendable {
        public var engine: GameEngine
        public var lods: Bool
        public var collider: Bool
        /// The ten humanoid clips, when the character is a person.
        public var humanoidClips: Bool

        public init(engine: GameEngine, lods: Bool = true, collider: Bool = true, humanoidClips: Bool = true) {
            self.engine = engine
            self.lods = lods
            self.collider = collider
            self.humanoidClips = humanoidClips
        }
    }

    /// A part's surface in the rig's space, the joint it rides, and its face states as offsets of its corners.
    struct Piece {
        var part: GLTFScene.LocalPart
        var joint: Int
        var targets: [(name: String, offsets: [SIMD3<Float>])]
        var states: CharacterPart?
    }

    /// A clip as frames: each joint's local transform, and each face mesh's state weights.
    struct Clip {
        var name: String
        var times: [Double]
        var poses: [[Transform]]
        var weights: [ObjectID: [[Float]]]
    }

    /// The GLB (nil when the thing has no rig). `parts` gives the shapes Core can't make (placed models).
    public static func glb(_ root: ObjectID, document: Document, options: Options,
                           parts: @escaping (SceneObject) -> [GLTFScene.LocalPart] = { _ in [] }) -> Data? {
        let scene = document.scene
        guard let object = scene.objects[root], let rig = object.rig, !rig.skeleton.isEmpty else { return nil }
        let look = document.effectiveLook
        let pieces = pieces(root, rig: rig, scene: scene, look: look, parts: parts)
        guard !pieces.isEmpty else { return nil }
        var writer = GLTFSceneWriter(scene: scene, look: look, parts: parts)
        let clips = clips(root, rig: rig, document: document, pieces: pieces, options: options)
        guard let node = writer.addGameCharacter(object, rig: rig, pieces: pieces, clips: clips, options: options) else { return nil }
        writer.roots.append(node)
        return writer.finish(generator: "Maquette")
    }

    /// Every surface under the character in the rig's space (the character's own), each riding the joint its piece rides.
    static func pieces(_ root: ObjectID, rig: ObjectRig, scene: Scene, look: Look, parts: (SceneObject) -> [GLTFScene.LocalPart]) -> [Piece] {
        let rootWorld = scene.worldTransform(of: root)
        let first = rig.skeleton.joints.firstIndex { $0.parent == nil } ?? 0
        return scene.subtree(of: root).flatMap { id -> [Piece] in
            guard id != root, let object = scene.objects[id], scene.isEffectivelyVisible(id), object.part?.shows == nil else { return [] }
            let local: [GLTFScene.LocalPart] = if let mesh = SceneExport.localMesh(of: object, look: look), !mesh.isEmpty {
                [GLTFScene.LocalPart(name: object.name, mesh: mesh, material: SceneExport.material(of: object, look: look))]
            } else {
                parts(object)
            }
            let place = Transform.relative(world: scene.worldTransform(of: id), toParent: rootWorld)
            let joint = riding(id, root: root, scene: scene).flatMap(rig.skeleton.index(of:)) ?? first
            return local.map { piece in
                var moved = piece
                moved.mesh = piece.mesh.transformed(place)
                let targets = faceTargets(object, mesh: piece.mesh, place: place)
                return Piece(part: moved, joint: joint, targets: targets, states: targets.isEmpty ? nil : object.part)
            }
        }
    }

    /// The joint a thing rides: its own, or that of the piece of the character it hangs from.
    static func riding(_ id: ObjectID, root: ObjectID, scene: Scene) -> String? {
        var current: ObjectID? = id
        while let at = current, at != root {
            if let bone = scene.objects[at]?[.attachBone]?.stringValue { return bone }
            current = scene.objects[at]?.parent
        }
        return nil
    }

    /// A mouth's or brows' states as blend shapes: each state's bend, as offsets in the rig's space.
    static func faceTargets(_ object: SceneObject, mesh: MeshData, place: Transform) -> [(name: String, offsets: [SIMD3<Float>])] {
        guard let part = object.part, part.job == .mouth || part.job == .brow, let bounds = mesh.bounds else { return [] }
        let base = mesh.transformed(place).positions
        return FaceStates.names(for: part.job).dropFirst().map { state in
            let bent = FaceStates.bend(of: part, state).bend(mesh, bounds: bounds, side: part.side.sign).transformed(place).positions
            return (state, zip(bent, base).map { $0 - $1 })
        }
    }
}
