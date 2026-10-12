import Foundation
@testable import LoweyCore
import XCTest

/// Pins and dots (U4): one tool for soft things and joints, rigs that can be changed afterwards, solid parts hinged
/// by a dot, and shapes cut finer so they can bend.
final class RigMarksTests: XCTestCase {
    static func vertices(_ mesh: MeshData) -> [Vec3] {
        mesh.positions.map { Vec3(Double($0.x), Double($0.y), Double($0.z)) }
    }

    /// The creature's tail pinned at its base and its tip, weighed, on a document.
    static func pinnedTail() throws -> (document: Document, mesh: MeshData, rig: ObjectRig, weights: SkinWeights) {
        let mesh = try RiggingTests.importedCreature()
        let height = RigSamples.tailHeight
        var marks: [RigMark] = []
        marks = RigMarks.adding(.pin, at: Vec3(RigSamples.tailStart + 0.1, height, 0), thickness: 0.15, to: nil, in: marks).marks
        marks = RigMarks.adding(.pin, at: Vec3(RigSamples.tailEnd - 0.03, height, 0), thickness: 0.07, to: nil, in: marks).marks
        let built = RigMarks.rig(marks, surface: vertices(mesh))
        let object = SceneObject(id: "creature", name: "Creature", kind: .asset("creature"))
        let weighted = try XCTUnwrap(RigOperations.weighted(built, object: object, mesh: mesh))
        var placed = object
        placed.rig = weighted.rig
        var document = makeDocument()
        document.scene = RiggingTests.scene(with: placed)
        let weights = try SkinWeights(data: XCTUnwrap(weighted.files.values.first))
        return (document, mesh, weighted.rig, weights)
    }

    func testTwoPinsOnATailBuildAStretchThatBendsWhileTheBodyHolds() throws {
        let (document, mesh, rig, weights) = try Self.pinnedTail()
        XCTAssertEqual(rig.skeleton.joints[0].name, RigMarks.rootName, "the body gets its own joint")
        XCTAssertLessThan(rig.restPositions[0].x, 0.2, "in the middle of the body")
        XCTAssertEqual(rig.skeleton.names, ["root", "j1", "j2~0", "j2~1", "j2~2", "j2"])
        XCTAssertEqual(rig.marks.map(\.name), ["j1", "j2"], "the marks travel with the rig")
        // The tip pin is a handle; the base pin holds and isn't.
        let handles = IKHandles.handles(of: "creature", in: document.scene)
        XCTAssertEqual(handles.map(\.name), ["j2"])
        let tip = try XCTUnwrap(handles.first)
        let target = Vec3(RigSamples.tailEnd - 0.4, RigSamples.tailHeight + 0.7, 0)
        var posed = document
        posed.scene = RiggingTests.applied(IKHandles.solve(tip, to: target, in: document.scene, rest: document.scene), to: document.scene)
        let object = try XCTUnwrap(posed.scene.objects["creature"])
        let moved = RiggingTests.skinned(mesh, weights: weights, rig: rig, object: object)
        let original = Self.vertices(mesh)
        var bodyDrift = 0.0
        var tipLift = 0.0
        for (before, after) in zip(original, moved) {
            if before.x < 0.25 { bodyDrift = max(bodyDrift, before.distance(to: after)) }
            if before.x > RigSamples.tailEnd - 0.05 { tipLift = max(tipLift, after.y - before.y) }
        }
        XCTAssertLessThan(bodyDrift, 0.02, "the body holds still")
        XCTAssertGreaterThan(tipLift, 0.4, "the tip swung up")
    }

    func testMarksMoveAddAndGoWithoutLosingWhatTheOthersHold() throws {
        var marks: [RigMark] = []
        for (index, x) in [0.0, 1, 2, 3].enumerated() {
            marks = RigMarks.adding(.dot, at: Vec3(x, 0, 0), to: index == 0 ? nil : "j\(index)", in: marks).marks
        }
        XCTAssertEqual(marks.map(\.parent), [nil, "j1", "j2", "j3"])
        let rig = RigMarks.rig(marks, surface: [])
        XCTAssertEqual(rig.skeleton.names, ["j1", "j2", "j3", "j4"], "no body to carry, so no root")
        // Moving keeps the names (and so every pose keyed on them).
        let moved = RigMarks.rig(RigMarks.moving("j3", to: Vec3(2, 0.5, 0), in: marks), surface: [])
        XCTAssertEqual(moved.skeleton.names, rig.skeleton.names)
        XCTAssertEqual(moved.restPositions[2], Vec3(2, 0.5, 0))
        // A branch from j2, then j2 taken away: what hung from it hangs from j1.
        let branched = RigMarks.adding(.pin, at: Vec3(1, 1, 0), to: "j2", in: marks)
        XCTAssertEqual(branched.name, "j5")
        let removed = RigMarks.removing("j2", from: branched.marks)
        XCTAssertEqual(removed.first { $0.name == "j3" }?.parent, "j1")
        XCTAssertEqual(removed.first { $0.name == "j5" }?.parent, "j1")
        // Taking the first away: its first follower takes its place.
        let headless = RigMarks.removing("j1", from: marks)
        XCTAssertNil(headless.first { $0.name == "j2" }?.parent)
        // Dots bring the limb along: pulling j4 turns j1, j2 and j3.
        let object = SceneObject(id: "arm", name: "Arm", kind: .group)
        var placed = object
        placed.rig = rig
        let scene = RiggingTests.scene(with: placed)
        let handle = try XCTUnwrap(IKHandles.handles(of: "arm", in: scene).first { $0.name == "j4" })
        XCTAssertEqual(handle.kind, .chain([0, 1, 2, 3]))
        XCTAssertTrue(handle.isEnd)
    }

    func testARigFromBefore014ReadsAsDotsAndAPersonKeepsItsDots() throws {
        let rig = ObjectRig(names: ["root", "j1", "j2", "j3"], parents: [nil, 0, 1, 2],
                            positions: [Vec3(0, 0, 0), Vec3(1, 0, 0), Vec3(2, 0, 0), Vec3(3, 0, 0)])
        let marks = RigMarks.marks(of: rig)
        XCTAssertEqual(marks.map(\.name), ["j1", "j2", "j3"], "the made root comes back by itself")
        XCTAssertEqual(marks.map(\.parent), [nil, "j1", "j2"])
        XCTAssertTrue(marks.allSatisfy { $0.kind == .dot })
        // Marks and a person's dots survive JSON.
        var marked = RigMarks.rig(RigMarks.adding(.pin, at: Vec3(1, 2, 3), thickness: 0.2, to: nil, in: []).marks, surface: [])
        marked.person = ["head": Vec3(0, 2, 0)]
        XCTAssertEqual(try LoweyJSON.decode(ObjectRig.self, from: LoweyJSON.encode(marked)), marked)
        // A person rig keeps its dots, and one from before 0.14 reads them back from its joints.
        let (_, parts) = try RiggingTests.astronaut()
        let dots = try RiggingTests.astronautDots(parts)
        var union: Bounds?
        for part in parts.values {
            union = union.map { $0.union(part) } ?? part
        }
        let bounds = try XCTUnwrap(union)
        let person = try XCTUnwrap(HumanRig.rig(from: dots, bounds: bounds))
        XCTAssertEqual(HumanRig.dots(of: person)?[.leftElbow], dots[.leftElbow])
        var old = person
        old.person = nil
        let read = try XCTUnwrap(HumanRig.dots(of: old))
        for dot in HumanRig.Dot.allCases {
            let back = try XCTUnwrap(read[dot])
            let placed = try XCTUnwrap(dots[dot])
            XCTAssertLessThan(back.distance(to: placed), 1e-6, "\(dot)")
        }
    }

    // MARK: Solid parts

    func testADotBetweenTwoSolidPartsHingesThemWithoutSkin() throws {
        var scene = Scene(id: "s", name: "S")
        var group = SceneObject(id: "g", name: "Arm", kind: .group, children: ["upper", "lower"])
        let upper = SceneObject(id: "upper", name: "Upper", kind: .primitive(.cube), parent: "g",
                                transform: Transform(position: Vec3(0, 0, 0), scale: Vec3(0.2, 1, 0.2)))
        let lower = SceneObject(id: "lower", name: "Lower", kind: .primitive(.cube), parent: "g",
                                transform: Transform(position: Vec3(0, 1, 0), scale: Vec3(0.2, 1, 0.2)))
        // The held part's middle, then the dot where they meet.
        var marks = RigMarks.adding(.dot, at: Vec3(0, 0.5, 0), to: nil, in: []).marks
        marks[0].name = RigMarks.rootName
        marks = RigMarks.adding(.dot, at: Vec3(0, 1, 0), to: RigMarks.rootName, in: marks).marks
        group.rig = RigMarks.rig(marks, surface: [])
        XCTAssertEqual(group.rig?.skeleton.names, ["root", "j2"])
        scene.objects = ["g": group, "upper": upper, "lower": lower]
        scene.roots = ["g"]
        let binding = RigidParts.binding("g", rig: group.rig, in: scene)
        XCTAssertEqual(Set(binding.map(\.object)), ["upper", "lower"])
        XCTAssertEqual(binding.first { $0.object == "upper" }?.value, .string("root"))
        XCTAssertEqual(binding.first { $0.object == "lower" }?.value, .string("j2"))
        scene = RiggingTests.applied(binding, to: scene)
        // Turn the hinge a quarter: the lower part swings about the dot, the upper stays.
        scene.objects["g"]?[.boneTurn("j2")] = .quat(Quat(angle: .pi / 2, axis: .unitZ))
        var document = makeDocument()
        document.scene = scene
        let frame = Animator.evaluate(document, at: 0).scene
        XCTAssertEqual(frame.objects["upper"]?.transform.position, upper.transform.position)
        let swung = try XCTUnwrap(frame.objects["lower"]?.transform.position)
        XCTAssertEqual(swung.x, 0, accuracy: 1e-9, "the lower part's base sits on the dot")
        XCTAssertEqual(swung.y, 1, accuracy: 1e-9)
        let up = try XCTUnwrap(frame.objects["lower"]?.transform.rotation).act(.unitY)
        XCTAssertEqual(up.x, -1, accuracy: 1e-9, "and it points sideways now")
        // Unbinding clears the parts.
        XCTAssertEqual(RigidParts.binding("g", rig: nil, in: scene).count, 2)
    }

    // MARK: Shapes that lack geometry

    func testACubeIsCutFinerSoItCanBendAndKeepsItsShape() throws {
        let cube = PrimitiveMesh.make(.cube, shading: .smooth)
        let bones = [(head: Vec3(0, 0.05, 0), tail: Vec3(0, 0.5, 0)), (head: Vec3(0, 0.5, 0), tail: Vec3(0, 0.95, 0))]
        let cuts = try XCTUnwrap(MeshDensify.cuts(for: cube, bones: bones), "eight corners can't bend at the middle")
        XCTAssertGreaterThanOrEqual(cuts, 6)
        let dense = MeshDensify.densified(cube, cuts: cuts)
        XCTAssertGreaterThan(dense.positions.count, cube.positions.count * 10)
        XCTAssertEqual(dense.bounds, cube.bounds, "the same shape")
        XCTAssertLessThanOrEqual(MeshDensify.longestEdge(dense), 1.0 / Double(cuts) + 1e-6)
        // Every triangle still faces out (the cube is centred on x and z, its base at y = 0).
        for triangle in stride(from: 0, to: dense.indices.count, by: 3) {
            let a = dense.positions[Int(dense.indices[triangle])], b = dense.positions[Int(dense.indices[triangle + 1])]
            let c = dense.positions[Int(dense.indices[triangle + 2])]
            let normal = cross3(b - a, c - a)
            let centre = (a + b + c) / 3 - SIMD3<Float>(0, 0.5, 0)
            XCTAssertGreaterThan(normal.x * centre.x + normal.y * centre.y + normal.z * centre.z, 0)
        }
        // A mesh fine enough already isn't touched; the object's property is what every builder reads.
        XCTAssertNil(MeshDensify.cuts(for: dense, bones: bones))
        var object = SceneObject(id: "c", name: "Cube", kind: .primitive(.cube))
        XCTAssertEqual(PaintSource.mesh(of: object), cube)
        object[.bendDetail] = .float(Double(cuts))
        XCTAssertEqual(PaintSource.mesh(of: object), dense)
        XCTAssertEqual(SceneExport.localMesh(of: object, look: Look())?.triangleCount, dense.triangleCount)
    }
}
