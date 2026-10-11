import XCTest

/// Responsive on every size (CONTEXT §10.10): in landscape and in portrait, every control of the chrome and of each
/// panel is whole on the screen and none sits on another. The CI job runs it on the 13-inch iPad; the Atlas workflow
/// runs it on the mini and the 11-inch too. The canvas still owns the screen with a thing selected and the timeline
/// open (the object panel is a chip then).
@MainActor
final class ChromeFitTests: XCTestCase {
    private var app: XCUIApplication!

    /// The corner clusters, the scene's name, the sidebar's undo and redo, the bottom row.
    private static let chrome = ["Home", "Actions", "Look", "Select", "Library", "scene-name", "Model", "Draw", "Paint", "Rig", "Animate",
                                 "Undo", "Redo", "timeline-toggle", "views-menu", "Frame the selection", "camera-button"]
    /// The panels each cluster button opens.
    private static let panels = ["Actions", "Look", "Library", "Model", "Draw", "Paint", "Rig", "scene-name"]

    override func setUp() async throws {
        continueAfterFailure = true
        executionTimeAllowance = 900
        app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
    }

    override func tearDown() async throws {
        XCUIDevice.shared.orientation = .landscapeLeft
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier].firstMatch
    }

    private func settle(_ seconds: TimeInterval) {
        _ = XCTWaiter.wait(for: [XCTestExpectation(description: "settle")], timeout: seconds)
    }

    private func newProject() {
        let plus = element("new-project")
        XCTAssertTrue(plus.waitForExistence(timeout: 20))
        plus.tap()
        XCTAssertTrue(app.otherElements["stage"].waitForExistence(timeout: 20))
        settle(1)
    }

    private func attach(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testTheChromeFitsInLandscapeAndPortrait() {
        app.launch()
        newProject()
        for orientation in [UIDeviceOrientation.landscapeLeft, .portrait] {
            XCUIDevice.shared.orientation = orientation
            settle(2)
            let name = orientation == .portrait ? "portrait" : "landscape"
            attach("Chrome, \(name)")
            assertWholeAndApart(Self.chrome, in: name)
            for panel in Self.panels {
                guard element(panel).exists else { continue }
                element(panel).tap()
                settle(1.5)
                assertPanelFits(after: panel, in: name)
                if element(panel).exists, element(panel).isHittable { element(panel).tap() }
                settle(0.5)
            }
        }
    }

    /// The 85 % rule with a thing selected and the whole timeline open: the object panel folds to its chip, and the
    /// chrome over the stage covers no more than 15 % of it.
    func testTheStageStaysTheStageWithASelectionAndTheTimeline() {
        app.launch()
        newProject()
        element("Model").tap()
        settle(1)
        element("model-add").tap()
        element("add-cube").tap()
        XCTAssertTrue(element("inspector").waitForExistence(timeout: 5))
        element("Animate").tap()
        settle(2)
        XCTAssertTrue(element("inspector-chip").waitForExistence(timeout: 5), "the object panel folds to its chip")
        XCTAssertFalse(element("inspector").exists)
        let stage = app.otherElements["stage"].frame
        let covering = ["Home", "Actions", "Look", "Select", "Library", "Model", "Draw", "Paint", "Rig", "Animate", "inspector-chip",
                        "sidebar", "view-controls"].map { element($0) }.filter(\.exists).map { $0.frame.intersection(stage) }
        let covered = covering.filter { !$0.isNull }.reduce(0) { $0 + $1.width * $1.height }
        let share = 1 - covered / max(stage.width * stage.height, 1)
        attach(String(format: "Selection and timeline: the stage keeps %.1f%%", share * 100))
        XCTAssertGreaterThanOrEqual(share, 0.85, "the canvas owns the screen")
    }

    // MARK: Checks

    private func assertWholeAndApart(_ identifiers: [String], in orientation: String) {
        let window = app.windows.firstMatch.frame
        var frames: [(String, CGRect)] = []
        for identifier in identifiers {
            let target = element(identifier)
            guard target.exists else {
                XCTFail("\(identifier) isn't on screen in \(orientation)")
                continue
            }
            let frame = target.frame
            XCTAssertTrue(window.insetBy(dx: -1, dy: -1).contains(frame), "\(identifier) is cut by the screen's edge in \(orientation): \(frame)")
            frames.append((identifier, frame))
        }
        assertApart(frames, in: orientation)
    }

    /// The open panel is whole on the screen, and its labels and buttons don't sit on each other.
    private func assertPanelFits(after button: String, in orientation: String) {
        let window = app.windows.firstMatch.frame
        let controls = app.descendants(matching: .any).matching(NSPredicate(format: "elementType == %d OR elementType == %d",
                                                                                XCUIElement.ElementType.button.rawValue,
                                                                                XCUIElement.ElementType.staticText.rawValue))
        var frames: [(String, CGRect)] = []
        for index in 0 ..< min(controls.count, 120) {
            let control = controls.element(boundBy: index)
            guard control.exists, control.isHittable else { continue }
            let frame = control.frame
            guard frame.width > 2, frame.height > 2 else { continue }
            if window.intersects(frame) {
                XCTAssertTrue(window.insetBy(dx: -1, dy: -1).contains(frame),
                              "\(button) › \(control.label) is cut by the screen's edge in \(orientation)")
            }
            frames.append(("\(button) › \(control.label)", frame))
        }
        assertApart(frames, in: orientation)
    }

    /// No two frames overlap by more than a hair (a label inside its own button is the button's, so equal or nested
    /// frames are one control).
    private func assertApart(_ frames: [(String, CGRect)], in orientation: String) {
        for (index, first) in frames.enumerated() {
            for second in frames[(index + 1)...] {
                let overlap = first.1.intersection(second.1)
                guard !overlap.isNull, overlap.width > 2, overlap.height > 2 else { continue }
                if first.1.contains(second.1) || second.1.contains(first.1) { continue }
                XCTFail("\(first.0) and \(second.0) overlap in \(orientation)")
            }
        }
    }
}
