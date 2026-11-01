@testable import HmmHeld
import XCTest

private enum SampleHeld: String, HmmHeldFeature {
    case livePerformance, mechanisms, ar, webLayer
}

final class HmmHeldTests: XCTestCase {
    func testAnEmptyListHoldsNothing() {
        let held = HmmHeld<SampleHeld>(list: "")
        XCTAssertTrue(held.holdsNothing)
        for feature in SampleHeld.allCases {
            XCTAssertTrue(held.isOn(feature))
        }
    }

    func testTheListHoldsWhatItNames() {
        let held = HmmHeld<SampleHeld>(list: "livePerformance  webLayer")
        XCTAssertFalse(held.isOn(.livePerformance))
        XCTAssertFalse(held.isOn(.webLayer))
        XCTAssertTrue(held.isOn(.mechanisms))
        XCTAssertTrue(held.isOn(.ar))
    }

    func testCommasAndNewlinesSeparateToo() {
        let held = HmmHeld<SampleHeld>(list: "ar,mechanisms\nwebLayer")
        XCTAssertEqual(held.held, [.ar, .mechanisms, .webLayer])
    }

    func testUnknownNamesAreIgnored() {
        let held = HmmHeld<SampleHeld>(list: "teleporter ar")
        XCTAssertEqual(held.held, [.ar])
    }

    func testTheInfoDictionaryCarriesTheList() {
        let held = HmmHeld<SampleHeld>(info: ["HmmHeld": "mechanisms", "Other": 1])
        XCTAssertEqual(held.held, [.mechanisms])
        XCTAssertTrue(HmmHeld<SampleHeld>(info: nil).holdsNothing)
        XCTAssertTrue(HmmHeld<SampleHeld>(info: ["HmmHeld": 3]).holdsNothing)
    }
}
