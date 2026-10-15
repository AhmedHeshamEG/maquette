import Foundation
@testable import LoweyCore
import XCTest

/// P1: real things, mechanisms, ragdolls, cloth and jelly, breaking, fluids, Keep it, Settle, does it stand, the sun.
final class PhysicsTests: XCTestCase {
    static func document(_ objects: [SceneObject], physics: ScenePhysics? = ScenePhysics(), duration: Double = 3, fps: Int = 30) -> Document {
        var scene = Scene(id: "s", name: "Physics")
        for object in objects {
            scene.objects[object.id] = object
            if object.parent == nil { scene.roots.append(object.id) }
        }
        scene.timeline = Timeline(fps: fps, duration: duration)
        scene.physics = physics
        return Document(project: ProjectInfo(id: "p", name: "Physics"), scene: scene)
    }

    static func cube(_ id: ObjectID, at position: Vec3, size: Double = 1, material: PhysicsMaterial = .wood,
                     motion: ObjectPhysics.Motion = .falls) -> SceneObject {
        var object = SceneObject(id: id, name: id.raw, kind: .primitive(.cube), transform: Transform(position: position, scale: Vec3(size, size, size)))
        object.physics = ObjectPhysics(material: material, motion: motion)
        return object
    }

    static func input(_ document: Document) throws -> PhysicsInput {
        let look = document.effectiveLook
        return try XCTUnwrap(PhysicsInput.make(document, mesh: { SceneExport.localMesh(of: $0, look: look) }))
    }

    static func run(_ document: Document) throws -> PhysicsFrames {
        try XCTUnwrap(PhysicsSimulator.run(input(document)))
    }

    // MARK: Falling

    /// The golden: a 1 m wood cube and a 1 m steel cube dropped side by side land the same, with their real masses, and
    /// the stage (a run played while it's made) shows exactly what an export (the whole run first) shows.
    func testWoodAndSteelCubesLandTheSameInPreviewAndExport() throws {
        let document = Self.document([Self.cube("wood", at: Vec3(-1, 2, 0)), Self.cube("steel", at: Vec3(1, 2, 0), material: .steel)])
        let input = try Self.input(document)
        let export = try XCTUnwrap(PhysicsSimulator.run(input))
        XCTAssertEqual(export.frames.count, export.total)
        XCTAssertEqual(export.masses[0], 700, accuracy: 6)
        XCTAssertEqual(export.masses[1], 7850, accuracy: 60)
        // The stage: frames read while the run is still being made.
        let stage = try XCTUnwrap(PhysicsSimulator(input))
        var seen: [Double] = []
        while stage.step() {
            seen.append(Animator.evaluate(document, at: stage.frames.reach, physics: stage.frames).scene.objects["wood"]?.transform.position.y ?? -1)
        }
        for time in [0.0, 0.3, 0.6, 1.0, 2.9] {
            let preview = Animator.evaluate(document, at: time, physics: stage.frames).scene
            let exported = Animator.evaluate(document, at: time, physics: export).scene
            for id: ObjectID in ["wood", "steel"] {
                XCTAssertEqual(preview.objects[id]?.transform, exported.objects[id]?.transform, "\(id) at \(time)")
            }
        }
        let end = Animator.evaluate(document, at: 3, physics: export).scene
        let wood = try XCTUnwrap(end.objects["wood"]).transform
        let steel = try XCTUnwrap(end.objects["steel"]).transform
        XCTAssertEqual(wood.position.y, 0, accuracy: 0.02, "on the ground (its pivot is its base)")
        XCTAssertEqual(steel.position.y, 0, accuracy: 0.02)
        XCTAssertEqual(wood.position.y, steel.position.y, accuracy: 0.01, "they land the same")
        // Galileo: halfway down at the same moment.
        let fall = Animator.evaluate(document, at: 0.4, physics: export).scene
        XCTAssertEqual(fall.objects["wood"]?.transform.position.y ?? 0, fall.objects["steel"]?.transform.position.y ?? 1, accuracy: 0.005)
        // Jolt steps at 60 Hz (symplectic Euler), 3 cm ahead of ½gt² at 0.4 s.
        XCTAssertEqual(fall.objects["wood"]?.transform.position.y ?? 0, 2 - 0.5 * 9.81 * 0.16, accuracy: 0.04)
        XCTAssertFalse(seen.isEmpty)
    }

    func testTheSameSceneSimulatesToTheSameFrames() throws {
        var objects = (0 ..< 8).map { Self.cube(ObjectID(raw: "c\($0)"), at: Vec3(Double($0 % 3) * 0.3, 1 + Double($0) * 1.1, 0), size: 0.6) }
        objects[3].properties[.rotation] = .quat(Quat(angle: 0.4, axis: .unitZ))
        let document = Self.document(objects)
        let a = try Self.run(document)
        let b = try Self.run(document)
        XCTAssertEqual(try Self.input(document).key, try Self.input(document).key)
        XCTAssertEqual(a.frames.last?.transforms, b.frames.last?.transforms)
        var moved = document
        moved.scene.objects["c0"]?.properties[.position] = .vec3(Vec3(0, 3, 0))
        XCTAssertNotEqual(try Self.input(moved).key, try Self.input(document).key, "a change makes a new run")
    }

    func testBeforeTheStartThingsHoldTheirPlace() throws {
        var settings = ScenePhysics()
        settings.start = 1
        let document = Self.document([Self.cube("c", at: Vec3(0, 2, 0))], physics: settings)
        let frames = try Self.run(document)
        XCTAssertEqual(Animator.evaluate(document, at: 0.5, physics: frames).scene.objects["c"]?.transform.position.y ?? 0, 2, accuracy: 1e-9)
        XCTAssertLessThan(Animator.evaluate(document, at: 1.5, physics: frames).scene.objects["c"]?.transform.position.y ?? 9, 1.9)
    }

    func testMoonGravityAndWind() throws {
        var moon = ScenePhysics(gravity: .moon)
        moon.ground = false
        let falling = try Self.run(Self.document([Self.cube("c", at: Vec3(0, 10, 0))], physics: moon, duration: 1))
        let y = Animator.evaluate(Self.document([Self.cube("c", at: Vec3(0, 10, 0))], physics: moon, duration: 1), at: 1, physics: falling)
            .scene.objects["c"]?.transform.position.y ?? 0
        XCTAssertEqual(y, 10 - 0.5 * 1.62, accuracy: 0.03)
        var windy = ScenePhysics(windHeading: 90, windSpeed: 20, gusts: 0)
        windy.ground = false
        windy.customGravity = 0
        let foam = Self.document([Self.cube("f", at: Vec3(0, 1, 0), size: 0.3, material: .foam)], physics: windy, duration: 1)
        let blown = try Self.run(foam)
        XCTAssertGreaterThan(Animator.evaluate(foam, at: 1, physics: blown).scene.objects["f"]?.transform.position.x ?? 0, 0.5, "foam blows east")
    }

    // MARK: Mechanisms

    func testAMotorTurnsAWheelOnAHinge() throws {
        var wheel = SceneObject(id: "wheel", name: "Wheel", kind: .primitive(.cylinder), transform: Transform(position: Vec3(0, 1, 0), scale: Vec3(1, 0.1, 1)))
        wheel.physics = ObjectPhysics(material: .steel)
        var settings = ScenePhysics(gravity: .none)
        settings.joints = [PhysicsJoint(id: "axle", kind: .hinge, first: "wheel", anchor: Vec3(0, 0.5, 0), axis: .unitY, motorSpeed: 90)]
        let document = Self.document([wheel], physics: settings, duration: 2)
        let frames = try Self.run(document)
        let turned = try XCTUnwrap(Animator.evaluate(document, at: 1, physics: frames).scene.objects["wheel"]).transform
        XCTAssertEqual(turned.position.distance(to: Vec3(0, 1, 0)), 0, accuracy: 0.01, "the axle holds it")
        let angle = 2 * acos(min(abs(turned.rotation.normalized.w), 1)) * 180 / .pi
        XCTAssertEqual(angle, 90, accuracy: 6, "90° a second")
    }

    func testAPendulumSwingsOnABallJointAndASpringBounces() throws {
        var bob = Self.cube("bob", at: Vec3(1, 2, 0), size: 0.2, material: .steel)
        bob.physics?.friction = 0
        var spring = Self.cube("weight", at: Vec3(-1, 1.5, 0), size: 0.2)
        spring.physics?.bounce = 0
        var settings = ScenePhysics()
        settings.joints = [
            PhysicsJoint(id: "pivot", kind: .rope, first: "bob", anchor: Vec3(0, 0.1, 0), otherAnchor: Vec3(0, 2.1, 0), length: 1),
            PhysicsJoint(id: "spring", kind: .spring, first: "weight", anchor: Vec3(0, 0.1, 0), otherAnchor: Vec3(-1, 2.6, 0), springiness: 1.5, length: 1)
        ]
        let document = Self.document([bob, spring], physics: settings, duration: 2)
        let frames = try Self.run(document)
        let swung = try XCTUnwrap(Animator.evaluate(document, at: 0.5, physics: frames).scene.objects["bob"]).transform.position
        XCTAssertLessThan(swung.x, 0.9, "it swings toward the middle")
        XCTAssertLessThanOrEqual(swung.distance(to: Vec3(0, 2, 0)) - 0.1, 1.02, "the rope holds")
        let heights = stride(from: 0.0, through: 2, by: 0.1).compactMap {
            Animator.evaluate(document, at: $0, physics: frames).scene.objects["weight"]?.transform.position.y
        }
        XCTAssertGreaterThan((heights.max() ?? 0) - (heights.min() ?? 0), 0.05, "the spring bounces")
        XCTAssertGreaterThan(heights.min() ?? 0, 0.5, "and holds it up")
    }

    // MARK: Commands

    func testPhysicsCommandsRevertAndTravel() throws {
        let document = Self.document([Self.cube("c", at: .zero)])
        try assertReverts(.setPhysics("c", ObjectPhysics(material: .rubber, motion: .stays, mass: 3, hangs: true)), on: document)
        try assertReverts(.setPhysics("c", nil), on: document)
        var settings = ScenePhysics(gravity: .mars, windHeading: 45, windSpeed: 3)
        settings.joints = [PhysicsJoint(id: "j", kind: .hinge, first: "c", limits: -30 ... 60, motorSpeed: 10)]
        try assertReverts(.setScenePhysics(settings), on: document)
        let data = try LoweyJSON.encode(document)
        XCTAssertEqual(try LoweyJSON.decode(Document.self, from: data), document)
        let force = SceneObject(id: "fan", name: "Fan", kind: .force(ForceRecipe(kind: .fan)))
        let fluid = SceneObject(id: "tap", name: "Tap", kind: .fluid(FluidRecipe(kind: .pour)))
        let decoded = try LoweyJSON.decode([SceneObject].self, from: LoweyJSON.encode([force, fluid]))
        XCTAssertEqual(decoded, [force, fluid])
    }
}
