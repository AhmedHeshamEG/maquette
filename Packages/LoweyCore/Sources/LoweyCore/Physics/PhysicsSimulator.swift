import Foundation

/// Runs one `PhysicsInput` frame by frame: rigid bodies, joints and mechanisms, ragdolls, cloth and jelly, things that
/// break, forces and wind, and fluids. Deterministic: the same input gives the same frames on every device, so the stage
/// (which plays a run while it's being made) and an export (which waits for all of it) agree.
public final class PhysicsSimulator {
    public let input: PhysicsInput
    public private(set) var frames: PhysicsFrames
    let world: PhysicsWorld
    let dt: Double
    let substeps: Int
    var frame = 0

    struct Rigid {
        var id: ObjectID
        var body: Int32
        /// The body's origin in the thing's turned frame (scaled), so the thing's place is the body's minus it.
        var offset: Vec3
        var mass: Double
        /// Area the air pushes on (m²).
        var area: Double
        var breakable: Int?
        var lastVelocity: Vec3 = .zero
    }

    struct RagdollPart {
        var joint: Int
        var body: Int32
        /// The joint's world transform is the body's times this.
        var jointFromBody: Transform
        var mass: Double
    }

    struct RagdollState {
        var id: ObjectID
        var skeleton: Skeleton
        var parts: [RagdollPart]
        /// Model-space start pose of every joint (unscaled) and the thing's start world transform.
        var model: [Transform]
        var world: Transform
    }

    struct SoftState {
        var id: ObjectID
        var body: Int32
        var count: Int
    }

    struct BreakState {
        var rigid: Int
        var centres: [Vec3]
        var pieces: [MeshData]
        var bodies: [Int32] = []
        var threshold: Double
        var bounce: Double
        var friction: Double
        var density: Double
    }

    var rigids: [Rigid] = []
    var ragdolls: [RagdollState] = []
    var softs: [SoftState] = []
    var breaks: [BreakState] = []
    var liquids: [LiquidSolver] = []
    var smokes: [SmokeSolver] = []
    /// Fluids in their order of `input.fluids`: a liquid or smoke index.
    var fluidSlots: [(liquid: Int?, smoke: Int?)] = []

    public init?(_ input: PhysicsInput) {
        guard let world = PhysicsWorld(capacity: input.bodies.count * 24 + 64, gravity: input.settings.acceleration) else { return nil }
        self.input = input
        self.world = world
        dt = 1 / Double(input.fps)
        substeps = max(1, Int((60 / Double(input.fps)).rounded(.up)))
        frames = PhysicsFrames(key: input.key, start: input.start, fps: input.fps, total: input.frameCount, bodies: [], masses: [], ragdolls: [],
                               breakables: [], softs: [], fluids: input.fluids, frames: [])
        addGround()
        for id in input.bodies {
            addThing(id)
        }
        addJoints()
        addFluids()
        frames.bodies = rigids.map(\.id)
        frames.masses = rigids.map(\.mass)
        frames.ragdolls = ragdolls.map { PhysicsFrames.Ragdoll(object: $0.id, joints: $0.skeleton.names) }
        frames.breakables = breaks.map { state in
            PhysicsFrames.Breakable(object: rigids[state.rigid].id, pieces: state.pieces.map(Self.storable), brokeAt: nil)
        }
        frames.softs = softs.map { soft in
            PhysicsFrames.Soft(object: soft.id, triangles: softTriangles[soft.id] ?? [], start: input.scene.worldTransform(of: soft.id))
        }
        record()
    }

    var softTriangles: [ObjectID: [UInt32]] = [:]

    /// A piece as a shape that saves exactly as it is (project files keep corners to the nanometre).
    static func storable(_ mesh: MeshData) -> EditableMesh {
        let positions = mesh.positions.map { Vec3($0).map(EditableMesh.rounded) }
        let triangles = stride(from: 0, to: mesh.indices.count - 2, by: 3).map {
            (Int(mesh.indices[$0]), Int(mesh.indices[$0 + 1]), Int(mesh.indices[$0 + 2]))
        }
        return MeshBuilder.mesh(positions: positions, triangles: triangles)
    }

    /// The whole run at once (exports, tests).
    public static func run(_ input: PhysicsInput) -> PhysicsFrames? {
        guard let simulator = PhysicsSimulator(input) else { return nil }
        while simulator.step() {}
        return simulator.frames
    }

    /// Simulates the next frame and records it; false once the run is complete.
    @discardableResult
    public func step() -> Bool {
        guard frames.frames.count < frames.total else { return false }
        frame += 1
        let time = input.start + Double(frame) * dt
        applyForces(at: time)
        moveFollowers()
        world.step(dt, substeps: substeps)
        breakWhatBroke()
        stepFluids(at: time)
        record()
        return frames.frames.count < frames.total
    }

    private func addGround() {
        guard input.settings.ground else { return }
        let material = input.settings.groundMaterial
        _ = world.add(PhysicsWorld.BodySpec(shape: BodyShape(kind: .box(half: Vec3(500, 1, 500))), position: Vec3(0, -1, 0), rotation: .identity,
                                            motion: .stays, density: material.density, friction: material.friction, bounce: material.bounce))
    }

    /// Records the current state as the next frame.
    func record() {
        var transforms: [Float] = []
        var velocities: [Float] = []
        transforms.reserveCapacity(rigids.count * 7)
        for rigid in rigids {
            let (position, rotation) = world.transform(of: rigid.body)
            PhysicsFrames.write(position - rotation.act(rigid.offset), rotation, into: &transforms)
            let velocity = world.velocity(of: rigid.body).linear
            velocities += [Float(velocity.x), Float(velocity.y), Float(velocity.z)]
        }
        let pieces = breaks.map { state -> [Float] in
            var values: [Float] = []
            for body in state.bodies {
                let (position, rotation) = world.transform(of: body)
                PhysicsFrames.write(position, rotation, into: &values)
            }
            return values
        }
        let soft = softs.map { world.softVertices(of: $0.body, count: $0.count) }
        frames.frames.append(PhysicsFrames.Frame(transforms: transforms, velocities: velocities, ragdolls: ragdolls.map(ragdollFrame),
                                                 pieces: pieces, soft: soft, fluids: fluidLooks()))
        for index in breaks.indices where frames.breakables[index].brokeAt == nil && !breaks[index].bodies.isEmpty {
            frames.breakables[index].brokeAt = frames.frames.count - 1
        }
    }

    /// Things that follow their keys go where the keys put them by the end of this step.
    private func moveFollowers() {
        for rigid in rigids {
            guard let path = input.paths[rigid.id], !path.isEmpty else { continue }
            let target = path[min(frame, path.count - 1)]
            world.moveKinematic(rigid.body, to: target.position + target.rotation.act(rigid.offset), rotation: target.rotation, dt: dt)
        }
    }

    /// The place of a force at this frame (fans can be keyed).
    func place(of force: ObjectID) -> Transform {
        if let path = input.paths[force], !path.isEmpty { return path[min(frame, path.count - 1)] }
        return input.scene.worldTransform(of: force)
    }
}
