import XCTest

/// U8's acceptance on the iPad simulator: a left-handed, re-ordered layout survives a relaunch, and Reset layout brings
/// back the layout as it comes. Then Present hides everything, and a note goes on a thing and is answered in place.
@MainActor
final class YoursTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        continueAfterFailure = false
        executionTimeAllowance = 600
        app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
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

    private func shot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func newProject() {
        XCTAssertTrue(tap("new-project", timeout: 15))
        XCTAssertTrue(stage.waitForExistence(timeout: 15))
    }

    /// The middle of a control on screen, across the window.
    private func middle(_ identifier: String) -> CGFloat {
        let target = element(identifier)
        XCTAssertTrue(target.waitForExistence(timeout: 8), identifier)
        return target.frame.midX / max(app.frame.width, 1)
    }

    /// Settings ▸ Your layout, from Home or from the project's Actions.
    private func openYourLayout(fromHome: Bool) {
        if fromHome {
            XCTAssertTrue(tap("Settings", timeout: 15))
        } else {
            XCTAssertTrue(tap("Actions"))
            XCTAssertTrue(tap("Settings"))
        }
        XCTAssertTrue(tap("settings-layout"))
    }

    private func closeSettings() {
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 5))
        app.buttons["Done"].tap()
    }

    private func assertLeftHanded(_ moment: String) {
        XCTAssertGreaterThan(middle("Home"), 0.5, "\(moment): the document's corner is on the right")
        XCTAssertLessThan(middle("Model"), 0.5, "\(moment): the making corner is on the left")
        XCTAssertGreaterThan(middle("sidebar"), 0.5, "\(moment): the sidebar is on the right edge")
        XCTAssertLessThan(middle("Library"), middle("Look"), "\(moment): Library moved before Look")
    }

    func testAMirroredReorderedLayoutSurvivesARelaunchAndResets() throws {
        openYourLayout(fromHome: true)
        XCTAssertTrue(app.buttons["Left hand"].waitForExistence(timeout: 5))
        app.buttons["Left hand"].tap()
        XCTAssertTrue(tap("layout-menu-library"))
        XCTAssertTrue(app.buttons["Move left"].waitForExistence(timeout: 5))
        app.buttons["Move left"].tap()
        shot("Your layout")
        closeSettings()
        newProject()
        assertLeftHanded("set")
        shot("Left-handed")

        app.terminate()
        app.launchArguments = ["-ui-testing", "-keep-layout"]
        app.launch()
        newProject()
        assertLeftHanded("after a relaunch")

        openYourLayout(fromHome: false)
        XCTAssertTrue(tap("layout-reset"))
        XCTAssertTrue(app.buttons["layout-reset-confirm"].waitForExistence(timeout: 5) || app.buttons["Reset layout"].exists)
        if app.buttons["layout-reset-confirm"].exists { app.buttons["layout-reset-confirm"].tap() } else { app.buttons["Reset layout"].tap() }
        closeSettings()
        XCTAssertLessThan(middle("Home"), 0.5, "reset: the document's corner is back on the left")
        XCTAssertGreaterThan(middle("Model"), 0.5, "reset: the making corner is back on the right")
        XCTAssertLessThan(middle("Look"), middle("Library"), "reset: Look is before Library again")
        shot("Reset")
    }

    func testPresentHidesEverythingAndANoteIsAnsweredInPlace() throws {
        newProject()
        XCTAssertTrue(tap("Model"))
        XCTAssertTrue(tap("model-add"))
        XCTAssertTrue(tap("add-cube"))
        // Present: nothing but the stage, a tap brings Done back.
        XCTAssertTrue(tap("Actions"))
        XCTAssertTrue(tap("present"))
        XCTAssertTrue(element("present").waitForExistence(timeout: 8))
        XCTAssertFalse(element("Actions").exists, "the chrome is gone while presenting")
        shot("Presenting")
        if !element("present-done").exists { stage.tap() }
        XCTAssertTrue(tap("present-done"))
        XCTAssertTrue(element("Actions").waitForExistence(timeout: 8), "the chrome is back")
        // A note on the cube, then an answer in its thread.
        XCTAssertTrue(tap("Actions"))
        XCTAssertTrue(tap("add-note"))
        stage.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let text = element("note-text")
        XCTAssertTrue(text.waitForExistence(timeout: 8))
        text.tap()
        text.typeText("Taller, please")
        XCTAssertTrue(tap("note-add"))
        XCTAssertTrue(element("note-pin-1").waitForExistence(timeout: 8))
        let reply = element("note-reply")
        XCTAssertTrue(reply.waitForExistence(timeout: 8), "the new note's thread is open")
        reply.tap()
        reply.typeText("Done\n")
        XCTAssertTrue(app.staticTexts["Done"].waitForExistence(timeout: 8), "the answer is in the thread")
        XCTAssertTrue(tap("note-resolve"))
        shot("A note answered")
    }
}
