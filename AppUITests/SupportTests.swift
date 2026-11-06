import XCTest

/// O1's in-app support: the thank-you card shows once after the first export, inside the Export sheet, and never again
/// or anywhere else; Settings ▸ About has Support and the credits.
@MainActor
final class SupportTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication()
        // -ui-testing-thanks starts the card fresh; every other UI test never sees it.
        app.launchArguments = ["-ui-testing", "-ui-testing-thanks"]
        app.launch()
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier].firstMatch
    }

    @discardableResult
    private func tap(_ identifier: String, timeout: TimeInterval = 10) -> Bool {
        let target = element(identifier)
        guard target.waitForExistence(timeout: timeout) else { return false }
        target.tap()
        return true
    }

    private func shot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Exports a still and waits for its result.
    private func exportAStill() {
        XCTAssertTrue(tap("export-start"))
        XCTAssertTrue(element("export-results").waitForExistence(timeout: 60), "the still was written")
        let progress = element("export-progress")
        let deadline = Date().addingTimeInterval(30)
        while progress.exists, Date() < deadline {
            _ = XCTWaiter.wait(for: [XCTestExpectation(description: "export")], timeout: 0.3)
        }
    }

    func testTheThankYouCardShowsOnceAndNeverOnTheCanvas() {
        XCTAssertTrue(tap("new-project", timeout: 15))
        let stage = app.otherElements["stage"]
        XCTAssertTrue(stage.waitForExistence(timeout: 15))
        XCTAssertFalse(element("thank-you-card").exists, "nothing before an export")

        XCTAssertTrue(tap("Actions"))
        XCTAssertTrue(tap("actions-share"))
        XCTAssertTrue(tap("open-export"))
        XCTAssertTrue(tap("export-for-picture"))
        XCTAssertTrue(tap("export-formats"))
        XCTAssertTrue(tap("export-format-png"))
        XCTAssertTrue(tap("export-stillHD"))
        exportAStill()
        XCTAssertTrue(element("thank-you-card").waitForExistence(timeout: 5), "after the first export")
        XCTAssertTrue(element("export-results").exists, "inside the Export sheet, beside the results")
        shot("The thank-you card")
        XCTAssertTrue(tap("thanks-close"), "one tap closes it")
        XCTAssertFalse(element("thank-you-card").waitForExistence(timeout: 2))

        exportAStill()
        XCTAssertFalse(element("thank-you-card").waitForExistence(timeout: 3), "never after the second export")

        app.buttons["Done"].firstMatch.tap()
        XCTAssertTrue(stage.waitForExistence(timeout: 5))
        XCTAssertFalse(element("thank-you-card").exists, "never on the canvas")
        shot("The stage after exporting")

        XCTAssertTrue(tap("Actions"))
        XCTAssertTrue(tap("Settings"))
        for _ in 0 ..< 8 where !(element("credits").exists && element("credits").isHittable) {
            app.swipeUp()
        }
        XCTAssertTrue(element("support-maquette").exists, "Settings ▸ About ▸ Support Maquette")
        XCTAssertTrue(tap("credits"))
        XCTAssertTrue(element("credits-list").waitForExistence(timeout: 5), "the credits, from the list in this build")
        shot("Credits")
    }
}
