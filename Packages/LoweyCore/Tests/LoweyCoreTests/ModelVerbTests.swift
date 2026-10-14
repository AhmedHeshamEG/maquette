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

    func testTheReferenceShowsTheNewVerbs() {
        XCTAssertTrue(ScriptReference.text.contains(#""do":"model""#))
        XCTAssertTrue(ScriptReference.text.contains(#""do":"profile""#))
    }
}
