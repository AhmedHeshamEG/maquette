import Foundation

/// Copies of a thing laid out together and moved by effects (Cinema 4D's cloner, made simple): a grid, a circle, a
/// line or along a drawn path; effects shift, turn and grow the copies, or have them play the thing's motion one after
/// another, and fields say where and when an effect acts (everywhere, near a point, or as a ring rippling out). The
/// thing itself is the first copy; the rest exist only in the shown scene, so a project stores one thing and a recipe.
public struct ObjectClones: Codable, Hashable, Sendable {
    public enum Layout: Codable, Hashable, Sendable {
        /// Columns along the thing's x, rows along its z, layers up its y, `spacing` apart, centred on it.
        case grid(columns: Int, rows: Int, layers: Int, spacing: Vec3)
        /// Around the thing's up axis, `radius` from it, each copy facing out when `facesOut`.
        case circle(count: Int, radius: Double, facesOut: Bool)
        /// One after another, `step` apart (in the thing's own directions), starting at the thing.
        case line(count: Int, step: Vec3)
        /// Evenly along a drawn path, turned along it when `along`.
        case path(count: Int, path: ObjectID, along: Bool)

        public var count: Int {
            switch self {
            case let .grid(columns, rows, layers, _): max(columns, 1) * max(rows, 1) * max(layers, 1)
            case let .circle(count, _, _), let .line(count, _), let .path(count, _, _): max(count, 1)
            }
        }

        public var title: String {
            switch self {
            case .grid: "Grid"
            case .circle: "Circle"
            case .line: "Line"
            case .path: "Along a path"
            }
        }
    }

    public var layout: Layout
    public var effects: [CloneEffect]
    /// Seeds the random effect, so the copies scatter the same way every time.
    public var seed: UInt64

    public init(layout: Layout, effects: [CloneEffect] = [], seed: UInt64 = 1) {
        self.layout = layout
        self.effects = effects
        self.seed = seed
    }

    /// At most this many copies (a 10 × 10 × 10 grid): every iPad keeps it smooth.
    public static let maximumCount = 1000

    public var count: Int { min(layout.count, Self.maximumCount) }

    /// A first layout for a thing about `size` metres across: a 5 × 5 grid with a little air between copies.
    public static func starting(size: Double) -> ObjectClones {
        let gap = max(size, 0.05) * 1.4
        return ObjectClones(layout: .grid(columns: 5, rows: 5, layers: 1, spacing: Vec3(gap, gap, gap)))
    }
}

/// What an effect does to the copies a field reaches.
public struct CloneEffect: Codable, Hashable, Sendable, Identifiable {
    public enum Kind: String, Codable, Sendable, CaseIterable, Identifiable {
        /// Each copy shifted, turned and grown by its own random amount (up to the numbers).
        case random
        /// Each copy plays the thing's motion `delay` seconds after the one before it, nearest the field's centre first.
        case delay
        /// Copies pushed by `move`, turned by `turn` and grown by `grow` as much as the field reaches them.
        case push

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .random: "Random"
            case .delay: "Delay"
            case .push: "Push"
            }
        }
    }

    public var id: String
    public var kind: Kind
    /// Metres, in the thing's own directions.
    public var move: Vec3
    /// Degrees about the thing's own axes.
    public var turn: Vec3
    /// A fraction: 0.5 is half as big again.
    public var grow: Double
    /// Seconds between one copy and the next (delay).
    public var delay: Double
    public var field: CloneField

    public init(id: String, kind: Kind, move: Vec3 = .zero, turn: Vec3 = .zero, grow: Double = 0, delay: Double = 0,
                field: CloneField = .everywhere) {
        self.id = id
        self.kind = kind
        self.move = move
        self.turn = turn
        self.grow = grow
        self.delay = delay
        self.field = field
    }

    /// An effect of `kind` with numbers that read at once for a thing `size` metres across.
    public static func starting(_ kind: Kind, id: String, size: Double) -> CloneEffect {
        let unit = max(size, 0.05)
        switch kind {
        case .random:
            return CloneEffect(id: id, kind: .random, move: Vec3(0, unit * 0.5, 0), turn: Vec3(0, 45, 0), grow: 0.3)
        case .delay:
            return CloneEffect(id: id, kind: .delay, delay: 0.08)
        case .push:
            return CloneEffect(id: id, kind: .push, move: Vec3(0, unit, 0), grow: 0.2,
                               field: .wave(speed: unit * 4, width: unit * 2.5, every: 2))
        }
    }
}

/// Where and when an effect acts, as a weight 0…1 for each copy.
public enum CloneField: Codable, Hashable, Sendable {
    /// On every copy, fully.
    case everywhere
    /// Fully within half of `radius` of a point (offset from the thing), fading to nothing at `radius`.
    case sphere(centre: Vec3, radius: Double)
    /// A ring travelling out from the thing at `speed` m/s, `width` metres wide; a new ring every `every` seconds (0: once).
    case wave(speed: Double, width: Double, every: Double)

    public var title: String {
        switch self {
        case .everywhere: "Everywhere"
        case .sphere: "Near a point"
        case .wave: "Ripple"
        }
    }

    /// Where the field is measured from, in the thing's own directions.
    public var centre: Vec3 {
        if case let .sphere(centre, _) = self { return centre }
        return .zero
    }

    /// The weight at `distance` metres from the centre at `time` seconds.
    public func weight(distance: Double, time: Double) -> Double {
        switch self {
        case .everywhere:
            return 1
        case let .sphere(_, radius):
            guard radius > 0 else { return 0 }
            return Self.smooth(1 - (distance - radius / 2) / (radius / 2))
        case let .wave(speed, width, every):
            guard speed > 0, width > 0 else { return 0 }
            var age = time - distance / speed
            if every > 0 { age -= (age / every).rounded(.down) * every }
            guard age >= 0 else { return 0 }
            // The ring's front is here when age = 0; it rises and falls over width / speed seconds.
            let span = width / speed
            guard age < span else { return 0 }
            return sin(.pi * age / span)
        }
    }

    /// A smoothstep on 0…1, clamped.
    static func smooth(_ value: Double) -> Double {
        let t = min(max(value, 0), 1)
        return t * t * (3 - 2 * t)
    }
}
