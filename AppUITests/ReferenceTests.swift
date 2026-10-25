import XCTest

/// Q1's acceptance on the iPad simulator: the Reference window opens, moves, resizes, switches its three modes, zooms a
/// picture, closes, comes back where and as big as it was, and is there again after a relaunch. A sheet laid on a
/// cube's face fits that face.
@MainActor
final class ReferenceTests: XCTestCase {
    private var app: XCUIApplication!
    private let folder = "Reference-\(UUID().uuidString)"

    override func setUp() async throws {
        continueAfterFailure = false
        executionTimeAllowance = 600
        app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-testing-folder", folder, "-ui-testing-restore", "-ui-testing-picture"]
        app.launch()
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier].firstMatch
    }

    @discardableResult
    private func tap(_ identifier: String, timeout: TimeInterval = 8) -> Bool {
        let target = element(identifier)
        guard target.waitForExistence(timeout: timeout) else { return false }
        target.tap()
        return true
    }

    private var stage: XCUIElement { app.otherElements["stage"] }
    private var window: XCUIElement { element("reference-window") }
    private var trail: String { element("debug-trail").label }

    private func waitForTrail(_ entry: String, timeout: TimeInterval = 5) -> Bool {
        let end = Date().addingTimeInterval(timeout)
        while Date() < end {
            if trail.contains(entry) { return true }
            _ = XCTWaiter.wait(for: [XCTestExpectation(description: "trail")], timeout: 0.2)
        }
        return false
    }

    private func settle(_ seconds: TimeInterval) {
        _ = XCTWaiter.wait(for: [XCTestExpectation(description: "settle")], timeout: seconds)
    }

    private func mode(_ title: String) {
        let control = app.segmentedControls["reference-mode"].firstMatch
        XCTAssertTrue(control.waitForExistence(timeout: 5), "the modes are on the bar")
        control.buttons[title].tap()
    }

    private func drag(_ identifier: String, by offset: CGVector) {
        let handle = element(identifier)
        XCTAssertTrue(handle.waitForExistence(timeout: 5), "\(identifier) is missing")
        let start = handle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(offset), withVelocity: XCUIGestureVelocity(400), thenHoldForDuration: 0.2)
        settle(0.8)
    }

    private func shot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func assertSameFrame(_ frame: CGRect, _ expected: CGRect, _ message: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(frame.minX, expected.minX, accuracy: 2, message, file: file, line: line)
        XCTAssertEqual(frame.minY, expected.minY, accuracy: 2, message, file: file, line: line)
        XCTAssertEqual(frame.width, expected.width, accuracy: 2, message, file: file, line: line)
        XCTAssertEqual(frame.height, expected.height, accuracy: 2, message, file: file, line: line)
    }

    func testTheReferenceWindowMovesSizesSwitchesAndComesBack() {
        XCTAssertTrue(tap("new-project", timeout: 15))
        XCTAssertTrue(stage.waitForExistence(timeout: 15))
        XCTAssertTrue(tap("Actions"))
        XCTAssertTrue(tap("open-reference"))
        XCTAssertTrue(window.waitForExistence(timeout: 5), "the window floats over the stage")
        XCTAssertTrue(element("reference-canvas").waitForExistence(timeout: 5), "it opens on the whole scene")
        shot("Reference: Canvas")

        // Moved by its bar: it follows, glides and settles inside the stage.
        let opened = window.frame
        drag("reference-grab", by: CGVector(dx: -320, dy: 220))
        let moved = window.frame
        XCTAssertLessThan(moved.minX, opened.minX - 150, "it moved left")
        XCTAssertGreaterThan(moved.minY, opened.minY + 100, "and down")
        XCTAssertTrue(app.windows.firstMatch.frame.contains(moved), "inside the screen")

        // Sized from its corner, from its top-left.
        drag("reference-resize", by: CGVector(dx: 120, dy: 90))
        let sized = window.frame
        XCTAssertEqual(sized.width, moved.width + 120, accuracy: 24, "wider by the drag")
        XCTAssertEqual(sized.minX, moved.minX, accuracy: 2, "its top-left stays")

        // Image: the picture on the clipboard, then zoomed with two fingers.
        mode("Image")
        XCTAssertTrue(element("reference-image").waitForExistence(timeout: 5))
        XCTAssertTrue(tap("reference-paste"))
        XCTAssertTrue(waitForTrail("reference=image"), "the picture is in the window")
        element("reference-image").pinch(withScale: 2.5, velocity: 2)
        XCTAssertTrue(waitForTrail("reference=zoom"), "two fingers zoom it inside the window")
        shot("Reference: Image, zoomed")

        // Face: the front camera (a simulator has none, and says so).
        mode("Face")
        XCTAssertTrue(element("reference-face").waitForExistence(timeout: 5))
        shot("Reference: Face")

        // Closed and opened again: where and as big as it was.
        let before = window.frame
        XCTAssertTrue(tap("reference-close"))
        XCTAssertFalse(window.waitForExistence(timeout: 1.5), "closed")
        XCTAssertTrue(tap("Actions"))
        XCTAssertTrue(tap("open-reference"))
        XCTAssertTrue(window.waitForExistence(timeout: 5))
        assertSameFrame(window.frame, before, "back where and as big as it was")
        XCTAssertTrue(element("reference-face").exists, "on the mode it was left on")

        // Relaunched: the project opens again and so does the window.
        settle(1.5)
        XCUIDevice.shared.press(.home)
        settle(2)
        app.terminate()
        app.launch()
        XCTAssertTrue(stage.waitForExistence(timeout: 30), "the project opens again")
        XCTAssertTrue(window.waitForExistence(timeout: 10), "and its Reference window")
        assertSameFrame(window.frame, before, "in the same place and size after a relaunch")
    }

    func testASheetLaidOnACubeFitsTheFace() {
        XCTAssertTrue(tap("new-project", timeout: 15))
        XCTAssertTrue(stage.waitForExistence(timeout: 15))
        XCTAssertTrue(tap("Model"))
        XCTAssertTrue(tap("model-add"))
        XCTAssertTrue(tap("add-cube"))
        XCTAssertTrue(element("inspector").waitForExistence(timeout: 5))
        XCTAssertTrue(tap("Model"), "the panel closes")
        XCTAssertTrue(tap("Draw"))
        // Draw's pop-over goes with a tap on the stage, away from the cube.
        settle(0.8)
        stage.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1)).tap()
        settle(0.8)
        // A finger's tap on the cube lays the sheet on the face under it, fitted to it.
        stage.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(waitForTrail("sheet=fitted face"), "the sheet lies on the cube's face, fitted (trail: \(trail))")
        XCTAssertTrue(element("sheet-chip").waitForExistence(timeout: 5), "its chip makes it exact")
        XCTAssertTrue(element("sheet-offset").exists)
        XCTAssertTrue(element("sheet-turn").exists)
        XCTAssertTrue(element("sheet-size").exists)
        shot("A sheet on a cube's face")
        XCTAssertTrue(tap("sheet-chip-done"))
        XCTAssertFalse(element("sheet-chip").waitForExistence(timeout: 1.5))
    }
}
