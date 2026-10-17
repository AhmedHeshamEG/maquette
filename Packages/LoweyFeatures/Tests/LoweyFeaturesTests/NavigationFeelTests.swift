@testable import LoweyFeatures
import XCTest

/// One sensitivity everywhere (K1 0.1): the view turns by the screen's long side, never by the stage's frame.
final class NavigationFeelTests: XCTestCase {
    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: AppSettings.navigationSpeed)
        super.tearDown()
    }

    func testOneRateWhateverTheFrame() {
        UserDefaults.standard.removeObject(forKey: AppSettings.navigationSpeed)
        let landscape = AppSettings.orbitDegreesPerPoint(screenLongSide: 1366)
        XCTAssertEqual(landscape * 1366, 180, accuracy: 1e-9, "half a turn across the long side")
        UserDefaults.standard.set(2.0, forKey: AppSettings.navigationSpeed)
        XCTAssertEqual(AppSettings.orbitDegreesPerPoint(screenLongSide: 1366), landscape * 2, accuracy: 1e-9)
    }
}
