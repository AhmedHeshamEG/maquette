import Foundation

public extension PropertyKey {
    /// How many times the shape is smoothed (Catmull–Clark, 0…3; missing = 0): the Smooth switch.
    static let subdivision: PropertyKey = "subdivision"
    /// Edges sharper than this many degrees stay crisp, softer ones are shaded smooth (missing = every edge crisp on a
    /// modelled shape, the Look's shading elsewhere).
    static let smoothAngle: PropertyKey = "smoothAngle"
    /// A whole-shape bend: "bend", "twist", "taper" or "bulge" (missing = none).
    static let deform: PropertyKey = "deform"
    /// How much: degrees for bend and twist, the change in size at the far end for taper, in the middle for bulge.
    static let deformAmount: PropertyKey = "deformAmount"
    /// The axis it bends along, in the thing's own space: "x", "y" or "z" (missing = y).
    static let deformAxis: PropertyKey = "deformAxis"
    /// Linked copies share a shape: things with the same link change together.
    static let linked: PropertyKey = "linked"
}

extension PropertySpec {
    static let shaping: [PropertyKey: PropertySpec] = [
        .subdivision: PropertySpec(type: .int, animatable: false, label: "Smooth"),
        .smoothAngle: PropertySpec(type: .float, animatable: false, label: "Smooth angle"),
        .deform: PropertySpec(type: .enumeration, animatable: false, label: "Bend"),
        .deformAmount: PropertySpec(type: .float, animatable: true, label: "Bend amount"),
        .deformAxis: PropertySpec(type: .enumeration, animatable: false, label: "Bend axis"),
        .linked: PropertySpec(type: .string, animatable: false, label: "Linked copy")
    ]
}

/// What's done to a shape after it's built and before it's shown: a cage of points pulled into a new shape, and
/// surface brushes (grab, smooth, inflate). The whole-shape bends are properties (they animate); these are edits.
public struct ObjectShaping: Codable, Hashable, Sendable {
    public var cage: DeformCage?
    public var sculpt: SculptLayer?

    public init(cage: DeformCage? = nil, sculpt: SculptLayer? = nil) {
        self.cage = cage
        self.sculpt = sculpt
    }

    public var isEmpty: Bool { cage == nil && sculpt == nil }
}

/// A box of points around a shape (2 to 4 each way); pulling a point pulls the shape near it, smoothly.
public struct DeformCage: Codable, Hashable, Sendable {
    /// Points along x, y and z.
    public var counts: [Int]
    /// The box the points stand on at rest (the shape's own space, a little larger than the shape).
    public var bounds: Bounds
    /// How far each point has been pulled from its rest place, x fastest, then y, then z.
    public var offsets: [Vec3]

    public static let countRange = 2 ... 4

    public init(counts: [Int], bounds: Bounds, offsets: [Vec3]? = nil) {
        let clamped = (0 ..< 3).map { axis in
            min(max(axis < counts.count ? counts[axis] : 2, Self.countRange.lowerBound), Self.countRange.upperBound)
        }
        self.counts = clamped
        self.bounds = bounds
        let total = clamped.reduce(1, *)
        self.offsets = offsets.flatMap { $0.count == total ? $0 : nil } ?? Array(repeating: .zero, count: total)
    }

    /// A cage around bounds, padded by 5 % so points sit just off the surface.
    public static func around(_ bounds: Bounds, counts: [Int] = [3, 3, 3]) -> DeformCage {
        let pad = Vec3.max(bounds.size * 0.05, Vec3(1e-4, 1e-4, 1e-4))
        return DeformCage(counts: counts, bounds: Bounds(min: bounds.min - pad, max: bounds.max + pad))
    }

    public func index(_ i: Int, _ j: Int, _ k: Int) -> Int { i + counts[0] * (j + counts[1] * k) }

    /// A point's rest place.
    public func restPoint(_ i: Int, _ j: Int, _ k: Int) -> Vec3 {
        let size = bounds.size
        return bounds.min + Vec3(size.x * Double(i) / Double(counts[0] - 1), size.y * Double(j) / Double(counts[1] - 1),
                                 size.z * Double(k) / Double(counts[2] - 1))
    }

    /// Every point where it is now, in order.
    public var points: [Vec3] {
        var result: [Vec3] = []
        for k in 0 ..< counts[2] {
            for j in 0 ..< counts[1] {
                for i in 0 ..< counts[0] {
                    result.append(restPoint(i, j, k) + offsets[index(i, j, k)])
                }
            }
        }
        return result
    }

    public var isAtRest: Bool { offsets.allSatisfy { $0 == .zero } }
}

/// Surface brush strokes: how far each moved corner of the shown surface has gone. Only moved corners are kept, so a
/// touch-up stays small; stored as base64 (Int32 corner, Float32 x, y, z), little-endian.
public struct SculptLayer: Hashable, Sendable {
    /// Corners of the surface it was made for: a shape changed since (more or fewer corners) leaves the strokes behind.
    public let vertexCount: Int
    public let moved: [Int: SIMD3<Float>]
    /// A fingerprint of the content, so caches can key on it every frame without walking it.
    public let fingerprint: UInt64

    public init(vertexCount: Int, moved: [Int: SIMD3<Float>]) {
        self.vertexCount = vertexCount
        self.moved = moved.filter { $0.key >= 0 && $0.key < vertexCount && $0.value != .zero }
        fingerprint = BrushKey.fnv(Self.pack(self.moved))
    }

    /// From an offset per corner (zeros dropped).
    public init(offsets: [SIMD3<Float>]) {
        var moved: [Int: SIMD3<Float>] = [:]
        for (corner, offset) in offsets.enumerated() where simd_length_squared3(offset) > 1e-14 {
            moved[corner] = offset
        }
        self.init(vertexCount: offsets.count, moved: moved)
    }

    /// An offset per corner.
    public var offsets: [SIMD3<Float>] {
        var result = Array(repeating: SIMD3<Float>(0, 0, 0), count: vertexCount)
        for (corner, offset) in moved { result[corner] = offset }
        return result
    }

    public static func == (lhs: SculptLayer, rhs: SculptLayer) -> Bool {
        lhs.fingerprint == rhs.fingerprint && lhs.vertexCount == rhs.vertexCount && lhs.moved == rhs.moved
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(fingerprint)
        hasher.combine(vertexCount)
    }

    static func pack(_ moved: [Int: SIMD3<Float>]) -> Data {
        var data = Data(capacity: moved.count * 16)
        for corner in moved.keys.sorted() {
            guard let offset = moved[corner] else { continue }
            withUnsafeBytes(of: Int32(corner).littleEndian) { data.append(contentsOf: $0) }
            for value in [offset.x, offset.y, offset.z] {
                withUnsafeBytes(of: value.bitPattern.littleEndian) { data.append(contentsOf: $0) }
            }
        }
        return data
    }

    static func unpack(_ data: Data) -> [Int: SIMD3<Float>] {
        var result: [Int: SIMD3<Float>] = [:]
        data.withUnsafeBytes { raw in
            for entry in 0 ..< data.count / 16 {
                let base = entry * 16
                let corner = Int(Int32(littleEndian: raw.loadUnaligned(fromByteOffset: base, as: Int32.self)))
                let values = (0 ..< 3).map { component in
                    Float(bitPattern: UInt32(littleEndian: raw.loadUnaligned(fromByteOffset: base + 4 + component * 4, as: UInt32.self)))
                }
                result[corner] = SIMD3<Float>(values[0], values[1], values[2])
            }
        }
        return result
    }
}

extension SculptLayer: Codable {
    private enum Key: String, CodingKey { case vertexCount, moved }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: Key.self)
        let text = try container.decode(String.self, forKey: .moved)
        guard let data = Data(base64Encoded: text) else {
            throw DecodingError.dataCorruptedError(forKey: .moved, in: container, debugDescription: "Strokes aren't base64")
        }
        try self.init(vertexCount: container.decode(Int.self, forKey: .vertexCount), moved: Self.unpack(data))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: Key.self)
        try container.encode(vertexCount, forKey: .vertexCount)
        try container.encode(Self.pack(moved).base64EncodedString(), forKey: .moved)
    }
}
