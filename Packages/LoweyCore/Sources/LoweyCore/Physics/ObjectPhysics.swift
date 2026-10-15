import Foundation

/// A thing made "Real": it has a material, a real mass, and takes part in the scene's simulation. Stored on the object
/// (`SceneObject.physics`); nil means the thing ignores physics entirely (nothing collides with it).
public struct ObjectPhysics: Codable, Hashable, Sendable {
    public enum Motion: String, Codable, Sendable, CaseIterable {
        /// Falls, collides, is pushed (a dynamic body).
        case falls
        /// Stays where it is; others land on it (static).
        case stays
        /// Moves only by its keys and pushes what it meets (kinematic). "Keep it" leaves things like this.
        case follows

        public var title: String {
            switch self {
            case .falls: "Falls"
            case .stays: "Stays put"
            case .follows: "Follows its keys"
            }
        }
    }

    public var material: PhysicsMaterial
    public var motion: Motion
    /// kg. Nil: the material's density times the real volume.
    public var mass: Double?
    public var friction: Double?
    public var bounce: Double?
    /// m/s at the start, in world space.
    public var startSpeed: Vec3?
    /// rad/s at the start, in world space.
    public var startSpin: Vec3?
    /// Breaks into pieces when knocked hard (nil: the material decides).
    public var breaks: Bool?
    /// Cloth and jelly: how stiff (0 floppy … 1 stiff).
    public var stiffness: Double?
    /// Cloth: hangs from its top edge (a flag, a curtain) instead of falling whole.
    public var hangs: Bool?

    public init(material: PhysicsMaterial = .wood, motion: Motion = .falls, mass: Double? = nil, friction: Double? = nil,
                bounce: Double? = nil, startSpeed: Vec3? = nil, startSpin: Vec3? = nil, breaks: Bool? = nil, stiffness: Double? = nil,
                hangs: Bool? = nil) {
        self.material = material
        self.motion = motion
        self.mass = mass
        self.friction = friction
        self.bounce = bounce
        self.startSpeed = startSpeed
        self.startSpin = startSpin
        self.breaks = breaks
        self.stiffness = stiffness
        self.hangs = hangs
    }

    public var effectiveFriction: Double { friction ?? material.friction }
    public var effectiveBounce: Double { bounce ?? material.bounce }
    public var effectiveBreaks: Bool { breaks ?? material.breaks }
    public var effectiveStiffness: Double { stiffness ?? (material == .jelly ? 0.35 : 0.8) }
}

/// The pull every thing feels.
public enum GravityPreset: String, Codable, Sendable, CaseIterable, Identifiable {
    case earth, moon, mars, jupiter, none

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .earth: "Earth"
        case .moon: "Moon"
        case .mars: "Mars"
        case .jupiter: "Jupiter"
        case .none: "Floating"
        }
    }

    /// m/s².
    public var acceleration: Double {
        switch self {
        case .earth: 9.81
        case .moon: 1.62
        case .mars: 3.71
        case .jupiter: 24.79
        case .none: 0
        }
    }
}

/// How two things are joined in a mechanism. Anchors and axes are in the first thing's own space, so moving it moves
/// the joint.
public struct PhysicsJoint: Codable, Hashable, Sendable, Identifiable {
    public enum Kind: String, Codable, Sendable, CaseIterable {
        /// Turns about an axis (a door, a wheel). A motor turns it.
        case hinge
        /// Slides along an axis (a drawer, a piston). A motor drives it.
        case slider
        /// Turns any way about a point (a shoulder, a pendulum).
        case ball
        /// Stuck together.
        case glue
        /// A spring between two points.
        case spring
        /// A rope: no closer pull, never farther than its length.
        case rope
        /// Two hinges turning together at a ratio (gears, belts).
        case gear

        public var title: String {
            switch self {
            case .hinge: "Hinge"
            case .slider: "Slider"
            case .ball: "Ball joint"
            case .glue: "Glue"
            case .spring: "Spring"
            case .rope: "Rope"
            case .gear: "Gear"
            }
        }

        public var systemImage: String {
            switch self {
            case .hinge: "door.left.hand.open"
            case .slider: "arrow.left.and.right"
            case .ball: "circle.dotted"
            case .glue: "link"
            case .spring: "alternatingcurrent"
            case .rope: "line.diagonal"
            case .gear: "gearshape.2"
            }
        }
    }

    public var id: String
    public var kind: Kind
    public var first: ObjectID
    /// Nil: the world (a hinge on a wall that doesn't move).
    public var second: ObjectID?
    /// In `first`'s own space.
    public var anchor: Vec3
    /// The second thing's point (springs and ropes), in its own space (world space when it's the world).
    public var otherAnchor: Vec3?
    /// The axis a hinge turns about or a slider slides along, in `first`'s own space.
    public var axis: Vec3
    /// Degrees for hinges, metres for sliders; nil = free.
    public var limits: ClosedRange<Double>?
    /// Degrees per second for hinges, m/s for sliders; nil = no motor.
    public var motorSpeed: Double?
    /// N·m or N; nil: strong enough for anything in the scene.
    public var motorStrength: Double?
    /// Springs: oscillations per second.
    public var springiness: Double?
    /// Springs and ropes: rest length (nil: the distance at the start).
    public var length: Double?
    /// Gears: the two hinge joints and the ratio of their turns.
    public var gears: [String]?
    public var ratio: Double?

    public init(id: String, kind: Kind, first: ObjectID, second: ObjectID? = nil, anchor: Vec3 = .zero, otherAnchor: Vec3? = nil,
                axis: Vec3 = .unitY, limits: ClosedRange<Double>? = nil, motorSpeed: Double? = nil, motorStrength: Double? = nil,
                springiness: Double? = nil, length: Double? = nil, gears: [String]? = nil, ratio: Double? = nil) {
        self.id = id
        self.kind = kind
        self.first = first
        self.second = second
        self.anchor = anchor
        self.otherAnchor = otherAnchor
        self.axis = axis
        self.limits = limits
        self.motorSpeed = motorSpeed
        self.motorStrength = motorStrength
        self.springiness = springiness
        self.length = length
        self.gears = gears
        self.ratio = ratio
    }
}

/// The scene's physics: gravity and wind (behind the scene's name), the ground, the joints, and when the run starts.
public struct ScenePhysics: Codable, Hashable, Sendable {
    public var gravity: GravityPreset
    /// m/s² when set (overrides the preset).
    public var customGravity: Double?
    /// Wind: where it blows toward (degrees around Y, 0 = toward -Z) and its speed (m/s).
    public var windHeading: Double
    public var windSpeed: Double
    /// Gusts: 0 steady … 1 gusty.
    public var gusts: Double
    /// A solid ground at y = 0.
    public var ground: Bool
    public var groundMaterial: PhysicsMaterial
    public var joints: [PhysicsJoint]
    /// Seconds into the timeline when things start to move (they hold their place before).
    public var start: Double

    public init(gravity: GravityPreset = .earth, customGravity: Double? = nil, windHeading: Double = 0, windSpeed: Double = 0,
                gusts: Double = 0.3, ground: Bool = true, groundMaterial: PhysicsMaterial = .concrete, joints: [PhysicsJoint] = [],
                start: Double = 0) {
        self.gravity = gravity
        self.customGravity = customGravity
        self.windHeading = windHeading
        self.windSpeed = windSpeed
        self.gusts = gusts
        self.ground = ground
        self.groundMaterial = groundMaterial
        self.joints = joints
        self.start = start
    }

    public var acceleration: Double { customGravity ?? gravity.acceleration }

    /// The wind's velocity (m/s) at a moment: steady plus seeded gusts, the same every run.
    public func wind(at time: Double) -> Vec3 {
        guard windSpeed > 0 else { return .zero }
        let heading = windHeading * .pi / 180
        let direction = Vec3(sin(heading), 0, -cos(heading))
        let gust = 1 + gusts * 0.45 * (sin(time * 1.7) * 0.6 + sin(time * 4.3 + 1.1) * 0.4)
        return direction * (windSpeed * max(gust, 0))
    }
}

public extension SceneObject {
    /// Things that take part in the simulation as bodies.
    var isReal: Bool { physics != nil }
}
