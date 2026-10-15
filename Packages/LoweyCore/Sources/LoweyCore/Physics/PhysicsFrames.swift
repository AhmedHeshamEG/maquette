import Foundation

/// What a run recorded, frame by frame. Frames are appended while the run goes on (in the background) and read by the
/// stage and exports; each frame is its own small value, so reading never copies the whole run.
public struct PhysicsFrames: Sendable {
    public struct Frame: Sendable {
        /// Per rigid body: world position (3) and rotation (4).
        public var transforms: [Float]
        /// Per rigid body: linear velocity (m/s).
        public var velocities: [Float]
        /// Per ragdoll: each joint's local rotation (4 per joint), then the thing's world transform (7).
        public var ragdolls: [[Float]]
        /// Per breakable thing that has broken: its pieces' world transforms (7 each); empty while whole.
        public var pieces: [[Float]]
        /// Per soft body: its vertices in world space (3 each).
        public var soft: [[Float]]
        /// Per fluid: what it looks like at this frame.
        public var fluids: [FluidLook]
    }

    /// One fluid at one frame, ready to draw.
    public struct FluidLook: Sendable {
        /// Water: its surface, world space.
        public var surface: MeshData?
        /// Smoke and fire: puffs, world space.
        public var puffs: [Particle]
        /// How much of the fluid there is (litres of water, or how much smoke).
        public var amount: Double

        public init(surface: MeshData? = nil, puffs: [Particle] = [], amount: Double = 0) {
            self.surface = surface
            self.puffs = puffs
            self.amount = amount
        }
    }

    public struct Ragdoll: Sendable {
        public var object: ObjectID
        public var joints: [String]
    }

    public struct Breakable: Sendable {
        public var object: ObjectID
        /// Each piece's shape in its own space, around its own centre.
        public var pieces: [EditableMesh]
        /// The frame it broke at (nil while whole).
        public var brokeAt: Int?
    }

    public struct Soft: Sendable {
        public var object: ObjectID
        public var triangles: [UInt32]
        /// The thing's world transform at the start (vertices go back into its own space through it).
        public var start: Transform
    }

    public var key: UInt64
    public var start: Double
    public var fps: Int
    /// How many frames the run will have once it's done.
    public var total: Int
    public var bodies: [ObjectID]
    /// kg per rigid body.
    public var masses: [Double]
    public var ragdolls: [Ragdoll]
    public var breakables: [Breakable]
    public var softs: [Soft]
    public var fluids: [ObjectID]
    public var frames: [Frame]

    public var isComplete: Bool { frames.count >= total }
    /// Seconds simulated so far, from the timeline's start.
    public var reach: Double { start + Double(max(frames.count - 1, 0)) / Double(max(fps, 1)) }

    /// The frame index and blend for a moment (nil before the start or before any frame exists).
    func position(at time: Double) -> (Int, Int, Double)? {
        guard time >= start, !frames.isEmpty else { return nil }
        let exact = (time - start) * Double(fps)
        let lower = min(Int(exact.rounded(.down)), frames.count - 1)
        let upper = min(lower + 1, frames.count - 1)
        return (lower, upper, lower == upper ? 0 : min(max(exact - Double(lower), 0), 1))
    }

    /// A rigid body's world transform at `time` (its scale is the thing's own).
    public func transform(of body: Int, at time: Double) -> (position: Vec3, rotation: Quat)? {
        guard let (lower, upper, blend) = position(at: time), body < bodies.count else { return nil }
        let a = Self.read(frames[lower].transforms, at: body * 7)
        let b = Self.read(frames[upper].transforms, at: body * 7)
        return (a.0.lerp(to: b.0, blend), a.1.slerp(to: b.1, blend).normalized)
    }

    public func velocity(of body: Int, at time: Double) -> Vec3? {
        guard let (lower, _, _) = position(at: time), body < bodies.count else { return nil }
        let values = frames[lower].velocities
        guard values.count >= body * 3 + 3 else { return nil }
        return Vec3(Double(values[body * 3]), Double(values[body * 3 + 1]), Double(values[body * 3 + 2]))
    }

    static func read(_ values: [Float], at offset: Int) -> (Vec3, Quat) {
        guard values.count >= offset + 7 else { return (.zero, .identity) }
        let position = Vec3(Double(values[offset]), Double(values[offset + 1]), Double(values[offset + 2]))
        let rotation = Quat(x: Double(values[offset + 3]), y: Double(values[offset + 4]), z: Double(values[offset + 5]), w: Double(values[offset + 6]))
        return (position, rotation)
    }

    static func write(_ position: Vec3, _ rotation: Quat, into values: inout [Float]) {
        values += [Float(position.x), Float(position.y), Float(position.z), Float(rotation.x), Float(rotation.y), Float(rotation.z), Float(rotation.w)]
    }
}
