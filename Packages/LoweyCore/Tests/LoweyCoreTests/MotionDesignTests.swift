import Foundation
import HmmMedia
import HmmVector
@testable import LoweyCore
import XCTest

/// D1: logos stood up, clones with their effects and fields, links between things and to sounds, letters that animate,
/// morphs, and loops that close.
final class MotionDesignTests: XCTestCase {
    static func document(_ objects: [SceneObject], duration: Double = 4, fps: Int = 30) -> Document {
        var scene = Scene(id: "s", name: "Motion design")
        for object in objects {
            scene.objects[object.id] = object
            if object.parent == nil { scene.roots.append(object.id) }
        }
        scene.timeline = Timeline(fps: fps, duration: duration)
        return Document(project: ProjectInfo(id: "p", name: "Motion design"), scene: scene)
    }

    static func cube(_ id: ObjectID, at position: Vec3 = .zero) -> SceneObject {
        SceneObject(id: id, name: id.raw, kind: .primitive(.cube), transform: Transform(position: position))
    }

    /// A red badge with a hole and a white bar on top of it, 200 × 100 units.
    static let badge = """
    <svg viewBox="0 0 200 100">
      <path id="badge" fill="#d81e2c" fill-rule="evenodd" d="M0 0H200V100H0Z M20 20V80H60V20Z"/>
      <rect id="bar" x="100" y="40" width="80" height="20" fill="#ffffff"/>
    </svg>
    """

    // MARK: Logos

    func testALogoStandsUpOneSolidAColourTheTopColourProud() throws {
        let drawing = try SVG.read(Data(Self.badge.utf8))
        var ids = IDFactory.sequential("logo")
        let made = try XCTUnwrap(LogoImport.objects(drawing, name: "Brand", width: 2, depth: 0.1) { ids.next() })
        XCTAssertEqual(made.objects.count, 3, "a group and a solid for each colour")
        let group = try XCTUnwrap(made.objects.first { $0.id == made.root })
        XCTAssertEqual(group.kind, .group)
        XCTAssertEqual(group.children.count, 2)
        let solids = made.objects.filter { $0.id != made.root }
        XCTAssertEqual(solids.map(\.name), ["badge", "bar"])
        var bounds: [Bounds] = []
        for solid in solids {
            guard case let .mesh(mesh) = solid.kind else { return XCTFail("a modelled solid") }
            try bounds.append(XCTUnwrap(Bounds(points: mesh.vertices)))
            XCTAssertTrue(MeshTopology(mesh).isClosedManifold, "\(solid.name) is watertight")
        }
        // Two metres wide, standing on the ground, half as tall (the drawing's shape), centred.
        XCTAssertEqual(bounds[0].size.x, 2, accuracy: 1e-9)
        XCTAssertEqual(bounds[0].min.y, 0, accuracy: 1e-9)
        XCTAssertEqual(bounds[0].size.y, 1, accuracy: 1e-9)
        XCTAssertEqual(bounds[0].center.x, 0, accuracy: 1e-9)
        // The white bar stands in front of the red badge.
        XCTAssertGreaterThan(bounds[1].max.z, bounds[0].max.z + 0.005)
        XCTAssertEqual(bounds[1].min.z, bounds[0].min.z, accuracy: 1e-9)
        // The badge kept its hole: its front face has an outline and a hole.
        guard case let .mesh(badge) = solids[0].kind else { return }
        XCTAssertTrue(badge.faces.contains { $0.loops.count == 2 })
        XCTAssertEqual(solids[1].color, .rgba(RGBA(1, 1, 1)))
    }

    func testStraightEdgesAreOneWallEach() {
        // A square drawn with a point every 0.1 along each side keeps only its corners.
        var square: [Vec2] = []
        for step in 0 ..< 40 {
            let t = Double(step % 10) / 10
            switch step / 10 {
            case 0: square.append(Vec2(t, 0))
            case 1: square.append(Vec2(1, t))
            case 2: square.append(Vec2(1 - t, 1))
            default: square.append(Vec2(0, 1 - t))
            }
        }
        XCTAssertEqual(LogoImport.simplified(square, tolerance: 1e-6).count, 4)
    }

    // MARK: Clones

    func testAGridOfCopiesAroundTheThing() throws {
        var cube = Self.cube("c", at: Vec3(1, 0, 0))
        cube.motionDesign = MotionDesign(clones: ObjectClones(layout: .grid(columns: 3, rows: 2, layers: 2, spacing: Vec3(2, 1, 3))))
        let shown = Animator.evaluate(Self.document([cube]), at: 0).scene
        let copies = shown.objects.values.filter { $0.cloneSource == "c" }
        XCTAssertEqual(copies.count, 11, "twelve in all, the thing itself the first")
        let places = try ([XCTUnwrap(shown.objects["c"])] + copies).map(\.transform.position)
        XCTAssertEqual(Set(places.map(\.x)), [-1, 1, 3])
        XCTAssertEqual(Set(places.map(\.z)), [-1.5, 1.5])
        XCTAssertEqual(Set(places.map(\.y)), [0, 1])
        XCTAssertEqual(copies.first?.name, "c")
        XCTAssertNil(shown.objects[ClonePlayback.copyID("c", 12)])
        XCTAssertTrue(Animator.evaluate(Self.document([cube]), at: 0).animated.contains(ClonePlayback.copyID("c", 3)))
    }

    func testACircleFacingOutAndAGroupCopiedWhole() throws {
        var group = SceneObject(id: "g", name: "Pair", kind: .group, children: ["a"])
        group.motionDesign = MotionDesign(clones: ObjectClones(layout: .circle(count: 4, radius: 2, facesOut: true)))
        var child = Self.cube("a", at: Vec3(0, 1, 0))
        child.parent = "g"
        let shown = Animator.evaluate(Self.document([group, child]), at: 0).scene
        let second = try XCTUnwrap(shown.objects[ClonePlayback.copyID("g", 1)])
        XCTAssertEqual(second.transform.position.x, 2, accuracy: 1e-9)
        XCTAssertEqual(second.transform.position.z, 0, accuracy: 1e-9)
        // Facing out: its front (+z) points away from the middle (+x).
        XCTAssertEqual(second.transform.rotation.act(.unitZ).x, 1, accuracy: 1e-9)
        let copiedChild = try XCTUnwrap(shown.objects[ClonePlayback.copyID("a", 1)])
        XCTAssertEqual(copiedChild.parent, ClonePlayback.copyID("g", 1))
        XCTAssertEqual(second.children, [ClonePlayback.copyID("a", 1)])
        XCTAssertEqual(copiedChild.cloneSource, "g", "a copy's parts pick as the thing")
        XCTAssertEqual(shown.worldTransform(of: copiedChild.id).position.y, 1, accuracy: 1e-9)
        XCTAssertTrue(shown.validate().isEmpty, "\(shown.validate())")
    }

    func testDelayedCopiesPlayTheMotionOneAfterAnother() throws {
        var cube = Self.cube("c")
        cube.motionDesign = MotionDesign(clones: ObjectClones(layout: .line(count: 3, step: Vec3(1, 0, 0)),
                                                              effects: [CloneEffect(id: "d", kind: .delay, delay: 0.5)]))
        var document = Self.document([cube])
        document.scene.timeline.tracks = [Track(id: "t", target: "c", property: .position,
                                                keyframes: [Keyframe(time: 0, value: .vec3(.zero), easing: .linear),
                                                            Keyframe(time: 1, value: .vec3(Vec3(0, 1, 0)), easing: .linear)])]
        let shown = Animator.evaluate(document, at: 1).scene
        XCTAssertEqual(shown.objects["c"]?.transform.position.y ?? -1, 1, accuracy: 1e-9)
        XCTAssertEqual(shown.objects[ClonePlayback.copyID("c", 1)]?.transform.position.y ?? -1, 0.5, accuracy: 1e-9)
        XCTAssertEqual(shown.objects[ClonePlayback.copyID("c", 2)]?.transform.position.y ?? -1, 0, accuracy: 1e-9)
        XCTAssertEqual(shown.objects[ClonePlayback.copyID("c", 2)]?.transform.position.x ?? -1, 2, accuracy: 1e-9)
        // A rise that happens once: before their moment comes, the last copies rest where it starts.
        let early = Animator.evaluate(document, at: 0.2).scene
        XCTAssertEqual(early.objects[ClonePlayback.copyID("c", 2)]?.transform.position.y ?? -1, 0, accuracy: 1e-9)
    }

    func testARippleTravelsOutAndTheStrengthScalesIt() throws {
        var cube = Self.cube("c")
        let push = CloneEffect(id: "p", kind: .push, move: Vec3(0, 1, 0), field: .wave(speed: 1, width: 1, every: 0))
        cube.motionDesign = MotionDesign(clones: ObjectClones(layout: .line(count: 4, step: Vec3(1, 0, 0)), effects: [push]))
        let document = Self.document([cube])
        func height(_ index: Int, at time: Double, in document: Document) -> Double {
            let id = index == 0 ? ObjectID("c") : ClonePlayback.copyID("c", index)
            return Animator.evaluate(document, at: time).scene.objects[id]?.transform.position.y ?? -1
        }
        // The ring's front reaches copy 2 (2 m out) at 2 s and has passed by 3 s.
        XCTAssertEqual(height(2, at: 2.5, in: document), 1, accuracy: 1e-9)
        XCTAssertEqual(height(0, at: 2.5, in: document), 0, accuracy: 1e-9)
        XCTAssertEqual(height(3, at: 2.5, in: document), 0, accuracy: 1e-9)
        var weaker = document
        weaker.scene.objects["c"]?[.effectStrength] = .float(0.5)
        XCTAssertEqual(height(2, at: 2.5, in: weaker), 0.5, accuracy: 1e-9)
    }

    func testRandomScattersTheSameWayEveryTime() throws {
        var cube = Self.cube("c")
        let random = CloneEffect.starting(.random, id: "r", size: 1)
        cube.motionDesign = MotionDesign(clones: ObjectClones(layout: .grid(columns: 4, rows: 4, layers: 1, spacing: Vec3(2, 2, 2)),
                                                              effects: [random], seed: 7))
        let first = Animator.evaluate(Self.document([cube]), at: 0).scene
        let again = Animator.evaluate(Self.document([cube]), at: 0).scene
        let id = ClonePlayback.copyID("c", 5)
        XCTAssertEqual(first.objects[id]?.transform, again.objects[id]?.transform)
        let heights = Set((1 ..< 16).compactMap { first.objects[ClonePlayback.copyID("c", $0)]?.transform.position.y })
        XCTAssertGreaterThan(heights.count, 10, "each copy its own")
        XCTAssertTrue(heights.allSatisfy { abs($0) <= 0.5 + 1e-9 })
    }

    func testAHiddenThingMakesNoCopies() {
        var cube = Self.cube("c")
        cube[.visible] = .bool(false)
        cube.motionDesign = MotionDesign(clones: ObjectClones(layout: .line(count: 3, step: Vec3(1, 0, 0))))
        XCTAssertNil(Animator.evaluate(Self.document([cube]), at: 0).scene.objects[ClonePlayback.copyID("c", 1)])
    }

    func testFieldsWeigh() {
        XCTAssertEqual(CloneField.everywhere.weight(distance: 9, time: 0), 1)
        let sphere = CloneField.sphere(centre: .zero, radius: 2)
        XCTAssertEqual(sphere.weight(distance: 0.9, time: 0), 1, accuracy: 1e-9)
        XCTAssertEqual(sphere.weight(distance: 1.5, time: 0), 0.5, accuracy: 1e-9)
        XCTAssertEqual(sphere.weight(distance: 2.5, time: 0), 0, accuracy: 1e-9)
        let ripple = CloneField.wave(speed: 2, width: 1, every: 3)
        XCTAssertEqual(ripple.weight(distance: 2, time: 1.25), 1, accuracy: 1e-9)
        XCTAssertEqual(ripple.weight(distance: 2, time: 4.25), 1, accuracy: 1e-9, "a new ring every three seconds")
    }
}
