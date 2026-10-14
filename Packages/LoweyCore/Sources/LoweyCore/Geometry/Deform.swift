import Foundation

/// Whole-shape bends: one number each, measured along an axis of the thing's own box, so a tower twists from its
/// foot, a tail bends from its root, a vase tapers and a barrel bulges. They move corners only (the surface keeps its
/// cuts), so paint, rigs and the cage still find their corners.
public enum Deform: String, Codable, Sendable, CaseIterable {
    case bend, twist, taper, bulge

    public var title: String {
        switch self {
        case .bend: "Bend"
        case .twist: "Twist"
        case .taper: "Taper"
        case .bulge: "Bulge"
        }
    }

    /// The amount's range: degrees for bend and twist, a change in size for taper and bulge.
    public var range: ClosedRange<Double> {
        switch self {
        case .bend: -360 ... 360
        case .twist: -720 ... 720
        case .taper: -1 ... 3
        case .bulge: -1 ... 2
        }
    }

    /// The amount a fresh bend starts with (enough to see it).
    public var starting: Double {
        switch self {
        case .bend: 45
        case .twist: 90
        case .taper: -0.5
        case .bulge: 0.3
        }
    }

    /// The object's bend, when it has one that does something.
    public static func of(_ object: SceneObject) -> (kind: Deform, amount: Double, axis: Axis)? {
        guard let kind = object[.deform]?.stringValue.flatMap(Deform.init(rawValue:)),
              let amount = object[.deformAmount]?.floatValue, abs(amount) > 1e-9 else { return nil }
        let axis = object[.deformAxis]?.stringValue.flatMap(Axis.init(rawValue:)) ?? .y
        return (kind, amount, axis)
    }

    /// The positions bent (object space), measured over `bounds` (the undeformed shape's box).
    public func apply(_ positions: [SIMD3<Float>], amount: Double, axis: Axis, bounds: Bounds) -> [SIMD3<Float>] {
        // The axis it runs along, then the two across it in turn (y: z then x).
        let along = axis.index, side = (along + 1) % 3, across = (along + 2) % 3
        let low = bounds.min[axis], length = max(bounds.size[axis], 1e-9)
        let centre = SIMD3<Double>(bounds.center.x, bounds.center.y, bounds.center.z)
        return positions.map { point in
            let p = SIMD3<Double>(Double(point.x), Double(point.y), Double(point.z))
            let t = (p[along] - low) / length
            var q = p
            switch self {
            case .bend:
                // Around a circle whose radius makes the whole length turn by `amount` degrees, toward the side axis.
                let angle = amount * .pi / 180
                let radius = length / angle
                let offset = p[side] - centre[side]
                q[along] = low + (radius - offset) * sin(t * angle)
                q[side] = centre[side] + radius - (radius - offset) * cos(t * angle)
            case .twist:
                let angle = amount * .pi / 180 * t
                let a = p[side] - centre[side], b = p[across] - centre[across]
                q[side] = centre[side] + a * cos(angle) - b * sin(angle)
                q[across] = centre[across] + a * sin(angle) + b * cos(angle)
            case .taper, .bulge:
                let scale = self == .taper ? 1 + amount * t : 1 + amount * sin(.pi * min(max(t, 0), 1))
                q[side] = centre[side] + (p[side] - centre[side]) * scale
                q[across] = centre[across] + (p[across] - centre[across]) * scale
            }
            return SIMD3<Float>(Float(q.x), Float(q.y), Float(q.z))
        }
    }
}

public extension Axis {
    /// Its place in a SIMD3.
    var index: Int {
        switch self {
        case .x: 0
        case .y: 1
        case .z: 2
        }
    }
}

/// Free-form deformation through a cage: each corner is a blend of the cage's points (Bernstein weights over the box),
/// so a cage at rest leaves the shape exactly as it was.
public enum CageDeform {
    public static func apply(_ cage: DeformCage, to positions: [SIMD3<Float>]) -> [SIMD3<Float>] {
        guard !cage.isAtRest else { return positions }
        let size = cage.bounds.size
        let points = cage.points
        let n = cage.counts
        return positions.map { point in
            let p = Vec3(Double(point.x), Double(point.y), Double(point.z))
            let local = Vec3((p.x - cage.bounds.min.x) / max(size.x, 1e-12), (p.y - cage.bounds.min.y) / max(size.y, 1e-12),
                             (p.z - cage.bounds.min.z) / max(size.z, 1e-12))
            // Points outside the cage follow its nearest face: the weights are taken at the clamped place, the rest
            // carried along unchanged.
            let clamped = local.map { min(max($0, 0), 1) }
            let outside = (local - clamped).scaled(by: size)
            let wx = bernstein(n[0] - 1, clamped.x), wy = bernstein(n[1] - 1, clamped.y), wz = bernstein(n[2] - 1, clamped.z)
            var result = Vec3.zero
            for k in 0 ..< n[2] {
                for j in 0 ..< n[1] {
                    let weight = wy[j] * wz[k]
                    guard weight > 0 else { continue }
                    for i in 0 ..< n[0] {
                        result += points[cage.index(i, j, k)] * (wx[i] * weight)
                    }
                }
            }
            result += outside
            return SIMD3<Float>(Float(result.x), Float(result.y), Float(result.z))
        }
    }

    /// The degree-`degree` Bernstein weights at t (they add up to one).
    static func bernstein(_ degree: Int, _ t: Double) -> [Double] {
        (0 ... degree).map { index in
            Double(binomial(degree, index)) * pow(t, Double(index)) * pow(1 - t, Double(degree - index))
        }
    }

    private static func binomial(_ n: Int, _ k: Int) -> Int {
        guard k >= 0, k <= n else { return 0 }
        var result = 1
        for step in 0 ..< k {
            result = result * (n - step) / (step + 1)
        }
        return result
    }
}
