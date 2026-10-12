import Foundation

/// Sketching talks back (CONTEXT §4.4, Shapr3D's standard): while a line is drawn its length and angle float beside
/// the tip, and the end snaps softly to what a person meant: a corner already drawn, an edge's middle, a round angle
/// (every 15°), or parallel and perpendicular to an edge already there. Each snap is named on a ghost line. All in
/// the drawing plane's own coordinates (metres; angles from its right, counter-clockwise).
public enum SketchAssist {
    public enum Snap: Hashable, Sendable {
        case corner
        case midpoint
        /// A round angle, in degrees.
        case angle(Int)
        case parallel
        case perpendicular

        /// The ghost line's name.
        public var label: String {
            switch self {
            case .corner: "Corner"
            case .midpoint: "Midpoint"
            case let .angle(degrees): "\(degrees)°"
            case .parallel: "Parallel"
            case .perpendicular: "Perpendicular"
            }
        }
    }

    public struct Guess: Hashable, Sendable {
        /// Where the end lands.
        public var point: Vec2
        public var snap: Snap?
        public var length: Double
        /// Degrees in 0 ..< 360.
        public var angle: Double
        /// The line that names the snap (from the start through the end and on), or the edge it lines up with.
        public var ghost: [Vec2]
    }

    /// Where a line from `start` towards `end` lands, with `edges` already drawn on the plane. `reach` is how near (in
    /// plane metres) counts as on a corner or a middle; `angleReach` how near (degrees) counts as on an angle.
    public static func guess(from start: Vec2, to end: Vec2, edges: [(Vec2, Vec2)], reach: Double, angleReach: Double = 2.5,
                             snapping: Bool = true) -> Guess {
        guard snapping else { return measured(start, end, snap: nil, ghost: []) }
        if let corner = nearest(edges.flatMap { [$0.0, $0.1] }, to: end, within: reach), corner != start {
            return measured(start, corner, snap: .corner, ghost: [])
        }
        if let middle = nearest(edges.map { ($0.0 + $0.1) * 0.5 }, to: end, within: reach) {
            return measured(start, middle, snap: .midpoint, ghost: [])
        }
        let direction = end - start
        let length = direction.length
        guard length > 1e-9 else { return measured(start, end, snap: nil, ghost: []) }
        let degrees = angle(of: direction)
        let round = (degrees / 15).rounded() * 15
        if abs(degrees - round) <= angleReach {
            let snapped = along(start, degrees: round, length: length)
            let name = Int(round.truncatingRemainder(dividingBy: 360))
            return measured(start, snapped, snap: .angle(name < 0 ? name + 360 : name), ghost: [start, along(start, degrees: round, length: length * 1.6)])
        }
        for (a, b) in edges {
            let edge = b - a
            guard edge.length > 1e-9 else { continue }
            let edgeAngle = angle(of: edge)
            for (offset, snap) in [(0.0, Snap.parallel), (90.0, .perpendicular)] {
                // A line and its reverse are the same direction.
                let target = edgeAngle + offset
                let difference = (degrees - target).truncatingRemainder(dividingBy: 180)
                let wrapped = difference > 90 ? difference - 180 : (difference < -90 ? difference + 180 : difference)
                guard abs(wrapped) <= angleReach else { continue }
                let snapped = along(start, degrees: degrees - wrapped, length: length)
                return measured(start, snapped, snap: snap, ghost: [a, b])
            }
        }
        return measured(start, end, snap: nil, ghost: [])
    }

    /// Degrees in 0 ..< 360 of a direction on the plane.
    public static func angle(of direction: Vec2) -> Double {
        let degrees = atan2(direction.y, direction.x) * 180 / .pi
        return degrees < 0 ? degrees + 360 : degrees
    }

    static func along(_ start: Vec2, degrees: Double, length: Double) -> Vec2 {
        let radians = degrees * .pi / 180
        return start + Vec2(cos(radians), sin(radians)) * length
    }

    static func nearest(_ points: [Vec2], to point: Vec2, within reach: Double) -> Vec2? {
        points.filter { ($0 - point).length <= reach }.min { ($0 - point).length < ($1 - point).length }
    }

    static func measured(_ start: Vec2, _ end: Vec2, snap: Snap?, ghost: [Vec2]) -> Guess {
        let direction = end - start
        return Guess(point: end, snap: snap, length: direction.length, angle: direction.length > 1e-12 ? angle(of: direction) : 0, ghost: ghost)
    }
}
