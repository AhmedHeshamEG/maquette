import Foundation
@testable import LoweyCore
import XCTest

/// M12: the bridge reaches everything. Every path in `BridgeCoverage` exists: its verb in the compiler, its op in the
/// Scene Script schema, its tool in the skill's tool reference; and the app asks and `duplicate` work.
final class BridgeCoverageTests: XCTestCase {
    private static let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    /// Verb → the ops its schema entry allows.
    private func schemaOps() throws -> [String: Set<String>] {
        let data = try Data(contentsOf: Self.repo.appendingPathComponent("schemas/scene-script.v3.schema.json"))
        let schema = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let action = try XCTUnwrap((schema["$defs"] as? [String: Any])?["action"] as? [String: Any])
        var result: [String: Set<String>] = [:]
        for entry in action["allOf"] as? [[String: Any]] ?? [] {
            guard let verb = ((entry["if"] as? [String: Any])?["properties"] as? [String: Any]).flatMap({ ($0["do"] as? [String: Any])?["const"] as? String }),
                  let properties = (entry["then"] as? [String: Any])?["properties"] as? [String: Any] else { continue }
            result[verb] = Set((properties["op"] as? [String: Any])?["enum"] as? [String] ?? [])
        }
        return result
    }

    func testEveryPathExists() throws {
        let ops = try schemaOps()
        let all = Array(BridgeCoverage.commands) + Array(BridgeCoverage.making)
        for (action, path) in all {
            switch path {
            case let .verb(verb, op):
                XCTAssertNotNil(ScriptState.handlers[verb], "\(action): no verb “\(verb)”")
                if let op { XCTAssertTrue(ops[verb]?.contains(op) == true, "\(action): “\(verb)” has no op “\(op)” in the schema") }
            case .app:
                break
            case let .tool(tool):
                let reference = try String(contentsOf: Self.repo.appendingPathComponent("skills/lowey/reference/tools.md"), encoding: .utf8)
                XCTAssertTrue(reference.contains("## `\(tool)`"), "\(action): no laptop tool “\(tool)”")
            }
        }
        XCTAssertGreaterThanOrEqual(BridgeCoverage.commands.count, 111, "every menu-bar command")
    }

    func testEveryKindTheAddPageMakesHasAVerb() {
        for kind in ["shape", "light", "particles", "force", "fluid", "overlay", "text3D", "media", "logo", "web", "character", "camera"] {
            XCTAssertNotNil(BridgeCoverage.making[kind], kind)
        }
    }

    func testAppAsksRideBesideTheEditInOrder() throws {
        let script = """
        {"version": 3, "title": "App", "actions": [
          {"do": "add", "shape": "cube", "name": "Box"},
          {"do": "app", "op": "tool", "value": "draw"},
          {"do": "app", "op": "playhead", "value": 2.5},
          {"do": "app", "op": "present", "value": "film"},
          {"do": "app", "op": "export", "value": "usdz"}
        ]}
        """
        let result = try ScriptCompiler.compile(
            LoweyJSON.decode(SceneScript.self, from: Data(script.utf8)),
            document: Document(project: ProjectInfo(id: "p", name: "P"), scene: Scene(id: "s", name: "S")),
            context: ScriptContext(ids: .sequential("run"))
        )
        XCTAssertEqual(result.app.map(\.op), [.tool, .playhead, .present, .export])
        XCTAssertEqual(result.app[1].value?.numberValue, 2.5)
        XCTAssertNotNil(result.command, "the cube is still the edit")
        XCTAssertTrue(result.report.contains("App: export usdz"))
        for bad in [#"{"do": "app", "op": "fly away"}"#, #"{"do": "app", "op": "tool"}"#, #"{"do": "app", "op": "playhead", "value": "soon"}"#] {
            let text = "{\"version\": 3, \"title\": \"Bad\", \"actions\": [\(bad)]}"
            XCTAssertThrowsError(
                try ScriptCompiler.compile(
                    LoweyJSON.decode(SceneScript.self, from: Data(text.utf8)),
                    document: Document(project: ProjectInfo(id: "p", name: "P"), scene: Scene(id: "s", name: "S")),
                    context: ScriptContext(ids: .sequential("run"))
                ),
                bad
            )
        }
    }

    func testDuplicateCopiesBesideTheOriginal() throws {
        var scene = Scene(id: "s", name: "S")
        scene.objects["c"] = SceneObject(id: "c", name: "Chair", kind: .primitive(.cube))
        scene.roots = ["c"]
        let script = #"{"version": 3, "title": "Dup", "actions": [{"do": "duplicate", "target": "Chair", "name": "Chair 2"}]}"#
        let result = try ScriptCompiler.compile(LoweyJSON.decode(SceneScript.self, from: Data(script.utf8)),
                                                document: Document(project: ProjectInfo(id: "p", name: "P"), scene: scene),
                                                context: ScriptContext(ids: .sequential("run")))
        let copy = try XCTUnwrap(result.document.scene.objects.values.first { $0.name == "Chair 2" })
        XCTAssertEqual(copy.transform.position, Vec3(0.5, 0, 0.5))
        XCTAssertEqual(result.created["Chair 2"], copy.id)
    }
}
