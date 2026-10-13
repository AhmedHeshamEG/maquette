@testable import HmmDesign
import XCTest

/// Every number is a slider: slow is fine, fast is coarse, the ends hold.
final class ScrubTests: XCTestCase {
    func testASlowDragMovesFinelyAndAFastOneCoarsely() {
        let scrub = HmmScrub(fine: 0.01)
        XCTAssertEqual(scrub.value(from: 1, delta: 10, speed: 40), 1.1, accuracy: 1e-12, "slow: a point is `fine`")
        XCTAssertEqual(scrub.value(from: 1, delta: 10, speed: 5000), 1 + 10 * 0.01 * HmmScrub.maximumGain, accuracy: 1e-12)
        let middle = scrub.value(from: 1, delta: 10, speed: 800) - 1
        XCTAssertGreaterThan(middle, 0.1)
        XCTAssertLessThan(middle, 0.1 * HmmScrub.maximumGain)
        XCTAssertEqual(HmmScrub.gain(speed: -2000), HmmScrub.maximumGain, "either direction")
    }

    func testTheRangeHoldsAndItsEndsAreKnown() {
        let scrub = HmmScrub(fine: 1, range: 0 ... 10)
        XCTAssertEqual(scrub.value(from: 9, delta: 50, speed: 0), 10)
        XCTAssertEqual(scrub.value(from: 1, delta: -50, speed: 0), 0)
        XCTAssertTrue(scrub.isAtEnd(10))
        XCTAssertTrue(scrub.isAtEnd(0))
        XCTAssertFalse(scrub.isAtEnd(5))
        XCTAssertFalse(HmmScrub(fine: 1).isAtEnd(1e9), "no range, no ends")
    }

    func testRightAndUpAreMoreWhicheverWayTheHandWentFurther() {
        XCTAssertEqual(HmmScrub.delta(dx: 12, dy: 3), 12)
        XCTAssertEqual(HmmScrub.delta(dx: 2, dy: -9), 9)
        XCTAssertEqual(HmmScrub.delta(dx: -2, dy: 9), -9)
    }
}
