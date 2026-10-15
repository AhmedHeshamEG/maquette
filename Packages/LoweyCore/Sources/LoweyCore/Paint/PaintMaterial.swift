import Foundation

/// A material (D-341): what a surface is made of, as numbers a person can push (two colours, roughness, metal, glow,
/// a pattern and its size, bumps), procedural so it has no seams and no resolution. Imported PBR sets carry pictures
/// instead of (or over) the pattern. Kept in the device's library and frozen into a project by the fill that uses it.
public struct PaintMaterial: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String
    /// The main colour and the pattern's second colour (sRGB).
    public var color: RGBA
    public var secondColor: RGBA
    public var roughness: Double
    public var metal: Double
    /// Glow colour; black is none.
    public var glow: RGBA
    public var pattern: MaterialPattern
    /// Metres the pattern repeats over (a plank's width, a brick's length, a grain's size).
    public var scale: Double
    /// How strongly the pattern shows: 0 is the main colour alone.
    public var variation: Double
    /// How deep the pattern's relief is: 0 flat … 1 deep.
    public var bumps: Double
    /// Pictures of an imported set (keys of files in the library's or the project's assets), laid over the pattern.
    public var pictures: MaterialPictures?
    public var author: String?
    public var licence: String?

    public init(id: String, name: String, color: RGBA, secondColor: RGBA? = nil, roughness: Double = 0.7, metal: Double = 0,
                glow: RGBA = .black, pattern: MaterialPattern = .none, scale: Double = 0.2, variation: Double = 0.5, bumps: Double = 0.3,
                pictures: MaterialPictures? = nil, author: String? = nil, licence: String? = nil) {
        self.id = id
        self.name = name
        self.color = color
        self.secondColor = secondColor ?? color
        self.roughness = min(max(roughness, 0), 1)
        self.metal = min(max(metal, 0), 1)
        self.glow = glow
        self.pattern = pattern
        self.scale = max(scale, 0.001)
        self.variation = min(max(variation, 0), 1)
        self.bumps = min(max(bumps, 0), 1)
        self.pictures = pictures
        self.author = author
        self.licence = licence
    }

    /// The maps a fill of this material writes: colour, roughness and metal always; glow when it glows; bumps when it
    /// has relief.
    public var maps: [PaintMap] {
        var maps: [PaintMap] = [.color, .roughness, .metal]
        if glow != .black || pictures?.glow != nil { maps.append(.glow) }
        if (bumps > 0 && pattern.hasRelief) || pictures?.height != nil { maps.append(.bumps) }
        return maps
    }
}

/// The pictures of an imported PBR set (D-344), each a key of a PNG. A set without a picture for a map uses the
/// material's own number for it.
public struct MaterialPictures: Codable, Hashable, Sendable {
    public var color: String?
    public var roughness: String?
    public var metal: String?
    public var height: String?
    public var normal: String?
    public var glow: String?
    public var occlusion: String?

    public init(color: String? = nil, roughness: String? = nil, metal: String? = nil, height: String? = nil, normal: String? = nil,
                glow: String? = nil, occlusion: String? = nil) {
        self.color = color
        self.roughness = roughness
        self.metal = metal
        self.height = height
        self.normal = normal
        self.glow = glow
        self.occlusion = occlusion
    }

    /// Every file it names.
    public var files: [String] {
        [color, roughness, metal, height, normal, glow, occlusion].compactMap(\.self)
    }
}

/// What a material looks like at one point of a surface.
public struct MaterialSample: Hashable, Sendable {
    /// sRGB 0…1.
    public var color: SIMD3<Float>
    public var roughness: Float
    public var metal: Float
    public var glow: SIMD3<Float>
    /// 0 low … 1 high; 0.5 is the surface itself.
    public var height: Float

    public init(color: SIMD3<Float>, roughness: Float, metal: Float, glow: SIMD3<Float> = .zero, height: Float = 0.5) {
        self.color = color
        self.roughness = roughness
        self.metal = metal
        self.glow = glow
        self.height = height
    }
}

/// The procedural patterns materials are made from.
public enum MaterialPattern: String, Codable, Sendable, CaseIterable {
    case none, noise, wood, planks, brushed, marble, stone, concrete, bricks, tiles, weave, leather, rust, sand

    public var title: String {
        switch self {
        case .none: "Plain"
        case .noise: "Mottled"
        case .wood: "Wood grain"
        case .planks: "Planks"
        case .brushed: "Brushed"
        case .marble: "Marble"
        case .stone: "Stone"
        case .concrete: "Concrete"
        case .bricks: "Bricks"
        case .tiles: "Tiles"
        case .weave: "Woven"
        case .leather: "Leather"
        case .rust: "Rust"
        case .sand: "Sand"
        }
    }

    /// Whether it has relief to raise as bumps.
    public var hasRelief: Bool {
        self != .none
    }
}

public extension PaintMaterial {
    /// The material at a point of a surface (object space, metres) facing `normal`.
    func sample(at position: SIMD3<Float>, normal: SIMD3<Float>, pictures: MaterialPictureSource? = nil) -> MaterialSample {
        let first = SIMD3<Float>(Float(color.r), Float(color.g), Float(color.b))
        let second = SIMD3<Float>(Float(secondColor.r), Float(secondColor.g), Float(secondColor.b))
        let shape = MaterialPatterns.evaluate(pattern, at: position / Float(scale), normal: normal)
        let amount = Float(variation)
        var result = MaterialSample(
            color: first + (second - first) * (shape.mix * amount),
            roughness: Float(roughness) + shape.roughness * amount,
            metal: Float(metal) * (1 - shape.dull * amount),
            glow: SIMD3<Float>(Float(glow.r), Float(glow.g), Float(glow.b)),
            height: 0.5 + (shape.height - 0.5) * Float(bumps)
        )
        if let pictures, let set = self.pictures {
            pictures.apply(set, at: position / Float(scale), normal: normal, to: &result, bumps: Float(bumps))
        }
        result.roughness = min(max(result.roughness, 0), 1)
        result.metal = min(max(result.metal, 0), 1)
        result.height = min(max(result.height, 0), 1)
        result.color = result.color.clamped(lowerBound: .zero, upperBound: SIMD3<Float>(repeating: 1))
        return result
    }
}

/// Decoded pictures of imported sets, sampled with triplanar projection (no unwrap needed, no seams).
public struct MaterialPictureSource: Sendable {
    public var images: [String: RGBAImage]

    public init(images: [String: RGBAImage]) {
        self.images = images
    }

    func apply(_ set: MaterialPictures, at point: SIMD3<Float>, normal: SIMD3<Float>, to sample: inout MaterialSample, bumps: Float) {
        if let color = set.color.flatMap({ images[$0] }) { sample.color = Self.triplanar(color, point, normal).rgb }
        if let rough = set.roughness.flatMap({ images[$0] }) { sample.roughness = Self.triplanar(rough, point, normal).rgb.x }
        if let metal = set.metal.flatMap({ images[$0] }) { sample.metal = Self.triplanar(metal, point, normal).rgb.x }
        if let glow = set.glow.flatMap({ images[$0] }) { sample.glow = Self.triplanar(glow, point, normal).rgb }
        if let height = set.height.flatMap({ images[$0] }) { sample.height = 0.5 + (Self.triplanar(height, point, normal).rgb.x - 0.5) * bumps * 2 }
        if let occlusion = set.occlusion.flatMap({ images[$0] }) { sample.color *= Self.triplanar(occlusion, point, normal).rgb.x }
    }

    /// The picture laid on the three planes of the object's space, blended by how the surface faces each.
    static func triplanar(_ image: RGBAImage, _ p: SIMD3<Float>, _ n: SIMD3<Float>) -> (rgb: SIMD3<Float>, a: Float) {
        var weights = pointwiseMax(n, -n)
        weights = weights * weights * weights * weights
        weights /= max(weights.x + weights.y + weights.z, 1e-6)
        var sum = SIMD4<Float>.zero
        for (weight, uv) in [(weights.x, SIMD2<Float>(p.z, -p.y)), (weights.y, SIMD2<Float>(p.x, p.z)), (weights.z, SIMD2<Float>(p.x, -p.y))]
            where weight > 0.001 {
            let wrapped = uv - uv.rounded(.down)
            let c = image.sample(u: Double(wrapped.x), v: Double(wrapped.y))
            sum += SIMD4<Float>(Float(c.r), Float(c.g), Float(c.b), Float(c.a)) * weight
        }
        return (SIMD3<Float>(sum.x, sum.y, sum.z), sum.w)
    }
}
