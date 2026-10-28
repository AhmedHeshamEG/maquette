import Foundation
@testable import LoweyCore
import XCTest

/// G1: the bridge reaches the guests' kits through the `guest` verb (and the mannequin through `character`), and the
/// Game and Study set-ups put their tools in reach.
final class GuestBridgeTests: XCTestCase {
    private func run(_ actions: String, on document: Document? = nil) throws -> ScriptResult {
        let script = try LoweyJSON.decode(SceneScript.self, from: Data("{\"version\": 3, \"title\": \"T\", \"actions\": [\(actions)]}".utf8))
        let start = document ?? Document(project: ProjectInfo(id: "p", name: "P"), scene: Scene(id: "s", name: "S"))
        return try ScriptCompiler.compile(script, document: start, context: ScriptContext(ids: .sequential("run")))
    }

    func testARoomFromAScript() throws {
        let result = try run("""
        {"do": "add", "shape": "cube", "name": "Walls", "at": [0, 0, 0], "size": [8, 2.7, 5]},
        {"do": "guest", "op": "roof", "kind": "hip", "over": "Walls", "name": "Roof"},
        {"do": "guest", "op": "column", "at": [5, 0, 3]},
        {"do": "guest", "op": "beam", "from": [0, 2.7, 0], "to": [4, 2.7, 0]},
        {"do": "guest", "op": "railing", "path": [[0, 0, 4], [3, 0, 4]]},
        {"do": "guest", "op": "person", "at": [2, 0, 4], "yaw": 20},
        {"do": "guest", "op": "terrain", "width": 30, "hills": 0},
        {"do": "guest", "op": "label", "text": "Kitchen", "at": [1, 0, 1]}
        """)
        let parts = Set(result.document.scene.objects.values.compactMap(\.buildingPart))
        XCTAssertEqual(parts, [.roof, .column, .beam, .railing, .person, .terrain])
        let roof = try XCTUnwrap(result.document.scene.objects.values.first { $0.buildingPart == .roof })
        XCTAssertEqual(roof.name, "Roof")
        XCTAssertThrowsError(try run(#"{"do": "guest", "op": "roof"}"#))
        XCTAssertThrowsError(try run(#"{"do": "guest", "op": "teleport"}"#)) { XCTAssertTrue(String(describing: $0).contains("greybox")) }
    }

    func testPrintingFromAScript() throws {
        let result = try run("""
        {"do": "add", "shape": "cube", "name": "Box", "at": [0, 0, 0], "size": [0.04, 0.02, 0.03]},
        {"do": "guest", "op": "hole", "target": "Box", "screw": "M3", "kind": "counterbore", "face": "top"},
        {"do": "guest", "op": "engrave", "target": "Box", "text": "GIULIA", "face": "front", "size": 0.005},
        {"do": "guest", "op": "split", "target": "Box", "axis": "y", "at": 0.01},
        {"do": "guest", "op": "print", "piece": "nut", "screw": "M5", "at": [0.1, 0, 0]},
        {"do": "guest", "op": "scale", "target": "Box", "size": 0.08, "axis": "x"}
        """)
        let names = result.document.scene.objects.values.map(\.name)
        XCTAssertTrue(names.contains("Box (2)"))
        XCTAssertTrue(names.contains("M5 nut"))
        let box = try XCTUnwrap(result.document.scene.objects.values.first { $0.name == "Box" })
        guard case let .mesh(mesh) = box.kind else { return XCTFail("the box became a modelled shape") }
        XCTAssertTrue(MeshBoolean.isSolid(mesh))
        // Scaled evenly until it's 8 cm across.
        let size = try XCTUnwrap(SceneBounds().worldBounds(of: box.id, in: result.document.scene)).size
        XCTAssertEqual(size.x, 0.08, accuracy: 1e-6)
    }

    func testStudyAndGameFromAScript() throws {
        let result = try run("""
        {"do": "add", "shape": "cube", "name": "Base", "at": [0, 0, 0]},
        {"do": "add", "shape": "cube", "name": "Lid", "at": [0, 1.2, 0]},
        {"do": "group", "target": ["Base", "Lid"], "name": "Gearbox"},
        {"do": "guest", "op": "explode", "target": "Gearbox"},
        {"do": "guest", "op": "greybox", "piece": "ramp", "at": [4.3, 0, 0.2]},
        {"do": "character", "op": "new", "start": "mannequin", "name": "Pose"}
        """)
        let scene = result.document.scene
        XCTAssertEqual(scene.objects.values.first { $0.name == "Gearbox" }?.explodeAmount, 1)
        XCTAssertEqual(scene.objects.values.first { $0.name == GreyboxPiece.ramp.title }?.transform.position, Vec3(4, 0, 0))
        XCTAssertEqual(scene.objects.values.first { $0.name == "Pose" }?[.characterStart]?.stringValue, "mannequin")
    }

    func testTheGameSetUpAndStudyIsGone() {
        XCTAssertEqual(StarterTemplate.setUps, [.blank, .room, .print, .game, .animation], "Study was removed (§D.24)")
        let game = ProjectWorkspace().settingUp(for: .game)
        XCTAssertEqual(game.units, .metre)
        XCTAssertEqual(game.snap.gridSize, 1)
        XCTAssertEqual(game.setUp, .game)
        let study = ProjectWorkspace().settingUp(for: .study)
        XCTAssertEqual(study.units, .millimetre)
        XCTAssertTrue(study.showsDimensions)
        XCTAssertEqual(StarterTemplate.template(.study).lookPresetID, LookPreset.cleanProduct.id)
        XCTAssertEqual(study.setUp, .blank, "a project made for Study opens as Blank")
    }
}
