import XCTest

/// K1's acceptance on the iPad simulator: a bodyless eye creature and a four-legged dog are made, rigged and lip-synced
/// in under three minutes, the way a person would (Library ▸ Characters ▸ New, a part or two, Say a line). The debug
/// trail says what each step did; the clock runs from the first tap to the dog's line.
@MainActor
final class CharacterTests: XCTestCase {
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
        reveal(target)
        target.tap()
        return true
    }

    /// Scrolls the object panel (not the stage) until the control can be tapped.
    private func reveal(_ target: XCUIElement) {
        let panel = element("inspector")
        for _ in 0 ..< 6 where !target.isHittable && panel.exists {
            panel.swipeUp()
        }
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

    /// The number of joints the last character rigged itself with.
    private var lastRig: Int {
        let entries = trail.components(separatedBy: CharacterSet(charactersIn: " ,;\n")).filter { $0.hasPrefix("rig=") }
        return entries.last.flatMap { Int($0.dropFirst(4)) } ?? 0
    }

    private func shot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func newCharacter(_ start: String) {
        XCTAssertTrue(tap("Library"))
        XCTAssertTrue(tap("library-characters"))
        XCTAssertTrue(tap("new-character-\(start)"), "Characters ▸ New ▸ \(start)")
    }

    /// Opens Say a line in the panel and says one.
    private func say(_ line: String) {
        let field = element("say-line-text")
        if !field.exists { XCTAssertTrue(tap("character-say")) }
        XCTAssertTrue(field.waitForExistence(timeout: 5), "Say a line opens its field")
        reveal(field)
        field.tap()
        field.typeText(line)
        XCTAssertTrue(tap("say-line"))
    }

    func testAnEyeCreatureAndADogAreMadeRiggedAndLipSyncedInUnderThreeMinutes() {
        XCTAssertTrue(tap("new-project", timeout: 15))
        XCTAssertTrue(app.otherElements["stage"].waitForExistence(timeout: 15))
        let clock = Date()

        // A bodyless eye creature: nothing, an eye (one big eye), a mouth.
        newCharacter("nothing")
        XCTAssertTrue(waitForTrail("cmd=New nothing"))
        XCTAssertTrue(tap("add-part-eye"))
        XCTAssertTrue(waitForTrail("cmd=Add eyes"))
        XCTAssertTrue(tap("add-part-mouth"))
        XCTAssertTrue(waitForTrail("cmd=Add mouth"))
        XCTAssertEqual(lastRig, 1, "one joint holds a bodyless creature")
        say("I see you.")
        XCTAssertTrue(waitForTrail("cmd=Say"), "the creature lip-syncs a typed line")
        shot("Eye creature")

        // A four-legged dog: rigged as it lands, then a line.
        tap("fold-inspector")
        newCharacter("fourLegs")
        XCTAssertTrue(waitForTrail("cmd=New four legs"))
        XCTAssertGreaterThan(lastRig, 15, "a dog rigs itself with its legs, neck, head and tail")
        say("Who's a good dog?")
        XCTAssertTrue(waitForTrail("cmd=Say “Who's a good dog?”"))
        shot("Dog")

        let elapsed = Date().timeIntervalSince(clock)
        XCTContext.runActivity(named: "Made, rigged and lip-synced in \(Int(elapsed)) s") { _ in }
        XCTAssertLessThan(elapsed, 180, "K1: under three minutes for both")
    }
}
