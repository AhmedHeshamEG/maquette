import Foundation
@testable import LoweyCore
import XCTest

/// U6's modelling set on the mesh: subdivide, loop cut, knife, fill hole, merge, bridge, sweep, revolve, loft and
/// clean topology.
final class ModelingSetTests: XCTestCase {
    private var cube: EditableMesh { .box(min: Vec3(-0.5, 0, -0.5), max: Vec3(0.5, 1, 0.5)) }

    private func assertSolid(_ mesh: EditableMesh, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(MeshTopology(mesh).isClosedManifold, "closed manifold", file: file, line: line)
        XCTAssertGreaterThan(mesh.volume, 0, "faces point out", file: file, line: line)
    }

    // MARK: Subdivide

    func testSubdividingACubeRoundsItIntoQuads() {
        let once = Subdivision.subdivide(cube, levels: 1)
        XCTAssertEqual(once.faces.count, 24)
        XCTAssertEqual(once.vertices.count, 26)
        XCTAssertTrue(once.faces.allSatisfy { $0.outline.count == 4 })
        assertSolid(once)
        XCTAssertLessThan(once.volume, cube.volume, "it shrinks toward a pebble")
        let twice = Subdivision.subdivide(cube, levels: 2)
        XCTAssertEqual(twice.faces.count, 96)
        assertSolid(twice)
        XCTAssertLessThan(twice.volume, once.volume)
        XCTAssertGreaterThan(twice.volume, 0.3)
    }

    func testSubdivisionKeepsAnOpenBorderInPlace() {
        let plane = EditableMesh(vertices: [Vec3(0, 0, 0), Vec3(1, 0, 0), Vec3(1, 0, -1), Vec3(0, 0, -1)], faces: [EditableMesh.Face([0, 1, 2, 3])])
        let result = Subdivision.subdivide(plane, levels: 1)
        XCTAssertEqual(result.faces.count, 4)
        XCTAssertTrue(result.vertices.allSatisfy { abs($0.y) < 1e-12 })
        XCTAssertEqual(result.bounds?.size.x ?? 0, 1, accuracy: 1e-9, "the border stays where it was")
        XCTAssertTrue(result.vertices.contains(Vec3(0, 0, 0)), "a border's corner keeps its place")
    }

    func testSubdivisionCapsAtThreeLevels() {
        XCTAssertEqual(Subdivision.subdivide(cube, levels: 9).faces.count, 6 * 64)
    }

    // MARK: Loop cut

    func testALoopCutRunsAroundTheCube() {
        // The bottom front edge (0 → 1 along x); its ring is the four edges along x round the sides.
        let ring = LoopCut.ring(from: MeshEdge(0, 1), in: cube)
        XCTAssertEqual(ring.count, 4)
        let cut = LoopCut.cut(cube, across: MeshEdge(0, 1))
        XCTAssertEqual(cut.faces.count, 10)
        XCTAssertEqual(cut.vertices.count, 12)
        assertSolid(cut)
        XCTAssertEqual(cut.volume, cube.volume, accuracy: 1e-12)
        let added = cut.vertices.suffix(4)
        XCTAssertTrue(added.allSatisfy { abs($0.x) < 1e-12 }, "every new corner sits halfway across")
    }

    func testSeveralCutsSpaceEvenly() {
        let cut = LoopCut.cut(cube, across: MeshEdge(0, 1), cuts: 3)
        XCTAssertEqual(cut.faces.count, 2 + 4 * 4)
        assertSolid(cut)
        let xs = Set(cut.vertices.suffix(12).map { ($0.x * 1000).rounded() })
        XCTAssertEqual(xs, [-250, 0, 250])
    }

    func testAnOffCentreCutLinesUpAroundTheRing() {
        let cut = LoopCut.cut(cube, across: MeshEdge(0, 1), position: 0.25)
        assertSolid(cut)
        let xs = Set(cut.vertices.suffix(4).map { ($0.x * 1000).rounded() })
        XCTAssertEqual(xs.count, 1, "the four new corners sit in one plane")
    }

    // MARK: Knife

    func testTheKnifeCutsTheFacesUnderTheLine() {
        // A cut down the middle in x, but only across the top (y > 0.9) and front (z > 0.4) faces.
        let cut = Knife.cut(cube, planePoint: .zero, planeNormal: .unitX) { point in point.y > 0.9 || point.z > 0.4 }
        XCTAssertEqual(cut.faces.count, 8)
        assertSolid(cut)
        XCTAssertEqual(cut.volume, cube.volume, accuracy: 1e-12)
    }

    func testTheKnifeAllTheWayRoundSplitsEverySide() {
        let cut = Knife.cut(cube, planePoint: Vec3(0, 0.3, 0), planeNormal: .unitY) { _ in true }
        XCTAssertEqual(cut.faces.count, 10)
        assertSolid(cut)
    }

    // MARK: Holes, merging, bridging

    func testFillHoleClosesAnOpenBox() {
        var faces = cube.faces
        faces.removeLast()
        let open = EditableMesh(vertices: cube.vertices, faces: faces)
        XCTAssertFalse(MeshTopology(open).isClosedManifold)
        XCTAssertEqual(MeshRepair.holes(in: open).count, 1)
        let closed = MeshRepair.fillHoles(open)
        assertSolid(closed)
        XCTAssertEqual(closed.volume, cube.volume, accuracy: 1e-12)
    }

    func testMergingTheTopCornersMakesAPyramid() {
        let top = Set(cube.vertices.indices.filter { cube.vertices[$0].y > 0.5 })
        let pyramid = MeshRepair.merge(top, in: cube)
        XCTAssertEqual(pyramid.vertices.count, 5)
        XCTAssertEqual(pyramid.faces.count, 5)
        assertSolid(pyramid)
        XCTAssertEqual(pyramid.volume, 1.0 / 3, accuracy: 1e-9)
    }

    func testMergeByDistanceWeldsDoubledCorners() {
        var vertices = cube.vertices
        vertices.append(vertices[0] + Vec3(1e-7, 0, 0))
        let faces = cube.faces.map { face in EditableMesh.Face(face.outline.map { $0 == 0 ? 8 : $0 }) }
        let doubled = EditableMesh(vertices: vertices + [vertices[0]], faces: faces)
        let welded = MeshRepair.merge(within: 1e-5, in: doubled)
        XCTAssertEqual(welded.vertices.count, 8)
        assertSolid(welded)
    }

    func testBridgingTwoBoxesMakesOneSolid() {
        let left = EditableMesh.box(min: Vec3(-2, 0, 0), max: Vec3(-1, 1, 1))
        let right = EditableMesh.box(min: Vec3(1, 0, 0), max: Vec3(2, 1, 1))
        let both = EditableMesh(vertices: left.vertices + right.vertices,
                                faces: left.faces + right.faces.map { EditableMesh.Face($0.outline.map { $0 + 8 }) })
        // The facing sides: left's +x face and right's −x face.
        let facing = both.faces.indices.filter { abs(both.normal(of: $0).x) > 0.9 && abs(both.centroid(of: $0).x) < 1.5 }
        XCTAssertEqual(facing.count, 2)
        let bridged = try? MeshRepair.bridge(facing[0], facing[1], in: both)
        XCTAssertNotNil(bridged)
        if let bridged {
            assertSolid(bridged)
            XCTAssertEqual(bridged.faces.count, 14)
            XCTAssertEqual(bridged.volume, 4, accuracy: 1e-9, "two boxes and the two-metre tunnel between")
        }
    }

    func testBridgingFacesWithDifferentCornerCountsEvensThemOut() throws {
        let box = EditableMesh.box(min: Vec3(-2, 0, 0), max: Vec3(-1, 1, 1))
        let prism = Prism.make(outline: [Vec3(1, 0, 0), Vec3(1, 0, 1), Vec3(1, 1, 0.5)].map { $0 }, holes: [], normal: .unitX, from: 0, to: 1)
        let both = EditableMesh(vertices: box.vertices + prism.vertices,
                                faces: box.faces + prism.faces.map { EditableMesh.Face($0.outline.map { $0 + 8 }) })
        let left = try XCTUnwrap(both.faces.indices.first { both.normal(of: $0).x > 0.9 && both.centroid(of: $0).x < 0 })
        let right = try XCTUnwrap(both.faces.indices.first { both.normal(of: $0).x < -0.9 && both.centroid(of: $0).x > 0 })
        let bridged = try MeshRepair.bridge(left, right, in: both)
        assertSolid(bridged)
    }

    func testBridgingRefusesTouchingFaces() {
        XCTAssertThrowsError(try MeshRepair.bridge(0, 2, in: cube)) { error in
            XCTAssertEqual(error as? MeshRepair.BridgeFailure, .touching)
        }
    }

    // MARK: Sweep, revolve, loft

    private let square = SketchRegion(outline: [Vec2(-0.1, -0.1), Vec2(0.1, -0.1), Vec2(0.1, 0.1), Vec2(-0.1, 0.1)], holes: [])

    func testSweepingASquareAlongALineMakesABox() throws {
        let plane = PlaneFrame(normal: .unitX, origin: .zero)
        let solid = try ProfileSolids.sweep(ProfileSolids.loops(of: square, on: plane), plane: plane, along: [.zero, Vec3(2, 0, 0)], closed: false)
        assertSolid(solid)
        XCTAssertEqual(solid.volume, 0.04 * 2, accuracy: 1e-9)
    }

    func testSweepingAlongABendTurnsTheProfile() throws {
        let plane = PlaneFrame(normal: .unitX, origin: .zero)
        let path = [Vec3.zero, Vec3(1, 0, 0), Vec3(1, 0, -1)]
        let solid = try ProfileSolids.sweep(ProfileSolids.loops(of: square, on: plane), plane: plane, along: path, closed: false)
        assertSolid(solid)
        XCTAssertGreaterThan(solid.volume, 0.06)
    }

    func testSweepingARingWithAHoleKeepsTheHole() throws {
        let ring = SketchRegion(outline: square.outline.map { $0 * 2 }, holes: [Array(square.outline.reversed())])
        let plane = PlaneFrame(normal: .unitY, origin: .zero)
        let solid = try ProfileSolids.sweep(ProfileSolids.loops(of: ring, on: plane), plane: plane, along: [.zero, Vec3(0, 1, 0)], closed: false)
        assertSolid(solid)
        XCTAssertEqual(solid.volume, (0.16 - 0.04) * 1, accuracy: 1e-9)
    }

    func testRevolvingARectangleMakesATube() throws {
        // A 1 × 1 square from x = 1 to 2, turned around the y axis: a ring of volume π(2² − 1²) · 1.
        let profile = SketchRegion(outline: [Vec2(1, 0), Vec2(2, 0), Vec2(2, 1), Vec2(1, 1)], holes: [])
        let plane = PlaneFrame(origin: .zero, normal: .unitZ, u: .unitX, v: .unitY)
        let solid = try ProfileSolids.revolve(ProfileSolids.loops(of: profile, on: plane), plane: plane, axisPoint: .zero,
                                              axisDirection: .unitY, segments: 64)
        assertSolid(solid)
        XCTAssertEqual(solid.volume, 3 * .pi, accuracy: 0.05)
    }

    func testRevolvingAProfileTouchingTheAxisMakesASolidWithoutAHole() throws {
        let profile = SketchRegion(outline: [Vec2(0, 0), Vec2(1, 0), Vec2(1, 1), Vec2(0, 1)], holes: [])
        let plane = PlaneFrame(origin: .zero, normal: .unitZ, u: .unitX, v: .unitY)
        let solid = try ProfileSolids.revolve(ProfileSolids.loops(of: profile, on: plane), plane: plane, axisPoint: .zero,
                                              axisDirection: .unitY, segments: 48)
        assertSolid(solid)
        XCTAssertEqual(solid.volume, .pi, accuracy: 0.02)
    }

    func testAHalfTurnIsClosedAtBothEnds() throws {
        let profile = SketchRegion(outline: [Vec2(1, 0), Vec2(2, 0), Vec2(2, 1), Vec2(1, 1)], holes: [])
        let plane = PlaneFrame(origin: .zero, normal: .unitZ, u: .unitX, v: .unitY)
        let solid = try ProfileSolids.revolve(ProfileSolids.loops(of: profile, on: plane), plane: plane, axisPoint: .zero,
                                              axisDirection: .unitY, degrees: 180, segments: 64)
        assertSolid(solid)
        XCTAssertEqual(solid.volume, 1.5 * .pi, accuracy: 0.03)
    }

    func testRevolveRefusesAProfileOnTheAxis() {
        let profile = [[Vec3(0, 0, 0), Vec3(0, 1, 0), Vec3(0, 1, 0.000_000_000_1)]]
        XCTAssertThrowsError(try ProfileSolids.revolve(profile, plane: PlaneFrame(normal: .unitZ, origin: .zero), axisPoint: .zero,
                                                       axisDirection: .unitY))
    }

    func testLoftingASquareIntoASmallerOneMakesAFrustum() throws {
        let bottom = [Vec3(-1, 0, -1), Vec3(1, 0, -1), Vec3(1, 0, 1), Vec3(-1, 0, 1)]
        let top = [Vec3(-0.5, 1, -0.5), Vec3(0.5, 1, -0.5), Vec3(0.5, 1, 0.5), Vec3(-0.5, 1, 0.5)]
        let solid = try ProfileSolids.loft([bottom, top], normals: [.unitY, .unitY])
        assertSolid(solid)
        // A frustum: h/3 (A1 + A2 + √(A1·A2)) = (4 + 1 + 2) / 3.
        XCTAssertEqual(solid.volume, 7.0 / 3, accuracy: 1e-9)
    }

    func testLoftingACircleIntoASquareResamplesThem() throws {
        let circle = (0 ..< 24).map { index -> Vec3 in
            let angle = Double(index) / 24 * 2 * .pi
            return Vec3(cos(angle), 0, sin(angle))
        }
        let square = [Vec3(-1, 2, -1), Vec3(1, 2, -1), Vec3(1, 2, 1), Vec3(-1, 2, 1)]
        let solid = try ProfileSolids.loft([circle, square], normals: [.unitY, .unitY])
        assertSolid(solid)
        XCTAssertEqual(solid.faces.count, 24 + 2)
    }

    func testLoftNeedsTwoProfiles() {
        XCTAssertThrowsError(try ProfileSolids.loft([[.zero, .unitX, .unitY]], normals: [.unitZ]))
    }

    // MARK: Clean topology

    func testCleaningUpABallGivesQuads() throws {
        let ball = PrimitiveMesh.make(.sphere, shading: .smooth)
        let cleaned = try QuadRemesh.remesh(MeshDensify.densified(ball, cuts: 12), options: QuadRemesh.Options(faces: 150))
        XCTAssertGreaterThan(cleaned.faces.count, 80)
        XCTAssertLessThan(cleaned.faces.count, 300)
        let quads = cleaned.faces.filter { $0.outline.count == 4 }.count
        XCTAssertGreaterThan(Double(quads) / Double(cleaned.faces.count), 0.6)
        XCTAssertGreaterThan(cleaned.volume, 0, "it faces out like the ball")
        let bounds = try XCTUnwrap(cleaned.bounds)
        XCTAssertEqual(bounds.size.x, 1, accuracy: 0.1)
    }

    func testCleaningUpNothingIsRefused() {
        XCTAssertThrowsError(try QuadRemesh.remesh(MeshData(), options: QuadRemesh.Options(faces: 100)))
    }
}
