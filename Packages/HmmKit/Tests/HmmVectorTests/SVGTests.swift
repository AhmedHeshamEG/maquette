@testable import HmmVector
import XCTest

/// SVG files as filled shapes: path commands, shapes, transforms, paint as it inherits, CSS classes, gradients, and
/// what can't be carried counted.
final class SVGTests: XCTestCase {
    private func read(_ svg: String, tolerance: Double? = nil) throws -> VectorDrawing {
        try SVG.read(Data(svg.utf8), tolerance: tolerance)
    }

    private func area(_ contour: [VectorPoint]) -> Double {
        var sum = 0.0
        for index in contour.indices {
            let a = contour[index], b = contour[(index + 1) % contour.count]
            sum += a.x * b.y - b.x * a.y
        }
        return abs(sum) / 2
    }

    func testARectangleAndItsColour() throws {
        let drawing = try read(##"<svg viewBox="0 0 100 50"><rect x="10" y="5" width="80" height="40" fill="#ff8800"/></svg>"##)
        XCTAssertEqual(drawing.shapes.count, 1)
        XCTAssertEqual(drawing.shapes[0].fill.hex, "#ff8800")
        XCTAssertEqual(area(drawing.shapes[0].contours[0]), 3200, accuracy: 1e-9)
        let bounds = try XCTUnwrap(drawing.bounds)
        XCTAssertEqual(bounds.min, VectorPoint(10, 5))
        XCTAssertEqual(bounds.max, VectorPoint(90, 45))
    }

    func testPathCommandsAbsoluteAndRelative() throws {
        // The same 10 × 10 square three ways: absolute, relative with H/V, and implicit linetos after a moveto.
        for d in ["M0 0 L10 0 L10 10 L0 10 Z", "m0,0 h10 v10 h-10 z", "M0 0 10 0 10 10 0 10z"] {
            let drawing = try read("<svg width='10' height='10'><path d='\(d)'/></svg>")
            XCTAssertEqual(area(drawing.shapes[0].contours[0]), 100, accuracy: 1e-9, d)
        }
    }

    func testNumbersThatTouch() {
        var scanner = PathScanner("1.5.5-2e1,3E-1")
        XCTAssertEqual(scanner.number(), 1.5)
        XCTAssertEqual(scanner.number(), 0.5)
        XCTAssertEqual(scanner.number(), -20)
        XCTAssertEqual(scanner.number(), 0.3)
        XCTAssertNil(scanner.number())
    }

    func testCurvesStayWithinTheTolerance() throws {
        // A circle of radius 50 as four arcs and as a circle element: every point within 0.05 of the circle.
        let d = "M0,50 A50,50 0 0 1 50,0 A50,50 0 0 1 100,50 A50 50 0 0150 100 A50,50 0 0 1 0,50 Z"
        for svg in ["<svg><path d='\(d)' transform='translate(-50,-50)'/></svg>", "<svg><circle r='50'/></svg>"] {
            let contour = try read(svg, tolerance: 0.05).shapes[0].contours[0]
            XCTAssertGreaterThan(contour.count, 40)
            for point in contour {
                XCTAssertEqual((point.x * point.x + point.y * point.y).squareRoot(), 50, accuracy: 0.06)
            }
            XCTAssertEqual(area(contour), .pi * 2500, accuracy: 15)
        }
        // A cubic quarter circle (the usual 0.5523 handles) ends exactly where it should.
        let quarter = try read("<svg><path d='M50 0 C50 27.6 27.6 50 0 50 L0 0 Z'/></svg>", tolerance: 0.01).shapes[0].contours[0]
        XCTAssertTrue(quarter.contains(VectorPoint(0, 50)))
    }

    func testSmoothCurvesReflectTheirControlPoints() throws {
        // S after C mirrors the second control point: this S-curve is symmetric about its middle (50, 0).
        let contour = try read("<svg><path d='M0 0 C0 -40 40 -40 50 0 S100 40 100 0 Z'/></svg>", tolerance: 0.01).shapes[0].contours[0]
        let low = try XCTUnwrap(contour.map(\.y).min())
        let high = try XCTUnwrap(contour.map(\.y).max())
        XCTAssertEqual(low, -high, accuracy: 0.05)
        // T after Q the same: a wave of two equal humps.
        let wave = try read("<svg><path d='M0 0 Q25 -50 50 0 T100 0 Z'/></svg>", tolerance: 0.01).shapes[0].contours[0]
        XCTAssertEqual(try XCTUnwrap(wave.map(\.y).min()), try -XCTUnwrap(wave.map(\.y).max()), accuracy: 0.05)
    }

    func testTransformsNestAndUseMovesIt() throws {
        let svg = """
        <svg viewBox="0 0 100 100">
          <defs><rect id="dot" width="2" height="2"/></defs>
          <g transform="translate(10 20) scale(2)">
            <use href="#dot" x="5" y="0"/>
            <rect width="1" height="1" transform="rotate(90)"/>
          </g>
        </svg>
        """
        let drawing = try read(svg)
        XCTAssertEqual(drawing.shapes.count, 2)
        let used = drawing.shapes[0].contours[0]
        XCTAssertEqual(used.map(\.x).min() ?? 0, 20, accuracy: 1e-9)
        XCTAssertEqual(used.map(\.y).max() ?? 0, 24, accuracy: 1e-9)
        let turned = drawing.shapes[1].contours[0]
        XCTAssertEqual(turned.map(\.x).min() ?? 0, 8, accuracy: 1e-9)
        XCTAssertEqual(turned.map(\.y).max() ?? 0, 22, accuracy: 1e-9)
    }

    func testPaintInheritsAndTheStyleSheetWins() throws {
        let svg = """
        <svg width="10" height="10">
          <style><![CDATA[ /* brand */ .brand, .other { fill: #E30613; } #special { fill: rgb(0, 128, 255) } ]]></style>
          <g fill="green" opacity="0.5">
            <rect width="1" height="1"/>
            <rect class="brand" width="1" height="1"/>
            <rect id="special" class="brand" width="1" height="1" style="fill-opacity: 50%"/>
            <rect width="1" height="1" fill="none"/>
            <rect width="1" height="1" style="display:none"/>
          </g>
        </svg>
        """
        let drawing = try read(svg)
        XCTAssertEqual(drawing.shapes.map(\.fill.hex), ["#008000", "#e30613", "#0080ff"])
        XCTAssertEqual(drawing.shapes[0].fill.alpha, 0.5, accuracy: 1e-9)
        XCTAssertEqual(drawing.shapes[2].fill.alpha, 0.25, accuracy: 1e-9)
        XCTAssertEqual(drawing.colors.count, 3)
    }

    func testGradientsBecomeTheirAverage() throws {
        let svg = """
        <svg width="10" height="10">
          <linearGradient id="a"><stop offset="0" stop-color="#ff0000"/><stop offset="1" style="stop-color:#0000ff"/></linearGradient>
          <linearGradient id="b" xlink:href="#a"/>
          <rect width="5" height="5" fill="url(#b)"/>
        </svg>
        """
        let fill = try read(svg).shapes[0].fill
        XCTAssertEqual(fill.red, 0.5, accuracy: 1e-9)
        XCTAssertEqual(fill.blue, 0.5, accuracy: 1e-9)
    }

    func testColourForms() {
        XCTAssertEqual(SVGColor.parse("#abc")?.hex, "#aabbcc")
        XCTAssertEqual(SVGColor.parse("#11223380")?.alpha ?? 0, 128.0 / 255, accuracy: 1e-9)
        XCTAssertEqual(SVGColor.parse("rgb(100%, 0%, 0%)")?.hex, "#ff0000")
        XCTAssertEqual(SVGColor.parse("hsl(120, 100%, 50%)")?.hex, "#00ff00")
        XCTAssertEqual(SVGColor.parse("Navy")?.hex, "#000080")
        XCTAssertNil(SVGColor.parse("not-a-colour"))
    }

    func testRoundedRectanglesAndHoles() throws {
        let svg = """
        <svg viewBox="0 0 100 100"><rect width="100" height="60" rx="10"/>
        <path fill-rule="evenodd" d="M0 0h50v50H0z M10 10v30h30V10z"/></svg>
        """
        let drawing = try read(svg)
        XCTAssertEqual(area(drawing.shapes[0].contours[0]), 6000 - (400 - .pi * 100), accuracy: 8)
        XCTAssertEqual(drawing.shapes[1].contours.count, 2)
    }

    func testWhatCannotBeCarriedIsCounted() throws {
        let svg = """
        <svg width="10" height="10"><rect width="5" height="5" stroke="black"/>
        <line x1="0" y1="0" x2="10" y2="10" stroke="black"/><path d="M0 0L5 5" fill="none" stroke="red"/>
        <text>Hello</text><image href="a.png"/></svg>
        """
        let drawing = try read(svg)
        XCTAssertEqual(drawing.shapes.count, 1)
        XCTAssertEqual(drawing.skipped.strokes, 3)
        XCTAssertEqual(drawing.skipped.texts, 1)
        XCTAssertEqual(drawing.skipped.images, 1)
    }

    func testFailures() {
        XCTAssertThrowsError(try read("<html></html>")) { XCTAssertEqual($0 as? SVG.Failure, .notSVG) }
        XCTAssertThrowsError(try read("<svg><path d='M0 0 L10 10' fill='none' stroke='red'/></svg>")) {
            XCTAssertEqual($0 as? SVG.Failure, .nothingFilled)
        }
        XCTAssertThrowsError(try SVG.read(Data([0xFF, 0x00, 0x13]))) { XCTAssertEqual($0 as? SVG.Failure, .notSVG) }
    }

    func testXMLDeclarationsCommentsAndNamespaces() throws {
        let svg = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE svg PUBLIC "-//W3C//DTD SVG 1.1//EN" "http://www.w3.org/Graphics/SVG/1.1/DTD/svg11.dtd" [ <!ENTITY a "b"> ]>
        <!-- Generator: Adobe Illustrator -->
        <svg:svg xmlns:svg="http://www.w3.org/2000/svg" viewBox="0 0 10 10"><svg:polygon points="0,0 10,0 5,8"/></svg:svg>
        """
        XCTAssertEqual(try read(svg).shapes.count, 1)
    }
}
