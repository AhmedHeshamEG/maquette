import LoweyCore
@testable import LoweyFeatures
import XCTest

/// M12: the bridge reaches everything. Every menu-bar command has a bridge path (and the table names no command that
/// isn't there); the app asks reach the editor; a web piece added by script plays on a card.
@MainActor
final class BridgeCoverageFlowTests: XCTestCase {
    private var app: AppModel?

    func testEveryMenuCommandHasABridgePath() {
        let commands = Set(KeyCommands.all.map(\.id))
        let covered = Set(BridgeCoverage.commands.keys)
        XCTAssertEqual(commands.subtracting(covered).sorted(), [], "commands with no bridge path")
        XCTAssertEqual(covered.subtracting(commands).sorted(), [], "paths for commands that aren't there")
    }

    func testAppAsksReachTheEditor() throws {
        let app = AppModel()
        self.app = app
        app.createProject(named: "App asks \(UUID().uuidString.prefix(6))", mood: .day, look: LookPreset.ink.id)
        let editor = try XCTUnwrap(app.editor)
        let script = """
        {"version": 3, "title": "Asks", "actions": [
          {"do": "add", "shape": "cube", "name": "Box"},
          {"do": "camera", "name": "Shot"},
          {"do": "app", "op": "playhead", "value": 1.5},
          {"do": "app", "op": "select", "value": "Box"},
          {"do": "app", "op": "panel", "value": "look"},
          {"do": "app", "op": "directorView", "value": true},
          {"do": "app", "op": "show", "value": "ghosts", "on": false}
        ]}
        """
        guard case .success = try editor.applyScript(LoweyJSON.decode(SceneScript.self, from: Data(script.utf8))) else {
            return XCTFail("the script runs")
        }
        XCTAssertEqual(editor.time, 1.5, accuracy: 1e-9)
        XCTAssertEqual(editor.selection.compactMap { editor.baseScene.objects[$0]?.name }, ["Box"])
        XCTAssertEqual(editor.openPanel, .look)
        XCTAssertTrue(editor.directorView, "through the shot's camera (it needs one)")
        XCTAssertFalse(editor.animate.ghosts)
    }

    func testAWebPieceFromAScriptPlaysOnACard() throws {
        let app = AppModel()
        self.app = app
        app.createProject(named: "Web \(UUID().uuidString.prefix(6))", mood: .day, look: LookPreset.ink.id)
        let editor = try XCTUnwrap(app.editor)
        let script = #"{"version": 3, "title": "Web", "actions": [{"do": "web", "name": "Chart", "html": "<p>hi</p>", "start": 1}]}"#
        guard case .success = try editor.applyScript(LoweyJSON.decode(SceneScript.self, from: Data(script.utf8))) else {
            return XCTFail("the script runs")
        }
        let id = try XCTUnwrap(editor.baseScene.webPieceIDs.first)
        guard case let .card(card) = editor.baseScene.objects[id]?.kind else { return XCTFail("a card") }
        XCTAssertEqual(card.frameKey(at: 2, id: id), WebFrameKey.make(object: id, frame: 60))
        XCTAssertEqual(editor.baseScene.webPiece(id)?.source, "<p>hi</p>")
    }
}
