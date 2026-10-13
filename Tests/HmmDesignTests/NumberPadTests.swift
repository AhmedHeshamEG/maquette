@testable import HmmDesign
import XCTest

final class NumberPadTests: XCTestCase {
    private func typed(_ keys: [HmmNumberPadEntry.Key]) -> HmmNumberPadEntry {
        var entry = HmmNumberPadEntry()
        for key in keys {
            entry.press(key)
        }
        return entry
    }

    func testDigitsAndAPointMakeANumber() {
        let entry = typed([.digit(1), .digit(2), .point, .digit(5), .point, .digit(0)])
        XCTAssertEqual(entry.text, "12.50", "a second point in the same number is ignored")
        XCTAssertEqual(entry.value, 12.5)
        XCTAssertEqual(typed([.point, .digit(5)]).text, "0.5")
    }

    func testOperatorsReadAsTheAppsParseThem() {
        let entry = typed([.digit(2), .times, .digit(1), .digit(2), .minus, .digit(4), .divide, .digit(2)])
        XCTAssertEqual(entry.text, "2*12-4/2")
        XCTAssertEqual(entry.display, "2×12−4÷2")
        XCTAssertEqual(entry.value, 22)
    }

    func testAnotherOperatorReplacesTheOneJustTyped() {
        XCTAssertEqual(typed([.digit(3), .plus, .times, .digit(2)]).text, "3*2")
        XCTAssertEqual(typed([.digit(3), .times, .minus, .digit(2)]).text, "3*-2", "a negative number after ×")
        XCTAssertEqual(typed([.digit(3), .times, .minus, .digit(2)]).value, -6)
        XCTAssertEqual(typed([.digit(3), .times, .minus, .plus, .digit(2)]).text, "3+2")
    }

    func testOnlyAMinusCanStart() {
        XCTAssertEqual(typed([.plus, .times]).text, "")
        XCTAssertEqual(typed([.minus, .digit(4)]).value, -4)
        XCTAssertEqual(typed([.minus, .plus]).text, "-")
    }

    func testAUnitFollowsANumberAndAnotherUnitReplacesIt() {
        XCTAssertEqual(typed([.unit("cm")]).text, "", "nothing to measure yet")
        XCTAssertEqual(typed([.digit(5), .unit("cm"), .unit("mm")]).text, "5 mm")
        XCTAssertEqual(typed([.digit(1), .unit("ft"), .digit(6), .unit("in")]).text, "1 ft 6 in")
        XCTAssertEqual(typed([.digit(5), .plus, .unit("cm")]).text, "5+", "a unit needs a number before it")
        XCTAssertNil(typed([.digit(5), .unit("cm")]).value, "lengths with units are the app's to read")
    }

    func testBackspaceTakesAWholeUnit() {
        XCTAssertEqual(typed([.digit(1), .digit(5), .unit("cm"), .backspace]).text, "15")
        XCTAssertEqual(typed([.digit(1), .digit(5), .backspace]).text, "1")
        XCTAssertEqual(typed([.digit(1), .backspace, .backspace]).text, "")
        XCTAssertEqual(typed([.digit(1), .digit(5), .clear]).text, "")
    }

    func testArithmeticRefusesWhatIsNotANumber() {
        XCTAssertNil(HmmArithmetic.evaluate(""))
        XCTAssertNil(HmmArithmetic.evaluate("2+"))
        XCTAssertNil(HmmArithmetic.evaluate("4/0"))
        XCTAssertEqual(HmmArithmetic.evaluate("(1+2)*3"), 9)
        XCTAssertEqual(HmmArithmetic.evaluate("1,5"), 1.5, "a decimal comma reads as a point")
    }
}
