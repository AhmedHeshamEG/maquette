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
}
