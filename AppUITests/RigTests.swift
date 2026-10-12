import XCTest

/// U4's acceptance on the iPad simulator, timed as a person would do it (taps and strokes; checks come after). With
/// no Pencil a finger does the Pencil's jobs, so the strokes here place the pins and dots. Under 10 s for a tail and 30 s
/// for a person is the claim for a person on an iPad (the device checklist); CI's shared simulator spends seconds of
/// its own on each tap, so a run fails only past half as much again (D-175).
@MainActor
final class RigTests: XCTestCase {
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
    private func tap(_ identifier: String, timeout: TimeInterval = 5) -> Bool {
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

    private var stage: XCUIElement { app.otherElements["stage"] }

    private func point(_ x: Double, _ y: Double) -> XCUICoordinate {
        stage.coordinate(withNormalizedOffset: CGVector(dx: x, dy: y))
    }

    /// A point on the screen as a coordinate (the stage's top-left plus the offset).
    private func at(_ point: CGPoint) -> XCUICoordinate {
        stage.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: point.x - stage.frame.minX, dy: point.y - stage.frame.minY))
    }

    private var trail: String { element("debug-trail").label }

    /// Waits until the trail shows a command (weights land in the background).
    private func waitForTrail(_ text: String, timeout: TimeInterval = 40) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if trail.contains(text) { return true }
            _ = XCTWaiter.wait(for: [XCTestExpectation(description: "trail")], timeout: 0.2)
        }
        return false
    }

    private func newProject() {
        XCTAssertTrue(tap("new-project", timeout: 15))
        XCTAssertTrue(stage.waitForExistence(timeout: 15))
    }

    func testATailIsPinnedAndPosedInUnderTenSeconds() {
        newProject()
        tap("Model")
        tap("model-add")
        tap("add-cylinder")
        XCTAssertTrue(element("inspector").waitForExistence(timeout: 5))
        // Frame it: the cylinder stands in the middle of the stage.
        point(0.5, 0.5).doubleTap()
        _ = XCTWaiter.wait(for: [XCTestExpectation(description: "camera settles")], timeout: 0.8)

        let start = Date()
        tap("Rig")
        tap("rig-body-chain")
        // One stroke up its middle lays pins from its base to its top.
        point(0.5, 0.62).press(forDuration: 0.05, thenDragTo: point(0.5, 0.4))
        XCTAssertTrue(waitForTrail("cmd=Rig a chain"), "the chain was stored: \(trail)")
        let marks = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'rig-mark-'")).allElementsBoundByIndex
        XCTAssertGreaterThanOrEqual(marks.count, 2, "pins at its base and its tip")
        let tip = marks.map(\.frame).min { $0.midY < $1.midY } ?? .zero
        tap("rig-done")
        // Pull the tip to the side: the stretch bends, the base holds.
        at(CGPoint(x: tip.midX, y: tip.midY)).press(forDuration: 0.1, thenDragTo: at(CGPoint(x: tip.midX + 120, y: tip.midY + 30)))
        let elapsed = Date().timeIntervalSince(start)
        shot("A tail pinned and posed")
        XCTAssertTrue(waitForTrail("cmd=Change", timeout: 5), "the pull turned its joints: \(trail)")
        let report = XCTAttachment(string: String(format: "Pinned and posed in %.1f s", elapsed))
        report.lifetime = .keepAlways
        add(report)
        XCTAssertLessThan(elapsed, 15)
    }

    func testAPersonIsRiggedAndPosedInUnderThirtySeconds() {
        newProject()
        tap("Library")
        let search = element("library-search")
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("astronaut")
        XCTAssertTrue(tap("library-item-Astronaut a", timeout: 10), "the Kit's astronaut")
        // The object panel stays a chip while the Library is open; the selection says it landed.
        XCTAssertTrue(waitForTrail("sel=[Astronaut", timeout: 15), "the astronaut is placed: \(trail)")

        let start = Date()
        tap("Rig")
        tap("rig-body-person")
        // The guess places every dot; the wrists are where its hands will be grabbed.
        let wrist = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "a wrist")).firstMatch
        XCTAssertTrue(wrist.waitForExistence(timeout: 10), "the dots are on its front view")
        _ = XCTWaiter.wait(for: [XCTestExpectation(description: "the guess lands")], timeout: 1.5)
        let hand = wrist.frame
        shot("A person's dots, guessed")
        tap("rig-person-done")
        XCTAssertTrue(waitForTrail("as a person"), "the person rig was stored: \(trail)")
        // Raise a hand: the arm follows.
        at(CGPoint(x: hand.midX, y: hand.midY)).press(forDuration: 0.1, thenDragTo: at(CGPoint(x: hand.midX + 40, y: hand.midY - 140)))
        let elapsed = Date().timeIntervalSince(start)
        shot("A person rigged and posed")
        XCTAssertTrue(waitForTrail("cmd=Change", timeout: 5), "the pull turned its arm: \(trail)")
        let report = XCTAttachment(string: String(format: "Rigged as a person and posed in %.1f s", elapsed))
        report.lifetime = .keepAlways
        add(report)
        XCTAssertLessThan(elapsed, 45)
    }
}
