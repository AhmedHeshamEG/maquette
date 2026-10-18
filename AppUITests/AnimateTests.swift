import XCTest

/// A1 on the iPad simulator: a cube's way drawn in Animate becomes its motion (the debug trail names the step), the
/// path's chip offers its timing, and Export asks for the kind, then the format, then its presets.
@MainActor
final class AnimateTests: XCTestCase {
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

    @discardableResult
    private func tap(_ identifier: String, timeout: TimeInterval = 8) -> Bool {
        let target = element(identifier)
        guard target.waitForExistence(timeout: timeout) else { return false }
        target.tap()
        return true
    }

    private var stage: XCUIElement { app.otherElements["stage"] }

    private func point(_ x: Double, _ y: Double) -> XCUICoordinate {
        stage.coordinate(withNormalizedOffset: CGVector(dx: x, dy: y))
    }

    private var trail: String { element("debug-trail").label }

    private func waitForTrail(_ text: String, timeout: TimeInterval = 20) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if trail.contains(text) { return true }
            _ = XCTWaiter.wait(for: [XCTestExpectation(description: "trail")], timeout: 0.2)
        }
        return false
    }

    private func shot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testADrawnPathMovesTheCubeAndExportAsksFormatsFirst() {
        XCTAssertTrue(tap("new-project", timeout: 15))
        XCTAssertTrue(stage.waitForExistence(timeout: 15))
        XCTAssertTrue(tap("Model"))
        XCTAssertTrue(tap("model-add"))
        XCTAssertTrue(tap("add-cube"))
        XCTAssertTrue(element("inspector").waitForExistence(timeout: 5))

        // Animate ▸ Path, then the way the cube goes, drawn across the stage at a steady hand.
        XCTAssertTrue(tap("Animate"))
        XCTAssertTrue(tap("animate-path"))
        XCTAssertTrue(element("animate-hint").waitForExistence(timeout: 5))
        point(0.3, 0.62).press(forDuration: 0.05, thenDragTo: point(0.7, 0.58), withVelocity: XCUIGestureVelocity(600), thenHoldForDuration: 0)
        XCTAssertTrue(waitForTrail("cmd=Draw a motion"), "the drawing became the cube's motion")
        XCTAssertTrue(element("path-duration").waitForExistence(timeout: 5), "the chip shows how long it lasts")
        shot("A drawn path")
        XCTAssertTrue(tap("path-even-speed"))
        XCTAssertTrue(waitForTrail("cmd=Even speed"))
        XCTAssertTrue(tap("animate-dope-sheet"))
        shot("The dope sheet")
        XCTAssertTrue(tap("animate-path"), "putting Path down")

        // Export: the kind, the format, the presets.
        XCTAssertTrue(tap("Actions"))
        XCTAssertTrue(tap("open-export"))
        XCTAssertTrue(element("export-hd1080").waitForExistence(timeout: 5), "Video ▸ MP4 ▸ 1080p first")
        XCTAssertTrue(tap("export-format-passes"))
        XCTAssertTrue(element("export-passes1080").waitForExistence(timeout: 3))
        XCTAssertTrue(element("export-final").exists, "Final is an option of what renders")
        XCTAssertTrue(tap("export-kind-model"))
        XCTAssertTrue(tap("export-format-gltf"))
        XCTAssertTrue(element("export-gltfGodot").waitForExistence(timeout: 3), "glTF ▸ for Godot")
        XCTAssertTrue(tap("export-format-lookShader"))
        XCTAssertTrue(element("export-shaderGodot").waitForExistence(timeout: 3))
        XCTAssertTrue(tap("export-kind-paper"))
        XCTAssertTrue(element("export-paperFrameA4").waitForExistence(timeout: 3))
        shot("Export ▸ Paper")
    }
}
