import XCTest

/// U3's acceptance on the iPad simulator: a three-frame drawing in the air made without opening the timeline (on the
/// sheet, with the frame strip), and a line of an exact length drawn and typed on our number pad. No Pencil touches
/// the simulator, so a finger draws (Pencil or hand, CONTEXT §4.4).
@MainActor
final class DrawTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier].firstMatch
    }

    private func tap(_ identifier: String, timeout: TimeInterval = 10, file: StaticString = #filePath, line: UInt = #line) {
        let target = element(identifier)
        XCTAssertTrue(target.waitForExistence(timeout: timeout), "\(identifier) is missing", file: file, line: line)
        target.tap()
    }

    private func shot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private var stage: XCUIElement { app.otherElements["stage"] }

    private func point(_ x: Double, _ y: Double) -> XCUICoordinate {
        stage.coordinate(withNormalizedOffset: CGVector(dx: x, dy: y))
    }

    /// A stroke across the middle of the stage, where the sheet stands.
    private func stroke(_ offset: Double) {
        point(0.42 + offset, 0.45).press(forDuration: 0.05, thenDragTo: point(0.55 + offset, 0.55))
    }

    private func newProject() {
        tap("new-project", timeout: 15)
        XCTAssertTrue(stage.waitForExistence(timeout: 15))
    }

    func testAThreeFrameDrawingInTheAirWithoutTheTimeline() {
        newProject()
        tap("Draw")
        tap("tool-flipbook")
        XCTAssertTrue(element("sheet-edge").waitForExistence(timeout: 5), "the sheet is there before the first stroke")
        tap("Draw")
        stroke(0)
        XCTAssertTrue(element("frame-0").waitForExistence(timeout: 5), "the first stroke made the first drawing")
        tap("frame-add")
        stroke(0.04)
        tap("frame-add")
        stroke(0.08)
        XCTAssertTrue(element("frame-2").waitForExistence(timeout: 5), "three drawings on the strip")
        XCTAssertFalse(element("frame-3").exists)
        XCTAssertFalse(element("timeline").exists, "the timeline never opened")
        shot("Three drawings on the sheet")
        // They play round while you draw.
        tap("frame-loop")
        shot("Looping")
        tap("frame-loop")
    }

    func testALineOfAnExactLengthTypedOnTheNumberPad() {
        newProject()
        tap("Draw")
        tap("tool-sketch")
        tap("sketch-line")
        // Two corners on the sheet (on the ground, where a sketch starts), then Done ends the line.
        point(0.4, 0.62).tap()
        point(0.6, 0.6).tap()
        tap("Done")
        tap("dimension-length")
        XCTAssertTrue(element("number-pad-display").waitForExistence(timeout: 5), "our number pad, beside the number")
        XCTAssertFalse(app.keyboards.firstMatch.exists, "never the system keyboard")
        tap("number-pad-2")
        tap("number-pad-5")
        tap("number-pad-done")
        let length = element("dimension-length")
        XCTAssertTrue(length.waitForExistence(timeout: 5))
        XCTAssertEqual(length.label, "25 cm", "the line is as long as typed")
        shot("A line of 25 cm")
    }
}
