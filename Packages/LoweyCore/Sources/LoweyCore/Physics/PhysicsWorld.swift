import Foundation
import JoltCpp

/// One Jolt world, owned by one simulation on one thread. Swift values in, Swift values out; bodies are numbered in
/// the order they were added.
final class PhysicsWorld {
    private let world: OpaquePointer

    struct BodySpec {
        var shape: BodyShape
        var position: Vec3
        var rotation: Quat
        var motion: ObjectPhysics.Motion
        var density: Double
        var mass: Double?
        var friction: Double
        var bounce: Double
        var linearVelocity: Vec3 = .zero
        var angularVelocity: Vec3 = .zero
        var linearDamping: Double = 0.02
        var angularDamping: Double = 0.05
        var group: UInt32 = 0
        var sleeps = true
    }

    init?(capacity: Int, gravity: Double) {
        guard let world = JBWorldCreate(Int32(min(max(capacity, 16), 65000))) else { return nil }
        self.world = world
        JBWorldSetGravity(world, 0, Float(-gravity), 0)
    }

    deinit { JBWorldDestroy(world) }

    var lastError: String { String(cString: JBWorldLastError(world)) }

    func add(_ spec: BodySpec) -> Int32? {
        var desc = JBBodyDesc()
        desc.position = Self.triple(spec.position)
        desc.rotation = Self.quad(spec.rotation)
        desc.motion = switch spec.motion {
        case .falls: JBMotionDynamic
        case .stays: JBMotionStatic
        case .follows: JBMotionKinematic
        }
        desc.density = Float(max(spec.density, 1e-3))
        desc.mass = Float(spec.mass ?? 0)
        desc.friction = Float(spec.friction)
        desc.restitution = Float(spec.bounce)
        desc.linearDamping = Float(spec.linearDamping)
        desc.angularDamping = Float(spec.angularDamping)
        desc.linearVelocity = Self.triple(spec.linearVelocity)
        desc.angularVelocity = Self.triple(spec.angularVelocity)
        desc.group = spec.group
        desc.allowSleeping = spec.sleeps ? 1 : 0
        var points: [Float] = []
        var indices: [UInt32] = []
        var counts: [Int32] = []
        switch spec.shape.kind {
        case let .box(half):
            desc.shape = JBShapeBox
            desc.size = Self.triple(half)
        case let .sphere(radius):
            desc.shape = JBShapeSphere
            desc.size = (Float(radius), 0, 0)
        case let .cylinder(radius, halfHeight):
            desc.shape = JBShapeCylinder
            desc.size = (Float(radius), Float(halfHeight), 0)
        case let .hull(hull):
            desc.shape = JBShapeConvexHull
            points = hull.flatMap { [Float($0.x), Float($0.y), Float($0.z)] }
        case let .mesh(vertices, triangles):
            desc.shape = JBShapeMesh
            points = vertices.flatMap { [Float($0.x), Float($0.y), Float($0.z)] }
            indices = triangles
        case let .compound(hulls):
            desc.shape = JBShapeCompound
            points = hulls.flatMap { $0.flatMap { [Float($0.x), Float($0.y), Float($0.z)] } }
            counts = hulls.map { Int32($0.count) }
        }
        let body = points.withUnsafeBufferPointer { p in
            indices.withUnsafeBufferPointer { i in
                counts.withUnsafeBufferPointer { c in
                    desc.points = p.baseAddress
                    desc.pointCount = Int32(p.count / 3)
                    desc.indices = i.baseAddress
                    desc.indexCount = Int32(i.count)
                    desc.partCounts = c.baseAddress
                    desc.partCount = Int32(c.count)
                    return JBWorldAddBody(world, &desc)
                }
            }
        }
        return body >= 0 ? body : nil
    }

    func remove(_ body: Int32) { JBWorldRemoveBody(world, body) }

    struct SoftSpec {
        var vertices: [Vec3]
        var triangles: [UInt32]
        /// 0 pins a vertex.
        var masses: [Double]
        var compliance: Double
        var bendCompliance: Double
        var pressure: Double
        var friction: Double
        var bounce: Double
    }

    func addSoft(_ spec: SoftSpec) -> Int32? {
        let vertices = spec.vertices.flatMap { [Float($0.x), Float($0.y), Float($0.z)] }
        let masses = spec.masses.map(Float.init)
        let body = vertices.withUnsafeBufferPointer { v in
            masses.withUnsafeBufferPointer { m in
                spec.triangles.withUnsafeBufferPointer { t in
                    var desc = JBSoftDesc()
                    desc.vertices = v.baseAddress
                    desc.vertexCount = Int32(spec.vertices.count)
                    desc.triangles = t.baseAddress
                    desc.triangleCount = Int32(t.count / 3)
                    desc.vertexMass = m.baseAddress
                    desc.compliance = Float(spec.compliance)
                    desc.bendCompliance = Float(spec.bendCompliance)
                    desc.pressure = Float(spec.pressure)
                    desc.friction = Float(spec.friction)
                    desc.restitution = Float(spec.bounce)
                    desc.linearDamping = 0.1
                    desc.iterations = 6
                    desc.vertexRadius = 0.005
                    return JBWorldAddSoftBody(world, &desc)
                }
            }
        }
        return body >= 0 ? body : nil
    }

    enum JointKind {
        case fixed, ball, hinge, slider, spring, swingTwist, gear

        var bridge: JBJointKind {
            switch self {
            case .fixed: JBJointFixed
            case .ball: JBJointBall
            case .hinge: JBJointHinge
            case .slider: JBJointSlider
            case .spring: JBJointSpring
            case .swingTwist: JBJointSwingTwist
            case .gear: JBJointGear
            }
        }
    }

    struct JointSpec {
        var kind: JointKind
        var a: Int32
        var b: Int32
        var pointA: Vec3
        var pointB: Vec3
        var axis: Vec3
        var normal: Vec3
        var limits: ClosedRange<Double>?
        var motorSpeed: Double?
        var motorStrength: Double?
        var springFrequency: Double = 0
        var springDamping: Double = 0.3
        var swing: Double = 0
        var gears: (Int32, Int32) = (-1, -1)
        var ratio: Double = 1
    }

    func addJoint(_ spec: JointSpec) -> Int32? {
        var desc = JBJointDesc()
        desc.kind = spec.kind.bridge
        desc.bodyA = spec.a
        desc.bodyB = spec.b
        desc.pointA = Self.triple(spec.pointA)
        desc.pointB = Self.triple(spec.pointB)
        desc.axis = Self.triple(spec.axis)
        desc.normal = Self.triple(spec.normal)
        desc.limitMin = Float(spec.limits?.lowerBound ?? 1)
        desc.limitMax = Float(spec.limits?.upperBound ?? -1)
        desc.motor = spec.motorSpeed == nil ? 0 : 1
        desc.motorSpeed = Float(spec.motorSpeed ?? 0)
        desc.motorStrength = Float(spec.motorStrength ?? 0)
        desc.springFrequency = Float(spec.springFrequency)
        desc.springDamping = Float(spec.springDamping)
        desc.swing = Float(spec.swing)
        desc.gear1 = spec.gears.0
        desc.gear2 = spec.gears.1
        desc.ratio = Float(spec.ratio)
        let joint = JBWorldAddJoint(world, &desc)
        return joint >= 0 ? joint : nil
    }

    func step(_ dt: Double, substeps: Int) {
        JBWorldStep(world, Float(dt), Int32(substeps))
    }

    func transform(of body: Int32) -> (position: Vec3, rotation: Quat) {
        var position = [Float](repeating: 0, count: 3)
        var rotation: [Float] = [0, 0, 0, 1]
        JBBodyTransform(world, body, &position, &rotation)
        return (Vec3(Double(position[0]), Double(position[1]), Double(position[2])),
                Quat(x: Double(rotation[0]), y: Double(rotation[1]), z: Double(rotation[2]), w: Double(rotation[3])).normalized)
    }

    func velocity(of body: Int32) -> (linear: Vec3, angular: Vec3) {
        var linear = [Float](repeating: 0, count: 3)
        var angular = [Float](repeating: 0, count: 3)
        JBBodyVelocity(world, body, &linear, &angular)
        return (Vec3(Double(linear[0]), Double(linear[1]), Double(linear[2])), Vec3(Double(angular[0]), Double(angular[1]), Double(angular[2])))
    }

    func centerOfMass(of body: Int32) -> Vec3 {
        var position = [Float](repeating: 0, count: 3)
        JBBodyCenterOfMass(world, body, &position)
        return Vec3(Double(position[0]), Double(position[1]), Double(position[2]))
    }

    func mass(of body: Int32) -> Double { Double(JBBodyMass(world, body)) }

    func isAwake(_ body: Int32) -> Bool { JBBodyIsAwake(world, body) != 0 }

    func push(_ body: Int32, force: Vec3) {
        var value = [Float(force.x), Float(force.y), Float(force.z)]
        JBBodyAddForce(world, body, &value)
    }

    func setVelocity(_ body: Int32, linear: Vec3, angular: Vec3) {
        var l = [Float(linear.x), Float(linear.y), Float(linear.z)]
        var a = [Float(angular.x), Float(angular.y), Float(angular.z)]
        JBBodySetVelocity(world, body, &l, &a)
    }

    func moveKinematic(_ body: Int32, to position: Vec3, rotation: Quat, dt: Double) {
        var p = [Float(position.x), Float(position.y), Float(position.z)]
        var q = [Float(rotation.x), Float(rotation.y), Float(rotation.z), Float(rotation.w)]
        JBBodyMoveKinematic(world, body, &p, &q, Float(dt))
    }

    func softVertices(of body: Int32, count: Int) -> [Float] {
        var out = [Float](repeating: 0, count: count * 3)
        JBSoftBodyVertices(world, body, &out)
        return out
    }

    func blowSoft(_ body: Int32, wind: Vec3, dt: Double) {
        var value = [Float(wind.x), Float(wind.y), Float(wind.z)]
        JBSoftBodyApplyWind(world, body, &value, Float(dt))
    }

    private static func triple(_ v: Vec3) -> (Float, Float, Float) { (Float(v.x), Float(v.y), Float(v.z)) }
    private static func quad(_ q: Quat) -> (Float, Float, Float, Float) {
        let n = q.normalized
        return (Float(n.x), Float(n.y), Float(n.z), Float(n.w))
    }
}
