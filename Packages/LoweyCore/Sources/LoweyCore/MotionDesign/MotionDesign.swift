import Foundation

/// Motion design on a thing (D1): copies of it laid out and rippled (`clones`), a morph into another thing's shape
/// (`morph`), and letters that animate (`letters`, for 3D text). Each is optional; an empty one is removed.
public struct MotionDesign: Codable, Hashable, Sendable {
    public var clones: ObjectClones?
    public var morph: ObjectMorph?
    public var letters: TextAnimator?

    public init(clones: ObjectClones? = nil, morph: ObjectMorph? = nil, letters: TextAnimator? = nil) {
        self.clones = clones
        self.morph = morph
        self.letters = letters
    }

    public var isEmpty: Bool { clones == nil && morph == nil && letters == nil }

    /// nil when empty, so a thing without motion design carries nothing.
    public var orNil: MotionDesign? { isEmpty ? nil : self }
}

/// A thing becoming another thing's shape: `morph` (0…1, keyed) is how far along it is. The other thing is the shape
/// to reach; it is hidden while it serves as one.
public struct ObjectMorph: Codable, Hashable, Sendable {
    public var target: ObjectID

    public init(target: ObjectID) {
        self.target = target
    }
}

public extension PropertyKey {
    /// 0…1: how far a morph has gone into its target's shape.
    static let morph: PropertyKey = "morph"
    /// How strongly a thing's clone effects act (1 = as set; 0 = off). Keyed or linked to a sound for a ripple on the beat.
    static let effectStrength: PropertyKey = "effectStrength"
    /// Marks a copy made by a cloner in the shown scene: the id of the thing it copies (never stored in a project).
    static let cloneOf: PropertyKey = "cloneOf"
}

extension PropertySpec {
    static let motionDesign: [PropertyKey: PropertySpec] = [
        .morph: PropertySpec(type: .float, animatable: true, label: "Morph"),
        .effectStrength: PropertySpec(type: .float, animatable: true, label: "Effect strength"),
        .cloneOf: PropertySpec(type: .string, animatable: false, label: "Copy of")
    ]
}

public extension SceneObject {
    /// The copy made by a cloner this is, or nil for a real thing.
    var cloneSource: ObjectID? { self[.cloneOf]?.stringValue.map { ObjectID(raw: $0) } }

    var morphAmount: Double { min(max(self[.morph]?.floatValue ?? 0, 0), 1) }
}
