import Foundation
@testable import HmmDesign
import XCTest

final class ColourMathTests: XCTestCase {
    func testHexReadsAndWrites() {
        XCTAssertEqual(HmmColour(hex: "#FF8000")?.hex, "#FF8000")
        XCTAssertEqual(HmmColour(hex: "f80")?.hex, "#FF8800")
        XCTAssertEqual(HmmColour(hex: " #00ff00 ")?.green, 1)
        XCTAssertNil(HmmColour(hex: "#12345"))
        XCTAssertNil(HmmColour(hex: "nope"))
        XCTAssertEqual(HmmColour(red: 2, green: -1, blue: .nan), HmmColour(red: 1, green: 0, blue: 0), "clamped")
    }

    func testHSBRoundTrips() {
        for hex in ["#FF0000", "#00FF00", "#0000FF", "#FFB847", "#336699", "#000000", "#FFFFFF", "#808080"] {
            guard let colour = HmmColour(hex: hex) else { return XCTFail(hex) }
            XCTAssertEqual(HmmHSB(colour).rgb.hex, hex)
        }
        let orange = HmmHSB(HmmColour(red: 1, green: 0.5, blue: 0))
        XCTAssertEqual(orange.hue, 30.0 / 360, accuracy: 1e-9)
        XCTAssertEqual(orange.saturation, 1)
        XCTAssertEqual(HmmHSB(hue: 1.25, saturation: 1, brightness: 1).hue, 0.25, accuracy: 1e-9, "hue wraps")
    }

    func testTheDiscsGeometry() {
        XCTAssertEqual(HmmColourDisc.hue(atX: 0, y: -1), 0, accuracy: 1e-9, "red at the top")
        XCTAssertEqual(HmmColourDisc.hue(atX: 1, y: 0), 0.25, accuracy: 1e-9, "clockwise")
        XCTAssertTrue(HmmColourDisc.isOnRing(x: 0, y: -0.9))
        XCTAssertFalse(HmmColourDisc.isOnRing(x: 0, y: -0.3))
        let point = HmmColourDisc.point(hue: 0.25, saturation: 1)
        XCTAssertEqual(HmmColourDisc.saturation(atX: point.x, y: point.y), 1, accuracy: 1e-9)
        XCTAssertEqual(HmmColourDisc.hue(atX: point.x, y: point.y), 0.25, accuracy: 1e-9)
    }

    func testHistoryKeepsTenWithoutRepeats() {
        var history = HmmColourHistory()
        for value in 0 ..< 14 {
            history.use(HmmColour(red: Double(value) / 20, green: 0, blue: 0))
        }
        XCTAssertEqual(history.colours.count, HmmColourHistory.limit)
        XCTAssertEqual(history.colours.first?.red ?? 0, 13.0 / 20, accuracy: 1e-9, "newest first")
        history.use(HmmColour(red: 10.0 / 20, green: 0, blue: 0))
        XCTAssertEqual(history.colours.first?.red ?? 0, 0.5, accuracy: 1e-9)
        XCTAssertEqual(history.colours.filter { abs($0.red - 0.5) < 1e-9 }.count, 1, "moved, not repeated")
    }

    func testPalettesAndMemorySurviveDefaults() throws {
        var palette = HmmPalette(name: "Warm", colours: [.white])
        palette.add(.white)
        palette.add(.black)
        XCTAssertEqual(palette.colours, [.white, .black])
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "colour-memory-\(UUID().uuidString)"))
        var memory = HmmColourMemory()
        memory.palettes.append(palette)
        memory.history.use(.black)
        memory.save(defaults)
        XCTAssertEqual(HmmColourMemory.load(defaults), memory)
        XCTAssertEqual(HmmColourMemory.load(UserDefaults(suiteName: "empty-\(UUID().uuidString)") ?? defaults).palettes.count, 0)
    }
}
