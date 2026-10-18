import Foundation
@testable import HmmBrush
import XCTest

final class PencilFeelTests: XCTestCase {
    func testTwoStrokesFitACurveFromThisHandsLightestToItsHeaviest() throws {
        let curve = try XCTUnwrap(HmmPencilFeel.calibrated(lightest: [0.12, 0.15, 0.18, 0.14, 0.16], heaviest: [0.6, 0.7, 0.65, 0.68]))
        XCTAssertEqual(curve.value(at: 0.15), 0.08, accuracy: 1e-9, "the lightest touch is a thin visible line")
        XCTAssertEqual(curve.value(at: 0.665), 1, accuracy: 1e-9, "the heaviest is a full line")
        XCTAssertEqual(curve.value(at: 0.9), 1)
        XCTAssertEqual(curve.value(at: 0), 0)
        XCTAssertGreaterThan(curve.value(at: 0.4), curve.value(at: 0.3), "it climbs in between")
    }

    func testCalibrationRefusesStrokesThatSayNothing() {
        XCTAssertNil(HmmPencilFeel.calibrated(lightest: [0.2, 0.2], heaviest: [0.8, 0.8, 0.8, 0.8]), "too short")
        XCTAssertNil(HmmPencilFeel.calibrated(lightest: [0.4, 0.4, 0.4, 0.4], heaviest: [0.42, 0.43, 0.41, 0.44]), "not heavier")
    }

    func testPresetsGoFromLightToHeavy() {
        let light = HmmPencilFeel(hand: .light), normal = HmmPencilFeel(hand: .normal), heavy = HmmPencilFeel(hand: .heavy)
        XCTAssertGreaterThan(light.pressure(0.3), normal.pressure(0.3))
        XCTAssertGreaterThan(normal.pressure(0.3), heavy.pressure(0.3))
        for feel in [light, normal, heavy] {
            XCTAssertEqual(feel.pressure(1), 1)
            XCTAssertEqual(feel.pressure(0), 0)
        }
    }

    func testAPencilWithoutPressureThinsWithSpeed() {
        XCTAssertTrue(HmmPencilFeel.isFlat(Array(repeating: 1, count: 10)))
        XCTAssertFalse(HmmPencilFeel.isFlat([0.2, 0.3, 0.4, 0.5, 0.4, 0.3]))
        XCTAssertFalse(HmmPencilFeel.isFlat([1, 1]), "two samples prove nothing")
        let slow = (0 ..< 20).map { Vec2(Double($0), 0) }
        let fast = (0 ..< 20).map { Vec2(Double($0) * 60, 0) }
        let times = (0 ..< 20).map { Double($0) / 120 }
        let slowPressure = HmmPencilFeel.pressureFromSpeed(points: slow, times: times)
        let fastPressure = HmmPencilFeel.pressureFromSpeed(points: fast, times: times)
        XCTAssertGreaterThan(slowPressure.last ?? 0, 0.9)
        XCTAssertLessThan(fastPressure.last ?? 1, 0.4)
        XCTAssertGreaterThanOrEqual(fastPressure.min() ?? 0, 0.25)
    }

    func testTheFeelIsKeptOnTheDevice() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "pencil-feel-tests"))
        defaults.removePersistentDomain(forName: "pencil-feel-tests")
        XCTAssertEqual(HmmPencilFeel.load(from: defaults), .default)
        let feel = HmmPencilFeel(hand: .heavy, stabilisation: 0.4, speedForPressure: false)
        feel.save(to: defaults)
        XCTAssertEqual(HmmPencilFeel.load(from: defaults), feel)
    }
}
