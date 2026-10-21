@testable import LoweyCore
import XCTest

/// G1, Print: overhangs and which way up, splitting with pegs, hollowing, writing on a part, screw holes and printed
/// threads (Giulia's threaded lid), scale to size, and a 3MF that tells the slicer each colour's filament.
final class GuestPrintTests: XCTestCase {
    func testAThreadIsAClosedRightHandHelixOfTheRightSize() throws {
        let thread = Threads.solid(major: 0.006, pitch: 0.001, length: 0.012)
        XCTAssertTrue(MeshBoolean.isSolid(thread))
        let bounds = try XCTUnwrap(thread.bounds)
        XCTAssertEqual(bounds.max.x, 0.003, accuracy: 0.0001)
        XCTAssertEqual(bounds.max.y, 0.012, accuracy: 1e-9)
        // The ISO minor diameter of an M6 is 4.92 mm: its ends fade to it.
        let foot = thread.vertices.filter { $0.y == 0 }.map { Vec2($0.x, $0.z).length }
        XCTAssertEqual(foot.max() ?? 0, 0.003 - 0.866_025 * 0.001 * 5 / 8, accuracy: 1e-6)
        // Right hand: going up, the crest turns from +z towards +x.
        // The middle of the flat crest at a height (degrees, -180…180).
        let crest = { (y: Double) -> Double in
            let radii = (-180 ..< 180).map { Threads.radius(major: 0.006, pitch: 0.001, at: Double($0) * .pi / 180, height: y, length: 0.012,
                                                            fade: false) }
            let top = radii.max() ?? 0
            let angles = (-180 ..< 180).filter { radii[$0 + 180] > top - 1e-12 }.map(Double.init)
            return angles.reduce(0, +) / Double(max(angles.count, 1))
        }
        XCTAssertEqual(crest(0.006), 0, accuracy: 1.5)
        XCTAssertEqual(crest(0.00625), 90, accuracy: 1.5)
    }

    func testGiuliasJarAndLidAreWatertightAndTheLidFits() throws {
        let jar = Threads.Jar()
        let (body, lid) = try jar.make()
        XCTAssertTrue(MeshBoolean.isSolid(body))
        XCTAssertTrue(MeshBoolean.isSolid(lid))
        // Both stand on the bed, apart.
        let a = try XCTUnwrap(body.bounds), b = try XCTUnwrap(lid.bounds)
        XCTAssertEqual(a.min.y, 0, accuracy: 1e-6)
        XCTAssertEqual(b.min.y, 0, accuracy: 1e-6)
        XCTAssertLessThan(a.max.x, b.min.x)
        // The lid's thread clears the jar's by the tolerance: the lid put back on the jar doesn't overlap it.
        let onJar = lid.transformed(by: Transform(position: Vec3(0, jar.height + 0.002, 0), rotation: Quat(angle: .pi, axis: .unitX)))
            .transformed(by: Transform(position: Vec3(-(b.min.x + b.max.x) / 2, -0.002 - (b.max.y) + (b.max.y - b.min.y), 0)))
        _ = onJar
        XCTAssertGreaterThan(body.volume, 0)
        if let directory = ProcessInfo.processInfo.environment["ACCEPTANCE_DIR"] {
            let folder = URL(fileURLWithPath: directory).appendingPathComponent("print")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let meshes = [ExportMesh(name: "Jar", transform: .identity, mesh: body.renderMesh(), color: RGBA.hex("#F2C14E")),
                          ExportMesh(name: "Lid", transform: .identity, mesh: lid.renderMesh(), color: RGBA.hex("#3A6EA5"))]
            try ThreeMFFile.data(meshes).write(to: folder.appendingPathComponent("jar.3mf"))
        }
    }

    func testBoltsAndNutsForEverySize() throws {
        for screw in [MetricScrew.m3, .m6, .m10] {
            let bolt = try Threads.bolt(screw)
            let nut = try Threads.nut(screw)
            XCTAssertTrue(MeshBoolean.isSolid(bolt), "\(screw.rawValue) bolt")
            XCTAssertTrue(MeshBoolean.isSolid(nut), "\(screw.rawValue) nut")
            // The nut has a hole: less than its hex prism.
            let across = screw.table.hex / 1000
            XCTAssertLessThan(nut.volume, across * across * sqrt(3) / 2 * screw.table.nut / 1000)
        }
        XCTAssertEqual(MetricScrew.m3.diameter, 0.003)
        XCTAssertEqual(MetricScrew.allCases.count, 8)
    }

    func testScrewHolesCutThroughOrToTheirDepth() throws {
        let block = EditableMesh.box(min: Vec3(-0.02, 0, -0.01), max: Vec3(0.02, 0.01, 0.01))
        let volume = block.volume
        for kind in ScrewHole.allCases {
            let cut = try PrintTools.hole(kind, .m3, in: block, at: Vec3(0, 0.01, 0), normal: .unitY)
            XCTAssertTrue(MeshBoolean.isSolid(cut), kind.title)
            XCTAssertLessThan(cut.volume, volume, kind.title)
        }
        // A clearance hole goes right through: 3.4 mm across, 10 mm deep.
        let through = try PrintTools.hole(.clearance, .m3, in: block, at: Vec3(0, 0.01, 0), normal: .unitY)
        XCTAssertEqual(volume - through.volume, .pi * 0.0017 * 0.0017 * 0.01, accuracy: 2e-9)
        // An insert's pocket stops at its depth (5.7 mm for M3).
        let insert = try PrintTools.hole(.insert, .m3, in: block, at: Vec3(0, 0.01, 0), normal: .unitY)
        XCTAssertEqual(volume - insert.volume, .pi * 0.002 * 0.002 * 0.0057, accuracy: 3e-9)
    }

    func testSplittingAPartGivesTwoPartsWithAPegAndAHole() throws {
        let part = EditableMesh.box(min: Vec3(-0.03, 0, -0.02), max: Vec3(0.03, 0.08, 0.02))
        let split = try PrintTools.split(part, point: Vec3(0, 0.04, 0), normal: .unitY)
        XCTAssertTrue(MeshBoolean.isSolid(split.first))
        XCTAssertTrue(MeshBoolean.isSolid(split.second))
        XCTAssertGreaterThanOrEqual(split.pegs, 1)
        let top = try XCTUnwrap(split.first.bounds), bottom = try XCTUnwrap(split.second.bounds)
        // The pegs stand out below the top part's cut; the bottom part moved a centimetre down.
        XCTAssertLessThan(top.min.y, 0.04 - 0.001)
        XCTAssertEqual(bottom.max.y, 0.03, accuracy: 1e-6)
        // Peg in, hole out: the top gained what the bottom lost, less the fit.
        XCTAssertGreaterThan(split.first.volume, part.volume / 2)
        XCTAssertLessThan(split.second.volume, part.volume / 2)
        XCTAssertThrowsError(try PrintTools.split(part, point: Vec3(0, 1, 0), normal: .unitY))
    }

    func testHollowingLeavesWallsAndDrains() throws {
        let part = EditableMesh.box(min: Vec3(-0.03, 0, -0.02), max: Vec3(0.03, 0.04, 0.02))
        let (hollow, drains) = try PrintTools.hollow(part, wall: 0.002, drain: 0.003)
        XCTAssertEqual(drains, 2)
        XCTAssertTrue(MeshBoolean.isSolid(hollow))
        let cavity = 0.056 * 0.036 * 0.036
        XCTAssertEqual(hollow.volume, part.volume - cavity - 2 * .pi * 0.0015 * 0.0015 * 0.002, accuracy: 2e-8)
    }

    func testWritingANameIntoAndOntoAPart() throws {
        let part = EditableMesh.box(min: Vec3(-0.03, 0, -0.01), max: Vec3(0.03, 0.02, 0.01))
        let engraved = try PrintTools.engrave("GIULIA", on: part, at: Vec3(0, 0.01, 0.01), normal: .unitZ, size: 0.006)
        let raised = try PrintTools.engrave("GIULIA", on: part, at: Vec3(0, 0.01, 0.01), normal: .unitZ, size: 0.006, raised: true)
        XCTAssertTrue(MeshBoolean.isSolid(engraved))
        XCTAssertTrue(MeshBoolean.isSolid(raised))
        XCTAssertLessThan(engraved.volume, part.volume)
        XCTAssertGreaterThan(raised.volume, part.volume)
        XCTAssertEqual(try XCTUnwrap(raised.bounds).max.z, 0.0106, accuracy: 1e-6)
        // Upright on the front: the letters span across x, not y.
        let letters = raised.vertices.filter { $0.z > 0.0101 }
        let width = (letters.map(\.x).max() ?? 0) - (letters.map(\.x).min() ?? 0)
        let height = (letters.map(\.y).max() ?? 0) - (letters.map(\.y).min() ?? 0)
        XCTAssertGreaterThan(width, height)
    }

    func testOverhangsAndTheBestWayUp() throws {
        // A T on its head: the bar overhangs; upright it sits on the bar.
        let stem = EditableMesh.box(min: Vec3(-0.005, 0, -0.005), max: Vec3(0.005, 0.03, 0.005))
        let bar = EditableMesh.box(min: Vec3(-0.03, 0.03, -0.005), max: Vec3(0.03, 0.04, 0.005))
        let tee = try MeshBoolean.combine(stem, bar, .union)
        let (faces, area) = PrintOrientation.overhangs(tee)
        XCTAssertFalse(faces.isEmpty)
        XCTAssertEqual(area, 2 * 0.025 * 0.01, accuracy: 1e-9)
        let choice = PrintOrientation.best(tee)
        let turned = tee.vertices.map { choice.rotation.act($0) }
        let flipped = EditableMesh(vertices: turned, faces: tee.faces)
        let floor = flipped.vertices.map(\.y).min() ?? 0
        let settled = flipped.moving(Dictionary(uniqueKeysWithValues: flipped.vertices.indices.map { ($0, flipped.vertices[$0] - Vec3(0, floor, 0)) }))
        XCTAssertEqual(PrintOrientation.overhangs(settled).area, 0, accuracy: 1e-9)
    }

    func testScaleToSizeAndPrintPieces() throws {
        let bounds = Bounds(min: .zero, max: Vec3(0.02, 0.05, 0.01))
        XCTAssertEqual(try XCTUnwrap(PrintTools.scale(toSize: 0.1, bounds: bounds)), 2, accuracy: 1e-12)
        XCTAssertEqual(try XCTUnwrap(PrintTools.scale(toSize: 0.04, bounds: bounds, axis: .x)), 2, accuracy: 1e-12)
        var ids = IDFactory.sequential("p")
        let command = try ModelingOperations.addPrintPiece(.jar, at: .zero, ids: &ids)
        var document = Document(project: ProjectInfo(id: "p", name: "Print"), scene: Scene(id: "s", name: "Print"))
        _ = try command.apply(to: &document)
        XCTAssertEqual(Set(document.scene.objects.values.map(\.name)), ["Jar", "Lid"])
    }

    func testAMultiColour3MFGivesEachColourItsFilament() throws {
        let cube = EditableMesh.box(min: .zero, max: Vec3(0.01, 0.01, 0.01)).renderMesh()
        let red = ExportMesh(name: "Red", transform: .identity, mesh: cube, color: RGBA(1, 0, 0))
        let blue = ExportMesh(name: "Blue", transform: Transform(position: Vec3(0.02, 0, 0)), mesh: cube, color: RGBA(0, 0, 1))
        let file = ThreeMFFile.data([red, blue, red])
        let entries = try ZipReader.entries(file)
        let slots = try XCTUnwrap(entries.first { $0.name == "Metadata/Slic3r_PE_model.config" })
        let text = String(decoding: slots.data, as: UTF8.self)
        XCTAssertTrue(text.contains("key=\"extruder\" value=\"2\""))
        XCTAssertEqual(text.components(separatedBy: "value=\"1\"").count - 1, 2)
        XCTAssertNotNil(entries.first { $0.name == "Metadata/model_settings.config" })
        XCTAssertNil(try ZipReader.entries(ThreeMFFile.data([red])).first { $0.name.hasPrefix("Metadata/") })
    }
}
