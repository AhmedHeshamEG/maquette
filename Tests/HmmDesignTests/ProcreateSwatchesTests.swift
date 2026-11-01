@testable import HmmDesign
import XCTest

final class ProcreateSwatchesTests: XCTestCase {
    func testAProcreatePaletteComesInWithItsNameAndColours() throws {
        let json = """
        [{"name": "Sunset", "swatches": [
          {"hue": 0, "saturation": 1, "brightness": 1, "alpha": 1, "colorSpace": 0},
          null,
          {"hue": 0.6666667, "saturation": 1, "brightness": 0.5, "alpha": 1, "colorSpace": 0}
        ]}]
        """
        let palette = try XCTUnwrap(HmmPalette.procreate(swatchesJSON: Data(json.utf8)))
        XCTAssertEqual(palette.name, "Sunset")
        XCTAssertEqual(palette.colours.count, 2)
        XCTAssertEqual(palette.colours[0].hex, "#FF0000")
        XCTAssertEqual(palette.colours[1].hex, "#000080")
        let single = #"{"name": "", "swatches": [{"hue": 0.3333333, "saturation": 1, "brightness": 1}]}"#
        XCTAssertEqual(HmmPalette.procreate(swatchesJSON: Data(single.utf8))?.name, "Procreate palette")
        XCTAssertNil(HmmPalette.procreate(swatchesJSON: Data("{}".utf8)))
        XCTAssertNil(HmmPalette.procreate(swatchesJSON: Data("not json".utf8)))
    }
}
