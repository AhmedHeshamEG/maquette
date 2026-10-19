import Foundation
@testable import LoweyCore
import XCTest

/// U6's bridge verbs: `model` (the modelling set on one thing) and `profile` (sweep, revolve, loft a sketch region).
final class ModelVerbTests: XCTestCase {
    private func document() -> Document {
        var scene = Scene(id: "s", name: "Shapes")
        let box = SceneObject(id: "box", name: "Box", kind: .mesh(.box(min: Vec3(-0.5, 0, -0.5), max: Vec3(0.5, 1, 0.5))))
        let cube = SceneObject(id: "cube", name: "Cube", kind: .primitive(.cube), transform: Transform(position: Vec3(3, 0, 0)))
        let square = Sketch(plane: PlaneFrame(origin: .zero, normal: .unitZ, u: .unitX, v: .unitY),
                            curves: [.rectangle(Vec2(1, 0), Vec2(2, 1))])
        let sketch = SceneObject(id: "sketch", name: "Sketch", kind: .sketch(square))
        for object in [box, cube, sketch] {
            scene.objects[object.id] = object
            scene.roots.append(object.id)
        }
        return Document(project: ProjectInfo(id: "p", name: "P"), scene: scene)
    }

    private func run(_ actions: String) throws -> ScriptResult {
        let script = try LoweyJSON.decode(SceneScript.self, from: Data("{\"version\": 3, \"title\": \"T\", \"actions\": [\(actions)]}".utf8))
        return try ScriptCompiler.compile(script, document: document(), context: ScriptContext(ids: .sequential("run")))
    }

    private func mesh(_ result: ScriptResult, _ id: ObjectID) throws -> EditableMesh {
        guard case let .mesh(mesh) = result.document.scene.objects[id]?.kind else { throw XCTSkip("not a mesh") }
        return mesh
    }

    func testPullingTheTopFaceMakesItTaller() throws {
        let result = try run(#"{"do": "model", "target": "Box", "op": "pull", "face": "top", "distance": 0.5}"#)
        XCTAssertEqual(try mesh(result, "box").bounds?.size.y ?? 0, 1.5, accuracy: 1e-9)
    }

    func testSmoothBendCageAndFlatAreProperties() throws {
        let result = try run(#"""
        {"do": "model", "target": "Box", "op": "smooth", "levels": 2},
        {"do": "model", "target": "Box", "op": "bend", "kind": "twist", "amount": 90, "axis": "y"},
        {"do": "model", "target": "Cube", "op": "flat"},
        {"do": "model", "target": "Box", "op": "cage", "counts": [2, 2, 2]},
        {"do": "model", "target": "Box", "op": "cage", "point": [1, 1, 1], "offset": [0.3, 0, 0]}
        """#)
        let box = try XCTUnwrap(result.document.scene.objects["box"])
        XCTAssertEqual(box[.subdivision], .int(2))
        XCTAssertEqual(Deform.of(box)?.kind, .twist)
        XCTAssertEqual(result.document.scene.objects["cube"]?.shading, .flat)
        let cage = try XCTUnwrap(box.shaping?.cage)
        XCTAssertEqual(cage.offsets[cage.index(1, 1, 1)], Vec3(0.3, 0, 0))
        XCTAssertNotNil(result.command, "the whole script is one step")
    }

    func testACagePointOutOfRangeSaysWhichOnesExist() throws {
        let cage = #"{"do": "model", "target": "Box", "op": "cage", "counts": [2, 2, 4]}"#
        XCTAssertThrowsError(try run(cage + #", {"do": "model", "target": "Box", "op": "cage", "point": [0, 2, 3], "offset": [0, 1, 0]}"#)) { error in
            XCTAssertTrue("\(error)".contains("[2, 2, 4] points per axis, so i, j, k are 0–1, 0–1, 0–3"), "\(error)")
        }
        // One axis too far used to land on another point ([2, 0, 0] is (0, 1, 0) in a 2-wide cage).
        XCTAssertThrowsError(try run(cage + #", {"do": "model", "target": "Box", "op": "cage", "point": [2, 0, 0], "offset": [0, 1, 0]}"#))
        let clamped = try run(#"{"do": "model", "target": "Box", "op": "cage", "counts": [3, 3, 5]}"#)
        XCTAssertEqual(clamped.document.scene.objects["box"]?.shaping?.cage?.counts, [3, 3, 4])
        XCTAssertTrue(clamped.report.contains("Cage points per axis are 2–4: [3, 3, 5] became [3, 3, 4]"), "\(clamped.report)")
    }

    func testLoopCutKnifeAndHoles() throws {
        let cut = try run(#"{"do": "model", "target": "Box", "op": "loopCut", "along": "x", "cuts": 2}"#)
        XCTAssertEqual(try mesh(cut, "box").faces.count, 2 + 3 * 4)
        let knifed = try run(#"{"do": "model", "target": "Box", "op": "knife", "point": [0, 0.5, 0], "normal": [0, 1, 0]}"#)
        XCTAssertEqual(try mesh(knifed, "box").faces.count, 10)
        XCTAssertThrowsError(try run(#"{"do": "model", "target": "Box", "op": "fillHoles"}"#), "a closed box has no hole")
    }

    func testABrushDabMovesTheSurface() throws {
        let result = try run(#"{"do": "model", "target": "Cube", "op": "brush", "brush": "grab", "at": [3, 1, 0], "radius": 0.4, "by": [0, 0.3, 0]}"#)
        let cube = try XCTUnwrap(result.document.scene.objects["cube"])
        XCTAssertFalse(try XCTUnwrap(cube.shaping?.sculpt).moved.isEmpty)
    }

    func testLinkedCopyPivotAndSize() throws {
        let result = try run(#"""
        {"do": "model", "target": "Box", "op": "linkedCopy", "offset": [2, 0, 0]},
        {"do": "model", "target": "Cube", "op": "pivot", "to": "middle"},
        {"do": "model", "target": "Box", "op": "size", "axis": "y", "length": 0.25}
        """#)
        let scene = result.document.scene
        XCTAssertEqual(scene.objects.values.filter { $0[.linked] != nil }.count, 2)
        XCTAssertEqual(scene.objects["cube"]?.transform.position.y ?? 0, 0.5, accuracy: 1e-9)
        XCTAssertEqual(try mesh(result, "box").bounds?.size.y ?? 0, 0.25, accuracy: 1e-9)
    }

    func testCleaningUpMakesQuads() throws {
        let result = try run(#"{"do": "model", "target": "Box", "op": "smooth", "levels": 2}, {"do": "model", "target": "Box", "op": "cleanUp", "faces": 60}"#)
        let cleaned = try mesh(result, "box")
        XCTAssertGreaterThan(cleaned.faces.filter { $0.outline.count == 4 }.count, cleaned.faces.count / 2)
        XCTAssertNil(result.document.scene.objects["box"]?[.subdivision], "the smoothing is baked in")
    }

    func testRevolvingASketchRegion() throws {
        let result = try run(#"{"do": "profile", "target": "Sketch", "region": 0, "op": "revolve", "axis": {"point": [0, 0, 0], "direction": [0, 1, 0]}}"#)
        let solid = try XCTUnwrap(result.document.scene.objects.values.first { $0.name == "Solid" })
        guard case let .mesh(mesh) = solid.kind else { return XCTFail("a solid") }
        XCTAssertEqual(mesh.volume, 3 * .pi, accuracy: 0.1)
        XCTAssertNil(result.document.scene.objects["sketch"], "its only region was used up")
    }

    func testUnknownOpsSayWhatTheyCanBe() {
        XCTAssertThrowsError(try run(#"{"do": "model", "target": "Box", "op": "explode"}"#)) { error in
            XCTAssertTrue(String(describing: error).contains("cleanUp"))
        }
    }

    /// H1: a step pulled again through the bridge; the reply lists the steps.
    func testStepsAreListedAndChanged() throws {
        let result = try run(#"""
        {"do": "model", "target": "Box", "op": "pull", "face": "top", "distance": 0.5},
        {"do": "model", "target": "Box", "op": "step", "step": 1, "number": "distance", "value": 1},
        {"do": "model", "target": "Box", "op": "steps"}
        """#)
        XCTAssertEqual(try mesh(result, "box").bounds?.size.y ?? 0, 2, accuracy: 1e-9)
        XCTAssertTrue(result.report.contains("1. Push/pull (distance 1)"), result.report.joined(separator: " | "))
        XCTAssertThrowsError(try run(#"{"do": "model", "target": "Box", "op": "step", "step": 1, "value": 1}"#))
    }

    func testASketchFromAScriptPullsRevolvesAndCuts() throws {
        // A body of revolution: a profile on the side plane, turned about the up axis.
        let vase = try run(#"""
        {"do": "sketch", "name": "Side", "plane": "xy", "at": [5, 0, 0], "curves": [{"polyline": [[0.1, 0], [0.4, 0], [0.3, 1], [0.1, 1]], "closed": true}]},
        {"do": "profile", "target": "Side", "op": "revolve", "axis": {"point": [5, 0, 0], "direction": [0, 1, 0]}}
        """#)
        let made = vase.document.scene.objects.values.filter {
            if case .mesh = $0.kind {
                $0.id != "box"
            } else {
                false
            }
        }
        XCTAssertEqual(made.count, 1, "the revolve made a solid")
        XCTAssertTrue(vase.report.contains { $0.contains("1 closed area") }, "\(vase.report)")
        // Pulled from empty space into a new solid.
        let slab = try run(#"{"do": "sketch", "name": "Floor", "plane": "xz", "at": [0, 3, 0], "curves": [{"rectangle": [[0, 0], [2, 1]]}]},"#
            + #"{"do": "profile", "target": "Floor", "op": "pull", "distance": 0.2}"#)
        XCTAssertTrue(slab.report.contains("Pull 0.2 m"))
        // Drawn on the box's top face and cut in: a pocket, the box keeps its name.
        let pocket = try run(#"{"do": "sketch", "name": "Hole", "on": "Box", "face": "top", "curves": [{"circle": {"center": [0, 0], "radius": 0.2}}]},"#
            + #"{"do": "profile", "target": "Hole", "op": "pull", "distance": -0.3}"#)
        XCTAssertGreaterThan(try mesh(pocket, "box").faces.count, 6, "the pocket's walls are in the box")
        XCTAssertThrowsError(try run(#"{"do": "sketch", "curves": [{"triangle": []}]}"#)) { error in
            XCTAssertTrue("\(error)".contains("curve 1 is one of"), "\(error)")
        }
    }

    func testABooleanCutsOneThingOutOfAnother() throws {
        let result = try run(#"""
        {"do": "add", "shape": "cylinder", "name": "Arch", "at": [0, 0, 0.5], "size": [0.4, 2, 0.4], "onGround": false},
        {"do": "boolean", "op": "subtract", "target": "Box", "with": "Arch"}
        """#)
        let scene = result.document.scene
        XCTAssertNil(scene.objects.values.first { $0.name == "Arch" }, "the cutter is used up")
        XCTAssertGreaterThan(try mesh(result, "box").faces.count, 6)
        XCTAssertThrowsError(try run(#"{"do": "boolean", "op": "carve", "target": "Box", "with": "Cube"}"#))
    }

    func testTheReferenceShowsTheNewVerbs() {
        XCTAssertTrue(ScriptReference.text.contains(#""do":"model""#))
        XCTAssertTrue(ScriptReference.text.contains(#""do":"profile""#))
        XCTAssertTrue(ScriptReference.text.contains(#""do":"sketch""#) && ScriptReference.text.contains(#""do":"boolean""#))
    }
}
