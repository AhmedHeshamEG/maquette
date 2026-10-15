import Foundation

/// A force in the scene, placed like a thing (Model ▸ Add ▸ Effects): a fan's wind or a pull to a point.
public struct ForceRecipe: Codable, Hashable, Sendable {
    public enum Kind: String, Codable, Sendable, CaseIterable {
        /// Blows along the thing's own -Z (where it points), inside its reach.
        case fan
        /// Pulls things toward its point; a negative strength pushes them away.
        case pull
        /// Turns things around its own Y axis.
        case whirl

        public var title: String {
            switch self {
            case .fan: "Fan"
            case .pull: "Pull"
            case .whirl: "Whirl"
            }
        }

        public var systemImage: String {
            switch self {
            case .fan: "fan"
            case .pull: "scope"
            case .whirl: "tornado"
            }
        }
    }

    public var kind: Kind
    /// Fan: the wind's speed (m/s). Pull and whirl: the acceleration at the centre (m/s²).
    public var strength: Double
    /// How far it reaches (metres); it fades out toward the edge.
    public var reach: Double

    public init(kind: Kind, strength: Double? = nil, reach: Double = 3) {
        self.kind = kind
        self.strength = strength ?? (kind == .fan ? 8 : 12)
        self.reach = reach
    }

    /// The acceleration (m/s²) this force gives a thing at `point` moving at `velocity`, for a force placed at `place`.
    /// A fan pushes like air (by the difference of speeds, so a thing stops gaining once it moves with the wind).
    public func acceleration(at point: Vec3, velocity: Vec3, place: Transform) -> Vec3 {
        let local = place.inverseApply(to: point)
        let distance: Double
        switch kind {
        case .fan:
            // A cylinder along -Z from the fan.
            let along = -local.z
            guard along >= 0, along <= reach else { return .zero }
            let radius = (local.x * local.x + local.y * local.y).squareRoot()
            let width = max(reach * 0.25, 0.3)
            guard radius <= width else { return .zero }
            let fade = (1 - along / reach) * (1 - radius / width)
            let wind = place.applyDirection(Vec3(0, 0, -1)).normalized * (strength * fade)
            return (wind - velocity) * 1.2
        case .pull:
            distance = point.distance(to: place.position)
            guard distance <= reach, distance > 1e-4 else { return .zero }
            let fade = 1 - distance / reach
            return (place.position - point).normalized * (strength * fade)
        case .whirl:
            let axis = place.applyDirection(.unitY).normalized
            let offset = point - place.position
            let radial = offset - axis * offset.dot(axis)
            distance = radial.length
            guard distance <= reach, distance > 1e-4 else { return .zero }
            let fade = 1 - distance / reach
            return axis.cross(radial.normalized) * (strength * fade) - radial.normalized * (strength * 0.3 * fade)
        }
    }
}

/// A small-scale fluid in a room-sized box (Model ▸ Add ▸ Effects): water poured or splashed, smoke or fire. Simulated
/// in the background and played from a cache, so preview and export are the same.
public struct FluidRecipe: Codable, Hashable, Sendable {
    public enum Kind: String, Codable, Sendable, CaseIterable {
        /// A stream of water from the thing's point, down its -Y.
        case pour
        /// A block of water the size of the thing, let go at the start.
        case splash
        case smoke
        case fire

        public var title: String {
            switch self {
            case .pour: "Pour"
            case .splash: "Splash"
            case .smoke: "Smoke"
            case .fire: "Fire"
            }
        }

        public var systemImage: String {
            switch self {
            case .pour: "drop"
            case .splash: "water.waves"
            case .smoke: "smoke"
            case .fire: "flame"
            }
        }

        public var isLiquid: Bool { self == .pour || self == .splash }
    }

    public var kind: Kind
    /// The box it lives in (metres, centred under the thing; at most 4 m a side).
    public var box: Vec3
    /// Pour: litres per second. Smoke and fire: how much (0…1).
    public var amount: Double
    /// Seconds it keeps coming (pour, smoke, fire).
    public var duration: Double
    public var color: RGBA
    /// The stream's width (pour), metres.
    public var width: Double

    public init(kind: Kind, box: Vec3? = nil, amount: Double? = nil, duration: Double = 3, color: RGBA? = nil, width: Double = 0.04) {
        self.kind = kind
        self.box = Self.clamped(box ?? (kind.isLiquid ? Vec3(1, 1, 1) : Vec3(1.2, 2.4, 1.2)))
        self.amount = amount ?? (kind.isLiquid ? 0.5 : 0.6)
        self.duration = duration
        self.color = color ?? Self.defaultColor(kind)
        self.width = width
    }

    public static func clamped(_ box: Vec3) -> Vec3 { box.map { min(max($0, 0.1), 4) } }

    public static func defaultColor(_ kind: Kind) -> RGBA {
        switch kind {
        case .pour, .splash: RGBA.hex("#5AA9E6")
        case .smoke: RGBA.hex("#8C8C92")
        case .fire: RGBA.hex("#FF8A2A")
        }
    }
}
