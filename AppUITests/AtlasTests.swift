import XCTest

/// The atlas: a picture of every screen, panel and page, in landscape or portrait (`ATLAS_ORIENTATION`), to review the
/// layout as a whole.
/// It asserts nothing: a control that can't be reached is listed in the "Missing" attachment. It runs only with
/// `ATLAS=1` (the Atlas workflow), never in the smoke run.
@MainActor
final class AtlasTests: XCTestCase {
    private enum Side: CGFloat {
        case leading = 0.14
        case centre = 0.5
        case trailing = 0.86
    }

    private enum Start {
        case home, blank, cube, blob, sample
    }

    private struct Page {
        let name: String
        let steps: [String]
        var scrolls = 0
        var side = Side.trailing
    }

    private var app: XCUIApplication!
    private var area = ""
    private var count = 0
    private var missing: [String] = []

    override func setUp() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["ATLAS"] == "1", "the atlas runs in its own workflow")
        continueAfterFailure = true
        executionTimeAllowance = 1200
        XCUIDevice.shared.orientation = ProcessInfo.processInfo.environment["ATLAS_ORIENTATION"] == "portrait" ? .portrait : .landscapeLeft
        app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-testing-sample", "-ui-testing-screenshots"]
    }

    override func tearDown() async throws {
        guard !missing.isEmpty else { return }
        let attachment = XCTAttachment(string: missing.joined(separator: "\n"))
        attachment.name = "Atlas \(area) Missing"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    // MARK: Moving around

    private func settle(_ seconds: TimeInterval) {
        _ = XCTWaiter.wait(for: [XCTestExpectation(description: "settle")], timeout: seconds)
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier].firstMatch
    }

    @discardableResult
    private func tap(_ identifier: String, timeout: TimeInterval = 8) -> Bool {
        let target = element(identifier)
        guard target.waitForExistence(timeout: timeout) else {
            missing.append(identifier)
            return false
        }
        target.tap()
        return true
    }

    private func shot(_ name: String) {
        count += 1
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = String(format: "Atlas %@ %02d %@", area, count, name)
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func scroll(_ side: Side) {
        let window = app.windows.firstMatch
        let from = window.coordinate(withNormalizedOffset: CGVector(dx: side.rawValue, dy: 0.72))
        from.press(forDuration: 0.05, thenDragTo: window.coordinate(withNormalizedOffset: CGVector(dx: side.rawValue, dy: 0.28)))
    }

    /// A new launch, so whatever the last page left open can't leak into the next picture.
    private func fresh(_ start: Start) {
        app.terminate()
        app.launch()
        switch start {
        case .home:
            _ = element("new-project").waitForExistence(timeout: 30)
        case .sample:
            tap("project-Enigma — the story", timeout: 60)
            _ = app.otherElements["stage"].waitForExistence(timeout: 30)
            settle(4)
        case .blank, .cube, .blob:
            newProject()
            if start == .cube { addCube() }
            if start == .blob { addBlob() }
        }
    }

    private func newProject() {
        tap("new-project", timeout: 30)
        _ = app.otherElements["stage"].waitForExistence(timeout: 15)
    }

    private func addCube() {
        tap("Model")
        tap("model-add")
        tap("add-cube")
        _ = element("inspector").waitForExistence(timeout: 5)
    }

    private func addBlob() {
        tap("Library")
        tap("add-me")
    }

    private func open(_ page: Page) {
        for step in page.steps {
            tap(step)
            settle(1)
        }
        settle(page.steps.first == "Look" ? 3 : 1.5)
        shot(page.name)
        for index in 0 ..< page.scrolls {
            scroll(page.side)
            settle(1)
            shot("\(page.name), further \(index + 1)")
        }
    }

    /// Panels that close when their button is tapped again: one launch for all of them.
    private func walk(_ pages: [Page], from start: Start) {
        fresh(start)
        for page in pages {
            open(page)
            guard let first = page.steps.first else { continue }
            // Tapping the home again closes its panel (or puts Draw down).
            tap(first)
        }
    }

    /// Pages that open something of their own (a sheet, a menu, a library): a launch each.
    private func each(_ pages: [Page], from start: Start) {
        for page in pages {
            fresh(start)
            open(page)
        }
    }

    // MARK: The pictures

    func test01Home() {
        area = "1 Home"
        fresh(.home)
        shot("Home")
        each([
            Page(name: "Samples", steps: ["samples"]),
            Page(name: "Sort", steps: ["gallery-sort"]),
            Page(name: "Select several", steps: ["gallery-select"]),
            Page(name: "Home menu", steps: ["theater-menu"]),
            Page(name: "Settings", steps: ["Settings"], scrolls: 3, side: .centre),
            Page(name: "Search", steps: ["gallery-search"])
        ], from: .home)
    }

    func test02Panels() {
        area = "2 Panels"
        fresh(.blank)
        shot("Empty stage")
        walk([
            Page(name: "Actions", steps: ["Actions"], scrolls: 1, side: .leading),
            Page(name: "Look, Style", steps: ["Look", "look-style"], scrolls: 1, side: .leading),
            Page(name: "Look, World", steps: ["Look", "look-world"], scrolls: 1, side: .leading),
            Page(name: "Look, Finish", steps: ["Look", "look-finish"], scrolls: 1, side: .leading),
            Page(name: "Library, Things", steps: ["Library", "library-things"], scrolls: 2, side: .leading),
            Page(name: "Library, Yours", steps: ["Library", "library-yours"], side: .leading),
            Page(name: "The scene", steps: ["scene-name"], scrolls: 1, side: .leading),
            Page(name: "Model, Add", steps: ["Model", "model-add"], scrolls: 2),
            Page(name: "Model, Edit", steps: ["Model", "model-shape"], scrolls: 2),
            Page(name: "Model, Precision", steps: ["Model", "model-precision"], scrolls: 2),
            Page(name: "Draw", steps: ["Draw"]),
            Page(name: "Rig, nothing selected", steps: ["Rig"])
        ], from: .blank)
    }

    func test03Deeper() {
        area = "3 Deeper"
        each([
            Page(name: "Brush library, dropped down", steps: ["Draw", "draw-brush"]),
            Page(name: "Brush library, Solids", steps: ["Draw", "draw-brush", "brush-set-solids"]),
            Page(name: "Brush library, Shapes", steps: ["Draw", "draw-brush", "brush-set-shapes"]),
            Page(name: "Brush library, whole", steps: ["Draw", "draw-brush", "brush-library-open"], scrolls: 1, side: .centre),
            Page(name: "Colour", steps: ["Draw", "colour-well"]),
            Page(name: "Sheets", steps: ["Draw", "draw-sheets"]),
            Page(name: "Frames", steps: ["Draw", "draw-sheets", "draw-frames"], scrolls: 1, side: .centre),
            Page(name: "My Look editor", steps: ["Look", "look-style", "look-clay", "duplicate-look"], scrolls: 1, side: .leading),
            Page(name: "Fine tune the world", steps: ["Look", "Fine tune the world"], scrolls: 1, side: .leading),
            Page(name: "Set up for a Room", steps: ["scene-name", "setup-room", "scene-name", "Model", "model-add"]),
            Page(name: "Print check", steps: ["Model", "model-shape", "print-check"]),
            Page(name: "View cube", steps: ["view-cube"]),
            Page(name: "Through the camera", steps: ["camera-button"]),
            Page(name: "The sidebar awake", steps: ["sidebar-rail"])
        ], from: .blank)
    }

    func test04Sheets() {
        area = "4 Sheets"
        each([
            Page(name: "Export", steps: ["Actions", "open-export"], scrolls: 2, side: .centre),
            Page(name: "History", steps: ["Actions", "open-history"]),
            Page(name: "Board", steps: ["Actions", "open-board"]),
            Page(name: "Learn", steps: ["Actions", "open-learn"], side: .centre),
            Page(name: "Gestures", steps: ["Actions", "open-learn", "learn-gestures"], scrolls: 2, side: .centre),
            Page(name: "Settings", steps: ["Actions", "Settings"], scrolls: 3, side: .centre),
            Page(name: "Settings, Your Pencil", steps: ["Actions", "Settings", "settings-pencil"], scrolls: 3, side: .centre),
            Page(name: "Settings, Gestures", steps: ["Actions", "Settings", "settings-gestures"], scrolls: 2, side: .centre),
            Page(name: "Scripts", steps: ["Actions", "Settings", "open-scripts"]),
            Page(name: "Bridge", steps: ["Actions", "Settings", "open-bridge"], scrolls: 1, side: .centre),
            Page(name: "Diagnostics", steps: ["Actions", "Settings", "Diagnostics"], scrolls: 2, side: .centre)
        ], from: .blank)
    }

    func test05Selection() {
        area = "5 Selection"
        fresh(.cube)
        shot("Object panel")
        for index in 1 ... 2 {
            element("inspector").swipeUp()
            settle(1)
            shot("Object panel, further \(index)")
        }
        fresh(.cube)
        app.otherElements["stage"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 1.2)
        settle(1)
        shot("Hold menu on an object")
        each([
            Page(name: "Turn gizmo", steps: ["gizmo-rotate"]),
            Page(name: "Numbers", steps: ["transform-toggle"]),
            Page(name: "Number pad", steps: ["transform-toggle", "number-x"]),
            Page(name: "Look of this object", steps: ["object-look"], scrolls: 1),
            Page(name: "More ways to move", steps: ["more-motion"], scrolls: 2),
            Page(name: "The object's menu", steps: ["more-actions"]),
            Page(name: "Make it move, Bounce", steps: ["motion-bounce"]),
            Page(name: "The chip", steps: ["fold-inspector"]),
            Page(name: "Model, Edit on an object", steps: ["Model", "model-shape"], scrolls: 2),
            Page(name: "Draw over a thing", steps: ["Draw"]),
            Page(name: "Rig, body shortcuts", steps: ["Rig"], scrolls: 1),
            Page(name: "Rig, pins and dots", steps: ["Rig", "rig-marks"]),
            Page(name: "Rig as a person, guessed", steps: ["Rig", "rig-body-person"]),
            Page(name: "Library, Motion", steps: ["Library", "library-motion"]),
            Page(name: "Library, Characters", steps: ["Library", "library-characters"])
        ], from: .cube)
        fresh(.blob)
        open(Page(name: "Rig with a character", steps: ["Rig"], scrolls: 2))
        fresh(.blob)
        open(Page(name: "Perform with a character", steps: ["Animate", "timeline-mode-perform", "perform-character"], scrolls: 1, side: .centre))
    }

    func test06Timeline() {
        area = "6 Timeline"
        fresh(.cube)
        tap("Animate")
        settle(2)
        shot("Timeline, Keys")
        tap("timeline-mode-perform")
        settle(1)
        shot("Timeline, Perform")
        tap("Collapse the timeline")
        settle(1)
        shot("Slim transport")
        each([
            Page(name: "Sound and words", steps: ["Animate", "Sound and words"]),
            Page(name: "Timeline menu", steps: ["Animate", "timeline-menu"]),
            Page(name: "+ Overlay", steps: ["Animate", "add-overlay"]),
            Page(name: "Perform, Ready", steps: ["Animate", "timeline-mode-perform", "perform-record"])
        ], from: .cube)
    }

    func test07Sample() {
        area = "7 Sample"
        fresh(.sample)
        shot("A finished scene")
        walk([
            Page(name: "Look on a scene", steps: ["Look"], side: .leading),
            Page(name: "Objects on a scene", steps: ["scene-name"], side: .leading),
            Page(name: "Model over a scene", steps: ["Model", "model-add"])
        ], from: .sample)
        tap("Animate")
        settle(2)
        shot("Timeline on a scene")
        fresh(.home)
        shot("Home with projects")
    }
}
