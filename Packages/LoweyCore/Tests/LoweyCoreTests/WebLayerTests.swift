import Foundation
@testable import LoweyCore
import XCTest

/// M12: web pieces on a card and over the frame, their frames on the timeline's clock, the `web` verb and schema 25.
final class WebLayerTests: XCTestCase {
    private func document(_ objects: [SceneObject] = []) -> Document {
        var scene = Scene(id: "s", name: "S")
        for object in objects {
            scene.objects[object.id] = object
            scene.roots.append(object.id)
        }
        return Document(project: ProjectInfo(id: "p", name: "P"), scene: scene)
    }

    private func run(_ actions: String, on document: Document? = nil, files: [String: Data] = [:]) throws -> ScriptResult {
        let script = "{\"version\": 3, \"title\": \"Web\", \"actions\": [\(actions)]}"
        let context = ScriptContext(ids: .sequential("run"), file: { files[$0] })
        return try ScriptCompiler.compile(LoweyJSON.decode(SceneScript.self, from: Data(script.utf8)), document: document ?? self.document(),
                                          context: context)
    }

    func testFramesRunSixtyASecondFromTheStartAndHoldOrLoop() {
        var piece = WebPiece(source: "<p>", start: 2)
        XCTAssertEqual(piece.frame(at: 0), 0, "before it starts: its first frame")
        XCTAssertEqual(piece.frame(at: 2.5), 30)
        XCTAssertEqual(piece.frame(at: 2 + 1.0 / 60), 1, "a frame's own start belongs to it")
        piece.duration = 1
        XCTAssertEqual(piece.frame(at: 10), 59, "held on its last frame")
        piece.loop = true
        XCTAssertEqual(piece.frame(at: 3.25), 15, "looped")
    }

    func testFrameKeysNameTheObjectAndTheFrameAndAreNoVideoKeys() throws {
        let key = WebFrameKey.make(object: "card#1", frame: 42)
        let parsed = try XCTUnwrap(WebFrameKey.parse(key))
        XCTAssertEqual(parsed.object, "card#1")
        XCTAssertEqual(parsed.frame, 42)
        XCTAssertNil(VideoFrameKey.parse(key), "a web key never reads as a video's")
        XCTAssertNil(WebFrameKey.parse(VideoFrameKey.make(file: "clip.mov", time: 1)))
        XCTAssertNil(WebFrameKey.parse("still.png"))
    }

    func testACardAndAnOverlayShowTheirPiecesFrames() {
        let piece = WebPiece(source: "<p>", start: 1)
        let card = CardRecipe(aspect: piece.aspect, web: piece)
        XCTAssertEqual(card.frameKey(at: 2, id: "screen"), WebFrameKey.make(object: "screen", frame: 60))
        XCTAssertNil(CardRecipe(web: piece).frameKey(at: 2), "a web card needs its id")
        let overlay = SceneObject(id: "title", name: "Title", kind: .overlay(OverlayRecipe(shape: .image, web: piece)))
        let made = document([overlay])
        let scene = made.scene
        XCTAssertTrue(OverlayLayout.placements(in: scene, palette: made.palette, width: 1920, height: 1080, time: 0.5).isEmpty,
                      "over the frame, it shows from its start")
        let shown = OverlayLayout.placements(in: scene, palette: made.palette, width: 1920, height: 1080, time: 1.5)
        XCTAssertEqual(shown.first?.recipe.image, WebFrameKey.make(object: "title", frame: 30))
        XCTAssertEqual(scene.webPieceIDs, ["title"])
        XCTAssertEqual(scene.webPiece("title"), piece)
    }

    func testSizesStayWithinTheLargestPageShapeKept() {
        let big = WebPiece(width: 7680, height: 4320).clampedSize
        XCTAssertEqual(big.width, WebPiece.largest)
        XCTAssertEqual(big.height, 2160)
        XCTAssertEqual(WebPiece(width: 2, height: 2).clampedSize.width, 16)
        XCTAssertEqual(WebPiece.kind(forFile: "logo.JSON"), .lottie)
        XCTAssertEqual(WebPiece.kind(forFile: "scene.html"), .html)
    }

    func testTheVerbAddsAScreenAFrameOverlayAndALottie() throws {
        let lottie = #"{"v":"5.7.0","fr":30,"ip":0,"op":90,"w":400,"h":200,"layers":[]}"#
        let result = try run("""
        {"do": "web", "name": "Chart", "html": "<canvas></canvas>", "width": 800, "height": 600, "at": [1, 0, 0], "size": 2, "start": 1},
        {"do": "web", "name": "Lower third", "on": "frame", "html": "<h1>Hi</h1>", "at": [0, -0.7]},
        {"do": "web", "name": "Logo", "on": "frame", "lottie": \(lottie)},
        {"do": "web", "op": "list"}
        """)
        let scene = result.document.scene
        let chart = try XCTUnwrap(scene.objects.values.first { $0.name == "Chart" })
        guard case let .card(card) = chart.kind, let piece = card.web else { return XCTFail("a card with a piece") }
        XCTAssertEqual(piece.source, "<canvas></canvas>")
        XCTAssertEqual(piece.width, 800)
        XCTAssertEqual(piece.start, 1)
        XCTAssertEqual(card.aspect, 800.0 / 600, accuracy: 1e-9)
        XCTAssertEqual(chart.transform.position, Vec3(1, 0, 0))
        XCTAssertEqual(chart.transform.scale, Vec3(2, 2, 2))
        let third = try XCTUnwrap(scene.objects.values.first { $0.name == "Lower third" })
        XCTAssertTrue(third.kind.isOverlay)
        XCTAssertEqual(third.transform.position.y, -0.7)
        let logo = try XCTUnwrap(scene.webPiece(XCTUnwrap(scene.objects.values.first { $0.name == "Logo" }).id))
        XCTAssertEqual(logo.kind, .lottie)
        XCTAssertEqual(logo.width, 400)
        XCTAssertEqual(logo.duration ?? 0, 3, accuracy: 1e-9, "90 frames at 30")
        XCTAssertEqual(result.report.filter { $0.hasPrefix("“") }.count, 3, "list names every piece")
    }

    func testTheVerbEditsAPieceAndRefusesWhatIsntOne() throws {
        let first = try run(#"{"do": "web", "name": "Panel", "html": "<p>one</p>"}"#)
        let edited = try run(#"{"do": "web", "op": "edit", "target": "Panel", "html": "<p>two</p>", "loop": true, "duration": 4}"#,
                             on: first.document)
        let id = try XCTUnwrap(edited.document.scene.objects.values.first { $0.name == "Panel" }).id
        XCTAssertEqual(edited.document.scene.webPiece(id)?.source, "<p>two</p>")
        XCTAssertEqual(edited.document.scene.webPiece(id)?.loop, true)
        XCTAssertEqual(edited.document.scene.webPiece(id)?.duration, 4)
        let box = SceneObject(id: "box", name: "Box", kind: .primitive(.cube))
        XCTAssertThrowsError(try run(#"{"do": "web", "op": "edit", "target": "Box", "html": "<p>"}"#, on: document([box])))
        XCTAssertThrowsError(try run(#"{"do": "web"}"#), "nothing to play")
        XCTAssertThrowsError(try run(#"{"do": "web", "file": "missing.html"}"#), "the file has to be in the project")
        let fromFile = try run(#"{"do": "web", "file": "intro"}"#, files: ["intro/index.html": Data("<p>".utf8)])
        let piece = try XCTUnwrap(fromFile.document.scene.webPieceIDs.first.flatMap { fromFile.document.scene.webPiece($0) })
        XCTAssertEqual(piece.file, "intro")
        XCTAssertEqual(piece.kind, .html)
    }

    func testAPieceSurvivesTheFileAndSchema24FilesOpen() throws {
        let piece = WebPiece(kind: .lottie, source: "{}", width: 300, height: 300, start: 0.5, duration: 2, loop: true)
        let object = SceneObject(id: "w", name: "W", kind: .card(CardRecipe(web: piece)))
        let data = try SchemaCoder.shared.encode(document([object]).scene, kind: .scene)
        let back = try SchemaCoder.shared.decode(Scene.self, kind: .scene, from: data)
        XCTAssertEqual(back.webPiece("w"), piece)
        let old = """
        {"schemaVersion": 24, "kind": "scene", "payload": {"id": "s", "name": "Old", "objects": {}, "roots": [],
         "viewpoint": {"target": [0, 0.5, 0], "yaw": 35, "pitch": 28, "distance": 9, "projection": "perspective", "fieldOfView": 50},
         "timeline": {"fps": 30, "duration": 10, "stepping": 1, "tracks": []}}}
        """
        XCTAssertTrue(try SchemaCoder.shared.decode(Scene.self, kind: .scene, from: Data(old.utf8)).webPieceIDs.isEmpty)
        XCTAssertNotNil(ProjectHistory.opMigrations[24], "journals written at 24 replay")
    }
}

/// M12: the scene placed in the room for the AR view.
final class ARPlacementTests: XCTestCase {
    func testTheCameraIsCarriedIntoTheScenesSpace() {
        let placement = ARPlacement(position: Vec3(1, 0, -2), yaw: .pi / 2, scale: 0.1)
        let corner = Vec3(2, 0, 0)
        let roomCorner = placement.room(corner)
        XCTAssertEqual(roomCorner.x, 1, accuracy: 1e-9)
        XCTAssertEqual(roomCorner.z, -2.2, accuracy: 1e-9, "a quarter turn sends +x to −z, a tenth of the size")
        let camera = Transform(position: Vec3(1, 0.5, -1), rotation: Quat(angle: 0.3, axis: .unitY))
        let seen = placement.sceneCamera(camera)
        XCTAssertEqual(placement.room(seen.position).x, camera.position.x, accuracy: 1e-9)
        XCTAssertEqual(placement.room(seen.position).y, camera.position.y, accuracy: 1e-9)
        XCTAssertEqual(placement.room(seen.position).z, camera.position.z, accuracy: 1e-9)
        XCTAssertEqual(seen.position.length, 10 * (camera.position - placement.position).length, accuracy: 1e-9, "ten times as far")
        let forward = seen.rotation.act(Vec3(0, 0, -1))
        let roomForward = placement.rotation.act(forward)
        let expected = camera.rotation.act(Vec3(0, 0, -1))
        XCTAssertEqual(roomForward.x, expected.x, accuracy: 1e-9)
        XCTAssertEqual(roomForward.z, expected.z, accuracy: 1e-9)
        XCTAssertEqual(placement.sceneDepth(near: 0.01, far: 100).near, 0.1, accuracy: 1e-12)
    }

    func testATableSizeAndAPinchThatSnapsToLifeSize() {
        let house = Bounds(min: Vec3(-5, 0, -4), max: Vec3(5, 6, 4))
        XCTAssertEqual(ARPlacement.tableScale(for: house), 0.04, accuracy: 1e-9, "10 m across stands 40 cm wide")
        XCTAssertEqual(ARPlacement.tableScale(for: Bounds(min: .zero, max: Vec3(0.1, 0.1, 0.1))), 1, "never bigger than life")
        XCTAssertEqual(ARPlacement(scale: 0.95).pinched(1.02), 1, "near life size snaps to it")
        XCTAssertEqual(ARPlacement(scale: 0.5).pinched(0.5), 0.25, accuracy: 1e-12)
        XCTAssertEqual(ARPlacement(scale: 3).pinched(10), ARPlacement.scales.upperBound)
        XCTAssertTrue(ARPlacement().isLifeSize)
    }
}
