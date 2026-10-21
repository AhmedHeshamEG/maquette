import Foundation

/// A layered Photoshop file (G1, for illustrators: Lina's posed mannequin and its light as layers to draw over in
/// Procreate). RGB, 8 bits, each layer cropped to what it shows with its own transparency, its name in Unicode, and the
/// flattened picture after them for apps that only read that. Procreate, Photoshop and Affinity open it.
public enum PSDWriter {
    public static func data(_ image: LayeredImage) -> Data {
        var out = Data()
        out.append(contentsOf: Array("8BPS".utf8))
        out.bigEndian16(1)
        out.append(contentsOf: [UInt8](repeating: 0, count: 6))
        out.bigEndian16(3)
        out.bigEndian32(UInt32(image.height))
        out.bigEndian32(UInt32(image.width))
        out.bigEndian16(8)
        out.bigEndian16(3)
        out.bigEndian32(0)
        out.bigEndian32(0)
        let layers = layerInfo(image)
        out.bigEndian32(UInt32(layers.count + 4 + 4))
        out.bigEndian32(UInt32(layers.count))
        out.append(layers)
        out.bigEndian32(0)
        // The flattened picture over white, plain (no compression), one channel after another.
        let flat = image.flattened()
        out.bigEndian16(0)
        for channel in 0 ..< 3 {
            var plane = [UInt8](repeating: 255, count: image.width * image.height)
            for index in plane.indices {
                let alpha = Double(flat.pixels[index * 4 + 3]) / 255
                plane[index] = UInt8((Double(flat.pixels[index * 4 + channel]) * alpha + 255 * (1 - alpha)).rounded())
            }
            out.append(contentsOf: plane)
        }
        return out
    }

    /// The layer records (bottom first) and then each layer's channels, padded to an even length.
    static func layerInfo(_ image: LayeredImage) -> Data {
        var records = Data(), channels = Data()
        records.bigEndianSigned16(Int16(image.layers.count))
        for layer in image.layers {
            let box = layer.visibleBounds ?? (0, 0, 0, 0)
            let top = layer.y + box.y, left = layer.x + box.x
            records.bigEndianSigned32(Int32(top))
            records.bigEndianSigned32(Int32(left))
            records.bigEndianSigned32(Int32(top + box.height))
            records.bigEndianSigned32(Int32(left + box.width))
            records.bigEndian16(4)
            let planes = [3, 0, 1, 2].map { channel -> Data in
                var data = Data()
                data.bigEndian16(0)
                for row in box.y ..< box.y + box.height {
                    for column in box.x ..< box.x + box.width {
                        data.append(layer.image.pixels[(row * layer.image.width + column) * 4 + channel])
                    }
                }
                return data
            }
            for (id, plane) in zip([Int16(-1), 0, 1, 2], planes) {
                records.bigEndianSigned16(id)
                records.bigEndian32(UInt32(plane.count))
                channels.append(plane)
            }
            records.append(contentsOf: Array("8BIMnorm".utf8))
            records.append(UInt8((min(max(layer.opacity, 0), 1) * 255).rounded()))
            records.append(0)
            records.append(layer.hidden ? 2 : 0)
            records.append(0)
            let extra = extraData(name: layer.name)
            records.bigEndian32(UInt32(extra.count))
            records.append(extra)
        }
        var info = records + channels
        if info.count % 2 == 1 { info.append(0) }
        return info
    }

    /// No mask, no blending ranges, the name as a Pascal string (padded to four) and again in Unicode (`luni`).
    static func extraData(name: String) -> Data {
        var data = Data()
        data.bigEndian32(0)
        data.bigEndian32(0)
        let ascii = Array(name.unicodeScalars.map { $0.value < 128 ? UInt8($0.value) : UInt8(ascii: "?") }.prefix(255))
        var pascal = [UInt8(ascii.count)] + ascii
        while pascal.count % 4 != 0 {
            pascal.append(0)
        }
        data.append(contentsOf: pascal)
        let units = Array(name.utf16)
        var unicode = Data()
        unicode.bigEndian32(UInt32(units.count))
        for unit in units {
            unicode.bigEndian16(unit)
        }
        if unicode.count % 2 == 1 { unicode.append(0) }
        data.append(contentsOf: Array("8BIMluni".utf8))
        data.bigEndian32(UInt32(unicode.count))
        data.append(unicode)
        return data
    }
}

/// A rendered frame split into layers by what each pixel shows (G1): the background, then a layer a thing, named after
/// it, from the frame's colour and its id picture (each pixel's thing, 0 for none).
public enum LayeredPicture {
    public static func split(colour: RGBAImage, ids: [UInt32], names: [UInt32: String]) -> LayeredImage {
        let width = colour.width, height = colour.height
        var pictures: [UInt32: RGBAImage] = [:]
        var order: [UInt32] = [0]
        for index in 0 ..< min(ids.count, width * height) {
            let id = names[ids[index]] == nil ? 0 : ids[index]
            if pictures[id] == nil {
                pictures[id] = .clear(width: width, height: height)
                if id != 0 { order.append(id) }
            }
            for channel in 0 ..< 4 {
                pictures[id]?.pixels[index * 4 + channel] = colour.pixels[index * 4 + channel]
            }
        }
        let layers = order.compactMap { id -> LayeredImage.Layer? in
            guard let picture = pictures[id] else { return nil }
            return LayeredImage.Layer(name: id == 0 ? "Background" : names[id] ?? "Thing", x: 0, y: 0, image: picture)
        }
        return LayeredImage(width: width, height: height, layers: layers)
    }
}

extension Data {
    mutating func bigEndian16(_ value: UInt16) {
        append(contentsOf: [UInt8(value >> 8), UInt8(value & 0xFF)])
    }

    mutating func bigEndianSigned16(_ value: Int16) { bigEndian16(UInt16(bitPattern: value)) }

    mutating func bigEndian32(_ value: UInt32) {
        append(contentsOf: [UInt8(value >> 24), UInt8(value >> 16 & 0xFF), UInt8(value >> 8 & 0xFF), UInt8(value & 0xFF)])
    }

    mutating func bigEndianSigned32(_ value: Int32) { bigEndian32(UInt32(bitPattern: value)) }
}
