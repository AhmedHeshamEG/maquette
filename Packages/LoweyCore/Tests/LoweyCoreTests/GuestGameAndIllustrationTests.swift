@testable import LoweyCore
import XCTest

/// G1, Game (Dev's level: greybox, freeze, a glTF each engine reads its own way, one texture) and the illustrators'
/// tools (a mannequin, a layered PSD, papercraft, vector ink).
final class GuestGameAndIllustrationTests: XCTestCase {
    func testGreyboxPiecesSitOnTheMetreGrid() throws {
        for piece in GreyboxPiece.allCases {
            let mesh = piece.mesh()
            XCTAssertTrue(MeshBoolean.isSolid(mesh), piece.title)
            let bounds = try XCTUnwrap(mesh.bounds)
            // Footprints are whole metres (or a wall's thickness) about the middle.
            XCTAssertEqual(bounds.min.x.remainder(dividingBy: 0.25), 0, accuracy: 1e-9, piece.title)
        }
        var document = Document(project: ProjectInfo(id: "p", name: "Level"), scene: Scene(id: "s", name: "Level"))
        _ = try ModelingOperations.addGreybox(.ramp, at: Vec3(2.4, 0.2, -3.6), id: ObjectID(raw: "r")).apply(to: &document)
        let ramp = try XCTUnwrap(document.scene.objects[ObjectID(raw: "r")])
        XCTAssertEqual(ramp.transform.position, Vec3(2, 0, -4))
        XCTAssertEqual(ramp.color, .rgba(GreyboxPiece.ramp.color))
    }

    func testFreezeTransformsBakesTurnAndSize() throws {
        var document = Document(project: ProjectInfo(id: "p", name: "Level"), scene: Scene(id: "s", name: "Level"))
        let object = SceneObject(id: ObjectID(raw: "c"), name: "Crate", kind: .primitive(.cube),
                                 transform: Transform(position: Vec3(3, 0, 0), rotation: Quat(angle: .pi / 4, axis: .unitY), scale: Vec3(2, 1, 1)))
        _ = try EditCommand.insert(SceneFragment(object: object), parent: nil, index: nil).apply(to: &document)
        let before = SceneBounds().worldBounds(of: object.id, in: document.scene)
        let command = try XCTUnwrap(ModelingOperations.freezeTransforms([object.id], in: document.scene))
        _ = try command.apply(to: &document)
        let frozen = try XCTUnwrap(document.scene.objects[object.id])
        XCTAssertEqual(frozen.transform.rotation, .identity)
        XCTAssertEqual(frozen.transform.scale, .one)
        XCTAssertEqual(frozen.transform.position, Vec3(3, 0, 0))
        let after = SceneBounds().worldBounds(of: object.id, in: document.scene)
        XCTAssertEqual(try XCTUnwrap(after).size.x, try XCTUnwrap(before).size.x, accuracy: 1e-6)
        XCTAssertNil(ModelingOperations.freezeTransforms([object.id], in: document.scene))
    }

    func testALevelLeavesNamedForEachEngine() throws {
        let floor = ExportMesh(name: "Floor 4 × 4", transform: .identity, mesh: GreyboxPiece.floor.mesh().renderMesh(), color: GreyboxPiece.floor.color)
        let sphere = ExportMesh(name: "Ball", transform: Transform(position: Vec3(0, 1, 0)),
                                mesh: ShapeStack.primitive(.sphere, for: SceneObject(id: ObjectID(raw: "b"), name: "Ball", kind: .primitive(.sphere)),
                                                           shading: .smooth),
                                color: RGBA(1, 0, 0))
        func names(_ data: Data) throws -> [String] {
            let length = Int(data[12]) | Int(data[13]) << 8 | Int(data[14]) << 16 | Int(data[15]) << 24
            let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: data.subdata(in: 20 ..< 20 + length)) as? [String: Any])
            return (json["nodes"] as? [[String: Any]] ?? []).compactMap { $0["name"] as? String }
        }
        let godot = try names(GameLevel.glb([floor, sphere], options: GameLevel.Options(engine: .godot)))
        XCTAssertTrue(godot.contains("Floor_4___4-col"))
        XCTAssertTrue(godot.contains("Ball-col"))
        let unity = try names(GameLevel.glb([floor, sphere], options: GameLevel.Options(engine: .unity)))
        XCTAssertTrue(unity.contains("Ball_LOD0") && unity.contains("Ball_LOD2"))
        XCTAssertTrue(unity.contains("Ball_collider"))
        let unreal = try names(GameLevel.glb([floor, sphere], options: GameLevel.Options(engine: .unreal)))
        XCTAssertTrue(unreal.contains("UCX_Ball_00"))
        // One texture for everything.
        let atlas = try XCTUnwrap(TextureAtlas.pack([floor, sphere]))
        XCTAssertEqual(atlas.size, 64)
        XCTAssertTrue(atlas.meshes.allSatisfy { $0.color == .white && $0.mesh.uvs.count == $0.mesh.positions.count })
        let level = GameLevel.glb([floor, sphere], options: GameLevel.Options(engine: .godot, atlas: true))
        XCTAssertTrue(String(decoding: level, as: UTF8.self).contains("\"images\""))
        if let directory = ProcessInfo.processInfo.environment["ACCEPTANCE_DIR"] {
            let folder = URL(fileURLWithPath: directory).appendingPathComponent("game")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try level.write(to: folder.appendingPathComponent("level.glb"))
        }
    }

    func testTheMannequinIsAFacelessWoodenPerson() {
        var ids = IDFactory.sequential("m")
        let fragment = CharacterMaker.start(.mannequin, name: "Mannequin", at: .zero, ids: &ids)
        let jobs = fragment.objects.compactMap { $0.part?.job }
        XCTAssertTrue(jobs.contains(.head) && jobs.contains(.arm) && jobs.contains(.leg))
        XCTAssertFalse(jobs.contains(.eye) || jobs.contains(.mouth))
        XCTAssertTrue(fragment.objects.filter { $0.part != nil }.allSatisfy { $0.color == .rgba(RGBA.hex("#D9B98C")) })
    }

    func testALayeredPSDOpensWithItsLayers() throws {
        var colour = RGBAImage(width: 4, height: 2, color: RGBA(0.2, 0.2, 0.2, 1))
        colour.setPixel(1, 0, RGBA(1, 0, 0, 1))
        colour.setPixel(2, 1, RGBA(0, 0, 1, 1))
        let ids: [UInt32] = [0, 7, 0, 0, 0, 0, 9, 0]
        let layered = LayeredPicture.split(colour: colour, ids: ids, names: [7: "Mannequin", 9: "Lamp ★"])
        XCTAssertEqual(layered.layers.map(\.name), ["Background", "Mannequin", "Lamp ★"])
        let file = PSDWriter.data(layered)
        let back = try PSDReader.read(file)
        XCTAssertEqual(back.width, 4)
        XCTAssertEqual(back.layers.map(\.name), ["Background", "Mannequin", "Lamp ★"])
        let lamp = back.layers[2]
        XCTAssertEqual(lamp.x, 2)
        XCTAssertEqual(lamp.y, 1)
        XCTAssertEqual(lamp.image.pixel(0, 0).b, 1, accuracy: 0.01)
    }

    func testACubeUnfoldsIntoOneCrossWithTabsAndNumbers() throws {
        let cube = EditableMesh.box(min: .zero, max: Vec3(0.05, 0.05, 0.05))
        let net = Papercraft.unfold(cube)
        XCTAssertEqual(net.pieces, 1)
        XCTAssertEqual(net.scale, 1)
        let art = try XCTUnwrap(net.pages.first)
        let folds = art.strokes.filter { $0.pen == .mountain || $0.pen == .valley }
        // Five folds join the six faces; seven edges part, each with a tab (its base a valley fold).
        XCTAssertEqual(folds.filter { $0.pen == .mountain }.count, 5)
        XCTAssertEqual(art.labels.count, 14)
        XCTAssertEqual(Set(art.labels.map(\.text)).count, 7)
        let box = try XCTUnwrap(art.bounds)
        XCTAssertGreaterThan(box.min.x, 0)
        XCTAssertLessThan(box.max.y, net.paper.height)
        let pdf = net.pdf(title: "Cube", author: nil)
        XCTAssertTrue(String(decoding: pdf.prefix(5), as: UTF8.self).hasPrefix("%PDF"))
        let svg = net.svg(page: 0)
        XCTAssertTrue(svg.contains("#FF0000") && svg.contains("#0000FF"))
    }

    func testABallUnfoldsWithoutOverlapsAndShrinksToFit() throws {
        let ball = MeshBuilder.mesh(from: PrimitiveMesh.sphere(segments: 16, rings: 10))
        let net = Papercraft.unfold(ball)
        XCTAssertGreaterThanOrEqual(net.pieces, 1)
        // A metre-wide ball does not fit A4 at real size.
        XCTAssertLessThan(net.scale, 1)
        for page in net.pages {
            let box = try XCTUnwrap(page.bounds)
            XCTAssertGreaterThanOrEqual(box.min.x, 0)
            XCTAssertLessThanOrEqual(box.max.x, net.paper.width + 1e-9)
            XCTAssertLessThanOrEqual(box.max.y, net.paper.height + 1e-9)
        }
        if let directory = ProcessInfo.processInfo.environment["ACCEPTANCE_DIR"] {
            let folder = URL(fileURLWithPath: directory).appendingPathComponent("papercraft")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try net.pdf(title: "Ball", author: "Lina").write(to: folder.appendingPathComponent("ball.pdf"))
            try Data(net.svg(page: 0).utf8).write(to: folder.appendingPathComponent("ball.svg"))
        }
    }

    func testInkLeavesAsVectorsAndSwatchesUnzip() throws {
        let soup = TriangleSoup(EditableMesh.box(min: Vec3(-0.5, 0, -0.5), max: Vec3(0.5, 1, 0.5)), name: "box")
        let svg = InkVectors.svg(soup, eye: Vec3(2, 2, 3), forward: (Vec3(0, 0.5, 0) - Vec3(2, 2, 3)).normalized, up: .unitY, fieldOfView: 40,
                                 width: 1920, height: 1080)
        XCTAssertTrue(svg.contains("<polyline"))
        XCTAssertTrue(svg.contains("viewBox=\"0 0 1920 1080\""))
        let zip = ZipWriter.storedArchive([("Swatches.json", Data("[{\"name\":\"Mine\",\"swatches\":[]}]".utf8))])
        XCTAssertEqual(try ProcreateSwatchesFile.json(zip), Data("[{\"name\":\"Mine\",\"swatches\":[]}]".utf8))
        XCTAssertThrowsError(try ProcreateSwatchesFile.json(Data("nope".utf8)))
    }
}
