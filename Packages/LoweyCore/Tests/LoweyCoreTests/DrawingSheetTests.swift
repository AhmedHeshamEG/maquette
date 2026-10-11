import Foundation
@testable import LoweyCore
import XCTest

/// U3's acceptance: a stroke always lands where the sheet is, on all four shapes.
final class DrawingSheetTests: XCTestCase {
    private let eye = Vec3(0.3, 1.6, 6)

    /// Rays from the eye through a fan of points around where the sheet is.
    private func rays(towards centre: Vec3, spread: Double) -> [Ray] {
        var rays: [Ray] = []
        for i in -4 ... 4 {
            for j in -4 ... 4 {
                let target = centre + Vec3(Double(i) * spread / 4, Double(j) * spread / 4, 0)
                rays.append(Ray(origin: eye, direction: target - eye))
            }
        }
        return rays
    }

    /// Every landed point is on the shape's surface, faces the eye, sits on the ray, and its sheet coordinates lead
    /// back to the same point.
    private func assertLands(_ sheet: DrawingSheet, in scene: Scene, onSurface: (Vec3) -> Double, file: StaticString = #filePath, line: UInt = #line) {
        let centre = sheet.worldFrame(in: scene)?.origin ?? .zero
        var landed = 0
        for ray in rays(towards: centre, spread: sheet.shape == .flat ? sheet.width / 2 : sheet.radius * 0.7) {
            guard let hit = sheet.land(ray, in: scene) else { continue }
            landed += 1
            XCTAssertEqual(onSurface(hit.point), 0, accuracy: 1e-6, "on the surface", file: file, line: line)
            XCTAssertLessThan(hit.normal.dot(ray.direction), 0, "faces the eye", file: file, line: line)
            XCTAssertEqual((ray.point(at: hit.distance) - hit.point).length, 0, accuracy: 1e-9, file: file, line: line)
            let coordinates = try? XCTUnwrap(sheet.surfaceCoordinates(of: hit.point, in: scene))
            let back = coordinates.flatMap { sheet.worldPoint(at: $0, in: scene) }
            XCTAssertEqual(back.map { ($0 - hit.point).length } ?? 1, 0, accuracy: 1e-6, "coordinates round-trip", file: file, line: line)
        }
        XCTAssertGreaterThan(landed, 60, "the rays at the sheet land", file: file, line: line)
    }

    func testAStrokeLandsOnAFlatSheet() {
        let scene = makeDocument().scene
        let sheet = DrawingSheet.facing(eye: eye, at: Vec3(0, 1, 0), id: "s", name: "Sheet 1", size: 2)
        let normal = sheet.rotation.act(.unitZ)
        assertLands(sheet, in: scene) { ($0 - Vec3(0, 1, 0)).dot(normal) }
        XCTAssertEqual(normal.y, 0, accuracy: 1e-9, "it stands upright, like an easel")
        XCTAssertGreaterThan(normal.dot(eye - Vec3(0, 1, 0)), 0, "facing the eye")
        XCTAssertEqual(sheet.rotation.act(.unitY).y, 1, accuracy: 1e-9)
    }

    func testAStrokeLandsOnASheetWrappedAround() {
        let scene = makeDocument().scene
        let sheet = DrawingSheet.facing(eye: eye, at: Vec3(0, 1, 0), id: "s", name: "Sheet 1", size: 2).with(shape: .around)
        let normal = sheet.rotation.act(.unitZ), up = sheet.rotation.act(.unitY)
        let axisPoint = Vec3(0, 1, 0) - normal * sheet.radius
        assertLands(sheet, in: scene) { point in
            let offset = point - axisPoint
            return (offset - up * offset.dot(up)).length - sheet.radius
        }
        XCTAssertEqual(sheet.land(Ray(origin: eye, direction: Vec3(0, 1, 0) - eye), in: scene)?.point.distance(to: Vec3(0, 1, 0)) ?? 1, 0,
                       accuracy: 0.05, "its front passes through where it was placed")
    }

    func testAStrokeLandsOnADome() {
        let scene = makeDocument().scene
        let sheet = DrawingSheet.facing(eye: eye, at: Vec3(0, 1, 0), id: "s", name: "Sheet 1", size: 2).with(shape: .dome)
        let centre = Vec3(0, 1, 0) - sheet.rotation.act(.unitZ) * sheet.radius
        assertLands(sheet, in: scene) { ($0 - centre).length - sheet.radius }
    }

    func testASheetOnAnObjectRidesWithItAndLandsOnItsSurface() throws {
        var document = makeDocument()
        let hit = SurfaceHit(point: Vec3(1, 1, 0.5), normal: .unitZ, distance: 5)
        let sheet = DrawingSheet.lying(on: hit, object: "a", eye: eye, in: document.scene, id: "s", name: "Sheet 1", size: 1)
            .with(shape: .onObject)
        XCTAssertEqual(sheet.shape, .onObject)
        XCTAssertEqual(sheet.object, "a")
        XCTAssertNil(sheet.land(Ray(origin: eye, direction: Vec3(1, 1, 0.5) - eye), in: document.scene),
                     "its strokes land on the object's own surface (the stage raycasts it)")
        XCTAssertEqual(try XCTUnwrap(sheet.worldFrame(in: document.scene)).origin.distance(to: Vec3(1, 1, 0.5)), 0, accuracy: 1e-9)
        // The object moves: the sheet goes with it.
        document.scene.objects["a"]?.transform.position = Vec3(3, 0, 0)
        XCTAssertEqual(try XCTUnwrap(sheet.worldFrame(in: document.scene)).origin.distance(to: Vec3(3, 1, 0.5)), 0, accuracy: 1e-9)
        // Flat on the object, it lands on its plane like any flat sheet.
        let flat = sheet.with(shape: .flat)
        let landed = try XCTUnwrap(flat.land(Ray(origin: Vec3(3, 1, 5), direction: Vec3(0, 0, -1)), in: document.scene))
        XCTAssertEqual(landed.point.z, 0.5, accuracy: 1e-9)
    }

    func testOnTheObjectNeedsAnObject() {
        let sheet = DrawingSheet.facing(eye: eye, at: .zero, id: "s", name: "Sheet 1", size: 2)
        XCTAssertEqual(sheet.with(shape: .onObject).shape, .flat)
    }

    func testSeenFromAboveItLiesLevel() {
        let sheet = DrawingSheet.facing(eye: Vec3(0, 10, 0.5), at: .zero, id: "s", name: "Sheet 1", size: 2)
        XCTAssertEqual(sheet.rotation.act(.unitZ).y, 1, accuracy: 1e-9)
        XCTAssertLessThan(sheet.rotation.act(.unitY).z, 0, "its up points away from the eye")
    }

    func testOnTheGroundItLinesUpWithTheWorld() {
        // Seen from the front and a little to the side, a sheet on the floor still runs along x and z.
        let hit = SurfaceHit(point: Vec3(0.3, 0, -0.2), normal: .unitY, distance: 5)
        let sheet = DrawingSheet.lying(on: hit, object: nil, eye: Vec3(2, 4, 6), in: makeDocument().scene, id: "s", name: "S", size: 1)
        XCTAssertEqual(sheet.rotation.act(.unitX).x, 1, accuracy: 1e-9, "across is x")
        XCTAssertEqual(sheet.rotation.act(.unitY).z, -1, accuracy: 1e-9, "up the sheet is away from the eye, along -z")
    }

    func testTheGripPushesItAlongItsNormal() {
        let sheet = DrawingSheet.facing(eye: eye, at: Vec3(0, 1, 0), id: "s", name: "Sheet 1", size: 2)
        let pushed = sheet.pushed(by: 0.5)
        XCTAssertEqual((pushed.origin - sheet.origin).length, 0.5, accuracy: 1e-9)
        XCTAssertGreaterThan((pushed.origin - sheet.origin).dot(eye - sheet.origin), 0, "positive comes nearer")
    }

    func testKeptSheetsAreAnUndoableCommandAndSurviveJSON() throws {
        let document = makeDocument()
        let sheet = DrawingSheet.facing(eye: eye, at: Vec3(0, 1, 0), id: "s1", name: document.scene.nextSheetName(), size: 2)
        XCTAssertEqual(sheet.name, "Sheet 1")
        var applied = try assertReverts(.setSheets([SheetEdit(sheet)]), on: document)
        XCTAssertEqual(applied.scene.sheet("s1"), sheet)
        XCTAssertEqual(applied.scene.nextSheetName(), "Sheet 2")
        applied = try assertReverts(.setSheets([SheetEdit(sheet.with(shape: .dome))]), on: applied)
        XCTAssertEqual(applied.scene.sheet("s1")?.shape, .dome)
        try assertReverts(.setSheets([SheetEdit(id: "s1", sheet: nil)]), on: applied)
        let data = try LoweyJSON.encode(applied.scene)
        XCTAssertEqual(try LoweyJSON.decode(Scene.self, from: data).sheets, applied.scene.sheets)
        XCTAssertFalse(try String(decoding: LoweyJSON.encode(document.scene), as: UTF8.self).contains("sheets"), "no sheets, no key")
    }

    func testTheFillIsWhereTheSheetIs() throws {
        let scene = makeDocument().scene
        for shape in DrawingSheet.Shape.allCases {
            var sheet = DrawingSheet.lying(on: SurfaceHit(point: Vec3(1, 1, 0.5), normal: .unitZ, distance: 5), object: "a", eye: eye, in: scene,
                                           id: "s", name: "S", size: 1)
            sheet = sheet.with(shape: shape)
            let fill = SheetMesh.fill(sheet, in: scene)
            XCTAssertFalse(fill.isEmpty, "\(shape)")
            XCTAssertEqual(fill.positions.count, fill.normals.count)
            XCTAssertTrue(fill.indices.allSatisfy { Int($0) < fill.positions.count })
            let bounds = try XCTUnwrap(fill.bounds)
            let point = Vec3(1, 1, 0.5)
            XCTAssertTrue(point.x >= bounds.min.x - 0.01 && point.x <= bounds.max.x + 0.01 && point.y >= bounds.min.y - 0.01
                && point.y <= bounds.max.y + 0.01 && point.z >= bounds.min.z - 0.01 && point.z <= bounds.max.z + 0.01,
                "\(shape) is where it was laid")
        }
        let flat = DrawingSheet.facing(eye: eye, at: .zero, id: "s", name: "S", size: 2)
        XCTAssertEqual(SheetMesh.border(flat, in: scene, thickness: 0.01).triangleCount, 8)
    }
}
