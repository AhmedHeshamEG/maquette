import Foundation

/// A motion played again after it ends: the stretch from `start` to `end` (the whole row's animation, so every
/// property of a thing repeats together) comes back `repeats` more times, or forever when that's nil.
public struct TrackCycle: Codable, Hashable, Sendable {
    public var start: Double
    public var end: Double
    /// Plays after the first; nil loops forever.
    public var repeats: Int?

    public init(start: Double, end: Double, repeats: Int? = nil) {
        self.start = start
        self.end = end
        self.repeats = repeats
    }

    public var span: Double { end - start }

    /// When the last repeat ends (nil: never).
    public var finish: Double? { repeats.map { end + span * Double(max($0, 0)) } }

    /// The moment of the first play that `time` shows.
    public func time(at time: Double) -> Double {
        guard span > 1e-9, time > end else { return time }
        if let finish, time >= finish { return end }
        let into = (time - start).truncatingRemainder(dividingBy: span)
        return start + into
    }
}
