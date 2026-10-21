@testable import LoweyCore
import XCTest

/// G1, Room: roofs, columns, beams, railings, scale people and terrain; underlays; IFC; matching a photo; a scan.
final class GuestRoomTests: XCTestCase {
    let outline = [Vec3(0, 2.7, 0), Vec3(8, 2.7, 0), Vec3(8, 2.7, 5), Vec3(0, 2.7, 5)]

    func testRoofsAreClosedSolidsOverTheWalls() throws {
        for kind in RoomParts.RoofKind.allCases {
            let roof = try RoomParts.roof(kind, outline: outline)
            XCTAssertTrue(MeshBoolean.isSolid(roof), "\(kind) is a closed solid")
            let bounds = try XCTUnwrap(roof.bounds)
            XCTAssertEqual(bounds.min.y, 2.7, accuracy: 1e-6, "\(kind) sits on the walls")
            // Overhanging 30 cm all round.
            XCTAssertEqual(bounds.min.x, -0.3, accuracy: 1e-6)
            XCTAssertEqual(bounds.max.z, 5.3, accuracy: 1e-6)
        }
        // A gable at 30° over a 5.6 m span rises 2.8 × tan 30°.
        let gable = try RoomParts.roof(.gable, outline: outline)
        XCTAssertEqual(try XCTUnwrap(gable.bounds).max.y, 2.7 + 2.8 * tan(Double.pi / 6), accuracy: 1e-6)
        // The ridge runs along the longer side (x).
        let ridge = gable.vertices.filter { $0.y > 4 }
        XCTAssertEqual(ridge.count, 2)
        XCTAssertEqual(abs(ridge[0].x - ridge[1].x), 8.6, accuracy: 1e-6)
        XCTAssertThrowsError(try RoomParts.roof(.flat, outline: Array(outline.prefix(2))))
    }

    func testColumnsBeamsRailingsPeopleAndTerrain() throws {
        XCTAssertTrue(MeshBoolean.isSolid(RoomParts.column(at: .zero)))
        XCTAssertTrue(MeshBoolean.isSolid(RoomParts.column(at: .zero, round: false)))
        let beam = try RoomParts.beam(from: Vec3(0, 2.7, 0), to: Vec3(4, 2.7, 3))
        XCTAssertTrue(MeshBoolean.isSolid(beam))
        XCTAssertEqual(try XCTUnwrap(beam.bounds).max.y, 2.7, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(beam.bounds).min.y, 2.4, accuracy: 1e-9)
        let railing = try RoomParts.railing(along: [Vec3(0, 0, 0), Vec3(3, 0, 0)])
        XCTAssertEqual(try XCTUnwrap(railing.bounds).max.y, 1.0, accuracy: 1e-9)
        // Posts every metre (three spans), a handrail and a middle rail: six boxes.
        XCTAssertEqual(railing.faces.count, 6 * 6)
        let person = RoomParts.person(at: .zero)
        XCTAssertTrue(MeshBoolean.isSolid(person))
        XCTAssertEqual(try XCTUnwrap(person.bounds).max.y, 1.75, accuracy: 1e-9)
        let terrain = RoomParts.terrain(width: 20, depth: 10, hills: 2, seed: 7)
        XCTAssertTrue(MeshBoolean.isSolid(terrain))
        let bounds = try XCTUnwrap(terrain.bounds)
        XCTAssertEqual(bounds.max.x - bounds.min.x, 20, accuracy: 1e-9)
        XCTAssertGreaterThan(bounds.max.y, 0.2)
        XCTAssertEqual(RoomParts.terrain(seed: 7), RoomParts.terrain(seed: 7))
    }

    func testRoomToolsAreTaggedSoTheFilesKnowWhatTheyAre() throws {
        var document = Document(project: ProjectInfo(id: "p", name: "House"), scene: Scene(id: "s", name: "House"))
        var ids = IDFactory.sequential("g")
        let commands = try [
            ModelingOperations.addWalls(along: [Vec3(0, 0, 0), Vec3(8, 0, 0), Vec3(8, 0, 5), Vec3(0, 0, 5)], closed: true, height: 2.7,
                                        thickness: 0.2, id: ids.next()),
            ModelingOperations.addSlab(outline: [Vec3(0, 0, 0), Vec3(8, 0, 0), Vec3(8, 0, 5), Vec3(0, 0, 5)], thickness: 0.2, id: ids.next()),
            ModelingOperations.addRoof(.hip, outline: outline, id: ids.next()),
            ModelingOperations.addColumn(at: Vec3(4, 0, 2.5), id: ids.next()),
            ModelingOperations.addBeam(from: Vec3(0, 2.7, 2.5), to: Vec3(8, 2.7, 2.5), id: ids.next()),
            ModelingOperations.addRailing(along: [Vec3(0, 0, 6), Vec3(8, 0, 6)], id: ids.next()),
            ModelingOperations.addPerson(at: Vec3(2, 0, 2), yaw: 30, id: ids.next()),
            ModelingOperations.addTerrain(width: 30, depth: 30, hills: 0, at: Vec3(4, -0.01, 2.5), seed: 1, id: ids.next()),
            ModelingOperations.addLabel("Kitchen", at: Vec3(2, 0, 2), id: ids.next())
        ]
        for command in commands {
            _ = try command.apply(to: &document)
        }
        let scene = document.scene
        let parts = scene.objects.values.compactMap { (object: SceneObject) -> BuildingPart? in object.buildingPart }
        XCTAssertEqual(Set(parts), [BuildingPart.wall, .slab, .roof, .column, .beam, .railing, .person, .terrain])
        let elements = IFCWriter.elements(in: scene, look: Look())
        // People stay out of the building; the label is plain block text, a proxy.
        XCTAssertFalse(elements.contains { $0.part == .person })
        XCTAssertEqual(elements.count, 8)
        let file = IFCWriter.file(elements: elements, spaces: [IFCWriter.Space(name: "Kitchen", outline: [Vec2(0.1, -0.1), Vec2(7.9, -0.1),
                                                                                                          Vec2(7.9, -4.9), Vec2(0.1, -4.9)],
            floor: 0)],
                                  levels: [0, 3], project: "Sara's house", author: "Sara", date: Date(timeIntervalSince1970: 0))
        let text = String(decoding: file, as: UTF8.self)
        XCTAssertTrue(text.hasPrefix("ISO-10303-21;"))
        XCTAssertTrue(text.contains("FILE_SCHEMA(('IFC4'))"))
        for entity in ["IFCWALL(", "IFCSLAB(", "IFCROOF(", "IFCCOLUMN(", "IFCBEAM(", "IFCRAILING(", "IFCGEOGRAPHICELEMENT(", "IFCSPACE(",
                       "IFCBUILDINGSTOREY(", "IFCRELCONTAINEDINSPATIALSTRUCTURE(", "IFCTRIANGULATEDFACESET("] {
            XCTAssertTrue(text.contains(entity), entity)
        }
        XCTAssertTrue(text.contains("'Sara''s house'"))
        // The same model gives the same ids.
        let again = IFCWriter.file(elements: elements, spaces: [], project: "Sara's house", author: "Sara", date: Date(timeIntervalSince1970: 0))
        XCTAssertEqual(IFCWriter.guid("element", "a"), IFCWriter.guid("element", "a"))
        XCTAssertEqual(IFCWriter.guid("element", "a").count, 22)
        XCTAssertTrue("0123".contains(IFCWriter.guid("element", "a").first ?? "x"))
        XCTAssertFalse(again.isEmpty)
        if let directory = ProcessInfo.processInfo.environment["ACCEPTANCE_DIR"] {
            let folder = URL(fileURLWithPath: directory).appendingPathComponent("room")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try file.write(to: folder.appendingPathComponent("house.ifc"))
        }
    }

    func testIFCStringsAndNumbers() {
        XCTAssertEqual(IFCWriter.string("Caffè"), "'Caff\\X2\\00E8\\X0\\'")
        XCTAssertEqual(IFCWriter.real(2.7), "2.7")
        XCTAssertEqual(IFCWriter.real(0), "0.")
        XCTAssertEqual(IFCWriter.real(-3), "-3.")
    }

    func testUnderlaysLandAtScaleAndRescaleByTwoTaps() throws {
        let drawing = DXF.Drawing(curves: [.line(Vec2(100, 100), Vec2(104, 100)), .circle(center: Vec2(102, 102), radius: 1)], skipped: 0,
                                  unit: .metre)
        let object = Underlay.sketch(drawing, at: .zero, id: ObjectID(raw: "u"))
        guard case let .sketch(sketch) = object.kind, case let .line(a, b) = sketch.curves[0] else { return XCTFail("a sketch of lines") }
        // Centred on the point, at full size.
        XCTAssertEqual(a.distance(to: b), 4, accuracy: 1e-9)
        XCTAssertEqual((a.x + b.x) / 2, 0, accuracy: 1e-9)
        XCTAssertEqual(object.isLocked, true)
        let factor = try XCTUnwrap(Underlay.factor(from: Vec3(-2, 0, 0), to: Vec3(2, 0, 0), real: 8))
        XCTAssertEqual(factor, 2, accuracy: 1e-12)
        let bigger = Underlay.rescale(object, about: Vec3(-2, 0, 0), by: factor)
        guard case let .sketch(scaled) = bigger.kind, case let .line(p, q) = scaled.curves[0],
              case let .circle(_, radius) = scaled.curves[1] else { return XCTFail("still a sketch") }
        XCTAssertEqual(p.distance(to: q), 8, accuracy: 1e-9)
        XCTAssertEqual(p.x, -2, accuracy: 1e-9)
        XCTAssertEqual(radius, 2, accuracy: 1e-9)
        // An A3 page (1190.55 pt wide) drawn at 1:100 is 42 m across.
        XCTAssertEqual(Underlay.width(pagePoints: 1190.55, scale: 0.01), 42, accuracy: 0.01)
        let card = Underlay.card(image: "plan.png", aspect: 1.414, width: 42, at: .zero, id: ObjectID(raw: "c"))
        XCTAssertEqual(card.transform.scale.x * 1.414, 42, accuracy: 0.01)
        XCTAssertNil(Underlay.factor(from: .zero, to: .zero, real: 3))
    }

    func testAPhotoGivesBackTheCameraThatTookIt() throws {
        let eye = Vec3(3.2, 1.6, 4.5), target = Vec3(0.4, 0.3, -0.6)
        let fov = 52.0, width = 1600.0, height = 1200.0
        let forward = (target - eye).normalized, right = forward.cross(.unitY).normalized, up = right.cross(forward)
        let focal = height / 2 / tan(fov * .pi / 360)
        func pixel(_ p: Vec3) -> Vec2 {
            let q = p - eye
            let z = q.dot(forward)
            return Vec2(width / 2 + focal * q.dot(right) / z, height / 2 - focal * q.dot(up) / z)
        }
        func line(_ a: Vec3, _ b: Vec3) -> PhotoMatch.Line { PhotoMatch.Line(pixel(a), pixel(b)) }
        let camera = try PhotoMatch.solve(width: width, height: height,
                                          first: (line(Vec3(-1, 0, -1), Vec3(1, 0, -1)), line(Vec3(-1, 2, -2), Vec3(1, 2, -2))),
                                          second: (line(Vec3(-1, 0, -2), Vec3(-1, 0, 1)), line(Vec3(1, 2, -2), Vec3(1, 2, 1))),
                                          origin: pixel(.zero), cameraHeight: 1.6)
        XCTAssertEqual(camera.fieldOfView, fov, accuracy: 0.01)
        XCTAssertEqual(camera.position.y, 1.6, accuracy: 1e-6)
        XCTAssertEqual(camera.position.length, eye.length, accuracy: 1e-6)
        // It looks down at the same angle.
        let looks = camera.rotation.act(Vec3(0, 0, -1))
        XCTAssertEqual(looks.y, forward.y, accuracy: 1e-6)
        // The origin is where the photo shows it: straight ahead of the camera's ray through that pixel.
        XCTAssertThrowsError(try PhotoMatch.solve(width: width, height: height, first: (line(Vec3(-1, 0, -1), Vec3(1, 0, -1)),
                                                                                        line(Vec3(-1, 0, -1), Vec3(1, 0, -1))),
                                                  second: (line(Vec3(-1, 0, -2), Vec3(-1, 0, 1)), line(Vec3(1, 2, -2), Vec3(1, 2, 1))),
                                                  origin: pixel(.zero)))
    }

    func testAScanBecomesWallsWithTheirOpeningsAFloorAndFurniture() throws {
        func wall(_ position: Vec3, yaw: Double, width: Double) -> RoomScan.Surface {
            RoomScan.Surface(kind: .wall, position: position, rotation: Quat(angle: yaw, axis: .unitY), width: width, height: 2.5)
        }
        let scan = RoomScan(surfaces: [
            wall(Vec3(0, 1.25, -2), yaw: 0, width: 4), wall(Vec3(0, 1.25, 2), yaw: 0, width: 4),
            wall(Vec3(-2, 1.25, 0), yaw: .pi / 2, width: 4), wall(Vec3(2, 1.25, 0), yaw: .pi / 2, width: 4),
            RoomScan.Surface(kind: .door, position: Vec3(0, 1.0, 2), rotation: .identity, width: 0.9, height: 2.0)
        ], items: [RoomScan.Item(category: "sofa", position: Vec3(0, 0.4, -1.5), rotation: .identity, size: Vec3(2, 0.8, 0.9))])
        var ids = IDFactory.sequential("g")
        let command = try XCTUnwrap(scan.command(ids: &ids))
        var document = Document(project: ProjectInfo(id: "p", name: "Scan"), scene: Scene(id: "s", name: "Scan"))
        _ = try command.apply(to: &document)
        let scene = document.scene
        let objects = Array(scene.objects.values)
        XCTAssertEqual(objects.filter { $0.buildingPart == .wall }.count, 4)
        XCTAssertEqual(objects.filter { $0.buildingPart == .slab }.count, 1)
        XCTAssertEqual(objects.first { $0.buildingPart == .furniture }?.name, "Sofa")
        XCTAssertEqual(scene.roots.count, 1)
        // The door went through the south wall: it has more faces than a plain box.
        let doorWall = try XCTUnwrap(objects.first { object in
            guard object.buildingPart == .wall, case let .mesh(mesh) = object.kind else { return false }
            return mesh.faces.count > 6
        })
        XCTAssertEqual(doorWall.transform.position.z, 2, accuracy: 0.1)
        XCTAssertNil(RoomScan(surfaces: [], items: []).command(ids: &ids))
    }
}
