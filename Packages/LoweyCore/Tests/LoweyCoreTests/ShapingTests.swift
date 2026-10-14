import Foundation
@testable import LoweyCore
import XCTest

/// U6: whole-shape bends, the cage, surface brushes, the shape stack, linked copies, the pivot and typed sizes.
final class ShapingTests: XCTestCase {
    private func object(_ kind: ObjectKind, _ properties: [PropertyKey: PropertyValue] = [:]) -> SceneObject {
        SceneObject(id: ObjectID("thing"), name: "Thing", kind: kind, properties: properties)
    }

    /// A tall box cut finely enough to bend.
    private var column: MeshData {
        MeshDensify.densified(EditableMesh.box(min: Vec3(-0.5, 0, -0.5), max: Vec3(0.5, 4, 0.5)).renderMesh(), cuts: 16)
    }

    // MARK: Bends

    func testTwistTurnsTheTopAndLeavesTheFoot() throws {
        let column = column
        let bounds = try XCTUnwrap(column.bounds)
        let twisted = Deform.twist.apply(column.positions, amount: 90, axis: .y, bounds: bounds)
        for (before, after) in zip(column.positions, twisted) {
            if before.y < 1e-6 { XCTAssertEqual(before, after) }
            if before.y > 4 - 1e-6 {
                // A quarter turn about y: (x, z) → (−z… ) keeps the distance from the axis.
                XCTAssertEqual(hypot(Double(after.x), Double(after.z)), hypot(Double(before.x), Double(before.z)), accuracy: 1e-5)
            }
        }
        let corner = try XCTUnwrap(zip(column.positions, twisted).first { $0.0 == SIMD3<Float>(0.5, 4, 0.5) })
        // A right-handed quarter turn about +y: (x, z) → (z, −x).
        XCTAssertEqual(corner.1.x, 0.5, accuracy: 1e-5)
        XCTAssertEqual(corner.1.z, -0.5, accuracy: 1e-5)
    }

    func testBendTurnsTheTopByTheAmount() throws {
        let column = column
        let bounds = try XCTUnwrap(column.bounds)
        let bent = Deform.bend.apply(column.positions, amount: 90, axis: .y, bounds: bounds)
        let top = bent.enumerated().filter { column.positions[$0.offset].y > 4 - 1e-6 }.map(\.element)
        // A quarter bend lays the top on its side, facing +z: its corners share one z, a radius (4 / ½π) along.
        let sides = top.map(\.z)
        XCTAssertLessThan((sides.max() ?? 0) - (sides.min() ?? 0), 1e-4)
        XCTAssertEqual(Double(sides[0]), 4 / (.pi / 2), accuracy: 1e-4, "it curls toward +z")
        let foot = bent.enumerated().filter { column.positions[$0.offset].y < 1e-6 }
        XCTAssertTrue(foot.allSatisfy { $0.element == column.positions[$0.offset] })
    }

    func testTaperAndBulge() throws {
        let column = column
        let bounds = try XCTUnwrap(column.bounds)
        let tapered = Deform.taper.apply(column.positions, amount: -0.5, axis: .y, bounds: bounds)
        let top = tapered.enumerated().filter { column.positions[$0.offset].y > 4 - 1e-6 }.map(\.element)
        XCTAssertEqual(top.map(\.x).max() ?? 0, 0.25, accuracy: 1e-5)
        let bulged = Deform.bulge.apply(column.positions, amount: 1, axis: .y, bounds: bounds)
        let middle = bulged.enumerated().filter { abs(column.positions[$0.offset].y - 2) < 1e-6 }.map(\.element)
        XCTAssertEqual(middle.map(\.x).max() ?? 0, 1, accuracy: 1e-5)
    }

    func testAnObjectsBendIsReadFromItsProperties() {
        XCTAssertNil(Deform.of(object(.primitive(.cube))))
        let bent = object(.primitive(.cube), [.deform: .enumeration("twist"), .deformAmount: .float(30), .deformAxis: .enumeration("x")])
        XCTAssertEqual(Deform.of(bent)?.kind, .twist)
        XCTAssertEqual(Deform.of(bent)?.axis, .x)
        XCTAssertNil(Deform.of(object(.primitive(.cube), [.deform: .enumeration("twist"), .deformAmount: .float(0)])))
    }

    // MARK: Cage

    func testACageAtRestChangesNothing() throws {
        let column = column
        let cage = try DeformCage.around(XCTUnwrap(column.bounds))
        XCTAssertTrue(cage.isAtRest)
        XCTAssertEqual(CageDeform.apply(cage, to: column.positions), column.positions)
    }

    func testPullingTheCagesTopPointsStretchesTheTop() throws {
        let column = column
        var cage = try DeformCage.around(XCTUnwrap(column.bounds), counts: [2, 2, 2])
        for k in 0 ..< 2 {
            for i in 0 ..< 2 {
                cage.offsets[cage.index(i, 1, k)] = Vec3(0, 1, 0)
            }
        }
        let moved = CageDeform.apply(cage, to: column.positions)
        let topBefore = column.positions.map(\.y).max() ?? 0
        XCTAssertGreaterThan(moved.map(\.y).max() ?? 0, topBefore + 0.9)
        XCTAssertEqual(moved.map(\.y).min() ?? 1, 0, accuracy: 0.06, "the foot barely moves")
    }

    func testAMovedPointInABiggerCageMovesOnlyItsCorner() throws {
        let column = column
        var cage = try DeformCage.around(XCTUnwrap(column.bounds), counts: [3, 3, 3])
        cage.offsets[cage.index(2, 2, 2)] = Vec3(1, 0, 0)
        let moved = CageDeform.apply(cage, to: column.positions)
        let far = try XCTUnwrap(zip(column.positions, moved).first { $0.0 == SIMD3<Float>(0.5, 4, 0.5) })
        let near = try XCTUnwrap(zip(column.positions, moved).first { $0.0 == SIMD3<Float>(-0.5, 0, -0.5) })
        XCTAssertGreaterThan(far.1.x, 0.8)
        XCTAssertEqual(near.1.x, -0.5, accuracy: 1e-5)
    }

    func testCagesAreCodable() throws {
        var cage = DeformCage(counts: [2, 9, 1], bounds: Bounds(min: .zero, max: .one))
        XCTAssertEqual(cage.counts, [2, 4, 2], "2 to 4 points each way")
        cage.offsets[3] = Vec3(0.1, 0.2, 0.3)
        let shaping = ObjectShaping(cage: cage)
        let decoded = try JSONDecoder().decode(ObjectShaping.self, from: JSONEncoder().encode(shaping))
        XCTAssertEqual(decoded, shaping)
    }

    // MARK: Brushes

    private var ball: MeshData { MeshDensify.densified(PrimitiveMesh.make(.sphere, shading: .smooth), cuts: 10) }

    func testGrabPullsAPatchAndItsMirror() throws {
        let mesh = ball
        var stroke = SculptStroke(brush: .grab, mesh: mesh, cornerOffsets: nil, symmetry: .x)
        let side = try XCTUnwrap(mesh.positions.max { $0.x < $1.x })
        stroke.dab(at: side, radius: 0.2, strength: 1, moved: SIMD3<Float>(0.3, 0, 0))
        let offsets = stroke.cornerOffsets
        XCTAssertGreaterThan(offsets.map(\.x).max() ?? 0, 0.29, "the grabbed side moves out")
        XCTAssertLessThan(offsets.map(\.x).min() ?? 0, -0.29, "and its mirror image moves out the other way")
        // Corners at the same place moved together (the surface doesn't tear).
        for (i, position) in mesh.positions.enumerated() {
            for (j, other) in mesh.positions.enumerated() where j > i && position == other {
                XCTAssertEqual(offsets[i], offsets[j])
            }
        }
    }

    func testGrabHoldsThePatchItStartedWith() throws {
        let mesh = ball
        var stroke = SculptStroke(brush: .grab, mesh: mesh, cornerOffsets: nil, symmetry: nil)
        let top = try XCTUnwrap(mesh.positions.max { $0.y < $1.y })
        stroke.dab(at: top, radius: 0.2, strength: 1, moved: SIMD3<Float>(0, 0.2, 0))
        let first = stroke.cornerOffsets
        // The pencil has moved on, but the drag so far is what counts, on the same patch.
        stroke.dab(at: top + SIMD3<Float>(0, 0.2, 0), radius: 0.2, strength: 1, moved: SIMD3<Float>(0, 0.4, 0))
        let second = stroke.cornerOffsets
        XCTAssertEqual(Set(first.indices.filter { first[$0] != .zero }), Set(second.indices.filter { second[$0] != .zero }))
        XCTAssertEqual(second.map(\.y).max() ?? 0, 0.4, accuracy: 1e-5)
    }

    func testInflatePuffsOutAndSmoothEvensBumps() throws {
        let mesh = ball
        var inflate = SculptStroke(brush: .inflate, mesh: mesh, cornerOffsets: nil, symmetry: nil)
        let top = try XCTUnwrap(mesh.positions.max { $0.y < $1.y })
        inflate.dab(at: top, radius: 0.3, strength: 1)
        XCTAssertGreaterThan(inflate.positions.map(\.y).max() ?? 0, top.y)
        var smooth = SculptStroke(brush: .smooth, mesh: mesh, cornerOffsets: inflate.cornerOffsets, symmetry: nil)
        let peak = smooth.positions.map(\.y).max() ?? 0
        for _ in 0 ..< 10 {
            smooth.dab(at: top, radius: 0.3, strength: 1)
        }
        XCTAssertLessThan(smooth.positions.map(\.y).max() ?? 0, peak)
    }

    func testStrokesAreStoredSparselyAndReadBack() throws {
        var offsets = Array(repeating: SIMD3<Float>(0, 0, 0), count: 1000)
        offsets[7] = SIMD3<Float>(0.1, -0.2, 0.3)
        offsets[900] = SIMD3<Float>(1, 2, 3)
        let layer = SculptLayer(offsets: offsets)
        XCTAssertEqual(layer.moved.count, 2)
        let json = try JSONEncoder().encode(layer)
        XCTAssertLessThan(json.count, 120, "only the moved corners are written")
        let decoded = try JSONDecoder().decode(SculptLayer.self, from: json)
        XCTAssertEqual(decoded, layer)
        XCTAssertEqual(decoded.offsets, offsets)
    }

    // MARK: The stack

    func testTheStackAppliesStrokesCageAndBendInOrder() throws {
        let cube = SceneObject(id: ObjectID("c"), name: "Cube", kind: .mesh(EditableMesh.box(min: Vec3(-0.5, 0, -0.5), max: Vec3(0.5, 1, 0.5))))
        XCTAssertNil(ShapeStack.key(of: cube), "nothing to do")
        let plain = try XCTUnwrap(PaintSource.mesh(of: cube))
        var bent = cube
        bent[.deform] = .enumeration("taper")
        bent[.deformAmount] = .float(-1)
        XCTAssertNotNil(ShapeStack.key(of: bent))
        let shaped = try XCTUnwrap(PaintSource.mesh(of: bent))
        XCTAssertEqual(shaped.positions.count, plain.positions.count, "corners move, none are added")
        let top = shaped.positions.filter { $0.y > 0.99 }
        XCTAssertTrue(top.allSatisfy { abs($0.x) < 1e-5 && abs($0.z) < 1e-5 }, "tapered to a point")
        // Strokes for another number of corners are left behind.
        var stroked = cube
        stroked.shaping = ObjectShaping(sculpt: SculptLayer(vertexCount: 3, moved: [0: SIMD3<Float>(1, 0, 0)]))
        XCTAssertEqual(PaintSource.mesh(of: stroked)?.positions, plain.positions)
    }

    func testSmoothingAShapeRoundsItWherevaritsShown() throws {
        let cube = SceneObject(id: ObjectID("c"), name: "Cube", kind: .mesh(EditableMesh.box(min: Vec3(-0.5, 0, -0.5), max: Vec3(0.5, 1, 0.5))),
                               properties: [.subdivision: .int(2)])
        let shown = try XCTUnwrap(PaintSource.mesh(of: cube))
        XCTAssertEqual(shown.triangleCount, 96 * 2)
        let exported = try XCTUnwrap(SceneExport.localMesh(of: cube, look: Look()))
        XCTAssertEqual(exported.triangleCount, 96 * 2)
        let primitive = SceneObject(id: ObjectID("p"), name: "Cube", kind: .primitive(.cube), properties: [.subdivision: .int(1)])
        XCTAssertEqual(PaintSource.mesh(of: primitive)?.triangleCount, 24 * 2)
    }

    func testTheSmoothAngleKeepsHardEdgesCrisp() throws {
        let cube = EditableMesh.box(min: .zero, max: .one)
        let soft = SceneObject(id: ObjectID("c"), name: "Cube", kind: .mesh(cube), properties: [.smoothAngle: .float(120)])
        let rendered = ShapeStack.render(cube, for: soft)
        // Every corner of the cube averages three faces: no normal points straight along an axis.
        XCTAssertTrue(rendered.normals.allSatisfy { abs($0.x) < 0.99 && abs($0.y) < 0.99 })
        let crisp = ShapeStack.render(cube, for: SceneObject(id: ObjectID("d"), name: "Cube", kind: .mesh(cube), properties: [.smoothAngle: .float(30)]))
        XCTAssertTrue(crisp.normals.allSatisfy { max(abs($0.x), abs($0.y), abs($0.z)) > 0.999 })
    }

    // MARK: Commands

    private func scene(with objects: [SceneObject]) -> Scene {
        var scene = Scene(id: "s", name: "Test")
        for object in objects {
            scene.objects[object.id] = object
            scene.roots.append(object.id)
        }
        return scene
    }

    private func apply(_ command: EditCommand, to scene: Scene) throws -> Scene {
        var document = Document(project: ProjectInfo(id: "p", name: "T"), scene: scene)
        _ = try command.apply(to: &document)
        return document.scene
    }

    func testShapingRoundTripsThroughUndo() throws {
        let start = scene(with: [object(.primitive(.cube))])
        let shaping = ObjectShaping(cage: DeformCage.around(.unitBase), sculpt: SculptLayer(vertexCount: 3, moved: [1: SIMD3<Float>(0, 1, 0)]))
        var document = Document(project: ProjectInfo(id: "p", name: "T"), scene: start)
        let applied = try EditCommand.setShaping(ObjectID("thing"), shaping).apply(to: &document)
        XCTAssertEqual(document.scene.objects[ObjectID("thing")]?.shaping, shaping)
        _ = try applied.inverse.apply(to: &document)
        XCTAssertNil(document.scene.objects[ObjectID("thing")]?.shaping)
        let json = try JSONEncoder().encode(EditCommand.setShaping(ObjectID("thing"), shaping))
        XCTAssertEqual(try JSONDecoder().decode(EditCommand.self, from: json), .setShaping(ObjectID("thing"), shaping))
    }

    func testLinkedCopiesChangeTogether() throws {
        var ids = IDFactory.sequential("o")
        let original = SceneObject(id: ObjectID("a"), name: "Box", kind: .mesh(.box(min: .zero, max: .one)))
        var start = scene(with: [original])
        start = try apply(XCTUnwrap(LinkedCopies.makeCopy(of: ObjectID("a"), in: start, offset: Vec3(2, 0, 0), ids: &ids)), to: start)
        let copy = try XCTUnwrap(LinkedCopies.partners(of: ObjectID("a"), in: start).first)
        let edit = try ModelingOperations.pushPull(ObjectID("a"), face: 3, distance: 0.5, in: start)
        let after = try apply(LinkedCopies.propagate(edit, in: start), to: start)
        XCTAssertEqual(after.objects[copy]?.kind, after.objects[ObjectID("a")]?.kind)
        XCTAssertEqual(after.objects[copy]?.transform.position, Vec3(2, 0, 0), "where it stands is its own")
        let smoothed = try apply(LinkedCopies.propagate(.setProperties([PropertyChange(object: copy, key: .subdivision, value: .int(1))]), in: after),
                                 to: after)
        XCTAssertEqual(smoothed.objects[ObjectID("a")]?[.subdivision], .int(1))
        let unlinked = try apply(LinkedCopies.unlink(copy), to: smoothed)
        XCTAssertTrue(LinkedCopies.partners(of: ObjectID("a"), in: unlinked).isEmpty)
    }

    func testABakedScaleReachesPartnersAtTheirOwnSize() throws {
        var ids = IDFactory.sequential("o")
        let original = SceneObject(id: ObjectID("a"), name: "Box", kind: .mesh(.box(min: .zero, max: .one)), transform: Transform(scale: Vec3(2, 2, 2)))
        var start = scene(with: [original])
        start = try apply(XCTUnwrap(LinkedCopies.makeCopy(of: ObjectID("a"), in: start, offset: .zero, ids: &ids)), to: start)
        let copy = try XCTUnwrap(LinkedCopies.partners(of: ObjectID("a"), in: start).first)
        // Push/pull bakes the 2× scale into the original's corners; the copy keeps its own 2× and gets the unit shape.
        let edit = try ModelingOperations.pushPull(ObjectID("a"), face: 3, distance: 1, in: start)
        let after = try apply(LinkedCopies.propagate(edit, in: start), to: start)
        guard case let .mesh(copyMesh) = after.objects[copy]?.kind, case let .mesh(mine) = after.objects[ObjectID("a")]?.kind else {
            return XCTFail("both are meshes")
        }
        XCTAssertEqual(copyMesh.volume * 8, mine.volume, accuracy: 1e-9)
    }

    func testMovingThePivotKeepsTheShapeWhereItIs() throws {
        let start = scene(with: [SceneObject(id: ObjectID("a"), name: "Box", kind: .primitive(.cube), transform: Transform(position: Vec3(1, 0, 0)))])
        let before = SceneBounds().worldBounds(of: ObjectID("a"), in: start)
        let middle = try XCTUnwrap(Arrange.pivotPoint(.middle, of: ObjectID("a"), in: start, bounds: SceneBounds()))
        let after = try apply(Arrange.movePivot(ObjectID("a"), to: middle, in: start), to: start)
        XCTAssertEqual(after.objects[ObjectID("a")]?.transform.position, Vec3(1, 0.5, 0))
        let bounds = try XCTUnwrap(SceneBounds().worldBounds(of: ObjectID("a"), in: after))
        XCTAssertTrue(try bounds.min.isApproximately(XCTUnwrap(before).min))
    }

    func testTypingALengthResizesOneSide() throws {
        let start = scene(with: [SceneObject(id: ObjectID("a"), name: "Box", kind: .mesh(.box(min: Vec3(-0.5, 0, -0.5), max: Vec3(0.5, 1, 0.5))))])
        let after = try apply(Arrange.setLength(ObjectID("a"), axis: .y, to: 0.04, in: start), to: start)
        let bounds = try XCTUnwrap(SceneBounds().worldBounds(of: ObjectID("a"), in: after))
        XCTAssertEqual(bounds.size.y, 0.04, accuracy: 1e-12)
        XCTAssertEqual(bounds.min.y, 0, accuracy: 1e-12, "it stays on the ground")
        let primitive = scene(with: [SceneObject(id: ObjectID("p"), name: "Cube", kind: .primitive(.cube))])
        let wider = try apply(Arrange.setLength(ObjectID("p"), axis: .x, to: 3, in: primitive), to: primitive)
        XCTAssertEqual(wider.objects[ObjectID("p")]?.transform.scale.x ?? 0, 3, accuracy: 1e-12)
    }

    // MARK: Constraints

    func testAConstrainedSketchUpdatesWhenOneNumberChanges() throws {
        // Two lines from the origin: a horizontal base and a slanted side, kept perpendicular; the side twice the base.
        let base = SketchCurve.line(Vec2(0, 0), Vec2(1, 0))
        let side = SketchCurve.line(Vec2(0, 0), Vec2(0.2, 1))
        var sketch = Sketch(plane: PlaneFrame(normal: .unitY, origin: .zero), curves: [base, side])
        sketch = try sketch.constraining(.perpendicular(0, 1))
        sketch = try sketch.constraining(.ratio(1, 0, factor: 2))
        sketch = try sketch.constraining(.length(0, 1))
        guard case let .line(a, b) = sketch.curves[1], case let .line(baseA, baseB) = sketch.curves[0] else { return XCTFail("still lines") }
        XCTAssertEqual((b - a).length, 2, accuracy: 1e-6)
        XCTAssertEqual((b - a).dot(baseB - baseA), 0, accuracy: 1e-6, "perpendicular to the base")
        XCTAssertEqual((a - baseA).length, 0, accuracy: 1e-9, "the shared corner stays shared")
        // Type a new length for the base (its start and direction kept, as the stage does): the side follows.
        let longer = SketchCurve.line(baseA, baseA + (baseB - baseA) * 3)
        let changed = try sketch.changing(curve: 0, to: longer)
        guard case let .line(c, d) = changed.curves[1], case let .line(newA, newB) = changed.curves[0] else { return XCTFail("still lines") }
        XCTAssertEqual((d - c).length, 6, accuracy: 1e-5)
        XCTAssertEqual((newB - newA).length, 3, accuracy: 1e-6)
        XCTAssertEqual((c - newA).length, 0, accuracy: 1e-9, "still joined")
        XCTAssertTrue(changed.constraints.contains {
            if case let .length(0, value, _) = $0 {
                abs(value - 3) < 1e-9
            } else { false }
        },
        "the lock takes the typed number")
    }

    func testParallelEqualAngleAndTangent() throws {
        let curves: [SketchCurve] = [.line(Vec2(0, 0), Vec2(1, 0.1)), .line(Vec2(0, 1), Vec2(0.5, 1.4)), .circle(center: Vec2(0.5, 3), radius: 0.4)]
        var sketch = Sketch(plane: PlaneFrame(normal: .unitY, origin: .zero), curves: curves)
        sketch = try sketch.constraining(.angle(0, 0))
        sketch = try sketch.constraining(.parallel(1, 0))
        sketch = try sketch.constraining(.equal(1, 0))
        sketch = try sketch.constraining(.tangent(line: 1, circle: 2))
        let layout = Layout(sketch.curves)
        let p = layout.parameters(sketch.curves)
        let (a, b) = try XCTUnwrap(layout.ends(1, p))
        XCTAssertEqual(b.y - a.y, 0, accuracy: 1e-6)
        XCTAssertEqual(try XCTUnwrap(layout.size(1, p, side: 0)), try XCTUnwrap(layout.size(0, p, side: 0)), accuracy: 1e-6)
        let (centre, radius) = try XCTUnwrap(layout.circle(2, p))
        XCTAssertEqual(abs(centre.y - a.y), radius, accuracy: 1e-6)
    }

    func testConflictingRulesAreRefused() throws {
        let sketch = Sketch(plane: PlaneFrame(normal: .unitY, origin: .zero), curves: [.line(Vec2(0, 0), Vec2(1, 0))])
        let locked = try sketch.constraining(.length(0, 1))
        XCTAssertThrowsError(try locked.constraining(.length(0, 2)))
    }

    func testRulesFollowTheirCurvesWhenOthersAreRemoved() throws {
        var sketch = Sketch(plane: PlaneFrame(normal: .unitY, origin: .zero),
                            curves: [.circle(center: .zero, radius: 1), .line(Vec2(0, 0), Vec2(1, 0)), .line(Vec2(0, 1), Vec2(1, 1))])
        sketch.constraints = [.parallel(1, 2), .length(0, 2)]
        let trimmed = sketch.removingCurves([0])
        XCTAssertEqual(trimmed.constraints, [.parallel(0, 1)])
        let json = try JSONEncoder().encode(sketch)
        XCTAssertEqual(try JSONDecoder().decode(Sketch.self, from: json), sketch)
        let old = #"{"plane":{"origin":[0,0,0],"normal":[0,1,0],"u":[1,0,0],"v":[0,0,-1]},"curves":[]}"#
        XCTAssertEqual(try JSONDecoder().decode(Sketch.self, from: Data(old.utf8)).constraints, [], "older sketches have no rules")
    }
}
