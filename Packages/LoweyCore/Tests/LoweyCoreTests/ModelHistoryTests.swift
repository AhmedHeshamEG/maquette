import Foundation
@testable import LoweyCore
import XCTest

/// H1: the editable modelling history. Steps are recorded as the tools run; changing an early step's numbers replays
/// the steps after it, finding their faces and edges by tag.
final class ModelHistoryTests: XCTestCase {
    private let mm = 0.001

    // MARK: The SPIKE: M3's block

    /// SPIKE (H1): a hole cut through M3's block, its four upright edges rounded, then the hole made 8 mm in the history.
    /// The rounds are found again after the change, and the solid, its rounds and its STL all follow.
    func testTheM3BlocksHoleChangesInItsHistory() throws {
        var document = historyDocument()
        let id = try makeM3Block(in: &document, hole: 6 * mm)
        let roundsBefore = try roundUprightEdges(of: id, in: &document)
        let history = try XCTUnwrap(document.scene.objects[id]?.modelHistory)
        XCTAssertEqual(history.titles(format: millimetres), ["Hole, 6 mm", "Round, 2 mm"])

        let started = Date()
        let command = try ModelingOperations.changeStep(id, step: 0, number: 0, to: 8 * mm, in: document.scene, format: millimetres)
        let seconds = Date().timeIntervalSince(started)
        print("H1 SPIKE: the block's history replayed in \(String(format: "%.3f", seconds)) s")
        XCTAssertEqual(command.label, "Change Hole")
        try document.run(command)

        let changed = try mesh(of: id, in: document)
        assertSolid(changed)
        let fresh = try freshBlock(hole: 8 * mm)
        XCTAssertEqual(changed.volume, fresh.volume, accuracy: fresh.volume * 1e-6, "as if it had been made with an 8 mm hole")
        XCTAssertEqual(roundFaces(changed), roundsBefore, "the four rounds are still there")
        XCTAssertEqual(holeRadius(changed), 4 * mm, accuracy: 1e-6)
        let updated = try XCTUnwrap(document.scene.objects[id]?.modelHistory)
        XCTAssertEqual(updated.titles(format: millimetres), ["Hole, 8 mm", "Round, 2 mm"])
        XCTAssertTrue(updated.describes(changed))

        // Its export follows: the STL is the changed solid, watertight.
        let stl = STLFile.binary([ExportMesh(name: "Block", transform: .identity, mesh: changed.renderMesh(), color: RGBA(1, 0.5, 0))], name: "Block")
        let back = try MeshBuilder.mesh(from: STLFile.read(stl))
        XCTAssertTrue(MeshTopology(back).isClosedManifold)
        XCTAssertEqual(back.volume, changed.volume, accuracy: changed.volume * 1e-5)
    }

    func testAChangedStepIsOneUndoStep() throws {
        var document = historyDocument()
        let id = try makeM3Block(in: &document, hole: 6 * mm)
        _ = try roundUprightEdges(of: id, in: &document)
        let before = document.scene
        let inverse = try document.run(ModelingOperations.changeStep(id, step: 1, number: 0, to: 3 * mm, in: document.scene))
        XCTAssertNotEqual(document.scene, before)
        try document.run(inverse)
        XCTAssertEqual(document.scene, before)
    }

    // MARK: Faces that moved

    /// A face pulled up, its top edges bevelled; pulled further in the history, the bevels ride up with it.
    func testBevelsFollowAFacePulledFurther() throws {
        var document = historyDocument()
        let box = SceneObject(id: "box", name: "Box", kind: .mesh(.box(min: .zero, max: Vec3(20 * mm, 10 * mm, 20 * mm))))
        try document.run(.insert(SceneFragment(object: box), parent: nil, index: nil))
        var shape = try mesh(of: "box", in: document)
        try document.run(ModelingOperations.pushPull("box", face: face(shape, facing: .unitY), distance: 5 * mm, in: document.scene))
        shape = try mesh(of: "box", in: document)
        let top = edges(shape) { $0.contains { $0.y > 0.99 } }
        XCTAssertEqual(top.count, 4)
        try document.run(ModelingOperations.bevel("box", edges: top, size: 1 * mm, style: .chamfer, in: document.scene))

        try document.run(ModelingOperations.changeStep("box", step: 0, number: 0, to: 10 * mm, in: document.scene))
        let changed = try mesh(of: "box", in: document)
        assertSolid(changed)
        XCTAssertEqual(changed.bounds?.size.y ?? 0, 20 * mm, accuracy: 1e-9)
        // Four slanted faces and the corners where they meet: the same count as before the change.
        XCTAssertEqual(changed.faces.count, try mesh(after: [10 * mm], bevel: 1 * mm).faces.count)
        XCTAssertEqual(changed.volume, try mesh(after: [10 * mm], bevel: 1 * mm).volume, accuracy: 1e-12)
    }

    // MARK: When a replay can't go on

    func testAReplayThatCantContinueSaysWhere() throws {
        var document = historyDocument()
        let box = SceneObject(id: "box", name: "Box", kind: .mesh(.box(min: .zero, max: Vec3(20 * mm, 10 * mm, 20 * mm))))
        try document.run(.insert(SceneFragment(object: box), parent: nil, index: nil))
        let top = try face(mesh(of: "box", in: document), facing: .unitY)
        try document.run(ModelingOperations.inset("box", faces: [top], distance: 4 * mm, in: document.scene))
        try document.run(ModelingOperations.pushPull("box", face: top, distance: 3 * mm, in: document.scene))
        let before = document.scene
        XCTAssertThrowsError(try ModelingOperations.changeStep("box", step: 0, number: 0, to: 12 * mm, in: document.scene, format: millimetres)) { error in
            let line = (error as? ModelingOperations.HistoryFailure)?.description ?? ""
            XCTAssertTrue(line.hasPrefix("Step 1, Inset, 12 mm, can't follow the change"), line)
            XCTAssertFalse(line.contains("\n"), "one line")
        }
        XCTAssertEqual(document.scene, before, "nothing changes")
    }

    func testAShapeChangedByHandFixesItsSteps() throws {
        var document = historyDocument()
        let box = SceneObject(id: "box", name: "Box", kind: .mesh(.box(min: .zero, max: Vec3(20 * mm, 10 * mm, 20 * mm))))
        try document.run(.insert(SceneFragment(object: box), parent: nil, index: nil))
        let shape = try mesh(of: "box", in: document)
        try document.run(ModelingOperations.pushPull("box", face: face(shape, facing: .unitY), distance: 5 * mm, in: document.scene))
        try document.run(ModelingOperations.moveCorners("box", corners: [0], by: Vec3(0, -1 * mm, 0), in: document.scene))
        let object = try XCTUnwrap(document.scene.objects["box"])
        XCTAssertEqual(ModelingOperations.historyLock(of: object), .fixed)
        XCTAssertThrowsError(try ModelingOperations.changeStep("box", step: 0, number: 0, to: 1 * mm, in: document.scene))

        // The next step starts again from the shape as it is; the old one is listed as fixed.
        let moved = try mesh(of: "box", in: document)
        try document.run(ModelingOperations.pushPull("box", face: face(moved, facing: .unitX), distance: 2 * mm, in: document.scene))
        let history = try XCTUnwrap(document.scene.objects["box"]?.modelHistory)
        XCTAssertEqual(history.earlier.count, 1)
        XCTAssertEqual(history.steps.count, 1)
        XCTAssertEqual(history.titles(format: millimetres), ["Push/pull, 5 mm", "Push/pull, 2 mm"])
        XCTAssertNil(try ModelingOperations.historyLock(of: XCTUnwrap(document.scene.objects["box"])))
    }

    func testPaintingFixesTheHistory() throws {
        var document = historyDocument()
        let box = SceneObject(id: "box", name: "Box", kind: .mesh(.box(min: .zero, max: Vec3(20 * mm, 10 * mm, 20 * mm))))
        try document.run(.insert(SceneFragment(object: box), parent: nil, index: nil))
        let shape = try mesh(of: "box", in: document)
        try document.run(ModelingOperations.pushPull("box", face: face(shape, facing: .unitY), distance: 5 * mm, in: document.scene))
        try document.run(.setPaint("box", ObjectPaint(surface: PaintSurface(size: 512, unwrap: "u", mesh: "m"), layers: [])))
        let object = try XCTUnwrap(document.scene.objects["box"])
        XCTAssertEqual(ModelingOperations.historyLock(of: object), .painted)
        // A step after painting isn't recorded: the history stays as it was.
        let moved = try mesh(of: "box", in: document)
        try document.run(ModelingOperations.pushPull("box", face: face(moved, facing: .unitX), distance: 1 * mm, in: document.scene))
        XCTAssertEqual(document.scene.objects["box"]?.modelHistory?.steps.count, 1)
    }

    // MARK: Symmetry and booleans

    func testASymmetricPullChangesBothSides() throws {
        var document = historyDocument()
        let box = SceneObject(id: "box", name: "Box", kind: .mesh(.box(min: Vec3(-10 * mm, 0, -5 * mm), max: Vec3(10 * mm, 10 * mm, 5 * mm))),
                              properties: [.symmetry: .enumeration(SymmetryAxis.x.rawValue)])
        try document.run(.insert(SceneFragment(object: box), parent: nil, index: nil))
        let top = try face(mesh(of: "box", in: document), facing: .unitY)
        try document.run(ModelingOperations.inset("box", faces: [top], distance: 2 * mm, in: document.scene))
        let side = try face(mesh(of: "box", in: document), facing: .unitX)
        try document.run(ModelingOperations.pushPull("box", face: side, distance: 3 * mm, in: document.scene))
        XCTAssertEqual(try mesh(of: "box", in: document).bounds?.size.x ?? 0, 26 * mm, accuracy: 1e-9)
        try document.run(ModelingOperations.changeStep("box", step: 1, number: 0, to: 5 * mm, in: document.scene))
        let changed = try mesh(of: "box", in: document)
        assertSolid(changed)
        XCTAssertEqual(changed.bounds?.min.x ?? 0, -15 * mm, accuracy: 1e-9, "the mirror image follows")
        XCTAssertEqual(changed.bounds?.max.x ?? 0, 15 * mm, accuracy: 1e-9)
    }

    func testABooleanIsAStepOfTheOneThatStays() throws {
        var document = historyDocument()
        let a = SceneObject(id: "a", name: "A", kind: .mesh(.box(min: .zero, max: Vec3(20 * mm, 10 * mm, 20 * mm))))
        let b = SceneObject(id: "b", name: "B", kind: .mesh(.box(min: Vec3(15 * mm, -1 * mm, 5 * mm), max: Vec3(25 * mm, 11 * mm, 15 * mm))))
        try document.run(.insert(SceneFragment(objects: [a, b], roots: ["a", "b"]), parent: nil, index: nil))
        try document.run(ModelingOperations.boolean(["a", "b"], .subtract, in: document.scene))
        let history = try XCTUnwrap(document.scene.objects["a"]?.modelHistory)
        XCTAssertEqual(history.titles(format: millimetres), ["Subtract"])
        XCTAssertTrue(try history.describes(mesh(of: "a", in: document)))
        XCTAssertTrue(history.steps[0].numbers.isEmpty)
    }

    // MARK: Saving

    func testTheHistorySurvivesSavingAndStillDescribesItsShape() throws {
        var document = historyDocument()
        let id = try makeM3Block(in: &document, hole: 6 * mm)
        let data = try SchemaCoder.shared.encode(document.scene, kind: .scene)
        let scene = try SchemaCoder.shared.decode(Scene.self, kind: .scene, from: data)
        let object = try XCTUnwrap(scene.objects[id])
        XCTAssertEqual(object.modelHistory, document.scene.objects[id]?.modelHistory)
        XCTAssertNil(ModelingOperations.historyLock(of: object), "the saved shape is still the one the steps make")
        let command = EditCommand.setModelHistory(id, object.modelHistory)
        XCTAssertEqual(try JSONDecoder().decode(EditCommand.self, from: JSONEncoder().encode(command)), command)
    }

    func testTagsCarryThroughACutAndStayUnder53Bits() throws {
        let block = EditableMesh.box(min: .zero, max: Vec3(40 * mm, 10 * mm, 20 * mm))
        let step = ModelStep(tag: 7, action: .combine(tool: .cylinder(base: Vec3(20 * mm, -1 * mm, 10 * mm), radius: 3 * mm, height: 12 * mm, segments: 24),
                                                      operation: .subtract))
        let shape = try step.apply(to: ModelStep.Shape(mesh: block, tags: PartTags.base(count: 6)))
        let base = Set(PartTags.base(count: 6))
        XCTAssertEqual(shape.tags.filter(base.contains).count, 6, "the six sides keep their names")
        XCTAssertEqual(Set(shape.tags.filter { !base.contains($0) }).count, 24, "each wall of the hole is named once")
        XCTAssertTrue(shape.tags.allSatisfy { $0 < 1 << 53 })
    }

    // MARK: Helpers

    private func millimetres(_ metres: Double) -> String {
        let value = metres * 1000
        return value.rounded() == value ? "\(Int(value)) mm" : String(format: "%.1f mm", value)
    }

    /// M3's acceptance part in the app's way: a rectangle pulled 10 mm, a circle on its top cut through it.
    private func makeM3Block(in document: inout Document, hole: Double) throws -> ObjectID {
        var ids = IDFactory.sequential("h")
        let sketchID: ObjectID = ids.next()
        let base = ModelingOperations.newSketch(on: PlaneFrame(origin: .zero, normal: .unitY, u: .unitX, v: Vec3(0, 0, -1)),
                                                curves: [.rectangle(Vec2(0, -20 * mm), Vec2(40 * mm, 0))], target: nil, id: sketchID)
        try document.run(.insert(SceneFragment(object: base), parent: nil, index: nil))
        try document.run(ModelingOperations.pull(sketch: sketchID, region: 0, distance: 10 * mm, in: document.scene, ids: &ids))
        let solid = try XCTUnwrap(document.scene.objects.values.first { $0.kind.typeName == "mesh" })
        let top = PlaneFrame(origin: Vec3(0, 10 * mm, 0), normal: .unitY, u: .unitX, v: Vec3(0, 0, -1))
        let circleID: ObjectID = ids.next()
        let circle = ModelingOperations.newSketch(on: top, curves: [.circle(center: Vec2(20 * mm, -10 * mm), radius: hole / 2)],
                                                  target: solid.id, id: circleID)
        try document.run(.insert(SceneFragment(object: circle), parent: nil, index: nil))
        try document.run(ModelingOperations.pull(sketch: circleID, region: 0, distance: -10 * mm, in: document.scene, ids: &ids))
        return solid.id
    }

    /// Rounds the block's four upright edges by 2 mm; returns how many faces the rounds made.
    private func roundUprightEdges(of id: ObjectID, in document: inout Document) throws -> Int {
        let shape = try mesh(of: id, in: document)
        let upright = edges(shape) { normals in normals.allSatisfy { abs($0.y) < 1e-6 && (abs($0.x) > 0.99 || abs($0.z) > 0.99) } }
        XCTAssertEqual(upright.count, 4)
        try document.run(ModelingOperations.bevel(id, edges: upright, size: 2 * mm, style: .round, in: document.scene))
        return try roundFaces(mesh(of: id, in: document))
    }

    private func freshBlock(hole: Double) throws -> EditableMesh {
        var document = historyDocument()
        let id = try makeM3Block(in: &document, hole: hole)
        _ = try roundUprightEdges(of: id, in: &document)
        return try mesh(of: id, in: document)
    }

    private func mesh(after pulls: [Double], bevel: Double) throws -> EditableMesh {
        var mesh = EditableMesh.box(min: .zero, max: Vec3(20 * mm, 10 * mm, 20 * mm))
        for pull in pulls {
            mesh = try PushPull.apply(mesh, face: face(mesh, facing: .unitY), distance: pull)
        }
        return try EdgeBevel.apply(mesh, edges: edges(mesh) { $0.contains { $0.y > 0.99 } }, size: bevel, style: .chamfer)
    }

    /// Faces of a round: upright, facing neither straight along x nor along z, and outside the hole.
    private func roundFaces(_ mesh: EditableMesh) -> Int {
        let middle = Vec3.zero
        return mesh.faces.indices.filter { face in
            let normal = mesh.normal(of: face)
            let centre = mesh.centroid(of: face)
            return abs(normal.y) < 1e-6 && abs(normal.x) < 0.999 && abs(normal.z) < 0.999 && Vec3(centre.x - middle.x, 0, centre.z - middle.z).length > 6 * mm
        }.count
    }

    private func holeRadius(_ mesh: EditableMesh) -> Double {
        let middle = Vec3.zero
        return mesh.vertices.map { Vec3($0.x - middle.x, 0, $0.z - middle.z).length }.min() ?? 0
    }

    private func edges(_ mesh: EditableMesh, where test: ([Vec3]) -> Bool) -> Set<MeshEdge> {
        let topology = MeshTopology(mesh)
        return Set(mesh.edges.filter { edge in
            let normals = topology.faces(along: edge).map { mesh.normal(of: $0) }
            return normals.count == 2 && abs(normals[0].dot(normals[1])) < 1e-6 && test(normals)
        })
    }

    private func face(_ mesh: EditableMesh, facing direction: Vec3) -> Int {
        mesh.faces.indices.first { mesh.normal(of: $0).dot(direction) > 0.999 } ?? -1
    }

    private func mesh(of id: ObjectID, in document: Document) throws -> EditableMesh {
        guard case let .mesh(mesh)? = document.scene.objects[id]?.kind else { throw ModelingOperations.Failure.notEditable }
        return mesh
    }

    private func assertSolid(_ mesh: EditableMesh, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(MeshTopology(mesh).isClosedManifold, "closed manifold", file: file, line: line)
        XCTAssertTrue(MeshBoolean.isSolid(mesh), "Manifold accepts it", file: file, line: line)
        XCTAssertGreaterThan(mesh.volume, 0, "faces point out", file: file, line: line)
    }
}

private func historyDocument() -> Document {
    let scene = Scene(id: "scene-1", name: "Test", objects: [:], roots: [])
    let info = ProjectInfo(id: "project-1", name: "Test", created: Date(timeIntervalSince1970: 0), modified: Date(timeIntervalSince1970: 0),
                           sceneOrder: ["scene-1"], sceneNames: ["scene-1": "Test"])
    return Document(project: info, scene: scene)
}

private extension Document {
    @discardableResult
    mutating func run(_ command: EditCommand) throws -> EditCommand {
        try command.apply(to: &self).inverse
    }
}
