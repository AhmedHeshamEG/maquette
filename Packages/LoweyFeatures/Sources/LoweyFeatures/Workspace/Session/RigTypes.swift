import Foundation
import LoweyCore

/// Rig (CONTEXT §10.5, U4): pins and dots placed on a thing, what the Pencil does with them, the person being placed,
/// and the weight brush one step deeper.
public struct RigSettings: Equatable {
    public enum Mode: String, CaseIterable, Identifiable, Sendable {
        /// Pins and dots: the Pencil taps one on, a stroke along a part lays a chain of them; a mark dragged moves, a mark
        /// held goes.
        case marks
        /// The brush adds the chosen bone's weight where it passes (or takes it away).
        case weights
        /// A character's own parts (Q2): a tap names a piece, a circle with the Pencil names an area of a one-piece model.
        case parts

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .marks: "Pins and dots"
            case .weights: "Paint weights"
            case .parts: "Name its parts"
            }
        }

        public var systemImage: String {
            switch self {
            case .marks: "smallcircle.filled.circle"
            case .weights: "paintbrush.pointed"
            case .parts: "face.dashed"
            }
        }
    }

    /// A mark being dragged, and where it is now (rig space), before it lands.
    public struct MarkDrag: Equatable, Sendable {
        public var name: String
        public var position: Vec3
        public var thickness: Double?
    }

    public var mode: Mode = .marks
    /// The object being rigged.
    public var target: ObjectID?
    /// What the Pencil places: a dot (a joint) or a pin (a soft bend).
    public var markKind: RigMark.Kind = .dot
    /// The mark new ones hang from: the last placed, or the one tapped.
    public var current: String?
    public var dragging: MarkDrag?
    /// The joints the stroke under the Pencil would make (the rig's space), shown while it's drawn.
    public var preview: [Vec3] = []
    /// The joint whose weight the brush paints (skeleton index).
    public var joint: Int?
    /// The weight brush takes weight away instead.
    public var erase = false
    /// The quick menu's "Show the bones" switched them off (the marks stay).
    public var hidesBones = false
    /// The weight brush's size in points and how much one pass gives.
    public var size: Double = 40
    public var strength: Double = 0.5
    /// The newest rig whose weights are being worked out, per object: its marks still show, and the next change builds
    /// on it rather than on the rig the object had.
    public var weighing: [ObjectID: ObjectRig] = [:]
    /// Objects whose weights are being worked out.
    public var busy: Set<ObjectID> { Set(weighing.keys) }
    /// "Rig as a person": the dots on the model's front view.
    public var person: PersonRigging?
    /// A body shortcut being guessed (its dots appear when it lands; nothing says so).
    public var guessing: ObjectID?
    /// A piece tapped, or an area circled, waiting for its name (Name its parts).
    public var naming: PartNaming?

    public init() {}
}

/// What "Name its parts" is about to name (Q2): a piece of a character, or an area of one (the points circled, in the
/// piece's own space).
public struct PartNaming: Equatable {
    public var piece: ObjectID
    public var points: [Vec3]?
}

/// The dots of "Rig as a person", in the rig's space on the plane through the model's middle (the stage looks at its
/// front). The guess places them all; a wrong one is dragged.
public struct PersonRigging: Equatable {
    public var target: ObjectID
    public var dots: [HumanRig.Dot: Vec3]
    /// The dots placed by a tap or a drag (their other side follows them until it's placed itself).
    public var placed: Set<HumanRig.Dot>
    /// Whether the shape was read as a person (else the dots stand in the usual places of the model's box).
    public var found: Bool
    /// The bounds of the model in the rig's space.
    public var bounds: Bounds

    public init(target: ObjectID, dots: [HumanRig.Dot: Vec3], placed: Set<HumanRig.Dot>, found: Bool, bounds: Bounds) {
        self.target = target
        self.dots = dots
        self.placed = placed
        self.found = found
        self.bounds = bounds
    }
}
