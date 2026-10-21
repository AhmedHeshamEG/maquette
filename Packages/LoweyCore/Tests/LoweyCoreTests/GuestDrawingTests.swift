@testable import LoweyCore
import XCTest

/// G1: drawings from the model: hidden lines, sections, rooms with their areas, plans and elevations, and the files
/// they leave as (PDF, SVG, DXF).
final class GuestDrawingTests: XCTestCase {
    /// A 4 × 5 m room inside 20 cm walls (their centre line 4.2 × 5.2 m), 2.7 m high, with a door cut through one wall.
    static func room(door: Bool = true) throws -> EditableMesh {
        let corners = [Vec3(-2.1, 0, -2.6), Vec3(2.1, 0, -2.6), Vec3(2.1, 0, 2.6), Vec3(-2.1, 0, 2.6)]
        var walls = try Architecture.walls(along: corners, closed: true)
        if door {
            let block = try Architecture.openingBlock(at: Vec3(0, 0, 2.7), facing: Vec3(0, 0, 1), wallBase: 0, wallDepth: 0.2, width: 0.9,
                                                      height: 2.1, sill: 0)
            walls = try MeshBoolean.combine(walls, block, .subtract)
        }
        return walls
    }

    func testARoomWithADoorIsFoundWithItsArea() throws {
        let soup = try TriangleSoup(Self.room(), name: "Walls")
        let rooms = RoomFinder.rooms(soup)
        XCTAssertEqual(rooms.count, 1)
        XCTAssertEqual(rooms.first?.area ?? 0, 20, accuracy: 0.05)
        XCTAssertEqual(rooms.first?.name, "Room 1")
    }

    func testARoomTakesTheNameLyingInIt() throws {
        let soup = try TriangleSoup(Self.room(), name: "Walls")
        let rooms = RoomFinder.rooms(soup, labels: [("Kitchen", Vec2(0.5, 0.5)), ("Garden", Vec2(9, 9))])
        XCTAssertEqual(rooms.map(\.name), ["Kitchen"])
    }

    func testTwoRoomsSideBySideAreTwo() throws {
        var soup = try TriangleSoup(Self.room(door: false), name: "A")
        let second = try Architecture.walls(along: [Vec3(2.1, 0, -2.6), Vec3(6.3, 0, -2.6), Vec3(6.3, 0, 2.6), Vec3(2.1, 0, 2.6)], closed: true)
        soup.add(second, transform: .identity, name: "B")
        let rooms = RoomFinder.rooms(soup)
        XCTAssertEqual(rooms.count, 2)
        for room in rooms {
            XCTAssertEqual(room.area, 20, accuracy: 0.1)
        }
    }

    func testThePlanCutsTheWallsAndWritesTheArea() throws {
        let soup = try TriangleSoup(Self.room(), name: "Walls")
        let (art, rooms) = PlanDrawing.plan(soup)
        XCTAssertEqual(rooms.count, 1)
        let cut = art.strokes.filter { $0.pen == .cut }
        XCTAssertFalse(cut.isEmpty)
        XCTAssertTrue(cut.allSatisfy(\.filled))
        XCTAssertTrue(art.labels.contains { $0.text == "20.0 m²" })
        // North is up: the wall at z = −2.6 is at the top of the plan.
        let bounds = try XCTUnwrap(art.bounds)
        XCTAssertEqual(bounds.max.y, 2.7, accuracy: 0.01)
    }

    func testAnElevationIsTheWallSeenStraightOnWithAGroundLine() throws {
        let soup = try TriangleSoup(Self.room(), name: "Walls")
        let art = PlanDrawing.elevation(soup, side: .south)
        let bounds = try XCTUnwrap(art.bounds)
        XCTAssertEqual(bounds.max.y, 2.7, accuracy: 0.01)
        XCTAssertTrue(art.strokes.contains { $0.pen == .cut })
        // The door is seen: a line at its head, 2.1 m up.
        XCTAssertTrue(art.strokes.contains { stroke in stroke.points.allSatisfy { abs($0.y - 2.1) < 0.01 } })
    }

    func testABoxBehindAnotherIsPartlyHidden() {
        var soup = TriangleSoup(EditableMesh.box(min: Vec3(-1, 0, 0), max: Vec3(1, 2, 1)), name: "front")
        soup.add(EditableMesh.box(min: Vec3(0, 0, -3), max: Vec3(2, 1, -2)), transform: .identity, name: "back")
        let art = HiddenLines.draw(soup, view: .front, options: HiddenLines.Options(hidden: true))
        let seen = art.strokes.filter { $0.pen == .outline }
        let hidden = art.strokes.filter { $0.pen == .hidden }
        XCTAssertFalse(hidden.isEmpty)
        // The back box's left edge (x = 0) is behind the front box: nothing seen there below y = 1.
        XCTAssertFalse(seen.contains { stroke in stroke.points.allSatisfy { abs($0.x) < 0.01 } && stroke.points.contains { $0.y < 0.99 } })
    }

    func testDrawingsLeaveAsPDFSVGAndDXF() throws {
        let soup = try TriangleSoup(Self.room(), name: "Walls")
        let plan = PlanDrawing.plan(soup).art
        let pdf = PlanDrawing.sheets(plan: plan, elevations: [(.south, PlanDrawing.elevation(soup, side: .south))], paper: .a4,
                                     title: "House", author: "Sara")
        XCTAssertTrue(String(decoding: pdf.prefix(8), as: UTF8.self).hasPrefix("%PDF"))
        XCTAssertTrue(String(decoding: pdf, as: UTF8.self).contains("B*"))
        let bounds = try XCTUnwrap(plan.bounds)
        let svg = plan.svg(PaperPlacement(scale: 0.01, origin: bounds.min, at: Vec2(10, 10)), width: 297, height: 210)
        XCTAssertTrue(svg.contains("fill-rule=\"evenodd\""))
        XCTAssertTrue(svg.contains("20.0 m²"))
        let dxf = DXF.data(plan)
        let back = try DXF.read(dxf)
        XCTAssertEqual(back.unit, .millimetre)
        let size = try XCTUnwrap(back.bounds)
        // Read back in metres at full size.
        XCTAssertEqual(size.max.x - size.min.x, 4.4, accuracy: 0.05)
        if let directory = ProcessInfo.processInfo.environment["ACCEPTANCE_DIR"] {
            let folder = URL(fileURLWithPath: directory).appendingPathComponent("room")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try pdf.write(to: folder.appendingPathComponent("plan.pdf"))
            try dxf.write(to: folder.appendingPathComponent("plan.dxf"))
            try Data(svg.utf8).write(to: folder.appendingPathComponent("plan.svg"))
        }
    }

    func testADXFUnderlayReadsLinesArcsAndCirclesInItsUnits() throws {
        let file = Self.underlayDXF
        let drawing = try DXF.read(Data(file.utf8))
        XCTAssertEqual(drawing.unit, .centimetre)
        XCTAssertEqual(drawing.curves.count, 4)
        XCTAssertEqual(drawing.skipped, 1)
        guard case let .line(a, b) = drawing.curves[0] else { return XCTFail("a line first") }
        XCTAssertEqual(a.distance(to: b), 4, accuracy: 1e-9)
        guard case let .arc(start, _, end) = drawing.curves[3] else { return XCTFail("an arc last") }
        XCTAssertEqual(start.x, 1, accuracy: 1e-9)
        XCTAssertEqual(end.y, 1, accuracy: 1e-9)
        XCTAssertThrowsError(try DXF.read(Data("hello".utf8)))
    }

    func testAFrameDrawnThroughACameraKeepsItsSilhouette() {
        let soup = TriangleSoup(EditableMesh.box(min: Vec3(-0.5, 0, -0.5), max: Vec3(0.5, 1, 0.5)), name: "box")
        let view = DrawingView.perspective(eye: Vec3(2, 2, 3), forward: (Vec3(0, 0.5, 0) - Vec3(2, 2, 3)).normalized, up: .unitY,
                                           fieldOfView: 40, width: 1920, height: 1080)
        let art = HiddenLines.draw(soup, view: view)
        // A box seen from a corner shows nine edges (six around, three meeting at the near top corner).
        XCTAssertGreaterThanOrEqual(art.strokes.count, 9)
        let bounds = art.bounds
        XCTAssertNotNil(bounds)
        XCTAssertTrue(art.strokes.allSatisfy { $0.points.allSatisfy { $0.x >= 0 && $0.x <= 1920 && $0.y >= 0 && $0.y <= 1080 } })
    }

    /// A DXF in centimetres: a line, a closed polyline, a circle, an arc and a block placed by reference.
    static let underlayDXF = """
      0
    SECTION
      2
    HEADER
      9
    $INSUNITS
     70
    5
      0
    ENDSEC
      0
    SECTION
      2
    ENTITIES
      0
    LINE
      8
    0
     10
    0
     20
    0
     11
    400
     21
    0
      0
    LWPOLYLINE
      8
    0
     90
    3
     70
    1
     10
    0
     20
    0
     10
    100
     20
    0
     10
    100
     20
    100
      0
    CIRCLE
      8
    0
     10
    50
     20
    50
     40
    10
      0
    ARC
      8
    0
     10
    0
     20
    0
     40
    100
     50
    0
     51
    90
      0
    INSERT
      8
    0
      0
    ENDSEC
      0
    EOF
    """
}
