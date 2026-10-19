import Foundation
import LoweyCore
@testable import LoweyFeatures
import XCTest

/// D1 in the editor: Clone… from the hold menu, letters from the text's panel, Morph into… and Link by tapping the other
/// thing, a logo from an SVG file, and Close the loop, each one undo step.
@MainActor
final class DesignFlowTests: XCTestCase {
    private var app: AppModel?

    private func makeEditor() throws -> EditorModel {
        let app = AppModel()
        self.app = app
        app.createProject(named: "Design \(UUID().uuidString.prefix(6))", mood: .day, look: LookPreset.ink.id)
        return try XCTUnwrap(app.editor)
    }

    func testCloneFromTheHoldMenuAndUndo() throws {
        let editor = try makeEditor()
        editor.addPrimitive(.cube)
        let cube = try XCTUnwrap(editor.singleSelection?.id)
        let more = try XCTUnwrap(editor.holdMenu(for: [cube]).extras.first { $0.title == "More" })
        XCTAssertTrue(more.children.contains { $0.title == "Clone…" })
        XCTAssertTrue(more.children.contains { $0.title == "Morph into…" })
        editor.cloneSelection()
        XCTAssertEqual(editor.baseScene.objects[cube]?.motionDesign?.clones?.count, 25)
        XCTAssertNotNil(editor.displayed.scene.objects[ClonePlayback.copyID(cube, 24)], "the copies are on the stage")
        editor.addCloneEffect(.push, to: cube)
        XCTAssertEqual(editor.baseScene.objects[cube]?.motionDesign?.clones?.effects.map(\.kind), [.push])
        editor.undo()
        editor.undo()
        XCTAssertNil(editor.baseScene.objects[cube]?.motionDesign)
    }

    func testLettersAndAFontOnText() throws {
        let editor = try makeEditor()
        editor.addText3D("HELLO")
        let text = try XCTUnwrap(editor.singleSelection?.id)
        editor.time = 1
        editor.setLetters(.bounce, for: text)
        XCTAssertEqual(editor.baseScene.objects[text]?.motionDesign?.letters?.preset, .bounce)
        XCTAssertEqual(editor.baseScene.objects[text]?.motionDesign?.letters?.start ?? -1, 1, accuracy: 1e-9, "from the playhead")
        editor.updateLetters(of: text) { $0.order = .middle }
        XCTAssertEqual(editor.baseScene.objects[text]?.motionDesign?.letters?.order, .middle)
        editor.setLetters(nil, for: text)
        XCTAssertNil(editor.baseScene.objects[text]?.motionDesign)
        XCTAssertTrue(editor.projectFonts.isEmpty)
        editor.setFont("fonts/brand.otf", for: text)
        guard case let .text(recipe) = editor.baseScene.objects[text]?.kind else { return XCTFail("still text") }
        XCTAssertEqual(recipe.font, "fonts/brand.otf")
    }

    func testMorphAndLinkWaitForTheTappedThing() throws {
        let editor = try makeEditor()
        editor.addPrimitive(.sphere)
        let ball = try XCTUnwrap(editor.singleSelection?.id)
        editor.addPrimitive(.cube)
        let cube = try XCTUnwrap(editor.singleSelection?.id)
        editor.beginMorph()
        XCTAssertEqual(editor.design.wait, .morph(cube))
        XCTAssertTrue(editor.designTap(picked: ball))
        XCTAssertNil(editor.design.wait)
        XCTAssertEqual(editor.baseScene.objects[cube]?.motionDesign?.morph?.target, ball)
        XCTAssertEqual(editor.baseScene.objects[ball]?.isVisible, false)
        editor.select(cube)
        editor.beginLink(.turnAgainst)
        XCTAssertTrue(editor.designTap(picked: ball))
        XCTAssertEqual(editor.links(of: cube).first?.driver, .thing(id: ball, channel: .turnY))
        XCTAssertEqual(editor.links(of: cube).first?.amount, -1)
        XCTAssertFalse(editor.designTap(picked: ball), "nothing waits now")
        editor.removeMorph(of: cube)
        XCTAssertEqual(editor.baseScene.objects[ball]?.isVisible, true)
    }

    func testCloseTheLoop() throws {
        let editor = try makeEditor()
        editor.addPrimitive(.cube)
        let cube = try XCTUnwrap(editor.singleSelection?.id)
        editor.perform(.batch("Spin", [.setTimeline({
            var timeline = editor.timeline
            timeline.duration = 10
            timeline.behaviors = [Behavior(id: "spin", target: cube, kind: .spin(degreesPerSecond: 90, axis: .y))]
            return timeline
        }())]))
        XCTAssertEqual(editor.loopSeams.map(\.object), [cube])
        editor.closeTheLoop()
        XCTAssertEqual(editor.loopSeams, [])
        editor.undo()
        XCTAssertFalse(editor.loopSeams.isEmpty, "closing is one undo step")
    }

    func testALogoFromAFile() throws {
        let editor = try makeEditor()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Brand-\(UUID().uuidString.prefix(6)).svg")
        try Data("""
        <svg viewBox="0 0 100 40"><rect width="100" height="40" fill="#123456"/><circle cx="20" cy="20" r="10" fill="#ffffff"/>
        <path d="M60 10 L90 30" stroke="black" fill="none"/></svg>
        """.utf8).write(to: url)
        editor.importLogo(url)
        let logo = try XCTUnwrap(editor.singleSelection)
        XCTAssertEqual(logo.kind, .group)
        XCTAssertEqual(logo.children.count, 2)
        XCTAssertEqual(editor.operations.bounds.worldBounds(of: logo.id, in: editor.baseScene)?.size.x ?? 0, 1, accuracy: 1e-6)
        editor.undo()
        XCTAssertNil(editor.baseScene.objects[logo.id])
    }
}
