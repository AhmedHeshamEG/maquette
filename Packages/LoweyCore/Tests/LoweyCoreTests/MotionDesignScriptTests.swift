import Foundation
@testable import LoweyCore
import XCTest

/// The bridge's `design` verb: a logo from SVG text, clones and effects, links to a thing and to a sound, letters, a
/// morph, and the loop check that closes the loop.
final class MotionDesignScriptTests: XCTestCase {
    private func script(_ actions: String, on document: Document) throws -> ScriptResult {
        let json = #"{"version": 3, "title": "Design", "actions": [\#(actions)]}"#
        let script = try LoweyJSON.decode(SceneScript.self, from: Data(json.utf8))
        return try ScriptCompiler.compile(ScriptMigration.upgraded(script), document: document, context: ScriptContext(ids: .sequential("d")))
    }

    private var document: Document {
        var document = MotionDesignTests.document([MotionDesignTests.cube("Gear"), MotionDesignTests.cube("Other", at: Vec3(2, 0, 0))])
        var text = SceneObject(id: "Title", name: "Title", kind: .text(TextRecipe(text: "LOOP")))
        text.transform.position = Vec3(0, 2, 0)
        document.scene.objects[text.id] = text
        document.scene.roots.append(text.id)
        document.scene.timeline.audio = [MotionDesignMoreTests.music()]
        return document
    }

    func testALogoFromSVGText() throws {
        let svg = MotionDesignTests.badge.replacingOccurrences(of: "\"", with: "'").replacingOccurrences(of: "\n", with: " ")
        let result = try script(#"{"do": "design", "op": "logo", "svg": "\#(svg)", "name": "Brand", "width": 2, "at": [0, 0, -3]}"#, on: document)
        let brand = try XCTUnwrap(result.document.scene.objects.values.first { $0.name == "Brand" })
        XCTAssertEqual(brand.kind, .group)
        XCTAssertEqual(brand.children.count, 2)
        XCTAssertEqual(brand.transform.position, Vec3(0, 0, -3))
        XCTAssertTrue(result.report.contains { $0.hasPrefix("2 colour(s)") }, "\(result.report)")
        XCTAssertThrowsError(try script(#"{"do": "design", "op": "logo", "svg": "<html/>"}"#, on: document))
    }

    func testClonesEffectsAndLinks() throws {
        let result = try script("""
        {"do": "design", "op": "clone", "target": "Gear", "layout": "circle", "count": 6, "radius": 3},
        {"do": "design", "op": "effect", "target": "Gear", "kind": "push", "move": [0, 0.5, 0], "field": "ripple", "speed": 2, "every": 2},
        {"do": "design", "op": "link", "target": "Other", "channel": "turnY", "from": "Gear", "fromChannel": "turnY", "amount": -1},
        {"do": "design", "op": "link", "target": "Gear", "channel": "effect", "sound": "Music", "feature": "beat"}
        """, on: document)
        let gear = try XCTUnwrap(result.document.scene.objects["Gear"])
        XCTAssertEqual(gear.motionDesign?.clones?.count, 6)
        XCTAssertEqual(gear.motionDesign?.clones?.effects.first?.kind, .push)
        XCTAssertEqual(gear[.effectStrength], .float(0), "a sound-driven ripple starts from nothing")
        let links = result.document.scene.timeline.links
        XCTAssertEqual(links.map(\.channel), [.turnY, .effect])
        XCTAssertEqual(links.last?.driver, .sound("music", .beat))
        XCTAssertEqual(links.last?.amount, 1)
        let off = try script(#"{"do": "design", "op": "link", "target": "Other", "off": true}"#, on: result.document)
        XCTAssertEqual(off.document.scene.timeline.links.count, 1)
        XCTAssertThrowsError(try script(#"{"do": "design", "op": "effect", "target": "Other", "kind": "push"}"#, on: document),
                             "no clones yet")
        XCTAssertThrowsError(try script(#"{"do": "design", "op": "link", "target": "Gear", "channel": "glow", "sound": "Nope"}"#, on: document))
    }

    func testLettersMorphAndTheLoop() throws {
        let result = try script("""
        {"do": "design", "op": "letters", "target": "Title", "preset": "wave", "length": 1.5},
        {"do": "design", "op": "morph", "target": "Gear", "into": "Other", "at": 1, "duration": 2},
        {"do": "design", "op": "loop", "close": true}
        """, on: document)
        let scene = result.document.scene
        XCTAssertEqual(scene.objects["Title"]?.motionDesign?.letters?.preset, .wave)
        XCTAssertEqual(scene.objects["Gear"]?.motionDesign?.morph?.target, "Other")
        XCTAssertEqual(scene.objects["Other"]?.isVisible, false)
        // The morph keys don't meet over the loop: closing keys it back to where it began.
        XCTAssertTrue(result.report.last?.hasPrefix("loops seamlessly") ?? false, "\(result.report)")
        XCTAssertThrowsError(try script(#"{"do": "design", "op": "letters", "target": "Gear", "preset": "wave"}"#, on: document))
        XCTAssertThrowsError(try script(#"{"do": "design", "op": "spin"}"#, on: document))
    }
}
