import Foundation

/// Procreate's own `.procreate` files read directly (L2 SPIKE, D-488): a zip of the document's keyed archive and each
/// layer's pixels in square tiles. Tiles are premultiplied RGBA, stored bottom row first; the canvas is then turned the
/// way it was held (`orientation`) and mirrored if it was flipped. A layer's mask fades it; groups are kept as names.
/// Checked against Procreate's own files and their thumbnails (the fixtures).
public enum ProcreateReader {
    public static let fileExtension = "procreate"

    public static func read(_ data: Data) throws(LayeredReadFailure) -> LayeredImage {
        let entries: [String: Data]
        do {
            entries = try Dictionary(ZipReader.entries(data) { !$0.hasPrefix("video/") }.map { ($0.name, $0.data) },
                                     uniquingKeysWith: { first, _ in first })
        } catch {
            throw .notLayered
        }
        guard let archiveData = entries["Document.archive"] else { throw .notLayered }
        let archive: KeyedArchive
        do {
            archive = try KeyedArchive(BinaryPlist.read(archiveData))
        } catch {
            throw .damaged("the document")
        }
        let canvas = try Canvas(archive)
        var tiles: [String: [String]] = [:]
        for name in entries.keys {
            let parts = name.split(separator: "/")
            if parts.count == 2 { tiles[String(parts[0]), default: []].append(String(parts[1])) }
        }
        let groups = groupPaths(archive)
        var layers: [LayeredImage.Layer] = []
        for object in archive.items(of: archive.root["layers"].flatMap(archive.resolve)).reversed() {
            guard let uuid = archive.value("UUID", in: object)?.string else { continue }
            var pixels = try canvas.raw(uuid, tiles: tiles[uuid] ?? [], entries: entries)
            if let mask = archive.value("mask", in: object), mask != .null, let maskID = archive.value("UUID", in: mask)?.string {
                // A mask is one grey byte a pixel; where it has no tile it was never painted, so it shows everything.
                let fade = try canvas.raw(maskID, tiles: tiles[maskID] ?? [], entries: entries, channels: 1, fill: 255)
                for index in stride(from: 0, to: pixels.count, by: 4) {
                    let keep = Int(fade[index / 4])
                    for channel in 0 ..< 4 {
                        pixels[index + channel] = UInt8(Int(pixels[index + channel]) * keep / 255)
                    }
                }
            }
            let picture = canvas.upright(canvas.straight(pixels))
            var layer = LayeredImage.Layer(name: archive.value("name", in: object)?.string ?? "Layer", x: 0, y: 0, image: picture,
                                           opacity: archive.value("opacity", in: object)?.double ?? 1,
                                           hidden: archive.value("hidden", in: object)?.bool ?? false,
                                           blend: blend(archive.value("extendedBlend", in: object)?.double ?? archive.value("blend", in: object)?.double),
                                           groups: groups[uuid]?.names ?? [])
            if groups[uuid]?.hidden == true { layer.hidden = true }
            guard let crop = trimmed(layer) else { continue }
            layers.append(crop)
        }
        return LayeredImage(width: canvas.shownWidth, height: canvas.shownHeight, layers: layers)
    }

    /// The canvas as stored, and how it's shown.
    struct Canvas {
        var width: Int
        var height: Int
        var tile: Int
        var orientation: Int
        var flippedH: Bool
        var flippedV: Bool

        init(_ archive: KeyedArchive) throws(LayeredReadFailure) {
            let size = (archive.string("size") ?? "").split { !$0.isNumber }.compactMap { Int($0) }
            guard size.count == 2, size[0] > 0, size[1] > 0, size[0] <= 20000, size[1] <= 20000 else { throw .damaged("the canvas size") }
            width = size[0]
            height = size[1]
            tile = Int(archive.double("tileSize") ?? 256)
            guard tile > 0, tile <= 4096 else { throw .damaged("the tile size") }
            orientation = Int(archive.double("orientation") ?? 1)
            flippedH = archive.bool("flippedHorizontally") ?? false
            flippedV = archive.bool("flippedVertically") ?? false
        }

        /// Held sideways, the shown picture's sides swap.
        var turned: Bool { orientation == 3 || orientation == 4 }
        var shownWidth: Int { turned ? height : width }
        var shownHeight: Int { turned ? width : height }

        /// A layer's tiles laid out as stored (premultiplied RGBA, or one grey byte for a mask; rows as stored).
        func raw(_ uuid: String, tiles names: [String], entries: [String: Data], channels: Int = 4,
                 fill: UInt8 = 0) throws(LayeredReadFailure) -> [UInt8] {
            var pixels = [UInt8](repeating: fill, count: width * height * channels)
            let columns = (width + tile - 1) / tile
            let rows = (height + tile - 1) / tile
            for name in names {
                let stem = name.split(separator: ".").first.map(String.init) ?? ""
                let place = stem.split(separator: "~").compactMap { Int($0) }
                guard place.count == 2, place[0] < columns, place[1] < rows, let data = entries["\(uuid)/\(name)"] else { continue }
                let tileWidth = min(tile, width - place[0] * tile)
                let tileHeight = min(tile, height - place[1] * tile)
                let expected = tileWidth * tileHeight * channels
                let bytes = name.hasSuffix(".chunk") ? try TileCompression.lzo1x(data, expected: expected)
                    : try TileCompression.appleLZ4(data, expected: expected)
                guard bytes.count >= expected else { throw .damaged("a tile's size") }
                let rowBytes = tileWidth * channels
                for row in 0 ..< tileHeight {
                    let to = ((place[1] * tile + row) * width + place[0] * tile) * channels
                    pixels.replaceSubrange(to ..< to + rowBytes, with: bytes[row * rowBytes ..< (row + 1) * rowBytes])
                }
            }
            return pixels
        }

        /// Premultiplied to straight alpha.
        func straight(_ pixels: [UInt8]) -> [UInt8] {
            var result = pixels
            for index in stride(from: 0, to: result.count, by: 4) {
                let alpha = Int(result[index + 3])
                guard alpha > 0, alpha < 255 else { continue }
                for channel in 0 ..< 3 {
                    result[index + channel] = UInt8(min(Int(result[index + channel]) * 255 / alpha, 255))
                }
            }
            return result
        }

        /// The stored picture the way it was drawn: rows bottom first, then turned as the iPad was held (3 a quarter
        /// turn one way, 4 the other, 2 upside down) and mirrored if the canvas was flipped.
        func upright(_ pixels: [UInt8]) -> RGBAImage {
            let outWidth = shownWidth, outHeight = shownHeight
            var result = [UInt8](repeating: 0, count: pixels.count)
            for y in 0 ..< height {
                for x in 0 ..< width {
                    // Flip the rows (bottom first), then turn.
                    let flippedY = height - 1 - y
                    var (sx, sy): (Int, Int) = switch orientation {
                    case 3: (flippedY, width - 1 - x)
                    case 4: (height - 1 - flippedY, x)
                    case 2: (width - 1 - x, height - 1 - flippedY)
                    default: (x, flippedY)
                    }
                    if flippedH { sx = outWidth - 1 - sx }
                    if flippedV { sy = outHeight - 1 - sy }
                    let from = (y * width + x) * 4, to = (sy * outWidth + sx) * 4
                    result[to] = pixels[from]
                    result[to + 1] = pixels[from + 1]
                    result[to + 2] = pixels[from + 2]
                    result[to + 3] = pixels[from + 3]
                }
            }
            return RGBAImage(width: outWidth, height: outHeight, pixels: result)
        }
    }

    /// A whole-canvas layer cut to what shows (nil when nothing does).
    static func trimmed(_ layer: LayeredImage.Layer) -> LayeredImage.Layer? {
        guard let box = layer.visibleBounds else { return nil }
        var cut = RGBAImage.clear(width: box.width, height: box.height)
        cut.place(layer.image, x: -box.x, y: -box.y)
        var result = layer
        result.image = cut
        result.x = box.x
        result.y = box.y
        return result
    }

    /// Each layer's groups (outermost first) and whether a hidden group hides it, from the tree of layers.
    static func groupPaths(_ archive: KeyedArchive) -> [String: (names: [String], hidden: Bool)] {
        var paths: [String: (names: [String], hidden: Bool)] = [:]
        func walk(_ items: [PlistValue], names: [String], hidden: Bool) {
            for item in items {
                let className = archive.resolve(item["$class"])?["$classname"]?.string
                if className == "SilicaGroup" {
                    let name = archive.value("name", in: item)?.string ?? "Group"
                    let groupHidden = hidden || archive.value("isHidden", in: item)?.bool == true || archive.value("hidden", in: item)?.bool == true
                    walk(archive.items(of: archive.value("children", in: item)), names: names + [name], hidden: groupHidden)
                } else if let uuid = archive.value("UUID", in: item)?.string {
                    paths[uuid] = (names, hidden)
                }
            }
        }
        walk(archive.items(of: archive.root["unwrappedLayers"].flatMap(archive.resolve)), names: [], hidden: false)
        return paths
    }

    /// Procreate's mixing numbers (its `extendedBlend`).
    static func blend(_ value: Double?) -> LayerBlend {
        switch Int(value ?? 0) {
        case 0: .normal
        case 1: .multiply
        case 2: .screen
        case 3: .add
        case 4: .lighten
        case 6: .difference
        case 9: .colorDodge
        case 10: .colorBurn
        case 11: .overlay
        case 12: .hardLight
        case 17: .softLight
        case 19: .darken
        default: .other
        }
    }
}
