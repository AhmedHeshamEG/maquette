@testable import HmmDesign
import XCTest

final class PanelPositionTests: XCTestCase {
    private let bounds = CGRect(x: 0, y: 0, width: 1000, height: 800)
    private let frame = CGRect(x: 600, y: 20, width: 300, height: 400)

    func testAnOffsetInsideTheScreenIsKept() {
        let position = HmmPanelPosition(id: "test")
        XCTAssertEqual(position.clamped(CGSize(width: -200, height: 100), frame: frame, in: bounds), CGSize(width: -200, height: 100))
    }

    func testThePanelCantLeaveTheScreen() {
        let position = HmmPanelPosition(id: "test", keepVisible: 72)
        let right = position.clamped(CGSize(width: 900, height: 0), frame: frame, in: bounds)
        XCTAssertEqual(right.width, 1000 - 600 - 72)
        let left = position.clamped(CGSize(width: -2000, height: 0), frame: frame, in: bounds)
        XCTAssertEqual(left.width, 0 - 900 + 72)
        let up = position.clamped(CGSize(width: 0, height: -500), frame: frame, in: bounds)
        XCTAssertEqual(up.height, -20, "the title row stays on screen")
        let down = position.clamped(CGSize(width: 0, height: 2000), frame: frame, in: bounds)
        XCTAssertEqual(down.height, 800 - 20 - 72)
    }

    func testItIsRememberedPerPanel() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "PanelPositionTests"))
        defaults.removePersistentDomain(forName: "PanelPositionTests")
        let position = HmmPanelPosition(id: "inspector")
        XCTAssertNil(position.load(from: defaults))
        position.save(CGSize(width: -40, height: 12), to: defaults)
        XCTAssertEqual(position.load(from: defaults), CGSize(width: -40, height: 12))
        XCTAssertNil(HmmPanelPosition(id: "other").load(from: defaults))
        position.reset(in: defaults)
        XCTAssertNil(position.load(from: defaults))
    }
}
