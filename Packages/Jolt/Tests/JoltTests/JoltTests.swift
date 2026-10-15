import Foundation
import JoltCpp
import Testing

struct JoltTests {
    private func box(at position: (Float, Float, Float), half: Float = 0.5, density: Float = 700) -> JBBodyDesc {
        var desc = JBBodyDesc()
        desc.shape = JBShapeBox
        desc.size = (half, half, half)
        desc.position = position
        desc.rotation = (0, 0, 0, 1)
        desc.motion = JBMotionDynamic
        desc.density = density
        desc.friction = 0.5
        desc.restitution = 0.1
        desc.allowSleeping = 1
        return desc
    }

    private func transform(_ world: OpaquePointer, _ body: Int32) -> ([Float], [Float]) {
        var position = [Float](repeating: 0, count: 3)
        var rotation = [Float](repeating: 0, count: 4)
        JBBodyTransform(world, body, &position, &rotation)
        return (position, rotation)
    }

    private func ground(_ world: OpaquePointer) {
        var desc = JBBodyDesc()
        desc.shape = JBShapeBox
        desc.size = (50, 0.5, 50)
        desc.position = (0, -0.5, 0)
        desc.rotation = (0, 0, 0, 1)
        desc.motion = JBMotionStatic
        desc.friction = 0.6
        _ = JBWorldAddBody(world, &desc)
    }

    @Test func aWoodCubeHasItsRealMassAndLands() throws {
        let world = try #require(JBWorldCreate(16))
        defer { JBWorldDestroy(world) }
        JBWorldSetGravity(world, 0, -9.81, 0)
        ground(world)
        var cube = box(at: (0, 2, 0))
        let body = JBWorldAddBody(world, &cube)
        #expect(body == 1)
        // 1 m³ of wood at 700 kg/m³ (the rounded corners take a little).
        #expect(abs(JBBodyMass(world, body) - 700) < 5)
        for _ in 0 ..< 180 {
            JBWorldStep(world, 1.0 / 60, 1)
        }
        let (position, _) = transform(world, body)
        #expect(abs(position[1] - 0.5) < 0.02)
    }

    @Test func theSameStepsGiveTheSameResult() throws {
        func run() throws -> [Float] {
            let world = try #require(JBWorldCreate(64))
            defer { JBWorldDestroy(world) }
            JBWorldSetGravity(world, 0, -9.81, 0)
            ground(world)
            for index in 0 ..< 20 {
                var desc = box(at: (Float(index % 3) * 0.3, 1 + Float(index) * 1.1, Float(index % 2) * 0.2), half: 0.4)
                desc.angularVelocity = (0.3 * Float(index), 0.1, 0)
                _ = JBWorldAddBody(world, &desc)
            }
            for _ in 0 ..< 240 {
                JBWorldStep(world, 1.0 / 60, 1)
            }
            var out: [Float] = []
            for index in 1 ... 20 {
                let (p, q) = transform(world, Int32(index))
                out += p + q
            }
            return out
        }
        #expect(try run() == run())
    }

    @Test func aHingeMotorTurnsAWheel() throws {
        let world = try #require(JBWorldCreate(16))
        defer { JBWorldDestroy(world) }
        JBWorldSetGravity(world, 0, 0, 0)
        var wheel = JBBodyDesc()
        wheel.shape = JBShapeCylinder
        wheel.size = (0.5, 0.05, 0)
        wheel.position = (0, 1, 0)
        wheel.rotation = (0, 0, 0, 1)
        wheel.motion = JBMotionDynamic
        wheel.density = 1000
        let body = JBWorldAddBody(world, &wheel)
        var hinge = JBJointDesc()
        hinge.kind = JBJointHinge
        hinge.bodyA = -1
        hinge.bodyB = body
        hinge.pointA = (0, 1, 0)
        hinge.axis = (0, 1, 0)
        hinge.normal = (1, 0, 0)
        hinge.limitMin = 1
        hinge.limitMax = -1
        hinge.motor = 1
        hinge.motorSpeed = 2
        hinge.motorStrength = 1000
        #expect(JBWorldAddJoint(world, &hinge) == 0)
        for _ in 0 ..< 60 {
            JBWorldStep(world, 1.0 / 60, 1)
        }
        var linear = [Float](repeating: 0, count: 3)
        var angular = [Float](repeating: 0, count: 3)
        JBBodyVelocity(world, body, &linear, &angular)
        #expect(abs(angular[1] - 2) < 0.05)
    }

    @Test func clothHangsFromTwoCorners() throws {
        let world = try #require(JBWorldCreate(16))
        defer { JBWorldDestroy(world) }
        JBWorldSetGravity(world, 0, -9.81, 0)
        let side = 10
        var vertices: [Float] = []
        var masses: [Float] = []
        for row in 0 ... side {
            for column in 0 ... side {
                vertices += [Float(column) * 0.1, 2, Float(row) * 0.1]
                masses.append(row == 0 && (column == 0 || column == side) ? 0 : 0.01)
            }
        }
        var triangles: [UInt32] = []
        for row in 0 ..< side {
            for column in 0 ..< side {
                let a = UInt32(row * (side + 1) + column)
                let b = a + 1
                let c = a + UInt32(side + 1)
                triangles += [a, c, b, b, c, c + 1]
            }
        }
        let body = vertices.withUnsafeBufferPointer { v in
            masses.withUnsafeBufferPointer { m in
                triangles.withUnsafeBufferPointer { t in
                    var desc = JBSoftDesc()
                    desc.vertices = v.baseAddress
                    desc.vertexCount = Int32(masses.count)
                    desc.triangles = t.baseAddress
                    desc.triangleCount = Int32(triangles.count / 3)
                    desc.vertexMass = m.baseAddress
                    desc.compliance = 0
                    desc.bendCompliance = 1.0e-3
                    desc.friction = 0.5
                    desc.iterations = 5
                    desc.vertexRadius = 0.01
                    return JBWorldAddSoftBody(world, &desc)
                }
            }
        }
        #expect(body == 0)
        for _ in 0 ..< 240 {
            JBWorldStep(world, 1.0 / 60, 1)
        }
        var out = [Float](repeating: 0, count: vertices.count)
        JBSoftBodyVertices(world, body, &out)
        // The pinned corners stay; the far edge hangs below them.
        #expect(abs(out[1] - 2) < 1.0e-4)
        #expect(out[(side * (side + 1) + side / 2) * 3 + 1] < 1.6)
    }

    /// The SPIKE: a stack of 500 boxes in a 10 × 10 × 5 tower settles, stepped at 60 Hz. The frame budget on a Tier B
    /// iPad is checked on the device; CI's time per step is printed for the phase notes.
    @Test func fiveHundredBodyStack() throws {
        let world = try #require(JBWorldCreate(600))
        defer { JBWorldDestroy(world) }
        JBWorldSetGravity(world, 0, -9.81, 0)
        ground(world)
        for layer in 0 ..< 5 {
            for row in 0 ..< 10 {
                for column in 0 ..< 10 {
                    var desc = box(at: (Float(column) * 0.51 - 2.5, 0.25 + Float(layer) * 0.5, Float(row) * 0.51 - 2.5), half: 0.25)
                    _ = JBWorldAddBody(world, &desc)
                }
            }
        }
        let start = Date()
        let steps = 120
        for _ in 0 ..< steps {
            JBWorldStep(world, 1.0 / 60, 1)
        }
        let perStep = Date().timeIntervalSince(start) / Double(steps) * 1000
        print("JOLT_SPIKE 500 bodies: \(String(format: "%.2f", perStep)) ms per 60 Hz step")
        let (p, _) = transform(world, 500)
        // The top corner box is still on top: the tower stood.
        #expect(abs(p[1] - 2.25) < 0.05)
    }
}
