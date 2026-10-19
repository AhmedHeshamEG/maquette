import Foundation

/// A drawing in layers, as Photoshop or Procreate saved it (L2, "Bring your drawing"): the canvas and each layer's
/// picture where it sits on it, bottom layer first. Groups are kept as a path of names on each layer.
public struct LayeredImage: Sendable {
    public struct Layer: Sendable {
        public var name: String
        /// The picture's top left on the canvas, in pixels (it may reach outside the canvas).
        public var x: Int
        public var y: Int
        public var image: RGBAImage
        public var opacity: Double
        public var hidden: Bool
        /// How the layer mixed in the app it came from (normal, multiply…); the diorama can't mix, so it's only named.
        public var blend: LayerBlend
        /// The groups it sits in, outermost first.
        public var groups: [String]

        public init(name: String, x: Int, y: Int, image: RGBAImage, opacity: Double = 1, hidden: Bool = false, blend: LayerBlend = .normal,
                    groups: [String] = []) {
            self.name = name
            self.x = x
            self.y = y
            self.image = image
            self.opacity = opacity
            self.hidden = hidden
            self.blend = blend
            self.groups = groups
        }

        /// The smallest box holding every pixel that shows (nil: the layer is empty), in the layer's own pixels.
        public var visibleBounds: (x: Int, y: Int, width: Int, height: Int)? {
            var minX = image.width, minY = image.height, maxX = -1, maxY = -1
            for row in 0 ..< image.height {
                for column in 0 ..< image.width where image.pixels[(row * image.width + column) * 4 + 3] > 0 {
                    minX = min(minX, column)
                    maxX = max(maxX, column)
                    minY = min(minY, row)
                    maxY = max(maxY, row)
                }
            }
            return maxX < 0 ? nil : (minX, minY, maxX - minX + 1, maxY - minY + 1)
        }
    }

    public var width: Int
    public var height: Int
    /// Bottom first.
    public var layers: [Layer]
    /// What couldn't come in as a picture, counted by what it was ("adjustment layer"), so the app can say so.
    public var skipped: [String: Int]

    public init(width: Int, height: Int, layers: [Layer], skipped: [String: Int] = [:]) {
        self.width = width
        self.height = height
        self.layers = layers
        self.skipped = skipped
    }

    /// The visible layers laid over each other (normal mixing, each layer's opacity), the canvas transparent.
    public func flattened() -> RGBAImage {
        var result = RGBAImage.clear(width: width, height: height)
        for layer in layers where !layer.hidden {
            for row in 0 ..< layer.image.height {
                let y = layer.y + row
                guard y >= 0, y < height else { continue }
                for column in 0 ..< layer.image.width {
                    let x = layer.x + column
                    guard x >= 0, x < width else { continue }
                    let from = (row * layer.image.width + column) * 4
                    let alpha = Double(layer.image.pixels[from + 3]) / 255 * layer.opacity
                    guard alpha > 0 else { continue }
                    let to = (y * width + x) * 4
                    let below = Double(result.pixels[to + 3]) / 255
                    let out = alpha + below * (1 - alpha)
                    for channel in 0 ..< 3 {
                        let source = Double(layer.image.pixels[from + channel]) / 255
                        let backdrop = Double(result.pixels[to + channel]) / 255
                        let value = (source * alpha + backdrop * below * (1 - alpha)) / max(out, 1e-6)
                        result.pixels[to + channel] = UInt8((min(max(value, 0), 1) * 255).rounded())
                    }
                    result.pixels[to + 3] = UInt8((min(max(out, 0), 1) * 255).rounded())
                }
            }
        }
        return result
    }
}

/// A layer's mixing in the app it came from, by name; what the diorama can't do is named, never guessed.
public enum LayerBlend: String, Sendable, CaseIterable {
    case normal, multiply, screen, overlay, add, darken, lighten, softLight, hardLight, colorDodge, colorBurn, difference, other
}

/// Big-endian bytes, read in order (Photoshop's files).
struct BigEndianReader {
    let bytes: [UInt8]
    var position = 0

    init(_ data: Data) {
        bytes = [UInt8](data)
    }

    var remaining: Int { bytes.count - position }

    mutating func skip(_ count: Int) throws(LayeredReadFailure) {
        guard count >= 0, position + count <= bytes.count else { throw .damaged("the file ends early") }
        position += count
    }

    /// Reads a four-byte length and skips that many bytes.
    mutating func skipBlock() throws(LayeredReadFailure) {
        let length = try u32()
        try skip(length)
    }

    mutating func u8() throws(LayeredReadFailure) -> Int {
        guard position < bytes.count else { throw .damaged("the file ends early") }
        defer { position += 1 }
        return Int(bytes[position])
    }

    mutating func u16() throws(LayeredReadFailure) -> Int {
        try u8() << 8 | u8()
    }

    mutating func i16() throws(LayeredReadFailure) -> Int {
        try Int(Int16(truncatingIfNeeded: u16()))
    }

    mutating func u32() throws(LayeredReadFailure) -> Int {
        try u16() << 16 | u16()
    }

    mutating func i32() throws(LayeredReadFailure) -> Int {
        try Int(Int32(truncatingIfNeeded: u32()))
    }

    mutating func u64() throws(LayeredReadFailure) -> Int {
        let high = try u32()
        let low = try u32()
        guard high < 1 << 30 else { throw .damaged("a length is too large") }
        return high << 32 | low
    }

    mutating func ascii(_ count: Int) throws(LayeredReadFailure) -> String {
        guard position + count <= bytes.count else { throw .damaged("the file ends early") }
        defer { position += count }
        return String(decoding: bytes[position ..< position + count], as: UTF8.self)
    }

    mutating func slice(_ count: Int) throws(LayeredReadFailure) -> ArraySlice<UInt8> {
        guard count >= 0, position + count <= bytes.count else { throw .damaged("the file ends early") }
        defer { position += count }
        return bytes[position ..< position + count]
    }

    func peekASCII(_ count: Int) -> String? {
        guard position + count <= bytes.count else { return nil }
        return String(decoding: bytes[position ..< position + count], as: UTF8.self)
    }
}

/// Why a layered file couldn't be read, in words for the person.
public enum LayeredReadFailure: Error, Equatable, CustomStringConvertible {
    case notLayered
    case unsupported(String)
    case damaged(String)

    public var description: String {
        switch self {
        case .notLayered: "That isn't a Photoshop or Procreate file"
        case let .unsupported(what): "Maquette can't read \(what) yet"
        case let .damaged(why): "The file is damaged (\(why))"
        }
    }
}
