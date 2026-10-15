import Foundation

/// Everything one run needs, as values: the scene as it stands when things start to move, the meshes of the real
/// things, the paths of what follows its keys, and the frames to fill. Two inputs with the same `key` simulate to the
/// same frames, which is how the stage and an export agree and how a run is reused.
public struct PhysicsInput: Sendable {
    public var scene: Scene
    public var settings: ScenePhysics
    /// The local mesh of every real thing (a group's parts by their own ids), fluids' colliders included.
    public var meshes: [ObjectID: MeshData]
    /// Rigged real things: the skeleton and its pose at the start (ragdolls).
    public var skeletons: [ObjectID: Skeleton]
    public var startPoses: [ObjectID: [Transform]]
    /// World transforms, one per frame, of things that follow their keys and of forces (fans move).
    public var paths: [ObjectID: [Transform]]
    public var fps: Int
    public var start: Double
    public var frameCount: Int
    public var key: UInt64

    /// The things that take part, top-most first (a real group's parts ride inside it).
    public var bodies: [ObjectID] { Self.realThings(in: scene) }

    public var forces: [ObjectID] { scene.orderedIDs().filter {
        if case .force = scene.objects[$0]?.kind {
            true
        } else {
            false
        }
    } }
    public var fluids: [ObjectID] { scene.orderedIDs().filter {
        if case .fluid = scene.objects[$0]?.kind {
            true
        } else {
            false
        }
    } }

    /// Real things whose ancestors aren't real, in outliner order.
    public static func realThings(in scene: Scene) -> [ObjectID] {
        scene.orderedIDs().filter { id in
            guard scene.objects[id]?.physics != nil else { return false }
            var parent = scene.objects[id]?.parent
            while let current = parent {
                if scene.objects[current]?.physics != nil { return false }
                parent = scene.objects[current]?.parent
            }
            return true
        }
    }

    /// Does this scene simulate anything?
    public static func hasPhysics(_ scene: Scene) -> Bool {
        scene.objects.values.contains { object in
            if object.physics != nil { return true }
            if case .fluid = object.kind { return true }
            return false
        }
    }

    /// The input for `document`, or nil when nothing in it is real. `mesh` gives a thing's local mesh (the stage's
    /// loaded models included); `skeleton` a rigged thing's skeleton.
    public static func make(_ document: Document, mesh: (SceneObject) -> MeshData?, skeleton: (SceneObject) -> Skeleton? = { $0.rig?.skeleton },
                            rigs: [AssetID: RigAsset] = [:]) -> PhysicsInput? {
        guard hasPhysics(document.scene) else { return nil }
        let settings = document.scene.physics ?? ScenePhysics()
        let timeline = document.scene.timeline
        let fps = max(timeline.fps, 1)
        let start = min(max(settings.start, 0), timeline.duration)
        let frameCount = max(Int(((timeline.duration - start) * Double(fps)).rounded(.up)), 1) + 1
        let startState = Animator.evaluate(document, at: start, rigs: rigs)
        let scene = startState.scene
        let found = sources(of: startState, mesh: mesh, skeleton: skeleton)
        let paths = paths(in: document, scene: scene, start: start, fps: fps, frameCount: frameCount)
        var input = PhysicsInput(scene: scene, settings: settings, meshes: found.meshes, skeletons: found.skeletons, startPoses: found.poses,
                                 paths: paths, fps: fps, start: start, frameCount: frameCount, key: 0)
        input.key = input.fingerprint()
        return input
    }

    /// The meshes of real things and fluids' surroundings, and rigged real things' skeletons and start poses.
    static func sources(of state: AnimatedScene, mesh: (SceneObject) -> MeshData?, skeleton: (SceneObject) -> Skeleton?)
        -> (meshes: [ObjectID: MeshData], skeletons: [ObjectID: Skeleton], poses: [ObjectID: [Transform]]) {
        let scene = state.scene
        var meshes: [ObjectID: MeshData] = [:]
        var skeletons: [ObjectID: Skeleton] = [:]
        var poses: [ObjectID: [Transform]] = [:]
        for id in realThings(in: scene) + scene.objects.keys.filter({ isFluid(scene.objects[$0]) }) {
            for part in scene.subtree(of: id) {
                guard let object = scene.objects[part], let local = mesh(object), !local.isEmpty else { continue }
                meshes[part] = local
            }
            guard let object = scene.objects[id], let bones = skeleton(object), bones.joints.count > 1 else { continue }
            skeletons[id] = bones
            poses[id] = state.poses[id] ?? object.rig.map { RigPoses.posed($0.skeleton.restPose, skeleton: $0.skeleton, by: object) } ?? bones.restPose
        }
        // Fluids also meet things that aren't real (a glass on a table that never moves).
        let hasFluids = scene.objects.values.contains { isFluid($0) }
        for id in scene.orderedIDs() where hasFluids && meshes[id] == nil {
            guard let object = scene.objects[id], object.kind.hasSurface, scene.isEffectivelyVisible(id), let local = mesh(object) else { continue }
            meshes[id] = local
        }
        return (meshes, skeletons, poses)
    }

    /// World transforms per frame of what follows its keys and of keyed forces.
    static func paths(in document: Document, scene: Scene, start: Double, fps: Int, frameCount: Int) -> [ObjectID: [Transform]] {
        let timeline = document.scene.timeline
        let moving = scene.orderedIDs().filter { id in
            guard let object = scene.objects[id] else { return false }
            if object.physics?.motion == .follows { return true }
            if case .force = object.kind { return timeline.tracks.contains { $0.target == id } }
            return false
        }
        guard !moving.isEmpty else { return [:] }
        var paths: [ObjectID: [Transform]] = [:]
        for frame in 0 ..< frameCount {
            let keyed = Animator.keyedScene(document, at: start + Double(frame) / Double(fps))
            for id in moving {
                paths[id, default: []].append(keyed.worldTransform(of: id))
            }
        }
        return paths
    }

    static func isFluid(_ object: SceneObject?) -> Bool {
        if case .fluid = object?.kind { return true }
        return false
    }

    /// A stable fingerprint (the same on every device and every launch) of what decides the run.
    func fingerprint() -> UInt64 {
        var hasher = StableHasher()
        hasher.add("physics-v1")
        hasher.add(Double(fps))
        hasher.add(start)
        hasher.add(Double(frameCount))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        if let data = try? encoder.encode(settings) { hasher.add(data) }
        for id in bodies + forces + fluids {
            for part in scene.subtree(of: id) {
                guard let object = scene.objects[part] else { continue }
                hasher.add(part.raw)
                if let data = try? encoder.encode(Snapshot(object: object, world: scene.worldTransform(of: part))) { hasher.add(data) }
            }
        }
        addMeshesAndPaths(to: &hasher)
        return hasher.value
    }

    private func addMeshesAndPaths(to hasher: inout StableHasher) {
        for id in meshes.keys.sorted() {
            hasher.add(id.raw)
            guard let mesh = meshes[id] else { continue }
            hasher.add(Double(mesh.positions.count))
            for position in mesh.positions {
                hasher.add(position)
            }
            for index in mesh.indices {
                hasher.add(UInt64(index))
            }
            hasher.add(scene.worldTransform(of: id))
        }
        for id in paths.keys.sorted() {
            for transform in paths[id] ?? [] {
                hasher.add(transform)
            }
        }
        for id in startPoses.keys.sorted() {
            for transform in startPoses[id] ?? [] {
                hasher.add(transform)
            }
        }
    }

    private struct Snapshot: Encodable {
        var object: SceneObject
        var world: Transform
    }
}

/// FNV-1a over bytes: stable across launches and devices (Swift's `Hasher` is seeded per launch).
struct StableHasher {
    private(set) var value: UInt64 = 0xCBF2_9CE4_8422_2325

    mutating func add(_ bytes: some Sequence<UInt8>) {
        for byte in bytes {
            value ^= UInt64(byte)
            value &*= 0x0000_0100_0000_01B3
        }
    }

    mutating func add(_ text: String) { add(Array(text.utf8)) }
    mutating func add(_ data: Data) { add(Array(data)) }
    mutating func add(_ number: UInt64) { withUnsafeBytes(of: number.littleEndian) { add($0) } }
    mutating func add(_ number: Double) { add(number.bitPattern) }
    mutating func add(_ vector: SIMD3<Float>) {
        add(UInt64(vector.x.bitPattern))
        add(UInt64(vector.y.bitPattern))
        add(UInt64(vector.z.bitPattern))
    }

    mutating func add(_ transform: Transform) {
        for value in [transform.position.x, transform.position.y, transform.position.z, transform.rotation.x, transform.rotation.y,
                      transform.rotation.z, transform.rotation.w, transform.scale.x, transform.scale.y, transform.scale.z] {
            add(value)
        }
    }
}
