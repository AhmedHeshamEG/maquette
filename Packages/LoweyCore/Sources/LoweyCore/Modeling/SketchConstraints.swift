import Foundation

/// A rule a sketch keeps while it changes: two lines stay parallel, a side stays 40 mm, this one stays twice that.
/// Curves are named by their place in `Sketch.curves`. Lengths are metres, angles degrees from the plane's first axis.
public enum SketchConstraint: Codable, Hashable, Sendable {
    case parallel(Int, Int)
    case perpendicular(Int, Int)
    /// Same length (lines, rectangle widths) or same radius (circles).
    case equal(Int, Int)
    /// A line touching a circle or an arc.
    case tangent(line: Int, circle: Int)
    /// A line's length, a circle's diameter, a rectangle's width (or its height with `side: 1`).
    case length(Int, Double, side: Int = 0)
    case angle(Int, Double)
    /// "This is twice that": the first's length is `factor` times the second's.
    case ratio(Int, Int, factor: Double)

    /// The curves it involves.
    public var curves: [Int] {
        switch self {
        case let .parallel(a, b), let .perpendicular(a, b), let .equal(a, b), let .ratio(a, b, _): [a, b]
        case let .tangent(line, circle): [line, circle]
        case let .length(a, _, _), let .angle(a, _): [a]
        }
    }

    /// The same rule after the curves were renumbered (nil when one of its curves is gone).
    public func renumbered(_ map: [Int: Int]) -> SketchConstraint? {
        let mapped = curves.compactMap { map[$0] }
        guard mapped.count == curves.count else { return nil }
        return replacing(mapped)
    }

    /// A locked length or angle on `curve` takes the value it has in `curves` now (the user typed it); other rules stay.
    func retaking(_ curve: Int, from curves: [SketchCurve]) -> SketchConstraint {
        let layout = Layout(curves)
        let p = layout.parameters(curves)
        switch self {
        case let .length(index, _, side) where index == curve:
            return layout.size(curve, p, side: side).map { .length(curve, $0, side: side) } ?? self
        case let .angle(index, _) where index == curve:
            guard let direction = layout.direction(curve, p) else { return self }
            return .angle(curve, atan2(direction.y, direction.x) * 180 / .pi)
        default:
            return self
        }
    }

    private func replacing(_ new: [Int]) -> SketchConstraint {
        switch self {
        case .parallel: .parallel(new[0], new[1])
        case .perpendicular: .perpendicular(new[0], new[1])
        case .equal: .equal(new[0], new[1])
        case .tangent: .tangent(line: new[0], circle: new[1])
        case let .length(_, value, side): .length(new[0], value, side: side)
        case let .angle(_, value): .angle(new[0], value)
        case let .ratio(_, _, factor): .ratio(new[0], new[1], factor: factor)
        }
    }
}

/// Our own 2D constraint solver: every line, rectangle, circle and arc of a sketch is a few numbers; each rule (and
/// every pair of ends that touched before) is a sum that should be zero; Levenberg–Marquardt finds the numbers nearest
/// the drawing that make them all zero. Splines and polylines hold still.
public enum SketchSolver {
    public enum Failure: Error, Equatable, CustomStringConvertible {
        case conflicting

        public var description: String { "These rules can't all hold at once" }
    }

    /// The curves solved for the sketch's rules; ends that met keep meeting (ends that met in `joinedAs`, the sketch
    /// before a curve was changed, when given).
    public static func solve(_ curves: [SketchCurve], constraints: [SketchConstraint],
                             joinedAs before: [SketchCurve]? = nil) throws(Failure) -> [SketchCurve] {
        guard !constraints.isEmpty else { return curves }
        let layout = Layout(curves)
        let start = layout.parameters(curves)
        let joins = layout.joins(before.flatMap { $0.count == curves.count ? $0 : nil } ?? curves)
        // First near the drawing (the pull keeps free numbers where they were drawn), then the rules exactly: the second
        // pass starts there and takes the smallest steps that close what's left.
        var p = iterate(start) { residuals($0, start: start, layout: layout, constraints: constraints, joins: joins) }
        p = iterate(p) { residuals($0, start: start, layout: layout, constraints: constraints, joins: joins, regularize: false) }
        // Only the rules count toward success; the pull toward the drawing is a preference.
        let rules = residuals(p, start: start, layout: layout, constraints: constraints, joins: joins, regularize: false)
        let scale = max(start.map(abs).max() ?? 1, 1e-3)
        guard rules.allSatisfy({ abs($0) < scale * 1e-6 }) else { throw .conflicting }
        return layout.curves(from: p, original: curves)
    }

    /// Levenberg–Marquardt from `start` on the sums `f` returns.
    private static func iterate(_ start: [Double], _ f: ([Double]) -> [Double]) -> [Double] {
        var p = start
        var lambda = 1e-3
        var cost = sum(f(p))
        for _ in 0 ..< 100 where cost > 1e-30 {
            let r = f(p)
            guard let step = dampedStep(numericJacobian(p, r: r, f), r, lambda: lambda) else { break }
            let trial = zip(p, step).map { $0 + $1 }
            let trialCost = sum(f(trial))
            if trialCost < cost {
                p = trial
                cost = trialCost
                lambda = max(lambda / 4, 1e-12)
                if step.map(abs).max() ?? 0 < 1e-14 { break }
            } else {
                lambda *= 8
                if lambda > 1e8 { break }
            }
        }
        return p
    }

    private static func sum(_ values: [Double]) -> Double { values.reduce(0) { $0 + $1 * $1 } }

    // MARK: The sums that should be zero

    static func residuals(_ p: [Double], start: [Double], layout: Layout, constraints: [SketchConstraint], joins: [(Int, Int)],
                          regularize: Bool = true) -> [Double] {
        var result: [Double] = []
        let size = max(start.map(abs).max() ?? 1, 1e-3)
        for constraint in constraints {
            result += residual(constraint, p, layout: layout, size: size)
        }
        for (a, b) in joins {
            result += [p[a] - p[b], p[a + 1] - p[b + 1]]
        }
        if regularize {
            // A gentle pull toward the drawing, so free numbers stay where they were drawn.
            result += zip(p, start).map { ($0 - $1) * 1e-3 }
        }
        return result
    }

    private static func residual(_ constraint: SketchConstraint, _ p: [Double], layout: Layout, size: Double) -> [Double] {
        switch constraint {
        case let .parallel(a, b):
            guard let u = layout.direction(a, p), let v = layout.direction(b, p) else { return [] }
            return [u.cross(v) / max(u.length * v.length, 1e-12) * size]
        case let .perpendicular(a, b):
            guard let u = layout.direction(a, p), let v = layout.direction(b, p) else { return [] }
            return [u.dot(v) / max(u.length * v.length, 1e-12) * size]
        case let .equal(a, b):
            guard let x = layout.size(a, p, side: 0), let y = layout.size(b, p, side: 0) else { return [] }
            return [x - y]
        case let .ratio(a, b, factor):
            guard let x = layout.size(a, p, side: 0), let y = layout.size(b, p, side: 0) else { return [] }
            return [x - factor * y]
        case let .length(a, value, side):
            guard let x = layout.size(a, p, side: side) else { return [] }
            return [x - value]
        case let .angle(a, degrees):
            guard let u = layout.direction(a, p) else { return [] }
            let angle = degrees * .pi / 180
            return [(u.x * sin(angle) - u.y * cos(angle)) / max(u.length, 1e-12) * size]
        case let .tangent(line, circle):
            guard let ends = layout.ends(line, p), let (centre, radius) = layout.circle(circle, p) else { return [] }
            let direction = ends.1 - ends.0
            let distance = abs(direction.cross(centre - ends.0)) / max(direction.length, 1e-12)
            return [distance - radius]
        }
    }

    // MARK: Numbers

    private static func numericJacobian(_ p: [Double], r: [Double], _ f: ([Double]) -> [Double]) -> [[Double]] {
        var columns: [[Double]] = []
        for index in p.indices {
            let h = max(abs(p[index]), 1e-3) * 1e-7
            var shifted = p
            shifted[index] += h
            let rs = f(shifted)
            columns.append(zip(rs, r).map { ($0 - $1) / h })
        }
        // Rows × columns.
        return r.indices.map { row in columns.map { $0[row] } }
    }

    /// Solves (JᵀJ + λ diag(JᵀJ)) Δ = −Jᵀr by Gaussian elimination.
    private static func dampedStep(_ j: [[Double]], _ r: [Double], lambda: Double) -> [Double]? {
        let n = j.first?.count ?? 0
        guard n > 0 else { return nil }
        var a = [[Double]](repeating: [Double](repeating: 0, count: n + 1), count: n)
        for row in j.indices {
            for c in 0 ..< n where j[row][c] != 0 {
                for d in 0 ..< n where j[row][d] != 0 {
                    a[c][d] += j[row][c] * j[row][d]
                }
                a[c][n] -= j[row][c] * r[row]
            }
        }
        for c in 0 ..< n {
            a[c][c] += lambda * max(a[c][c], 1e-9)
        }
        return gauss(&a, n)
    }

    private static func gauss(_ a: inout [[Double]], _ n: Int) -> [Double]? {
        for column in 0 ..< n {
            guard let pivot = (column ..< n).max(by: { abs(a[$0][column]) < abs(a[$1][column]) }), abs(a[pivot][column]) > 1e-300 else { return nil }
            a.swapAt(column, pivot)
            for row in column + 1 ..< n where a[row][column] != 0 {
                let factor = a[row][column] / a[column][column]
                for k in column ... n {
                    a[row][k] -= factor * a[column][k]
                }
            }
        }
        var x = [Double](repeating: 0, count: n)
        for row in stride(from: n - 1, through: 0, by: -1) {
            var value = a[row][n]
            for k in row + 1 ..< n {
                value -= a[row][k] * x[k]
            }
            x[row] = value / a[row][row]
        }
        return x
    }
}

/// Where each curve's numbers live in the solver's list: a line and a rectangle are two points, a circle a centre and
/// a radius, an arc three points; splines and polylines have none (they hold still).
struct Layout {
    enum Kind { case line, rectangle, circle, arc, other }

    let offsets: [Int?]
    let kinds: [Kind]
    let count: Int

    init(_ curves: [SketchCurve]) {
        var offsets: [Int?] = []
        var kinds: [Kind] = []
        var next = 0
        for curve in curves {
            let (kind, size): (Kind, Int) = switch curve {
            case .line: (.line, 4)
            case .rectangle: (.rectangle, 4)
            case .circle: (.circle, 3)
            case .arc: (.arc, 6)
            case .spline, .polyline: (.other, 0)
            }
            offsets.append(size > 0 ? next : nil)
            kinds.append(kind)
            next += size
        }
        self.offsets = offsets
        self.kinds = kinds
        count = next
    }

    func parameters(_ curves: [SketchCurve]) -> [Double] {
        curves.flatMap { curve -> [Double] in
            switch curve {
            case let .line(a, b), let .rectangle(a, b): [a.x, a.y, b.x, b.y]
            case let .circle(centre, radius): [centre.x, centre.y, radius]
            case let .arc(a, b, c): [a.x, a.y, b.x, b.y, c.x, c.y]
            case .spline, .polyline: []
            }
        }
    }

    func curves(from p: [Double], original: [SketchCurve]) -> [SketchCurve] {
        original.enumerated().map { index, curve in
            guard let o = offsets[index] else { return curve }
            switch curve {
            case .line: return .line(Vec2(p[o], p[o + 1]), Vec2(p[o + 2], p[o + 3]))
            case .rectangle: return .rectangle(Vec2(p[o], p[o + 1]), Vec2(p[o + 2], p[o + 3]))
            case .circle: return .circle(center: Vec2(p[o], p[o + 1]), radius: abs(p[o + 2]))
            case .arc: return .arc(Vec2(p[o], p[o + 1]), Vec2(p[o + 2], p[o + 3]), Vec2(p[o + 4], p[o + 5]))
            case .spline, .polyline: return curve
            }
        }
    }

    /// Pairs of point slots (x indices) that coincide in the drawing: line and arc ends that meet stay met.
    func joins(_ curves: [SketchCurve]) -> [(Int, Int)] {
        var ends: [(slot: Int, point: Vec2)] = []
        for (index, curve) in curves.enumerated() {
            guard let o = offsets[index] else { continue }
            switch curve {
            case let .line(a, b): ends += [(o, a), (o + 2, b)]
            case let .arc(a, _, c): ends += [(o, a), (o + 4, c)]
            default: break
            }
        }
        let size = max(ends.map { max(abs($0.point.x), abs($0.point.y)) }.max() ?? 1, 1e-3)
        var result: [(Int, Int)] = []
        for i in ends.indices {
            for j in ends.indices where j > i && (ends[i].point - ends[j].point).length <= size * 1e-6 {
                result.append((ends[i].slot, ends[j].slot))
            }
        }
        return result
    }

    func ends(_ curve: Int, _ p: [Double]) -> (Vec2, Vec2)? {
        guard offsets.indices.contains(curve), let o = offsets[curve] else { return nil }
        return (Vec2(p[o], p[o + 1]), Vec2(p[o + 2], p[o + 3]))
    }

    /// A line's direction (nil for anything but a line).
    func direction(_ curve: Int, _ p: [Double]) -> Vec2? {
        guard kinds.indices.contains(curve), kinds[curve] == .line, let (a, b) = ends(curve, p) else { return nil }
        return b - a
    }

    /// A centre and radius (circles, and arcs through their three points).
    func circle(_ curve: Int, _ p: [Double]) -> (Vec2, Double)? {
        guard offsets.indices.contains(curve), let o = offsets[curve] else { return nil }
        switch kinds[curve] {
        case .circle: return (Vec2(p[o], p[o + 1]), abs(p[o + 2]))
        case .arc:
            guard let arc = SketchArc(Vec2(p[o], p[o + 1]), Vec2(p[o + 2], p[o + 3]), Vec2(p[o + 4], p[o + 5])) else { return nil }
            return (arc.center, arc.radius)
        default: return nil
        }
    }

    /// A line's length, a circle's diameter, a rectangle's width (side 0) or height (side 1).
    func size(_ curve: Int, _ p: [Double], side: Int) -> Double? {
        guard offsets.indices.contains(curve), let o = offsets[curve] else { return nil }
        switch kinds[curve] {
        case .line: return (Vec2(p[o + 2], p[o + 3]) - Vec2(p[o], p[o + 1])).length
        case .rectangle: return abs(side == 0 ? p[o + 2] - p[o] : p[o + 3] - p[o + 1])
        case .circle: return 2 * abs(p[o + 2])
        case .arc: return circle(curve, p).map { 2 * $0.1 }
        case .other: return nil
        }
    }
}
