import Foundation

/// What a real thing is made of, in words. The word decides how heavy it is (its density times its real volume), how it
/// slides and bounces, whether it's stiff, cloth or jelly, and whether a hard knock breaks it. The numbers are one step
/// deeper (`ObjectPhysics` overrides), so nobody needs them to start.
public enum PhysicsMaterial: String, Codable, Sendable, CaseIterable, Identifiable {
    case wood, steel, aluminium, stone, concrete, glass, ice, plastic, rubber, foam, cardboard, cloth, jelly

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .wood: "Wood"
        case .steel: "Steel"
        case .aluminium: "Aluminium"
        case .stone: "Stone"
        case .concrete: "Concrete"
        case .glass: "Glass"
        case .ice: "Ice"
        case .plastic: "Plastic"
        case .rubber: "Rubber"
        case .foam: "Foam"
        case .cardboard: "Cardboard"
        case .cloth: "Cloth"
        case .jelly: "Jelly"
        }
    }

    public var systemImage: String {
        switch self {
        case .wood: "tree"
        case .steel, .aluminium: "wrench.and.screwdriver"
        case .stone, .concrete: "mountain.2"
        case .glass: "wineglass"
        case .ice: "snowflake"
        case .plastic: "cube"
        case .rubber: "circle.circle"
        case .foam: "cloud"
        case .cardboard: "shippingbox"
        case .cloth: "flag"
        case .jelly: "drop"
        }
    }

    /// kg/m³ (cloth: kg/m² of its surface).
    public var density: Double {
        switch self {
        case .wood: 700
        case .steel: 7850
        case .aluminium: 2700
        case .stone: 2600
        case .concrete: 2400
        case .glass: 2500
        case .ice: 917
        case .plastic: 950
        case .rubber: 1100
        case .foam: 30
        case .cardboard: 120
        case .cloth: 0.2
        case .jelly: 1050
        }
    }

    /// Sliding friction against a typical surface (0 slides forever, 1 grips).
    public var friction: Double {
        switch self {
        case .wood: 0.5
        case .steel: 0.45
        case .aluminium: 0.45
        case .stone: 0.7
        case .concrete: 0.75
        case .glass: 0.4
        case .ice: 0.03
        case .plastic: 0.4
        case .rubber: 0.95
        case .foam: 0.7
        case .cardboard: 0.55
        case .cloth: 0.6
        case .jelly: 0.8
        }
    }

    /// How much of its speed a bounce keeps (0 thuds, 1 bounces back as high).
    public var bounce: Double {
        switch self {
        case .wood: 0.3
        case .steel: 0.4
        case .aluminium: 0.35
        case .stone: 0.15
        case .concrete: 0.1
        case .glass: 0.35
        case .ice: 0.1
        case .plastic: 0.5
        case .rubber: 0.82
        case .foam: 0.2
        case .cardboard: 0.15
        case .cloth: 0
        case .jelly: 0.3
        }
    }

    public enum Body: String, Codable, Sendable {
        /// Keeps its shape.
        case rigid
        /// A surface that drapes (Jolt's soft body, no pressure).
        case cloth
        /// A closed surface kept full by pressure: it wobbles and squashes.
        case jelly
    }

    public var body: Body {
        switch self {
        case .cloth: .cloth
        case .jelly: .jelly
        default: .rigid
        }
    }

    /// Breaks by default when knocked hard enough.
    public var breaks: Bool { self == .glass || self == .ice }

    /// The change of speed in one step (m/s) that breaks it: a fall of about a metre for glass.
    public var breakingSpeed: Double {
        switch self {
        case .glass: 3.5
        case .ice: 4.5
        case .stone, .concrete: 9
        case .wood, .cardboard, .plastic, .foam: 12
        default: 20
        }
    }
}
