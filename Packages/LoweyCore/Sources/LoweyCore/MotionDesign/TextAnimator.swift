import Foundation

/// Letters of 3D text that animate one after another, from a preset on the text's panel: they fly in, bounce, cascade,
/// pop, spin, type on or ride a wave. Pure: the pose of every letter at any moment comes from these numbers alone, so the
/// stage and the export agree and the bridge can say where each letter is.
public struct TextAnimator: Codable, Hashable, Sendable {
    public enum Preset: String, Codable, Sendable, CaseIterable, Identifiable {
        case flyIn, bounce, cascade, pop, spin, typewriter, wave

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .flyIn: "Fly in"
            case .bounce: "Bounce in"
            case .cascade: "Cascade"
            case .pop: "Pop"
            case .spin: "Spin in"
            case .typewriter: "Type on"
            case .wave: "Wave"
            }
        }

        public var systemImage: String {
            switch self {
            case .flyIn: "paperplane"
            case .bounce: "arrow.down.to.line"
            case .cascade: "rectangle.stack"
            case .pop: "plus.magnifyingglass"
            case .spin: "arrow.triangle.2.circlepath"
            case .typewriter: "character.cursor.ibeam"
            case .wave: "water.waves"
            }
        }

        /// The wave keeps going; the others arrive once and stay.
        public var repeats: Bool { self == .wave }
    }

    /// Which letter goes first.
    public enum Order: String, Codable, Sendable, CaseIterable, Identifiable {
        case forward, backward, middle, random

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .forward: "First to last"
            case .backward: "Last to first"
            case .middle: "From the middle"
            case .random: "Random"
            }
        }
    }

    public var preset: Preset
    public var order: Order
    /// When the first letter starts (seconds on the timeline).
    public var start: Double
    /// Seconds between one letter and the next.
    public var stagger: Double
    /// Seconds a letter takes to arrive (the wave: seconds for one wave).
    public var length: Double

    public init(preset: Preset, order: Order = .forward, start: Double = 0, stagger: Double = 0.06, length: Double = 0.6) {
        self.preset = preset
        self.order = order
        self.start = start
        self.stagger = stagger
        self.length = length
    }

    /// The preset's own timing, starting at `start`.
    public static func starting(_ preset: Preset, at start: Double) -> TextAnimator {
        switch preset {
        case .typewriter: TextAnimator(preset: preset, start: start, stagger: 0.07, length: 0.05)
        case .wave: TextAnimator(preset: preset, start: start, stagger: 0.08, length: 1.6)
        case .cascade: TextAnimator(preset: preset, start: start, stagger: 0.05, length: 0.8)
        default: TextAnimator(preset: preset, start: start)
        }
    }

    /// When the last letter has arrived (the wave never does).
    public func end(letters: Int) -> Double? {
        preset.repeats ? nil : start + stagger * Double(max(letters - 1, 0)) + length
    }

    /// The letters that animate: an index for each character of `text` (nil for spaces and line breaks).
    public static func letterIndices(_ text: String) -> [Int?] {
        var next = 0
        return text.map { character in
            guard !character.isWhitespace else { return nil }
            defer { next += 1 }
            return next
        }
    }

    /// The order in which `count` letters start: `rank[i]` is how many go before letter i.
    public func ranks(count: Int) -> [Int] {
        switch order {
        case .forward: return Array(0 ..< count)
        case .backward: return (0 ..< count).map { count - 1 - $0 }
        case .middle:
            let middle = Double(count - 1) / 2
            return (0 ..< count).map { Int(abs(Double($0) - middle).rounded(.down)) }
        case .random:
            var random = SeededRandom(seed: 0x5EED_1E77)
            let shuffled = (0 ..< count).shuffled(using: &random)
            var ranks = [Int](repeating: 0, count: count)
            for (rank, letter) in shuffled.enumerated() {
                ranks[letter] = rank
            }
            return ranks
        }
    }

    /// Every letter's pose at `time` (letters in reading order, `size` the letters' height in metres).
    public func poses(count: Int, at time: Double, size: Double) -> [LetterPose] {
        let ranks = ranks(count: count)
        return (0 ..< count).map { letter in
            let begins = start + stagger * Double(ranks[letter])
            if preset.repeats { return LetterPose.wave(time: time - begins, length: length, size: size, started: time >= start) }
            let progress = length > 0 ? (time - begins) / length : (time >= begins ? 1 : 0)
            return LetterPose.arriving(preset, progress: min(max(progress, 0), 1), size: size)
        }
    }
}

/// Where a letter is, relative to where it rests: moved (metres, in the text's own directions), turned (degrees about
/// its own centre), sized, and how much of it shows.
public struct LetterPose: Hashable, Sendable {
    public var offset: Vec3
    public var turn: Vec3
    public var scale: Double
    public var opacity: Double

    public init(offset: Vec3 = .zero, turn: Vec3 = .zero, scale: Double = 1, opacity: Double = 1) {
        self.offset = offset
        self.turn = turn
        self.scale = scale
        self.opacity = opacity
    }

    public static let resting = LetterPose()

    public var isResting: Bool { self == .resting }

    /// A letter on its way in: `progress` 0 (not yet) … 1 (arrived, at rest).
    static func arriving(_ preset: TextAnimator.Preset, progress p: Double, size: Double) -> LetterPose {
        guard p < 1 else { return .resting }
        let out = 1 - pow(1 - p, 3)
        switch preset {
        case .flyIn:
            return LetterPose(offset: Vec3(0, -size * 0.6, size * 2.5) * (1 - out), turn: Vec3(-70 * (1 - out), 0, 0), opacity: min(p * 3, 1))
        case .bounce:
            return LetterPose(offset: Vec3(0, size * 1.6 * (1 - bounced(p)), 0), opacity: min(p * 6, 1))
        case .cascade:
            // Each letter drops in tipped back and swings upright, settling with a little bounce: a row of cards falling in.
            return LetterPose(offset: Vec3(0, size * 0.9 * (1 - out), 0), turn: Vec3(90 * (1 - bounced(p)), 0, 0), opacity: min(p * 2.5, 1))
        case .pop:
            return LetterPose(scale: max(overshoot(p), 0), opacity: p > 0 ? 1 : 0)
        case .spin:
            return LetterPose(turn: Vec3(0, -360 * (1 - out), 0), scale: 0.3 + 0.7 * out, opacity: min(p * 3, 1))
        case .typewriter:
            return LetterPose(opacity: p > 0 ? 1 : 0)
        case .wave:
            return .resting
        }
    }

    /// The wave: up and down by a quarter of the letters' height, `length` seconds a wave, from when the letters start.
    static func wave(time: Double, length: Double, size: Double, started: Bool) -> LetterPose {
        guard started, length > 0 else { return .resting }
        return LetterPose(offset: Vec3(0, size * 0.25 * sin(2 * .pi * time / length), 0))
    }

    /// A ball dropped onto the floor: down by p = 0.6, two smaller bounces after.
    static func bounced(_ p: Double) -> Double {
        let t = min(max(p, 0), 1)
        if t < 0.6 { return pow(t / 0.6, 2) }
        if t < 0.85 {
            let u = (t - 0.725) / 0.125
            return 1 - 0.12 * (1 - u * u)
        }
        let u = (t - 0.925) / 0.075
        return 1 - 0.03 * (1 - u * u)
    }

    /// Past full size and back (a spring that settles).
    static func overshoot(_ p: Double) -> Double {
        let t = min(max(p, 0), 1)
        return 1 - exp(-6 * t) * cos(9 * t) * (1 - t)
    }
}
