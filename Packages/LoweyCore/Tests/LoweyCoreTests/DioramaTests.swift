import Foundation
@testable import LoweyCore
import XCTest

/// Bring your drawing (L2's acceptance): a five-layer PSD becomes a five-sheet diorama.
final class DioramaTests: XCTestCase {
    private func fixture(_ name: String) throws -> Data {
        let root = try XCTUnwrap(Bundle.module.url(forResource: "Fixtures", withExtension: nil))
        return try Data(contentsOf: root.appendingPathComponent("layered").appendingPathComponent(name))
    }

    private func ids() -> () -> ObjectID {
        var next = 0
        return {
            next += 1
            return ObjectID(raw: "d\(next)")
        }
    }

    func testAFiveLayerDrawingBecomesFiveSheetsStackedInDepth() throws {
        let image = try LayeredImage.read(fixture("diorama-5.psd"))
        let made = try DioramaImport.make(image, name: "Hills", longSide: 2, makeID: ids())
        let group = try XCTUnwrap(made.objects.first)
        XCTAssertEqual(group.id, made.root)
        XCTAssertEqual(group.name, "Hills")
        let sheets = made.objects.dropFirst()
        XCTAssertEqual(sheets.map(\.name), ["Sky", "Far hills", "Near hills", "Tree", "Figure"])
        XCTAssertEqual(group.children, sheets.map(\.id))
        let depths = sheets.map(\.transform.position.z)
        XCTAssertEqual(depths, depths.sorted(), "the bottom layer at the back, each one above it nearer")
        XCTAssertEqual(depths.last ?? 1, 0, accuracy: 1e-9, "the top layer at the front")
        XCTAssertGreaterThan((depths.last ?? 0) - (depths.first ?? 0), 0.3)
        for sheet in sheets {
            guard case let .mesh(mesh) = sheet.kind else { return XCTFail("\(sheet.name) is a modelled sheet") }
            XCTAssertFalse(mesh.faces.isEmpty)
            let paint = try XCTUnwrap(sheet.paint, "\(sheet.name) is painted with its picture")
            XCTAssertFalse(paint.layers[0].tiles.isEmpty)
            XCTAssertEqual(paint.layers[0].name, sheet.name)
            for file in paint.layers[0].tiles.values {
                XCTAssertNotNil(made.files[file], "every tile is among the files to write")
            }
            XCTAssertNotNil(made.files[paint.surface.unwrap])
        }
        // The sky is 2 m wide and 1.25 m tall, standing on the ground in the middle.
        let sky = try XCTUnwrap(sheets.first)
        XCTAssertEqual(sky.transform.position.x, 0, accuracy: 1e-9)
        XCTAssertEqual(sky.transform.position.y, 0, accuracy: 1e-9)
        if case let .mesh(mesh) = sky.kind {
            let xs = mesh.vertices.map(\.x), ys = mesh.vertices.map(\.y)
            XCTAssertEqual((xs.max() ?? 0) - (xs.min() ?? 0), 2, accuracy: 0.02)
            XCTAssertEqual((ys.max() ?? 0) - (ys.min() ?? 0), 1.25, accuracy: 0.02)
        }
        // The tree sits right of the middle, its foot 0.25 m up (the drawing's 160th row of 200).
        let tree = try XCTUnwrap(sheets.first { $0.name == "Tree" })
        XCTAssertEqual(tree.transform.position.x, (205 + 29 - 160) / 160, accuracy: 0.01)
        XCTAssertEqual(tree.transform.position.y, (200.0 - 161) / 160, accuracy: 0.01)
        XCTAssertEqual(made.mixesLost, 0)
        XCTAssertTrue(made.skipped.isEmpty)
    }

    func testTheTreesPictureLandsOnItsFront() throws {
        let image = try LayeredImage.read(fixture("diorama-5.psd"))
        let made = try DioramaImport.make(image, name: "Hills", makeID: ids())
        let tree = try XCTUnwrap(made.objects.first { $0.name == "Tree" })
        let paint = try XCTUnwrap(tree.paint)
        let pictures = PaintPictures(paint) { made.files[$0] }
        let layer = try XCTUnwrap(pictures.all()[PaintPictures.key(paint.layers[0].id, .color)])
        // The crown's green and the trunk's brown are both in the painted texture.
        var colours: Set<[UInt8]> = []
        for index in stride(from: 0, to: layer.pixels.count, by: 4) where layer.pixels[index + 3] == 255 {
            colours.insert(Array(layer.pixels[index ..< index + 3]))
        }
        XCTAssertTrue(colours.contains([40, 110, 50]), "the crown")
        XCTAssertTrue(colours.contains([100, 70, 40]), "the trunk")
        guard case let .color(.rgba(edge))? = tree[.color] else { return XCTFail("the sheet has a colour for its edges") }
        XCTAssertLessThan(edge.g, 0.45, "the edges take the picture's average, dark green")
    }

    func testHiddenLayersGroupsAndWhatDoesntShow() throws {
        let hidden = try DioramaImport.make(LayeredImage.read(fixture("hidden-layer.psd")), name: "Shapes", makeID: ids())
        XCTAssertEqual(hidden.objects.dropFirst().map(\.name), ["Background", "Shape 1", "Shape 2"])
        XCTAssertEqual(hidden.objects.last?[.visible], .bool(false), "a hidden layer comes in hidden")
        let grouped = try DioramaImport.make(LayeredImage.read(fixture("group.psd")), name: "Grouped", makeID: ids())
        let group = try XCTUnwrap(grouped.objects.first { $0.name == "Group 1" })
        XCTAssertEqual(group.parent, grouped.root)
        let shape = try XCTUnwrap(grouped.objects.first { $0.name == "Shape 1" })
        XCTAssertEqual(shape.parent, group.id)
        XCTAssertEqual(group.children, [shape.id])
        let empty = LayeredImage(width: 10, height: 10, layers: [LayeredImage.Layer(name: "Nothing", x: 0, y: 0, image: .clear(width: 10, height: 10))])
        XCTAssertThrowsError(try DioramaImport.make(empty, name: "Empty", makeID: ids()))
    }

    func testOutlinesKeepHolesAndCornerTouchingShapesApart() {
        var ring = RGBAImage.clear(width: 9, height: 9)
        for y in 1 ... 7 {
            for x in 1 ... 7 where !(3 ... 5).contains(x) || !(3 ... 5).contains(y) {
                ring.setPixel(x, y, RGBA(1, 0, 0))
            }
        }
        let loops = AlphaOutline.contours(ring)
        XCTAssertEqual(loops.count, 2, "an outline and its hole")
        XCTAssertEqual(Outlines.shapes(loops).count, 1)
        XCTAssertEqual(Outlines.shapes(loops).first?.holes.count, 1)
        var diagonal = RGBAImage.clear(width: 4, height: 4)
        diagonal.setPixel(0, 0, RGBA(1, 1, 1))
        diagonal.setPixel(1, 1, RGBA(1, 1, 1))
        XCTAssertEqual(AlphaOutline.contours(diagonal).count, 2, "touching only at a corner, two loops")
    }
}
