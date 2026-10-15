import Foundation

/// What a layer's tiles describe (D-338). Colour is the layer's own `tiles`; the others live in its `maps`. Value maps
/// (roughness, metal, bumps, fur) are grey, white = 1; glow is a colour; the mask's alpha is how much of the layer
/// shows. Where a map is clear, the thing's own value shows through.
public enum PaintMap: String, Codable, Sendable, CaseIterable {
    case color, roughness, metal, glow, bumps, fur, mask

    /// The maps paint is made of (everything but the mask), in the order the layers list shows them.
    public static let channels: [PaintMap] = [.color, .roughness, .metal, .glow, .bumps, .fur]

    public var title: String {
        switch self {
        case .color: "Colour"
        case .roughness: "Roughness"
        case .metal: "Metal"
        case .glow: "Glow"
        case .bumps: "Bumps"
        case .fur: "Fur"
        case .mask: "Mask"
        }
    }

    /// Whether its tiles hold one number (grey) rather than a colour.
    public var isValue: Bool {
        switch self {
        case .roughness, .metal, .bumps, .fur: true
        case .color, .glow, .mask: false
        }
    }

    /// The colour a stroke lays on this map for a value 0…1 (grey) or a colour (colour and glow).
    public func strokeColor(value: Double, color: RGBA) -> RGBA {
        switch self {
        case .color, .glow: RGBA(color.r, color.g, color.b, 1)
        case .roughness, .metal, .bumps, .fur, .mask: RGBA(value, value, value, 1)
        }
    }
}

/// What a fill layer is made of (D-340). Its tiles are made from it whenever it or the surface changes.
public enum PaintFill: Hashable, Sendable {
    /// One colour over the whole surface.
    case color(RGBA)
    /// A material, frozen into the project as it was when it was dropped (so the project carries it, as brushes).
    case material(PaintMaterial)
    /// Dirt in the creases or scuffs on the edges, from the shape's own bakes (D-345).
    case wear(PaintWear)

    public var title: String {
        switch self {
        case .color: "Colour fill"
        case let .material(material): material.name
        case let .wear(wear): wear.kind.title
        }
    }
}

extension PaintFill: Codable {
    private enum CodingKeys: String, CodingKey { case type, color, material, wear }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(String.self, forKey: .type) {
        case "color": self = try .color(c.decode(RGBA.self, forKey: .color))
        case "material": self = try .material(c.decode(PaintMaterial.self, forKey: .material))
        case "wear": self = try .wear(c.decode(PaintWear.self, forKey: .wear))
        case let other: throw DecodingError.dataCorruptedError(forKey: .type, in: c, debugDescription: "Unknown fill \(other)")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .color(color):
            try c.encode("color", forKey: .type)
            try c.encode(color, forKey: .color)
        case let .material(material):
            try c.encode("material", forKey: .type)
            try c.encode(material, forKey: .material)
        case let .wear(wear):
            try c.encode("wear", forKey: .type)
            try c.encode(wear, forKey: .wear)
        }
    }
}

/// Automatic wear (D-345): where it gathers, how much, its colour and how rough it is.
public struct PaintWear: Codable, Hashable, Sendable {
    public enum Kind: String, Codable, Sendable, CaseIterable {
        /// Dark grime in creases and hollows (ambient occlusion and concave edges).
        case dirt
        /// Paint rubbed off the sharp outer edges (convex edges).
        case edges

        public var title: String {
            switch self {
            case .dirt: "Dirt"
            case .edges: "Worn edges"
            }
        }

        public var defaultColor: RGBA {
            switch self {
            case .dirt: RGBA.hex("#3B2F25")
            case .edges: RGBA.hex("#D9D2C3")
            }
        }

        public var defaultRoughness: Double {
            switch self {
            case .dirt: 0.95
            case .edges: 0.35
            }
        }
    }

    public var kind: Kind
    /// 0 none … 1 a lot.
    public var amount: Double
    public var color: RGBA
    public var roughness: Double
    public var seed: UInt32

    public init(kind: Kind, amount: Double = 0.5, color: RGBA? = nil, roughness: Double? = nil, seed: UInt32 = 1) {
        self.kind = kind
        self.amount = min(max(amount, 0), 1)
        self.color = color ?? kind.defaultColor
        self.roughness = min(max(roughness ?? kind.defaultRoughness, 0), 1)
        self.seed = seed
    }
}

/// An edge marked as a seam: its two ends in the object's own space (metres).
public struct PaintSeam: Codable, Hashable, Sendable {
    public var a: Vec3
    public var b: Vec3

    public init(_ a: Vec3, _ b: Vec3) {
        // Stored in one order so the same edge marked from either end is one seam.
        if (a.x, a.y, a.z) <= (b.x, b.y, b.z) {
            self.a = a
            self.b = b
        } else {
            self.a = b
            self.b = a
        }
    }
}

/// The axis of the object's own space strokes are mirrored across (the plane through its origin square to it).
public enum PaintMirror: String, Codable, Sendable, CaseIterable {
    case x, y, z

    public var title: String {
        switch self {
        case .x: "Left and right"
        case .y: "Top and bottom"
        case .z: "Front and back"
        }
    }

    /// The scale that mirrors a point across it.
    public var scale: SIMD3<Float> {
        switch self {
        case .x: SIMD3<Float>(-1, 1, 1)
        case .y: SIMD3<Float>(1, -1, 1)
        case .z: SIMD3<Float>(1, 1, -1)
        }
    }
}
