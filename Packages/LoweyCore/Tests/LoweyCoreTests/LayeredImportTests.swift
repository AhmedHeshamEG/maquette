import Foundation
@testable import LoweyCore
import XCTest

/// Photoshop and Procreate drawings read layer by layer (L2, "Bring your drawing"). The PSDs were made by Photoshop,
/// GIMP and ImageMagick; what each should hold was read with psd-tools, an independent reader.
final class LayeredImportTests: XCTestCase {
    private func fixture(_ name: String) throws -> Data {
        let root = try XCTUnwrap(Bundle.module.url(forResource: "Fixtures", withExtension: nil))
        return try Data(contentsOf: root.appendingPathComponent("layered").appendingPathComponent(name))
    }

    private func rgba(_ image: RGBAImage, _ x: Int, _ y: Int) -> [Int] {
        let index = (y * image.width + x) * 4
        return image.pixels[index ..< index + 4].map(Int.init)
    }

    func testFiveLayersWithTheirPlacesAndTransparency() throws {
        let image = try PSDReader.read(fixture("diorama-5.psd"))
        XCTAssertEqual(image.width, 320)
        XCTAssertEqual(image.height, 200)
        XCTAssertEqual(image.layers.map(\.name), ["Sky", "Far hills", "Near hills", "Tree", "Figure"], "bottom first")
        let places = image.layers.map { [$0.x, $0.y, $0.image.width, $0.image.height] }
        XCTAssertEqual(places, [[0, 0, 320, 200], [0, 80, 320, 120], [0, 135, 320, 65], [205, 60, 58, 101], [80, 120, 21, 56]])
        let far = image.layers[1].image
        XCTAssertEqual(rgba(far, 0, 0), [0, 0, 0, 0], "above the hills is transparent")
        XCTAssertEqual(rgba(far, far.width / 2, far.height - 1), [90, 120, 150, 255])
        XCTAssertEqual(rgba(image.layers[0].image, 160, 100), [120, 170, 225, 255])
        XCTAssertEqual(rgba(image.layers[3].image, 29, 100), [100, 70, 40, 255], "the tree's trunk")
        XCTAssertTrue(image.layers.allSatisfy { !$0.hidden && $0.opacity == 1 && $0.blend == .normal && $0.groups.isEmpty })
        let flat = image.flattened()
        XCTAssertEqual(rgba(flat, 90, 130), [240, 200, 160, 255], "the figure's face is on top")
    }

    func testUnicodeNamesAndPartialAlpha() throws {
        let image = try PSDReader.read(fixture("2layers.psd"))
        XCTAssertEqual(image.layers.map(\.name), ["Фон", "Слой"], "the Unicode names, not the old Pascal ones")
        let layer = image.layers[1]
        XCTAssertEqual([layer.x, layer.y, layer.image.width, layer.image.height], [8, 4, 85, 46])
        XCTAssertEqual(rgba(layer.image, 0, 0)[3], 0)
        XCTAssertEqual(rgba(layer.image, 42, 23), [242, 244, 194, 42])
        XCTAssertEqual(rgba(image.layers[0].image, 50, 27), [15, 186, 55, 255])
    }

    func testGroupsAndHiddenLayers() throws {
        let grouped = try PSDReader.read(fixture("group.psd"))
        XCTAssertEqual(grouped.layers.map(\.name), ["Background", "Shape 1"])
        XCTAssertEqual(grouped.layers[1].groups, ["Group 1"])
        XCTAssertEqual([grouped.layers[1].x, grouped.layers[1].y], [25, 24])
        let hidden = try PSDReader.read(fixture("hidden-layer.psd"))
        XCTAssertEqual(hidden.layers.map(\.name), ["Background", "Shape 1", "Shape 2"])
        XCTAssertEqual(hidden.layers.map(\.hidden), [false, false, true])
    }

    func testSixteenBitsLargeDocumentsAndOddEdges() throws {
        let deep = try PSDReader.read(fixture("16bit5x5.psd"))
        XCTAssertEqual(deep.layers.map(\.name), ["Background", "Background copy", "Background copy 2"])
        XCTAssertEqual(rgba(deep.layers[0].image, 2, 2), [236, 242, 251, 255])
        XCTAssertEqual([deep.layers[2].x, deep.layers[2].y, deep.layers[2].image.width, deep.layers[2].image.height], [4, 1, 1, 3])
        XCTAssertEqual(rgba(deep.layers[2].image, 0, 1), [46, 196, 104, 255])
        let large = try PSDReader.read(fixture("1layer.psb"))
        XCTAssertEqual([large.width, large.height], [101, 55])
        XCTAssertEqual(large.layers.count, 1)
        XCTAssertEqual(rgba(large.layers[0].image, 50, 27), [95, 225, 37, 255])
        let pixel = try PSDReader.read(fixture("pixel-layer.psd"))
        XCTAssertEqual(pixel.layers.map(\.name), ["Pixel"])
        XCTAssertEqual(rgba(pixel.layers[0].image, 14, 14), [0, 255, 255, 255], "psd-tools' channel data says 0 (its picture says 1)")
    }

    /// The SPIKE (D-488): a real Procreate file, read directly, lands as Procreate shows it: the layer under its mask,
    /// turned as the canvas was held, matches the thumbnail Procreate saved inside the file.
    func testAProcreateFileMatchesItsOwnThumbnail() throws {
        let data = try fixture("mask-test.procreate")
        let image = try ProcreateReader.read(data)
        XCTAssertEqual([image.width, image.height], [2048, 2048])
        XCTAssertEqual(image.layers.map(\.name), ["Layer 1"])
        let entries = try ZipReader.entries(data) { $0 == "QuickLook/Thumbnail.png" }
        let thumbnail = try PNGCodec.decode(XCTUnwrap(entries.first?.data))
        let flat = image.flattened()
        // On Procreate's white background, two by two pixels to one, as the thumbnail is half the canvas.
        var total = 0.0
        for y in 0 ..< thumbnail.height {
            for x in 0 ..< thumbnail.width {
                var mine = 0.0
                for (dx, dy) in [(0, 0), (1, 0), (0, 1), (1, 1)] {
                    let index = ((y * 2 + dy) * flat.width + x * 2 + dx) * 4
                    let alpha = Double(flat.pixels[index + 3]) / 255
                    mine += (Double(flat.pixels[index]) * alpha + 255 * (1 - alpha)) / 4
                }
                total += abs(mine - Double(thumbnail.pixels[(y * thumbnail.width + x) * 4]))
            }
        }
        let mean = total / Double(thumbnail.width * thumbnail.height)
        XCTAssertLessThan(mean, 1.5, "mean difference from Procreate's own thumbnail, in levels of 255")
    }

    func testTileCodes() throws {
        // LZ4: three literals, then a match reaching back across them; then a block that copies from the one before.
        var output: [UInt8] = []
        try TileCompression.lz4Block([0x30, 1, 2, 3][...], into: &output, size: 3)
        XCTAssertEqual(output, [1, 2, 3])
        try TileCompression.lz4Block([0x04, 3, 0][...], into: &output, size: 8)
        XCTAssertEqual(output, [1, 2, 3, 1, 2, 3, 1, 2, 3, 1, 2], "the second block reaches into the first")
        var framed = Data("bv41".utf8) + Data([3, 0, 0, 0, 4, 0, 0, 0, 0x30, 7, 8, 9])
        framed += Data("bv4-".utf8) + Data([2, 0, 0, 0, 5, 6]) + Data("bv4$".utf8)
        XCTAssertEqual(try TileCompression.appleLZ4(framed, expected: 5), [7, 8, 9, 5, 6])
        XCTAssertThrowsError(try TileCompression.appleLZ4(Data("nope".utf8), expected: 1))
        // LZO1X: a first literal run (17 + 4 bytes) and the end marker.
        let lzo = Data([21, 10, 20, 30, 40, 0x11, 0, 0])
        XCTAssertEqual(try TileCompression.lzo1x(lzo, expected: 4), [10, 20, 30, 40])
        XCTAssertThrowsError(try TileCompression.lzo1x(Data([21, 1]), expected: 4))
    }

    /// An older Procreate file's tile (LZO1X), against python-lzo's reading of the same bytes.
    func testAnOldProcreateTile() throws {
        let tile = try TileCompression.lzo1x(fixture("old-tile.chunk"), expected: 256 * 256 * 4)
        XCTAssertEqual(tile.count, 262_144)
        XCTAssertEqual(CRC32.checksum(Data(tile)), 3_126_821_818)
        XCTAssertEqual(stride(from: 3, to: tile.count, by: 4).filter { tile[$0] != 0 }.count, 10961, "pixels that show")
    }

    func testNotAPhotoshopFile() {
        XCTAssertThrowsError(try PSDReader.read(Data("hello".utf8))) { XCTAssertEqual($0 as? LayeredReadFailure, .notLayered) }
        var truncated = Data([0x38, 0x42, 0x50, 0x53, 0, 1])
        truncated += Data(repeating: 0, count: 8)
        XCTAssertThrowsError(try PSDReader.read(truncated))
        XCTAssertTrue(PSDReader.isPSD(Data([0x38, 0x42, 0x50, 0x53])))
    }
}
