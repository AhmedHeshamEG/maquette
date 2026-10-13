import XCTest

/// U5's acceptance on the iPad simulator: a three-frame flipbook drawn with flicks, without the timeline; a line of an
/// exact length drawn from the Shapes set and typed on our number pad; strokes that start under the touch with no
/// setup, in the air and over a surface; and a tap picking the stroke under it. No Pencil touches the simulator, so a
/// finger draws (Pencil or hand, CONTEXT §4.4).
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

    private func settle() {
        _ = XCTWaiter.wait(for: [XCTestExpectation(description: "settle")], timeout: 0.6)
    }

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

    /// A quick sideways finger flick across the stage (Dreams' way: right is a new frame): about 200 points in under a
    /// tenth of a second, well inside what reads as a flick (D-290).
    private func flick() {
        point(0.35, 0.75).press(forDuration: 0.01, thenDragTo: point(0.5, 0.75), withVelocity: XCUIGestureVelocity(2500), thenHoldForDuration: 0)
    }

    /// Every "land=" entry of the debug trail: where a touch began and where its stroke's first point landed.
    private func landings() -> [(touch: CGPoint, landed: CGPoint, surface: Bool)] {
        element("debug-trail").label.components(separatedBy: " | ").compactMap { entry in
            guard entry.hasPrefix("land=") else { return nil }
            let parts = entry.dropFirst(5).split(separator: ",")
            guard parts.count == 4, let x = Double(parts[0]) else { return nil }
            let middle = parts[1].split(separator: ">")
            guard middle.count == 2, let y = Double(middle[0]), let landedX = Double(middle[1]), let landedY = Double(parts[2]) else { return nil }
            return (CGPoint(x: x, y: y), CGPoint(x: landedX, y: landedY), parts[3] == "surface")
        }
    }

    func testAThreeFrameFlipbookDrawnWithFlicks() {
        newProject()
        tap("Draw")
        tap("draw-sheets")
        tap("draw-frames")
        // The pop-over goes with a tap on the stage.
        point(0.5, 0.1).tap()
        stroke(0)
        XCTAssertTrue(element("frame-0").waitForExistence(timeout: 5), "the first stroke made the first drawing")
        flick()
        XCTAssertTrue(element("frame-1").waitForExistence(timeout: 5), "a flick right made the next drawing")
        stroke(0.04)
        flick()
        stroke(0.08)
        XCTAssertTrue(element("frame-2").waitForExistence(timeout: 5), "three drawings on the strip")
        XCTAssertFalse(element("frame-3").exists, "a flick draws nothing")
        XCTAssertFalse(element("timeline").exists, "the timeline never opened")
        XCTAssertTrue(element("flipbook-timecode").exists, "the onion skins are on the timecode")
        shot("Three drawings, flicked")
        tap("frame-loop")
        shot("Looping")
        tap("frame-loop")
    }

    func testALineOfAnExactLengthTypedOnTheNumberPad() {
        newProject()
        tap("Draw")
        tap("draw-brush")
        tap("brush-set-shapes")
        tap("draw-kind-line")
        // Two corners on the sheet, then Done ends the line.
        point(0.4, 0.62).tap()
        point(0.6, 0.6).tap()
        tap("draw-done")
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

    /// U5's accuracy test: with no setup, a stroke's first point lands under the touch, in the air (on the sheet) and
    /// over a surface (on it); and a tap picks the stroke under it.
    func testAStrokeStartsUnderTheTouchInTheAirAndOnASurface() {
        newProject()
        tap("Model")
        tap("model-add")
        tap("add-cube")
        XCTAssertTrue(element("inspector").waitForExistence(timeout: 5))
        tap("Draw")
        // In the air, at three places clear of the object panel on the left; then starting on the cube in the middle.
        // At a person's pace: the object panel follows each new selection between strokes.
        for (x, y) in [(0.42, 0.22), (0.7, 0.25), (0.62, 0.78)] {
            settle()
            point(x, y).press(forDuration: 0.05, thenDragTo: point(x + 0.06, y + 0.04))
        }
        settle()
        point(0.5, 0.52).press(forDuration: 0.05, thenDragTo: point(0.53, 0.5))
        let landed = landings()
        XCTAssertEqual(landed.count, 4, "four strokes landed: \(element("debug-trail").label)")
        for landing in landed {
            let off = hypot(landing.touch.x - landing.landed.x, landing.touch.y - landing.landed.y)
            XCTAssertLessThan(off, 3, "the line starts under the touch (\(landing.touch) → \(landing.landed))")
        }
        XCTAssertEqual(landed.filter(\.surface).count, 1, "the stroke begun on the cube lies on it")
        shot("Strokes under the touch")
        // A tap on the first stroke picks it where it is: its chip opens (what the Pencil's lasso and taps rely on).
        point(0.45, 0.24).tap()
        XCTAssertTrue(element("stroke-chip").waitForExistence(timeout: 5), "the stroke under the tap was picked")
        shot("A picked stroke")
    }
}
