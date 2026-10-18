import XCTest

/// The main flows on the iPad simulator, with screenshots of each step (CI uploads them).
final class SmokeTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    private func launch(_ arguments: [String] = []) {
        app.launchArguments = ["-ui-testing"] + arguments
        app.launch()
    }

    private func shot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func tap(_ identifier: String, timeout: TimeInterval = 10, file: StaticString = #filePath, line: UInt = #line) {
        let element = app.descendants(matching: .any)[identifier].firstMatch
        XCTAssertTrue(element.waitForExistence(timeout: timeout), "\(identifier) is missing", file: file, line: line)
        element.tap()
    }

    /// The + on Home goes straight to a blank project in the dark studio, named by itself ("Untitled").
    private func newProject() {
        tap("new-project")
        XCTAssertTrue(app.otherElements["stage"].waitForExistence(timeout: 15))
        shot("New project")
    }

    /// Diagnostics live in Settings ▸ About, below the fold: the form is scrolled until the row is there.
    private func openDiagnostics() {
        tap("Actions")
        tap("Settings")
        let row = app.descendants(matching: .any)["Diagnostics"].firstMatch
        for _ in 0 ..< 8 where !(row.exists && row.isHittable) {
            app.swipeUp()
        }
        tap("Diagnostics")
    }

    func testCreateBuildUndoAndReopen() {
        launch()
        shot("Home")
        newProject()
        shot("Empty stage")
        tap("Model")
        tap("add-cube")
        XCTAssertTrue(app.otherElements["inspector"].waitForExistence(timeout: 5), "the inspector floats in beside the new cube")
        shot("A cube")
        tap("Model")
        tap("add-sphere")
        tap("gizmo-rotate")
        shot("Turn gizmo")
        // Two fingers tap undo, three redo (U5: the buttons are a Settings switch).
        let stage = app.otherElements["stage"]
        stage.twoFingerTap()
        stage.tap(withNumberOfTaps: 1, numberOfTouches: 3)
        tap("Home")
        let card = app.descendants(matching: .any)["project-Untitled"].firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        card.tap()
        XCTAssertTrue(app.otherElements["stage"].waitForExistence(timeout: 15))
        shot("Reopened")
    }

    func testLookCameraDirectorViewAndExportSheet() {
        launch()
        newProject()
        tap("Look")
        tap("look-style")
        tap("look-clay")
        tap("duplicate-look")
        shot("My Look")
        // The camera button: a tap with no camera makes one from this view and looks through it; again, back.
        tap("camera-button")
        shot("Director view")
        tap("camera-button")
        tap("Actions")
        tap("open-export")
        XCTAssertTrue(app.descendants(matching: .any)["export-hd1080"].firstMatch.waitForExistence(timeout: 5))
        shot("Export")
    }

    func testACharacterTheTimelineAndDiagnostics() {
        launch()
        newProject()
        tap("Library")
        tap("library-characters")
        tap("add-me")
        shot("A Blob")
        tap("Animate")
        tap("timeline-mode-keyframe")
        tap("timeline-mode-perform")
        shot("Perform")
        openDiagnostics()
        XCTAssertTrue(app.descendants(matching: .any)["run-benchmark"].firstMatch.waitForExistence(timeout: 5))
        shot("Diagnostics")
    }

    /// The feel recorder: a short run (three seconds here, a minute on the device) with touches on the stage, a dot while
    /// it listens, then the file to share in Diagnostics.
    func testTheFeelRecorder() {
        launch(["-feel-seconds", "3"])
        newProject()
        openDiagnostics()
        tap("record-feel")
        XCTAssertTrue(app.descendants(matching: .any)["feel-recording"].firstMatch.waitForExistence(timeout: 5), "the dot says it's listening")
        let stage = app.otherElements["stage"]
        for step in 0 ..< 4 {
            stage.coordinate(withNormalizedOffset: CGVector(dx: 0.4 + 0.05 * Double(step), dy: 0.5)).tap()
        }
        shot("Recording")
        let dot = app.descendants(matching: .any)["feel-recording"].firstMatch
        XCTAssertTrue(dot.waitForNonExistence(timeout: 20), "it stops by itself")
        openDiagnostics()
        let file = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'feel-'")).firstMatch
        XCTAssertTrue(file.waitForExistence(timeout: 5), "the recording is listed to share")
        shot("Feel recording saved")
    }

    /// Under load nothing is said on the canvas (CONTEXT §6): the preview lightens by itself and the numbers are in
    /// Diagnostics.
    func testNothingAppearsOnTheCanvasUnderLoad() {
        // As an M-series iPad, whatever the simulator is: there is a lighter preview to go to.
        launch(["-load-level", "over", "-device-tier", "A"])
        newProject()
        tap("Model")
        tap("add-cube")
        XCTAssertTrue(app.otherElements["inspector"].waitForExistence(timeout: 5))
        for identifier in ["load-chip", "lighter-preview"] {
            XCTAssertFalse(app.descendants(matching: .any)[identifier].firstMatch.exists, "\(identifier) is on the canvas")
        }
        let messages = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'keeps smooth' OR label CONTAINS[c] 'lighter preview'"))
        XCTAssertEqual(messages.count, 0, "a message about smoothness is on the canvas")
        shot("Under load")
        openDiagnostics()
        XCTAssertTrue(app.descendants(matching: .any)["load-summary-lighter"].firstMatch.waitForExistence(timeout: 5),
                      "the preview lightened by itself")
        shot("Diagnostics under load")
    }

    func testTourRunsToTheEnd() {
        launch(["-ui-testing-tour", "-ui-testing-sample"])
        XCTAssertTrue(app.descendants(matching: .any)["tour"].firstMatch.waitForExistence(timeout: 30))
        for index in 0 ..< 7 {
            shot("Tour \(index + 1)")
            tap("tour-next")
        }
        XCTAssertFalse(app.descendants(matching: .any)["tour"].firstMatch.exists)
    }

    /// Arabic: the chrome mirrors (the making tools move to the left, the document cluster to the right), the labels are
    /// Arabic, and the timeline keeps time running left to right.
    func testArabicIsRightToLeft() {
        launch(["-AppleLanguages", "(ar)", "-AppleLocale", "ar_EG"])
        shot("Theater (ar)")
        newProject()
        let model = app.descendants(matching: .any)["Model"].firstMatch
        let look = app.descendants(matching: .any)["Look"].firstMatch
        XCTAssertTrue(model.waitForExistence(timeout: 10))
        XCTAssertTrue(look.exists)
        XCTAssertLessThan(model.frame.midX, look.frame.midX, "Model (top right in English) sits on the left in Arabic")
        XCTAssertNotEqual(model.label, "Model", "the label is translated")
        tap("Model")
        shot("Model panel (ar)")
    }

    func testItalianLabels() {
        launch(["-AppleLanguages", "(it)", "-AppleLocale", "it_IT"])
        newProject()
        let draw = app.descendants(matching: .any)["Draw"].firstMatch
        XCTAssertTrue(draw.waitForExistence(timeout: 10))
        XCTAssertEqual(draw.label, "Disegna")
        shot("Stage (it)")
    }
}
