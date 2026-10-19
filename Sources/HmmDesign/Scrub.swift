/// Every number is a slider (Maquette U5): dragged slowly it moves by `fine` a point, dragged fast it moves coarsely,
/// up to twenty times as far. Pure maths, tested on its own.
public struct HmmScrub: Sendable, Equatable {
    /// The change one point of a slow drag makes.
    public var fine: Double
    /// Where the value stops (nil: anywhere).
    public var range: ClosedRange<Double>?

    public init(fine: Double, range: ClosedRange<Double>? = nil) {
        self.fine = fine
        self.range = range
    }

    /// Speeds under this (points a second) are fine work: one point is `fine`.
    public static let slow = 80.0
    /// From this speed on a point moves `maximumGain` times as far.
    public static let fast = 1600.0
    public static let maximumGain = 20.0

    /// How much farther than `fine` a point of drag goes at `speed` points a second: 1 when slow, rising smoothly (a
    /// square, so the middle stays controllable) to `maximumGain` when fast.
    public static func gain(speed: Double) -> Double {
        let speed = abs(speed)
        guard speed > slow else { return 1 }
        let t = min((speed - slow) / (fast - slow), 1)
        return 1 + (maximumGain - 1) * t * t
    }

    /// The value after a move of `delta` points (right or up is more) at `speed` points a second.
    public func value(from start: Double, delta: Double, speed: Double) -> Double {
        clamped(start + delta * fine * Self.gain(speed: speed))
    }

    public func clamped(_ value: Double) -> Double {
        guard let range else { return value }
        return min(max(value, range.lowerBound), range.upperBound)
    }

    /// The value sits on an end of its range (where the Pencil Pro buzzes, once).
    public func isAtEnd(_ value: Double) -> Bool {
        guard let range else { return false }
        let span = max(range.upperBound - range.lowerBound, 1e-12)
        return abs(value - range.lowerBound) <= span * 1e-9 || abs(value - range.upperBound) <= span * 1e-9
    }

    /// A drag's move as one number: right and up are more, whichever way the hand went further.
    public static func delta(dx: Double, dy: Double) -> Double {
        abs(dx) >= abs(dy) ? dx : -dy
    }
}
