import Foundation
@testable import LoweyCore
import XCTest

/// Q1's acceptance: a sheet placed on each face of a cube, on a slanted roof and on a sphere lies on the face (its normal
/// within 0.5°), its middle within 1 mm of where the touch snaps, never larger than the face.
final class SheetFitTests: XCTestCase {
    private let halfDegree = cos(0.5 * Double.pi / 180)

    /// Where a ray from `eye` towards `point` lands, and the face there.
    private func touch(_ mesh: MeshData, from eye: Vec3, towards point: Vec3) throws -> (hit: SurfaceHit, face: SheetFit.Face) {
        let ray = Ray(origin: eye, direction: point - eye)
        let landed = try XCTUnwrap(MeshRaycast.intersectTriangle(ray, mesh: mesh), "the ray hits the mesh")
        let face = try XCTUnwrap(SheetFit.face(around: landed.triangle, in: mesh, eye: eye))
        return (landed.hit, face)
    }

    func testASheetOnEachFaceOfACube() throws {
        // A 1 m cube standing on the ground (0…1 up), seen from 3 m off each face, the tip a little off the middle.
        let mesh = PrimitiveMesh.box(size: SIMD3(1, 1, 1))
        let middle = Vec3(0, 0.5, 0)
        for axis in [Vec3.unitX, -Vec3.unitX, .unitY, -Vec3.unitY, .unitZ, -Vec3.unitZ] {
            let faceMiddle = middle + axis * 0.5
            let side = abs(axis.y) > 0.5 ? Vec3.unitX : .unitY
            let tip = faceMiddle + side * 0.01
            let eye = tip + axis * 3
            let (hit, face) = try touch(mesh, from: eye, towards: tip)
            XCTAssertFalse(face.curved, "a cube's side is a face")
            XCTAssertEqual(face.triangles.count, 2, "both triangles of the side")
            XCTAssertGreaterThanOrEqual(face.normal.dot(axis), halfDegree, "the face's own normal (\(axis))")
            let placement = SheetFit.placement(on: face, tip: hit.point, maximum: (10, 10), snap: 0.02)
            XCTAssertGreaterThanOrEqual(placement.rotation.act(.unitZ).dot(axis), halfDegree, "the sheet lies on the face (\(axis))")
            XCTAssertLessThan((placement.center - faceMiddle).length, 0.001, "snapped to the middle within 1 mm (\(axis))")
            XCTAssertTrue(placement.snaps.contains(.middle))
            XCTAssertLessThanOrEqual(placement.width, 1)
            XCTAssertLessThanOrEqual(placement.height, 1)
            XCTAssertGreaterThan(placement.width, 0.85, "sized to the face, with a small margin")
            let sheet = DrawingSheet.fitted(placement, object: nil, in: makeDocument().scene, id: "s", name: "Sheet 1")
            let above = (sheet.origin - faceMiddle).dot(axis)
            XCTAssertGreaterThan(above, 0, "a hair above the surface")
            XCTAssertLessThan(above, 0.001)
        }
    }

    func testASheetOnASlantedRoof() throws {
        // A gable roof 4 m along x, its two slopes rising 30° to a ridge at 1 m.
        var mesh = MeshData()
        let rise = Float(tan(Double.pi / 6))
        let a = SIMD3<Float>(-2, 0, 1), b = SIMD3<Float>(2, 0, 1), c = SIMD3<Float>(2, rise, 0), d = SIMD3<Float>(-2, rise, 0)
        PrimitiveMesh.quad(&mesh, a, b, c, d)
        PrimitiveMesh.quad(&mesh, SIMD3(2, 0, -1), SIMD3(-2, 0, -1), d, c)
        let slope = Vec3(0, Double(rise), -1).normalized
        let normal = Vec3(0, 1, Double(rise)).normalized
        let tip = Vec3(0.6, Double(rise) / 2, 0.5)
        let (hit, face) = try touch(mesh, from: tip + normal * 4, towards: tip)
        XCTAssertFalse(face.curved)
        XCTAssertGreaterThanOrEqual(face.normal.dot(normal), halfDegree, "the slope's normal")
        XCTAssertGreaterThan(abs(face.right.dot(.unitX)), 0.999, "lined up with the ridge, the longest edge")
        XCTAssertGreaterThan(face.up.dot(.unitY), 0, "its up climbs the slope")
        XCTAssertGreaterThan(face.up.dot(slope), 0.99999, "straight up the slope")
        // A sheet no bigger than 1.5 m across slides under the tip and stays on the slope.
        let placement = SheetFit.placement(on: face, tip: hit.point, maximum: (1.5, 1.125), snap: 0.01)
        XCTAssertGreaterThanOrEqual(placement.rotation.act(.unitZ).dot(normal), halfDegree)
        XCTAssertLessThanOrEqual(placement.width, 1.5)
        let slopeLength = (Vec3(c) - Vec3(b)).length
        XCTAssertLessThan(placement.height, slopeLength, "never larger than the face")
        let along = (placement.center - face.middle).dot(face.right)
        XCTAssertEqual(along, 0.6, accuracy: 0.001, "the middle follows the tip along the ridge")
        // Near the gable end it stops flush with the edge, less the margin.
        let end = SheetFit.placement(on: face, tip: Vec3(1.9, Double(rise) / 2, 0.5), maximum: (1.5, 1.125), snap: 0.05)
        XCTAssertTrue(end.snaps.contains(.edge))
        XCTAssertLessThanOrEqual((end.center - face.middle).dot(face.right) + end.width / 2, 2.0001)
    }

    func testASheetOnASphereLiesOnItsTangentPlane() throws {
        let mesh = PrimitiveMesh.sphere(segments: 48, rings: 24)
        // Radius 0.5, standing on the ground.
        let centre = Vec3(0, 0.5, 0)
        let direction = Vec3(0.4, 0.5, 0.8).normalized
        let tip = centre + direction * 0.5
        let eye = centre + direction * 3
        let (hit, face) = try touch(mesh, from: eye, towards: tip)
        XCTAssertTrue(face.curved, "a sphere's facet is part of a curved surface")
        let placement = SheetFit.placement(on: face, tip: hit.point, maximum: (0.6, 0.45), snap: 0.02)
        XCTAssertGreaterThanOrEqual(placement.rotation.act(.unitZ).dot(hit.normal), halfDegree, "on the facet's plane under the tip")
        XCTAssertGreaterThan(placement.rotation.act(.unitZ).dot((hit.point - centre).normalized), 0.99, "nearly the sphere's own normal")
        XCTAssertLessThan((placement.center - hit.point).length, 0.001, "where the tip is")
        XCTAssertTrue(placement.snaps.isEmpty, "nothing snaps on a curve")
        let big = SheetFit.placement(on: face, tip: hit.point, maximum: (5, 5), snap: 0.02)
        XCTAssertLessThanOrEqual(big.width, 1.0001, "never larger than the sphere")
        XCTAssertLessThanOrEqual(big.height, 1.0001)
    }

    func testABigFaceKeepsTheSheetInsideAndSnapsToItsEdge() throws {
        var mesh = MeshData()
        PrimitiveMesh.quad(&mesh, SIMD3(-5, 0, 5), SIMD3(5, 0, 5), SIMD3(5, 0, -5), SIMD3(-5, 0, -5))
        let eye = Vec3(0, 6, 8)
        let (_, face) = try touch(mesh, from: eye, towards: Vec3(1, 0, 1))
        XCTAssertEqual(face.halfWidth, 5, accuracy: 1e-4)
        let free = SheetFit.placement(on: face, tip: Vec3(1, 0, 1), maximum: (2, 1.5), snap: 0.05)
        XCTAssertTrue(free.snaps.isEmpty)
        XCTAssertLessThan((free.center - Vec3(1, 0, 1)).length, 1e-9, "it follows the tip on the face")
        let edge = SheetFit.placement(on: face, tip: Vec3(4.5, 0, 0), maximum: (2, 1.5), snap: 0.2)
        XCTAssertTrue(edge.snaps.contains(.edge))
        let reach = max(abs((edge.center - face.middle).dot(face.right)) + edge.width / 2,
                        abs((edge.center - face.middle).dot(face.up)) + edge.height / 2)
        XCTAssertLessThan(reach, 5, "inside the face")
        XCTAssertGreaterThan(reach, 4.5, "flush with the edge, less the margin")
    }

    func testTheTurnSnapsToFifteenDegrees() {
        XCTAssertEqual(SheetFit.snappedTurn(43).degrees, 45)
        XCTAssertTrue(SheetFit.snappedTurn(43).snapped)
        XCTAssertEqual(SheetFit.snappedTurn(37.5).degrees, 37.5)
        XCTAssertFalse(SheetFit.snappedTurn(37.5).snapped)
    }

    func testAFittedSheetRidesWithItsObject() throws {
        var document = makeDocument()
        var object = SceneObject(id: "crate", name: "Crate", kind: .primitive(.cube))
        object.transform = Transform(position: Vec3(2, 0, 1), rotation: Quat(angle: 0.4, axis: .unitY))
        document.scene.objects["crate"] = object
        document.scene.roots.append("crate")
        let placement = SheetFit.Placement(center: Vec3(2, 0.5, 1.5), rotation: DrawingSheet.frame(normal: .unitZ, up: .unitY),
                                           width: 0.8, height: 0.6, snaps: [])
        let sheet = DrawingSheet.fitted(placement, object: object.id, in: document.scene, id: "s", name: "Sheet 1")
        XCTAssertEqual(sheet.object, object.id)
        let frame = try XCTUnwrap(sheet.worldFrame(in: document.scene))
        XCTAssertLessThan((frame.origin - placement.center).length, 0.001)
        XCTAssertGreaterThan(frame.rotation.act(.unitZ).dot(.unitZ), 0.99999)
    }
}

/// The Reference window (Q1): it settles inside the stage and off the clusters, resizes from its corner, zooms a picture
/// about the fingers, and older projects' window card becomes it.
final class ReferenceWindowLayoutTests: XCTestCase {
    private let stage = CGSize(width: 1180, height: 820)

    func testItKeepsAMarginFromTheEdges() {
        let window = ReferenceWindow(open: true).settled(at: CGPoint(x: 1300, y: -40), in: stage)
        let frame = window.frame(in: stage)
        XCTAssertEqual(frame.maxX, stage.width - ReferenceWindow.margin, accuracy: 0.01)
        XCTAssertEqual(frame.minY, ReferenceWindow.margin, accuracy: 0.01)
    }

    func testItNeverCoversTheClusters() {
        let cluster = CGRect(x: 900, y: 0, width: 280, height: 90)
        let window = ReferenceWindow(open: true).settled(at: CGPoint(x: 1000, y: 120), in: stage, avoiding: [cluster])
        let frame = window.frame(in: stage)
        XCTAssertFalse(frame.intersects(cluster.insetBy(dx: -ReferenceWindow.margin + 0.5, dy: -ReferenceWindow.margin + 0.5)))
        XCTAssertGreaterThanOrEqual(frame.minX, ReferenceWindow.margin - 0.01)
        XCTAssertLessThanOrEqual(frame.maxX, stage.width - ReferenceWindow.margin + 0.01)
    }

    func testResizingKeepsItsTopLeftAndItsLimits() {
        let window = ReferenceWindow(open: true, x: 0.5, y: 0.5, width: 300, height: 200)
        let before = window.frame(in: stage)
        let bigger = window.sized(width: 420, height: 260, in: stage)
        let after = bigger.frame(in: stage)
        XCTAssertEqual(after.minX, before.minX, accuracy: 0.01)
        XCTAssertEqual(after.minY, before.minY, accuracy: 0.01)
        XCTAssertEqual(bigger.width, 420)
        XCTAssertEqual(window.sized(width: 20, height: 20, in: stage).width, ReferenceWindow.widthRange.lowerBound)
        let huge = window.sized(width: 5000, height: 5000, in: stage)
        XCTAssertLessThanOrEqual(huge.frame(in: stage).height, stage.height - ReferenceWindow.margin * 2 + 0.01)
    }

    func testAPictureFitsWholeAndZoomsAboutTheFingers() throws {
        let window = ReferenceWindow(open: true, width: 400, height: 300).showing(image: "references/a.png", aspect: 0.5)
        let rect = try XCTUnwrap(window.pictureRect())
        XCTAssertEqual(rect.width, 400, accuracy: 1e-9)
        XCTAssertEqual(rect.height, 200, accuracy: 1e-9, "its own shape, never stretched")
        let focus = CGPoint(x: 300, y: 150)
        let under = try XCTUnwrap(window.picturePoint(at: focus))
        let zoomed = window.zoomed(by: 3, about: focus)
        XCTAssertEqual(zoomed.zoom, 3)
        let still = try XCTUnwrap(zoomed.picturePoint(at: focus))
        XCTAssertEqual(still.x, under.x, accuracy: 1e-9, "what was under the fingers stays there")
        XCTAssertEqual(still.y, under.y, accuracy: 1e-9)
        XCTAssertEqual(window.zoomed(by: 100, about: focus).zoom, ReferenceWindow.zoomRange.upperBound)
        let panned = zoomed.panned(by: CGSize(width: 1e6, height: 0))
        XCTAssertLessThanOrEqual(panned.panX, 1.5, "some of the picture always shows")
        XCTAssertNil(window.cleared.pictureRect())
    }

    func testTheCanvasCameraShowsTheWholeScene() {
        let bounds = Bounds(min: Vec3(-1, 0, -1), max: Vec3(3, 2, 1))
        let wide = ReferenceWindow.canvasView(framing: bounds, aspect: 1.6)
        let tall = ReferenceWindow.canvasView(framing: bounds, aspect: 0.6)
        XCTAssertEqual(wide.target, bounds.center)
        XCTAssertGreaterThan(tall.distance, wide.distance, "a narrow window stands farther back")
        XCTAssertEqual(ReferenceWindow.canvasView(framing: nil, aspect: 1).distance, Viewpoint().distance)
    }

    func testAnOlderWindowCardBecomesTheWindow() throws {
        var card = ReferenceCard(id: "w", image: "references/w.png", x: 0.7, y: 0.4, width: 280, aspect: 0.75)
        card.window = true
        let pinned = ReferenceCard(id: "p", image: "references/p.png")
        let json = try JSONEncoder().encode(["references": [pinned, card]])
        let workspace = try JSONDecoder().decode(ProjectWorkspace.self, from: json)
        let window = try XCTUnwrap(workspace.referenceWindow)
        XCTAssertEqual(window.image, "references/w.png")
        XCTAssertEqual(window.mode, .image)
        XCTAssertTrue(window.open)
        XCTAssertEqual(window.height, 210, accuracy: 1e-9)
        XCTAssertEqual(workspace.references.map(\.id), ["p"], "the board's pins stay cards")
        let again = try JSONDecoder().decode(ProjectWorkspace.self, from: JSONEncoder().encode(workspace))
        XCTAssertEqual(again.referenceWindow, window, "kept as it was")
    }

    func testADamagedWindowStillOpens() throws {
        let json = Data(#"{"open":true,"mode":"hologram","x":7,"width":-3,"zoom":"big","panX":99}"#.utf8)
        let window = try JSONDecoder().decode(ReferenceWindow.self, from: json)
        XCTAssertTrue(window.open)
        XCTAssertEqual(window.mode, .canvas)
        XCTAssertEqual(window.x, 1)
        XCTAssertEqual(window.width, ReferenceWindow.widthRange.lowerBound)
        XCTAssertEqual(window.zoom, 1)
        XCTAssertEqual(window.panX, 0, "no picture, no pan")
    }
}

/// The bridge reaches the Reference window (Q1): the `reference` verb asks, the project doesn't change.
final class ReferenceVerbTests: XCTestCase {
    private func compile(_ json: String) throws -> ScriptResult {
        let script = try LoweyJSON.decode(SceneScript.self, from: Data(json.utf8))
        return try ScriptCompiler.compile(ScriptMigration.upgraded(script), document: makeDocument(), context: ScriptContext(ids: .sequential("r")))
    }

    func testTheVerbAsksAndChangesNothing() throws {
        let result = try compile("""
        {"version":3,"title":"Look","actions":[{"do":"reference","op":"open","mode":"canvas"},{"do":"reference","mode":"face"},
        {"do":"reference","op":"image","image":"references/abc.png"},{"do":"reference","op":"frame"},{"do":"reference","op":"close"}]}
        """)
        XCTAssertNil(result.command, "not an edit")
        XCTAssertEqual(result.reference, [.open(.canvas), .mode(.face), .image("references/abc.png"), .frame, .close])
        XCTAssertEqual(result.report.count, 5)
    }

    func testABadAskSaysWhy() {
        XCTAssertThrowsError(try compile(#"{"version":3,"actions":[{"do":"reference","mode":"hologram"}]}"#))
        XCTAssertThrowsError(try compile(#"{"version":3,"actions":[{"do":"reference","op":"image","image":"../secret.png"}]}"#))
        XCTAssertThrowsError(try compile(#"{"version":3,"actions":[{"do":"reference","op":"spin"}]}"#))
    }
}

extension SheetFitTests {
    func testADenseShapeTakesTheTangentPlaneAndTheFaceLights() throws {
        let mesh = PrimitiveMesh.box(size: SIMD3(1, 1, 1))
        let eye = Vec3(0, 0.5, 3)
        let ray = Ray(origin: eye, direction: Vec3(0, 0.5, 0.5) - eye)
        let landed = try XCTUnwrap(MeshRaycast.intersectTriangle(ray, mesh: mesh))
        let tangent = SheetFit.tangentFace(at: landed.hit, triangle: landed.triangle, bounds: mesh.bounds, eye: eye)
        XCTAssertTrue(tangent.curved)
        XCTAssertEqual(tangent.halfWidth, 0.5, accuracy: 1e-6, "as big as the shape seen on that plane")
        let face = try XCTUnwrap(SheetFit.face(around: landed.triangle, in: mesh, eye: eye))
        let lit = SheetFit.mesh(of: face, in: mesh, lift: 0.001)
        XCTAssertEqual(lit.triangleCount, 2)
        XCTAssertTrue(lit.positions.allSatisfy { abs(Double($0.z) - 0.501) < 1e-5 }, "a hair in front of the face")
    }
}
