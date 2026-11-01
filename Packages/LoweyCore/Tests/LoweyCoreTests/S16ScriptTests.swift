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

    /// Item 1: a light's colour, strength, reach, cone and its softness, from the script.
    func testASpotLightFromTheScript() throws {
        let (document, result) = try compile("""
        {"do": "light", "type": "spot", "name": "Lamp", "at": [0, 2, 0], "aim": [0, 0, 0], "color": "#FFB070", "intensity": 3,
         "range": 4, "cone": 50, "penumbra": 0.6, "shadows": true}
        """)
        let lamp = try XCTUnwrap(document.scene.objects[XCTUnwrap(result.created["Lamp"])])
        XCTAssertEqual(lamp[.spotAngle]?.floatValue, 50)
        XCTAssertEqual(lamp[.spotSoftness]?.floatValue, 0.6)
        XCTAssertEqual(lamp[.lightIntensity]?.floatValue, 3)
        XCTAssertEqual(lamp[.lightRange]?.floatValue, 4)
        XCTAssertEqual(lamp[.lightShadows], .bool(true))
    }

    /// Item 6: a picture keeps its own colours when it's told to (unlit).
    func testUnlitIsAProperty() throws {
        let (document, result) = try compile("""
        {"do": "add", "shape": "plane", "name": "Spectrogram"},
        {"do": "set", "target": "Spectrogram", "property": "unlit", "value": true}
        """)
        XCTAssertEqual(try document.scene.objects[XCTUnwrap(result.created["Spectrogram"])]?[.unlit], .bool(true))
    }

    /// Item 3: "gold" on a placed model (its mesh is on the iPad) takes the material whole instead of being refused.
    func testAPlacedModelTakesAMaterialWhole() throws {
        var document = makeDocument()
        let lamp = SceneObject(id: "lamp", name: "Lamp", kind: .asset("kit.lamp"))
        document.scene.objects[lamp.id] = lamp
        document.scene.roots.append(lamp.id)
        let (painted, _) = try compile(##"{"do": "paint", "target": "Lamp", "op": "material", "material": "gold"}"##, document: document)
        let object = try XCTUnwrap(painted.scene.objects["lamp"])
        XCTAssertGreaterThan(object[.metallic]?.floatValue ?? 0, 0.8)
        XCTAssertNotNil(object[.roughness])
        XCTAssertNil(object.paint, "nothing painted")
    }

    /// Items 8 and 10: a camera watches a mark that moves (keys on the mark, not Euler angles), and drifts slowly.
    func testACameraWatchesAMovingMarkAndDrifts() throws {
        let (document, result) = try compile("""
        {"do": "mark", "name": "Plate", "at": [0, 1, 0], "radius": 0.05},
        {"do": "keys", "target": "Plate", "property": "position", "keys": [{"t": 0, "value": [0, 1, 0]}, {"t": 2, "value": [1, 1, 0]}]},
        {"do": "camera", "name": "Macro", "from": [0, 1.2, 1], "watch": "Plate", "drift": 0.5, "focalLength": 85},
        {"do": "frameShot", "subject": "Plate", "shotType": "closeUp", "camera": "Close"}
        """)
        let camera = try XCTUnwrap(result.created["Macro"])
        func forward(at time: Double) -> Vec3 {
            let posed = Animator.evaluate(document, at: time)
            return posed.scene.worldTransform(of: camera).rotation.act(Vec3(0, 0, -1))
        }
        XCTAssertLessThan(abs(forward(at: 0).x), 0.05, "looks straight at the mark")
        XCTAssertGreaterThan(forward(at: 2).x, 0.5, "and turns as it moves")
        let still = Animator.evaluate(document, at: 0.5).scene.worldTransform(of: camera).position
        let later = Animator.evaluate(document, at: 3.5).scene.worldTransform(of: camera).position
        XCTAssertGreaterThan((later - still).length, 1e-5, "the drift moves it")
        XCTAssertLessThan((later - still).length, 0.05, "slowly")
        XCTAssertNotNil(result.created["Close"], "a mark can be framed")
    }
}
