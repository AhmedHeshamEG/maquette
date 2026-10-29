import XCTest

/// G1's acceptance on the iPad simulator: each guest in USERS.md finishes their job without leaving the app, timed
/// from the first tap. Sara draws a room and sends it as IFC; Giulia prints a jar with a screw-on lid as 3MF; Dev
/// blocks out a level and takes it to Godot. (Omar's Study left with the set-up in 0.29, CONTEXT §D.24.)
@MainActor
final class GuestTests: XCTestCase {
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
        // XCUITest scrolls a panel's control into view on its own; swiping would turn the stage.
        target.tap()
        return true
    }

    private var stage: XCUIElement { app.otherElements["stage"] }

    private func point(_ x: Double, _ y: Double) -> XCUICoordinate {
        stage.coordinate(withNormalizedOffset: CGVector(dx: x, dy: y))
    }

    private var trail: String { element("debug-trail").label }

    private func waitForTrail(_ text: String, timeout: TimeInterval = 60) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if trail.contains(text) { return true }
            _ = XCTWaiter.wait(for: [XCTestExpectation(description: "trail")], timeout: 0.3)
        }
        return false
    }

    private func shot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// A new project set up for a job.
    private func start(_ setUp: String) {
        XCTAssertTrue(tap("new-project", timeout: 15))
        XCTAssertTrue(stage.waitForExistence(timeout: 15))
        XCTAssertTrue(tap("scene-name"))
        XCTAssertTrue(tap("setup-\(setUp)"))
    }

    /// Model ▸ Add ▸ one of the set-up's tiles.
    private func add(_ identifier: String) {
        XCTAssertTrue(tap("Model"))
        XCTAssertTrue(tap("model-add"))
        XCTAssertTrue(tap(identifier), identifier)
    }

    private func export(kind: String, format: String, preset: String, file: String) {
        XCTAssertTrue(tap("Actions"))
        XCTAssertTrue(tap("open-export"))
        XCTAssertTrue(tap("export-kind-\(kind)"))
        XCTAssertTrue(tap("export-format-\(format)"), format)
        XCTAssertTrue(tap("export-\(preset)"), preset)
        XCTAssertTrue(tap("export-start"))
        XCTAssertTrue(waitForTrail("exported="), "the \(format) was written")
        XCTAssertTrue(trail.contains(file), "\(trail)")
        shot("Exported \(format)")
    }

    func testSarasRoomBecomesAPlanAndAnIFCInUnderThreeMinutes() {
        let clock = Date()
        start("room")
        add("build-walls")
        for (x, y) in [(0.38, 0.42), (0.62, 0.42), (0.62, 0.66), (0.38, 0.66)] {
            point(x, y).tap()
        }
        point(0.38, 0.42).tap()
        XCTAssertTrue(waitForTrail("cmd=Walls"), "the room's walls")
        add("build-label")
        point(0.5, 0.54).tap()
        XCTAssertTrue(waitForTrail("cmd=Label"), "a name on its floor")
        add("room-plans")
        XCTAssertTrue(element("plans-drawing").waitForExistence(timeout: 30), "the plan is drawn")
        XCTAssertTrue(element("plans-rooms").waitForExistence(timeout: 5), "with its room and area")
        shot("Sara's plan")
        app.buttons["Done"].firstMatch.tap()
        export(kind: "model", format: "ifc", preset: "ifcBuilding", file: ".ifc")
        XCTAssertLessThan(Date().timeIntervalSince(clock), 180, "Sara's plan to IFC")
    }

    func testGiuliasThreadedLidGoesToTheSlicerAs3MFInUnderThreeMinutes() {
        let clock = Date()
        start("print")
        add("print-jar")
        XCTAssertTrue(waitForTrail("cmd=Jar & lid"), "the jar and its screw-on lid")
        shot("Giulia's jar and lid")
        export(kind: "model", format: "threeMF", preset: "threeMFPrint", file: ".3mf")
        XCTAssertLessThan(Date().timeIntervalSince(clock), 180, "Giulia's threaded lid to 3MF")
    }

    func testDevsLevelGoesToGodotInUnderThreeMinutes() {
        let clock = Date()
        start("game")
        for piece in ["floor", "ramp", "doorway", "pillar"] {
            add("greybox-\(piece)")
        }
        XCTAssertTrue(waitForTrail("cmd=Pillar"), "four greybox pieces")
        shot("Dev's level")
        export(kind: "model", format: "level", preset: "levelGodot", file: "level.glb")
        XCTAssertLessThan(Date().timeIntervalSince(clock), 180, "Dev's level to Godot")
    }
}
