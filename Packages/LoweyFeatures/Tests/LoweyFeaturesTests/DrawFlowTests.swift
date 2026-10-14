import Foundation
import LoweyCore
@testable import LoweyFeatures
import XCTest

/// U5's one Draw: the bar's verbs and the brush decide the Pencil's tool, a moved sheet carries its drawing in one
/// step, the quick menu starts with the lasso, the empty stage's menu holds the lasso and Select all, and the
/// eyedropper puts what it read in the hand.
@MainActor
final class DrawFlowTests: XCTestCase {
    private var app: AppModel?

    private func makeEditor() throws -> EditorModel {
        let app = AppModel()
        self.app = app
        app.createProject(named: "Draw \(UUID().uuidString.prefix(6))", mood: .day, look: LookPreset.ink.id)
        return try XCTUnwrap(app.editor)
    }

    func testDrawIsOneToolAndItsBrushDecidesWhatThePencilMakes() throws {
        let editor = try makeEditor()
        editor.openPanel = .look
        editor.toggleDraw()
        XCTAssertEqual(editor.tool, .ink, "lines first")
        XCTAssertNil(editor.openPanel, "Draw opens no panel")
        XCTAssertTrue(editor.isDrawing)
        editor.chooseDrawBrush(.solid(.lathe))
        XCTAssertEqual(editor.tool, .draw)
        XCTAssertEqual(editor.draw.style, .lathe)
        editor.chooseDrawBrush(.shape(.rectangle))
        XCTAssertTrue(editor.isSketching, "a shape is drawn by the sketch")
        XCTAssertTrue(editor.isDrawing)
        editor.chooseDrawBrush(.shadow(pushes: false))
        XCTAssertEqual(editor.tool, .shadowBrush)
        XCTAssertFalse(editor.shadowBrush.pushesShadow)
        editor.chooseDrawBrush(.paint)
        XCTAssertEqual(editor.tool, .paint)
        XCTAssertEqual(editor.colourPaint.mode, .paint)
        editor.chooseDrawVerb(.erase)
        XCTAssertEqual(editor.colourPaint.mode, .erase, "a paint brush erases paint")
        XCTAssertEqual(editor.drawVerbInUse, .erase)
        editor.chooseDrawBrush(.lines)
        editor.chooseDrawVerb(.smudge)
        XCTAssertEqual(editor.tool, .ink)
        XCTAssertEqual(editor.ink.mode, .reshape, "Smudge pushes lines")
        XCTAssertEqual(editor.drawVerbInUse, .smudge)
        editor.chooseDrawVerb(.brush)
        editor.setDrawFrames(true)
        XCTAssertEqual(editor.tool, .flipbook, "frames on the sheet are the flipbook")
        editor.toggleEraser()
        XCTAssertEqual(editor.flipbook.mode, .erase, "the eraser follows what is drawn")
        editor.toggleEraser()
        XCTAssertEqual(editor.flipbook.mode, .draw, "and back to the brush")
        editor.toggleDraw()
        XCTAssertEqual(editor.tool, .select, "Draw again puts it down")
        XCTAssertFalse(editor.isDrawing)
    }

    func testMovingAKeptSheetMovesWhatIsDrawnOnItInOneStep() throws {
        let editor = try makeEditor()
        editor.toggleDraw()
        let sheet = DrawingSheet.facing(eye: Vec3(0, 1, 6), at: Vec3(0, 1, 0), id: "sheet-a", name: "Sheet 1", size: 2)
        editor.drawingSheet = sheet
        editor.commitInkStroke(points: (0 ... 10).map { Vec3(Double($0) * 0.05, 1, 0) }, pressures: Array(repeating: 1, count: 11))
        let drawing = try XCTUnwrap(editor.activeInk)
        XCTAssertEqual(drawing[.drawnOn]?.stringValue, "sheet-a", "a drawing remembers its sheet")
        XCTAssertNotNil(editor.baseScene.sheet("sheet-a"), "the first stroke kept the sheet")
        let before = editor.baseScene.worldTransform(of: drawing.id).position
        editor.pushSheet(by: 0.5, gesture: "push")
        editor.endGesture()
        let after = editor.baseScene.worldTransform(of: drawing.id).position
        let normal = sheet.rotation.act(.unitZ)
        XCTAssertEqual((after - (before + normal * 0.5)).length, 0, accuracy: 1e-6, "the drawing came with it")
        editor.undo()
        XCTAssertEqual((editor.baseScene.worldTransform(of: drawing.id).position - before).length, 0, accuracy: 1e-6, "one undo step")
        XCTAssertEqual(editor.baseScene.sheet("sheet-a")?.origin, sheet.origin)
    }

    func testTheLassoLivesInTheQuickMenuTheEditBarAndTheEmptyStagesMenu() throws {
        let editor = try makeEditor()
        XCTAssertEqual(QuickAction.standard, [.lasso, .eyedropper, .eraser, .snap, .hideSheet, .frame])
        XCTAssertEqual(editor.quickMenuItems.first?.id, "lasso")
        editor.run(.lasso)
        XCTAssertEqual(editor.tool, .lasso)
        editor.toggleDraw()
        editor.run(.lasso)
        XCTAssertEqual(editor.tool, .ink, "while drawing the lasso picks strokes")
        XCTAssertEqual(editor.ink.mode, .select)
        editor.run(.hideSheet)
        XCTAssertTrue(editor.sheetHidden)
        XCTAssertTrue(editor.editBarItems.contains { $0.title == "Lasso" })
        XCTAssertTrue(editor.editBarItems.contains { $0.title == "Select all" })
        let menu = editor.emptyStageMenu()
        XCTAssertEqual(menu.extras.map(\.title), ["Lasso", "Select all"])
        editor.tool = .rig
        XCTAssertEqual(editor.quickMenuItems.map(\.id), RigQuickAction.allCases.map(\.rawValue), "Rig has its own six")
    }

    /// U5 step 6: a flick is quick, short and sideways; a stroke or a turn of the view is anything else.
    func testAFlickIsQuickShortAndSideways() {
        XCTAssertEqual(Flick.read(dx: 140, dy: 12, duration: 0.12), .right)
        XCTAssertEqual(Flick.read(dx: -90, dy: -20, duration: 0.1), .left)
        XCTAssertNil(Flick.read(dx: 140, dy: 12, duration: 0.6), "too slow: a stroke")
        XCTAssertNil(Flick.read(dx: 30, dy: 0, duration: 0.03), "too short")
        XCTAssertNil(Flick.read(dx: 100, dy: 90, duration: 0.1), "too steep")
        XCTAssertNil(Flick.read(dx: 100, dy: 0, duration: 0), "no time")
    }

    /// D-288: a closed shape is picked as it lands, and stays picked when its size is typed, so its pull number is there.
    func testAClosedShapeIsPickedAsItLandsAndStaysPickedWhenResized() throws {
        let editor = try makeEditor()
        editor.toggleDraw()
        editor.chooseDrawBrush(.shape(.rectangle))
        XCTAssertTrue(editor.isSketching)
        editor.modeling.pending = PendingSketch(plane: EditorModel.groundPlane, target: nil, sketch: nil, points: [])
        editor.addPoint(Vec2(0, 0), kind: .rectangle)
        editor.addPoint(Vec2(0.3, 0.2), kind: .rectangle)
        let region = try XCTUnwrap(editor.modeling.region, "picked as it lands")
        XCTAssertNotNil(editor.pullAxis, "with its arrow")
        editor.setDimension(.rectangleSide(horizontal: true), to: 0.4)
        editor.setDimension(.rectangleSide(horizontal: false), to: 0.2)
        XCTAssertEqual(editor.modeling.region?.sketch, region.sketch, "still picked at its new size")
        XCTAssertNotNil(editor.pullAxis)
    }

    func testTheEyedropperPutsWhatItReadInTheHand() throws {
        let editor = try makeEditor()
        editor.eyedropperLoupe = EyedropperLoupe(point: .zero, colour: RGBA(0.2, 0.4, 0.6))
        editor.eyedropping = true
        editor.finishEyedrop()
        XCTAssertEqual(editor.currentColor, .rgba(RGBA(0.2, 0.4, 0.6)))
        XCTAssertNil(editor.eyedropperLoupe)
        XCTAssertFalse(editor.eyedropping)
        editor.eyedropperLoupe = EyedropperLoupe(point: .zero, colour: RGBA(1, 0, 0))
        editor.finishEyedrop(commit: false)
        XCTAssertEqual(editor.currentColor, .rgba(RGBA(0.2, 0.4, 0.6)), "a cancelled hold changes nothing")
    }
}
