import Foundation
@testable import LoweyCore
import XCTest

/// The bridge reaches L2: every new Look, the grounds, the Finish and the drawn effects through Scene Script.
final class LookVerbL2Tests: XCTestCase {
    private func run(_ actions: String) throws -> ScriptResult {
        let script = try LoweyJSON.decode(SceneScript.self, from: Data("{\"version\": 3, \"title\": \"T\", \"actions\": [\(actions)]}".utf8))
        return try ScriptCompiler.compile(script, document: DirectorVerbTests.document(), context: ScriptContext(ids: .sequential("l2")))
    }

    func testEveryNewLookByName() throws {
        for preset in LookPreset.builtIns {
            let result = try run(#"{"do": "look", "look": "\#(preset.id)"}"#)
            XCTAssertEqual(result.document.effectiveLook.presetID, preset.id)
        }
        XCTAssertEqual(try run(#"{"do": "look", "look": "lowpoly"}"#).document.effectiveLook.presetID, "lowPoly", "any case")
        XCTAssertThrowsError(try run(#"{"do": "look", "look": "oil"}"#))
    }

    func testGroundsAndTheFinish() throws {
        let result = try run(#"{"do": "look", "ground": "snow", "finish": {"misregistration": true, "boil": 0.4, "benDay": 0.6, "texture": "riso"}}"#)
        let look = result.document.effectiveLook
        XCTAssertEqual(look.ground.surface, .snow)
        XCTAssertEqual(look.ground.color, GroundSurface.snow.color)
        XCTAssertTrue(look.post.misregistration)
        XCTAssertEqual(look.post.boil, 0.4)
        XCTAssertEqual(look.post.benDay, 0.6)
        XCTAssertEqual(look.post.texture, .riso)
        XCTAssertNil(try run(#"{"do": "look", "ground": "plain"}"#).document.effectiveLook.ground.surface)
        XCTAssertThrowsError(try run(#"{"do": "look", "ground": "lava"}"#))
        XCTAssertThrowsError(try run(#"{"do": "look", "finish": {"texture": "velvet"}}"#))
    }

    func testDrawnEffectsAim() throws {
        let result = try run(#"{"do": "effect", "kind": "focusLines", "at": 2, "target": "Door"}, "#
            + #"{"do": "effect", "kind": "kirbyDots", "at": 3, "center": [0.2, 0.7]}"#)
        let effects = result.document.scene.timeline.effects
        XCTAssertEqual(effects.map(\.kind), [.focusLines, .kirbyDots])
        XCTAssertEqual(effects[0].target, "door")
        XCTAssertEqual(effects[1].center, Vec2(0.2, 0.7))
        XCTAssertEqual(try run(#"{"do": "effect", "kind": "impact", "at": 1}"#).document.scene.timeline.effects.first?.duration, 0.25)
    }
}
