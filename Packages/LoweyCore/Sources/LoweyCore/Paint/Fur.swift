import Foundation

public extension PropertyKey {
    /// How long the fur is, in metres (missing or 0 = no fur).
    static let furLength: PropertyKey = "furLength"
    /// How thick it grows, 0 sparse … 1 dense (missing = 0.6).
    static let furDensity: PropertyKey = "furDensity"
    /// "shells" (soft fur, drawn as layers) or "cards" (hair cards: strips a game engine can draw) (missing = shells).
    static let furStyle: PropertyKey = "furStyle"
    /// How much it hangs under its own weight, 0 standing … 1 hanging (missing = 0.3).
    static let furDroop: PropertyKey = "furDroop"
}

extension PropertySpec {
    static let fur: [PropertyKey: PropertySpec] = [
        .furLength: PropertySpec(type: .float, animatable: true, label: "Fur length"),
        .furDensity: PropertySpec(type: .float, animatable: false, label: "Fur density"),
        .furStyle: PropertySpec(type: .enumeration, animatable: false, label: "Fur style"),
        .furDroop: PropertySpec(type: .float, animatable: true, label: "Fur droop")
    ]
}

/// Fur on a thing (D-355): stylised, smooth on every iPad. Shells draw the surface again a little further out each
/// time, keeping only the strands' cross-sections (soft fur, the stage and video); cards are strips standing on the
/// surface with strands drawn on them (what game engines draw). Its colour is the thing's paint; a Fur map painted on
/// it makes it longer where it's white and bare where it's black.
public struct FurSettings: Hashable, Sendable {
    public enum Style: String, Codable, Sendable, CaseIterable {
        case shells, cards

        public var title: String {
            switch self {
            case .shells: "Soft"
            case .cards: "Hair cards"
            }
        }
    }

    public var length: Double
    public var density: Double
    public var style: Style
    public var droop: Double

    public init(length: Double, density: Double = 0.6, style: Style = .shells, droop: Double = 0.3) {
        self.length = max(length, 0)
        self.density = min(max(density, 0), 1)
        self.style = style
        self.droop = min(max(droop, 0), 1)
    }

    /// The object's fur, or nil when it has none.
    public init?(_ object: SceneObject) {
        guard let length = object[.furLength]?.floatValue, length > 0 else { return nil }
        self.init(length: length, density: object[.furDensity]?.floatValue ?? 0.6,
                  style: object[.furStyle]?.stringValue.flatMap(Style.init(rawValue:)) ?? .shells, droop: object[.furDroop]?.floatValue ?? 0.3)
    }

    /// Strands across one metre of texture space (the shells' strand grid).
    public var strandsPerMetre: Double {
        120 + density * 680
    }

    /// Shells drawn on each tier (the stage); exports always draw `exportShells`.
    public static func shells(forTier tier: Int) -> Int {
        switch tier {
        case 0: 24
        case 1: 14
        default: 9
        }
    }

    public static let exportShells = 24
}

/// The meshes fur becomes in a 3D file and hair cards on the stage.
public enum FurGeometry {
    /// Hair cards: two crossed strips per tuft, standing on the surface, bending down by `droop`. Their uvs run 0…1
    /// across and up a strip (the strand picture: `strandPicture`). Seeded, so the same surface always grows the same
    /// tufts. `lengthAt` scales a tuft (the Fur map; 1 = full length, 0 = none).
    public static func cards(on mesh: MeshData, fur: FurSettings, seed: UInt32 = 1, limit: Int = 4000,
                             lengthAt: (SIMD2<Float>) -> Float = { _ in 1 }) -> MeshData {
        var result = MeshData()
        let area = surfaceArea(mesh)
        guard area > 0, fur.length > 0 else { return result }
        let length = Float(fur.length)
        let spacing = max(length * Float(0.35 - fur.density * 0.2), 1e-4)
        let count = min(Int(area / (spacing * spacing)), limit)
        var random = SeededGenerator(seed: UInt64(seed) &+ 0x9E37_79B9)
        let cumulative = cumulativeAreas(mesh)
        for _ in 0 ..< count {
            let target = Float.random(in: 0 ..< 1, using: &random) * area
            let face = cumulative.firstIndex { $0 >= target } ?? (mesh.triangleCount - 1)
            var u = Float.random(in: 0 ... 1, using: &random), v = Float.random(in: 0 ... 1, using: &random)
            if u + v > 1 { (u, v) = (1 - u, 1 - v) }
            let i = (Int(mesh.indices[face * 3]), Int(mesh.indices[face * 3 + 1]), Int(mesh.indices[face * 3 + 2]))
            let p = mesh.positions[i.0] * (1 - u - v) + mesh.positions[i.1] * u + mesh.positions[i.2] * v
            let uv = mesh.uvs.count == mesh.positions.count ? mesh.uvs[i.0] * (1 - u - v) + mesh.uvs[i.1] * u + mesh.uvs[i.2] * v : .zero
            let normal = normalize3(cross3(mesh.positions[i.1] - mesh.positions[i.0], mesh.positions[i.2] - mesh.positions[i.0]),
                                    fallback: SIMD3<Float>(0, 1, 0))
            let scale = min(max(lengthAt(uv), 0), 1)
            guard scale > 0.05 else { continue }
            let tuft = length * scale * Float.random(in: 0.75 ... 1.1, using: &random)
            let turn = Float.random(in: 0 ..< .pi, using: &random)
            let (t, b) = WearBake.basis(normal)
            let across = t * cos(turn) + b * sin(turn)
            for side in [across, cross3(normal, across)] {
                appendCard(&result, root: p, normal: normal, side: side, length: tuft, width: tuft * 0.45, droop: Float(fur.droop))
            }
        }
        return result
    }

    /// A strip from the root along the normal, bending toward −y as it goes, three segments long.
    static func appendCard(_ mesh: inout MeshData, root: SIMD3<Float>, normal: SIMD3<Float>, side: SIMD3<Float>, length: Float, width: Float,
                           droop: Float) {
        let base = UInt32(mesh.positions.count)
        let segments = 3
        let face = normalize3(cross3(side, normal), fallback: normal)
        for step in 0 ... segments {
            let t = Float(step) / Float(segments)
            let bend = SIMD3<Float>(0, -1, 0) * droop * t * t * length
            let centre = root + normal * (length * t) + bend
            for edge in [-0.5, 0.5] as [Float] {
                mesh.positions.append(centre + side * (width * edge * (1 - t * 0.6)))
                mesh.normals.append(face)
                mesh.uvs.append(SIMD2<Float>(edge + 0.5, 1 - t))
            }
        }
        for step in 0 ..< UInt32(segments) {
            let a = base + step * 2
            mesh.indices += [a, a + 1, a + 3, a, a + 3, a + 2]
            // Both faces, so a card reads from behind too.
            mesh.indices += [a, a + 3, a + 1, a, a + 2, a + 3]
        }
    }

    /// Fur shells for export: the surface pushed out along its normals, `count` times, each with uvs tiled over the
    /// strand picture (`strandPicture`) so only the strands' cross-sections show (alpha cut out).
    public static func shells(of mesh: MeshData, fur: FurSettings, count: Int = FurSettings.exportShells) -> [MeshData] {
        guard mesh.normals.count == mesh.positions.count, fur.length > 0 else { return [] }
        let repeats = Float(fur.strandsPerMetre * fur.length) / 8
        return (1 ... max(count, 1)).map { layer in
            let t = Float(layer) / Float(max(count, 1))
            var shell = mesh
            shell.positions = zip(mesh.positions, mesh.normals).map { p, n in
                p + n * (Float(fur.length) * t) + SIMD3<Float>(0, -1, 0) * (Float(fur.droop) * t * t * Float(fur.length) * 0.5)
            }
            shell.uvs = mesh.uvs.count == mesh.positions.count ? mesh.uvs.map { $0 * repeats } : mesh.positions.map { SIMD2<Float>($0.x, $0.z) * repeats }
            return shell
        }
    }

    /// The strands as a picture: tufts of soft dots, white with alpha (a shell keeps the dots; a card keeps strips).
    public static func strandPicture(size: Int = 128, cards: Bool) -> RGBAImage {
        var image = RGBAImage.clear(width: size, height: size)
        var random = SeededGenerator(seed: 7)
        let strands = cards ? 14 : 90
        for _ in 0 ..< strands {
            let cx = Float.random(in: 0 ..< 1, using: &random) * Float(size), cy = Float.random(in: 0 ..< 1, using: &random) * Float(size)
            let radius = Float(size) * (cards ? 0.025 : 0.04)
            for y in 0 ..< size {
                for x in 0 ..< size {
                    let dx = Float(x) + 0.5 - cx
                    let dy = cards ? 0 : Float(y) + 0.5 - cy
                    let distance = (dx * dx + dy * dy).squareRoot() / radius
                    guard distance < 1 else { continue }
                    let fade: Float = cards ? 1 - Float(y) / Float(size) * 0.3 : 1
                    let alpha = max(Float(image.pixels[(y * size + x) * 4 + 3]) / 255, (1 - distance) * fade)
                    image.setPixel(x, y, RGBA(1, 1, 1, Double(alpha)))
                }
            }
        }
        return image
    }

    static func surfaceArea(_ mesh: MeshData) -> Float {
        cumulativeAreas(mesh).last ?? 0
    }

    static func cumulativeAreas(_ mesh: MeshData) -> [Float] {
        var total: Float = 0
        return (0 ..< mesh.triangleCount).map { face in
            let a = mesh.positions[Int(mesh.indices[face * 3])], b = mesh.positions[Int(mesh.indices[face * 3 + 1])]
            let c = mesh.positions[Int(mesh.indices[face * 3 + 2])]
            total += length3(cross3(b - a, c - a)) / 2
            return total
        }
    }
}

/// A small seeded random source (SplitMix64), the same sequence on every device.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
