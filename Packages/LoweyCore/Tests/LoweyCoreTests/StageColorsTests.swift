@testable import LoweyCore
import XCTest

/// Nothing may go invisible in the dark studio (CONTEXT §10.10, his condition): the default shape colour, the colour
/// in the hand, the grid, the gizmo and the selection outline all stand out from its near-black ground.
final class StageColorsTests: XCTestCase {
    private let ground = MoodPresets.look(for: .darkStudio).ground.color

    func testTheColourInTheHandStandsOut() {
        // New shapes and every drawing tool start with the palette's first slot.
        let first = Look.default.palette.color(at: 0)
        XCTAssertGreaterThanOrEqual(StageColors.contrast(first, ground), 7, "the default shape and ink colour")
    }

    func testTheEditorLayerStandsOut() {
        XCTAssertGreaterThanOrEqual(StageColors.contrast(StageColors.selection, ground), 4.5, "the selection outline")
        for (axis, color) in StageColors.axes {
            XCTAssertGreaterThanOrEqual(StageColors.contrast(color, ground), 3, "the \(axis) handle")
        }
        let minor = StageColors.over(.white, alpha: StageColors.gridMinorAlpha, on: ground)
        let major = StageColors.over(.white, alpha: StageColors.gridMajorAlpha, on: ground)
        XCTAssertGreaterThanOrEqual(StageColors.contrast(minor, ground), 2, "a faint grid, but a grid")
        XCTAssertGreaterThanOrEqual(StageColors.contrast(major, ground), 3, "the five-metre lines")
        XCTAssertLessThan(StageColors.contrast(minor, ground), 7, "faint: it mustn't compete with what is made")
    }

    func testContrastIsTheWCAGRatio() {
        XCTAssertEqual(StageColors.contrast(.white, .black), 21, accuracy: 0.001)
        XCTAssertEqual(StageColors.contrast(.black, .black), 1, accuracy: 0.001)
        XCTAssertEqual(StageColors.over(.white, alpha: 1, on: .black), .white)
    }
}
