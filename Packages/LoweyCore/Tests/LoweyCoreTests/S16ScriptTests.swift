@testable import LoweyCore
import XCTest

/// The S16 field report (a finished three.js film rebuilt through the bridge): each test is one item that broke.
final class S16ScriptTests: XCTestCase {
    private func compile(_ actions: String, document: Document = makeDocument()) throws -> (Document, ScriptResult) {
        let script = try LoweyJSON.decode(SceneScript.self, from: Data("{\"title\": \"S16\", \"actions\": [\(actions)]}".utf8))
        let result = try ScriptCompiler.compile(script, document: document, context: ScriptContext(now: 0, ids: .sequential("s")))
        let command = try XCTUnwrap(result.command)
        return (try assertReverts(command, on: document), result)
    }

    private func error(_ actions: String) -> String {
        do {
            _ = try compile(actions)
            return "no error"
        } catch {
            return String(describing: error)
        }
    }

    /// Item 7: a zoom keyed in millimetres plays (it was stored under a name nothing reads).
    func testLensKeysInMillimetresAnimateTheFieldOfView() throws {
        let (document, result) = try compile("""
        {"do": "camera", "name": "Cam", "from": [0, 1, 4], "lookAt": [0, 0, 0]},
        {"do": "keys", "target": "Cam", "property": "focalLength", "keys": [{"t": 0, "value": 35}, {"t": 2, "value": 24}]}
        """)
        let camera = try XCTUnwrap(result.created["Cam"])
        let track = try XCTUnwrap(document.scene.timeline.track(for: camera, .fieldOfView))
        guard case let .float(start)? = track.keyframes.first?.value, case let .float(end)? = track.keyframes.last?.value else {
            return XCTFail("the keys are on the field of view")
        }
        XCTAssertEqual(start, CameraLens.fieldOfView(focalLength: 35), accuracy: 1e-9)
        XCTAssertEqual(end, CameraLens.fieldOfView(focalLength: 24), accuracy: 1e-9)
        XCTAssertNil(document.scene.timeline.track(for: camera, PropertyKey("focalLength")))
    }

    func testAnUnknownPropertyIsRefusedNotStored() {
        XCTAssertTrue(error(##"{"do": "add", "shape": "cube", "name": "A"}, {"do": "set", "target": "A", "property": "shininess", "value": 1}"##)
            .contains("unknown property “shininess”"))
    }

    /// Item 12: `"anchor": "center"` puts the middle at `at`; the bottom stays the default.
    func testAnchorCenterPutsTheMiddleAtThePoint() throws {
        let (document, result) = try compile("""
        {"do": "add", "shape": "cube", "name": "Mid", "at": [0, 1, 0], "size": [1, 0.5, 1], "anchor": "center"},
        {"do": "add", "shape": "cube", "name": "Base", "at": [2, 1, 0], "size": [1, 0.5, 1]}
        """)
        let bounds = SceneBounds()
        let mid = try XCTUnwrap(bounds.worldBounds(of: XCTUnwrap(result.created["Mid"]), in: document.scene))
        let base = try XCTUnwrap(bounds.worldBounds(of: XCTUnwrap(result.created["Base"]), in: document.scene))
        XCTAssertEqual(mid.center.y, 1, accuracy: 1e-6)
        XCTAssertEqual(base.min.y, 1, accuracy: 1e-6)
    }

    /// Item 13: a shape added "on" another stands on it, not on the floor.
    func testAShapeAddedOnAnotherStandsOnIt() throws {
        let (document, result) = try compile("""
        {"do": "add", "shape": "cube", "name": "Desk", "at": [0, 0, 0], "size": [1.6, 0.75, 0.8]},
        {"do": "add", "shape": "cylinder", "name": "Cup", "size": [0.08, 0.1, 0.08], "relation": "on", "reference": "Desk"}
        """)
        let bounds = SceneBounds()
        let cup = try XCTUnwrap(bounds.worldBounds(of: XCTUnwrap(result.created["Cup"]), in: document.scene))
        XCTAssertEqual(cup.min.y, 0.75, accuracy: 0.01)
    }

    /// Item 14: placing a thing that was laid down keeps it laid down; only its heading changes.
    func testPlacingKeepsATilt() throws {
        let (document, result) = try compile("""
        {"do": "add", "shape": "cube", "name": "Desk", "at": [0, 0, 0], "size": [1.6, 0.75, 0.8]},
        {"do": "add", "shape": "cube", "name": "Card", "at": [3, 0, 0], "size": [0.4, 0.3, 0.01], "rotation": [-90, 0, 0]},
        {"do": "place", "target": "Card", "relation": "on", "reference": "Desk"}
        """)
        let card = try XCTUnwrap(result.created["Card"])
        let up = document.scene.worldTransform(of: card).rotation.act(Vec3(0, 0, 1))
        XCTAssertEqual(abs(up.y), 1, accuracy: 1e-6, "the card's face still points up")
        XCTAssertEqual(abs(RelationSolver.tilt(of: Quat(angle: 0.7, axis: .unitY)).w), 1, accuracy: 1e-9, "a plain heading leaves no tilt")
    }
}
