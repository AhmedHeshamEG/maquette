import Foundation

/// How this hand presses the Pencil (Settings ▸ Pencil, one page with a test pad; every tool obeys it): the pressure
/// curve every stroke's pressure goes through before its brush's own dynamics, extra stabilisation, and what a Pencil
/// without pressure does (thickness follows speed). Kept on the device, shared by every studio app.
public struct HmmPencilFeel: Codable, Equatable, Sendable {
    /// A starting point, or the curve calibration fitted (or one dragged by hand).
    public enum Hand: String, Codable, CaseIterable, Identifiable, Sendable {
        case light, normal, heavy, calibrated

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .light: "Light hand"
            case .normal: "Normal"
            case .heavy: "Heavy hand"
            case .calibrated: "Mine"
            }
        }
    }

    public static let storageKey = "hmm.pencilFeel"

    public var hand: Hand
    /// Raw pressure → the pressure strokes get.
    public var curve: BrushCurve
    /// Added to every brush's own streamline (0…1).
    public var stabilisation: Double
    /// Pencils that report no pressure: thickness follows speed (on), or every stroke is full pressure (off).
    public var speedForPressure: Bool

    public init(hand: Hand = .normal, curve: BrushCurve? = nil, stabilisation: Double = 0, speedForPressure: Bool = true) {
        self.hand = hand
        self.curve = (curve ?? Self.curve(for: hand)).clamped
        self.stabilisation = stabilisation.clamped(0, 1)
        self.speedForPressure = speedForPressure
    }

    public static let `default` = HmmPencilFeel()

    /// The curve of a preset (calibrated starts from normal until two strokes fit one).
    public static func curve(for hand: Hand) -> BrushCurve {
        switch hand {
        case .light: BrushCurve([Vec2(0, 0), Vec2(0.05, 0.08), Vec2(0.45, 1), Vec2(1, 1)])
        case .normal, .calibrated: BrushCurve([Vec2(0, 0), Vec2(0.1, 0.08), Vec2(0.75, 1), Vec2(1, 1)])
        case .heavy: BrushCurve([Vec2(0, 0), Vec2(0.25, 0.08), Vec2(1, 1)])
        }
    }

    /// The pressure a stroke gets for what the Pencil reported.
    public func pressure(_ raw: Double) -> Double {
        curve.value(at: raw)
    }

    // MARK: Calibration

    /// "Draw your lightest line, now your heaviest": the curve that turns this hand's lightest touch into a thin
    /// visible line and its heaviest into a full one, straight in between. Nil when the strokes are too short or the
    /// heaviest wasn't heavier.
    public static func calibrated(lightest: [Double], heaviest: [Double]) -> BrushCurve? {
        guard lightest.count >= 4, heaviest.count >= 4, let light = median(lightest), let heavy = median(heaviest) else { return nil }
        guard heavy - light >= 0.08 else { return nil }
        let low = light.clamped(0.01, 0.9)
        let high = heavy.clamped(low + 0.05, 1)
        var points = [Vec2(0, 0), Vec2(low, 0.08), Vec2(high, 1)]
        if high < 1 { points.append(Vec2(1, 1)) }
        return BrushCurve(points)
    }

    static func median(_ values: [Double]) -> Double? {
        let sorted = values.filter(\.isFinite).sorted()
        guard !sorted.isEmpty else { return nil }
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }

    // MARK: Pencils without pressure

    /// A stroke whose pressure never moves: the Pencil has none (Apple Pencil USB-C, a pointer).
    public static func isFlat(_ pressures: [Double]) -> Bool {
        guard pressures.count >= 6, let low = pressures.min(), let high = pressures.max() else { return false }
        return high - low < 0.002
    }

    /// Pressure from speed for a Pencil without any: slow is full, fast thins down to a quarter, smoothed so a
    /// line doesn't flicker. `points` are on screen (points), `times` in seconds.
    public static func pressureFromSpeed(points: [Vec2], times: [Double]) -> [Double] {
        guard points.count == times.count, points.count > 1 else { return points.map { _ in 1 } }
        var result: [Double] = []
        result.reserveCapacity(points.count)
        var smoothed = 1.0
        for index in points.indices {
            let previous = max(index - 1, 0)
            let span = times[index] - times[previous]
            let distance = (points[index] - points[previous]).length
            let speed = span > 1e-4 ? distance / span : 0
            let target = (1 - speed / 2400).clamped(0.25, 1)
            smoothed = index == 0 ? target : smoothed + (target - smoothed) * 0.25
            result.append(smoothed)
        }
        return result
    }

    // MARK: On the device

    public static func load(from defaults: UserDefaults) -> HmmPencilFeel {
        guard let data = defaults.data(forKey: storageKey), let feel = try? JSONDecoder().decode(HmmPencilFeel.self, from: data) else {
            return .default
        }
        return feel
    }

    public func save(to defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}
