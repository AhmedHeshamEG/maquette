import Foundation
import LoweyCore
@testable import LoweyFeatures
import XCTest

/// U6's shape tools from the editor: Model's verbs, the Smooth switch and making it real, the bend, the cage, linked
/// copies changing together, the pivot, typed sides, the part chip's loop cut and merge, and a sketch's rules.
@MainActor
final class ShapeFlowTests: XCTestCase {
    private var app: AppModel?

    private func makeEditor() throws -> EditorModel {
        let app = AppModel()
        self.app = app
        app.createProject(named: "Shape \(UUID().uuidString.prefix(6))", mood: .day, look: LookPreset.ink.id)
        return try XCTUnwrap(app.editor)
    }

    private func cube(_ editor: EditorModel) throws -> SceneObject {
        editor.addPrimitive(.cube)
        return try XCTUnwrap(editor.singleSelection)
    }

    func testModelsVerbsPutTheModelToolInTheHand() throws {
        let editor = try makeEditor()
        editor.chooseModelVerb(.brush)
        XCTAssertEqual(editor.tool, .model)
        XCTAssertEqual(editor.modeling.verb, .brush)
        editor.chooseModelVerb(.measure)
        XCTAssertEqual(editor.modeling.mode, .measure)
        editor.chooseModelVerb(.shape)
        XCTAssertNotNil(editor.modeling.mode.pickMode, "shape is touch and drag: no faces, edges or corners mode to choose")
    }

    func testSmoothIsASwitchUntilItsMadeReal() throws {
        let editor = try makeEditor()
        let box = try cube(editor)
        editor.setSmooth(2)
        XCTAssertEqual(editor.singleSelection?[.subdivision], .int(2))
        editor.applySmooth()
        let made = try XCTUnwrap(editor.baseScene.objects[box.id])
        guard case let .mesh(mesh) = made.kind else { return XCTFail("the smoothing is real now") }
        XCTAssertEqual(mesh.faces.count, 6 * 16)
        XCTAssertNil(made[.subdivision], "and the switch is off")
        editor.undo()
        XCTAssertEqual(editor.baseScene.objects[box.id]?[.subdivision], .int(2), "one undo step")
    }

    func testABendWithItsHandleAndAxis() throws {
        let editor = try makeEditor()
        _ = try cube(editor)
        editor.setBend(.twist)
        let object = try XCTUnwrap(editor.singleSelection)
        XCTAssertEqual(editor.bend(of: object)?.kind, .twist)
        XCTAssertEqual(editor.bend(of: object)?.amount ?? 0, Deform.twist.starting, accuracy: 1e-9)
        editor.setBendAmount(5000, gesture: "drag")
        editor.endGesture()
        XCTAssertEqual(editor.singleSelection.flatMap { editor.bend(of: $0)?.amount } ?? 0, 720, accuracy: 1e-9, "kept in its range")
        editor.setBendAxis(.x)
        XCTAssertEqual(editor.singleSelection?[.deformAxis], .enumeration("x"))
        editor.setBend(nil)
        XCTAssertNil(editor.singleSelection?[.deform])
    }

    func testACageGoesOnAndComesOff() throws {
        let editor = try makeEditor()
        _ = try cube(editor)
        editor.addCage(counts: [2, 3, 2])
        let cage = try XCTUnwrap(editor.singleSelection?.shaping?.cage)
        XCTAssertEqual(cage.counts, [2, 3, 2])
        XCTAssertTrue(cage.isAtRest)
        editor.removeCage()
        XCTAssertNil(editor.singleSelection?.shaping)
    }

    func testLinkedCopiesChangeTogether() throws {
        let editor = try makeEditor()
        let box = try cube(editor)
        editor.makeLinkedCopy()
        let copy = try XCTUnwrap(editor.singleSelection)
        XCTAssertNotEqual(copy.id, box.id)
        XCTAssertTrue(editor.isLinked(copy))
        editor.setSmooth(1)
        XCTAssertEqual(editor.baseScene.objects[box.id]?[.subdivision], .int(1), "the original took the change")
        editor.unlinkSelection()
        editor.setSmooth(3)
        XCTAssertEqual(editor.baseScene.objects[box.id]?[.subdivision], .int(1), "unlinked, it goes its own way")
    }

    func testThePivotAndATypedSide() throws {
        let editor = try makeEditor()
        _ = try cube(editor)
        let before = try XCTUnwrap(editor.selectionLength(.y))
        editor.movePivot(to: .middle)
        XCTAssertEqual(editor.selectionLength(.y) ?? 0, before, accuracy: 1e-9, "nothing moved on screen")
        editor.setSelectionLength(.x, to: 0.04)
        XCTAssertEqual(editor.selectionLength(.x) ?? 0, 0.04, accuracy: 1e-9)
    }

    func testTheChipsLoopCutAndMerge() throws {
        let editor = try makeEditor()
        let box = try cube(editor)
        XCTAssertTrue(editor.prepareShapeObject(box.id), "a blockout becomes modelled quietly")
        guard case let .mesh(mesh) = editor.baseScene.objects[box.id]?.kind else { return XCTFail("modelled") }
        let edge = try XCTUnwrap(mesh.edges.first)
        editor.modeling.target = box.id
        editor.modeling.elements = MeshSelection(mode: .edge, edges: [edge])
        editor.loopCutPickedEdge()
        guard case let .mesh(cut) = editor.baseScene.objects[box.id]?.kind else { return XCTFail("still modelled") }
        XCTAssertEqual(cut.faces.count, 10)
        let top = Set(cut.vertices.indices.filter { cut.vertices[$0].y > cut.bounds.map { $0.max.y - 1e-6 } ?? 1 })
        editor.modeling.target = box.id
        editor.modeling.elements = MeshSelection(mode: .vertex, vertices: top)
        editor.mergePickedCorners()
        guard case let .mesh(merged) = editor.baseScene.objects[box.id]?.kind else { return XCTFail("still modelled") }
        XCTAssertLessThan(merged.vertices.count, cut.vertices.count, "the top corners became one")
    }

    func testASketchKeepsItsRules() throws {
        let editor = try makeEditor()
        let plane = PlaneFrame(normal: .unitY, origin: .zero)
        var ids = IDFactory.sequential("rule")
        let sketch = ModelingOperations.newSketch(on: plane, curves: [.line(Vec2(0, 0), Vec2(1, 0)), .line(Vec2(0, 1), Vec2(0.8, 1.3))],
                                                  target: nil, id: ids.next())
        XCTAssertTrue(editor.perform(.insert(SceneFragment(object: sketch), parent: nil, index: nil)))
        editor.modeling.ruleCurves = [SketchCurveRef(sketch: sketch.id, index: 0), SketchCurveRef(sketch: sketch.id, index: 1)]
        XCTAssertEqual(editor.availableRules, [.parallel, .perpendicular, .equal, .twice])
        editor.applyRule(.parallel)
        guard case let .sketch(kept) = editor.baseScene.objects[sketch.id]?.kind, case let .line(a, b) = kept.curves[0],
              case let .line(c, d) = kept.curves[1] else { return XCTFail("still a sketch of lines") }
        XCTAssertEqual((b - a).cross(d - c), 0, accuracy: 1e-6, "the lines turned parallel")
        XCTAssertEqual(kept.constraints, [.parallel(0, 1)])
    }
}
