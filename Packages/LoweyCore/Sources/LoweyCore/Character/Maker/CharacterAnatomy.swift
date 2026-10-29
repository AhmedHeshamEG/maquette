import Foundation

/// A made character as the maker reads it from the scene: its parts by job, and where its head and body are in the
/// character's own space. Everything the maker does to a character (add a part, rig it, change a proportion) starts
/// from this, so a part moved, recoloured or remodelled by hand is never undone by the maker.
public struct CharacterAnatomy: Sendable {
    public struct Piece: Sendable {
        public var id: ObjectID
        public var parent: ObjectID?
        public var part: CharacterPart
        /// From the piece's own space to the character's.
        public var toRoot: Transform
        /// Its shape's bounds in its own space (nil when nothing is known about its shape).
        public var bounds: Bounds?

        /// Its bounds in the character's space.
        public var rootBounds: Bounds? {
            guard let bounds else { return nil }
            let corners = [bounds.min, bounds.max, Vec3(bounds.min.x, bounds.min.y, bounds.max.z), Vec3(bounds.min.x, bounds.max.y, bounds.min.z),
                           Vec3(bounds.max.x, bounds.min.y, bounds.min.z), Vec3(bounds.max.x, bounds.max.y, bounds.min.z),
                           Vec3(bounds.max.x, bounds.min.y, bounds.max.z), Vec3(bounds.min.x, bounds.max.y, bounds.max.z)]
            return Bounds(points: corners.map(toRoot.apply(to:)))
        }
    }

    public var root: ObjectID
    public var start: CharacterStart
    public var pieces: [Piece]

    /// Reads a character. `shapeBounds` gives a thing's shape bounds in its own space (Core knows meshes, shapes and
    /// drawings; the app adds placed models).
    public init?(_ root: ObjectID, in scene: Scene, shapeBounds: (SceneObject) -> Bounds? = CharacterAnatomy.coreBounds) {
        guard let object = scene.objects[root] else { return nil }
        self.root = root
        start = object[.characterStart]?.stringValue.flatMap(CharacterStart.init(rawValue:)) ?? .nothing
        let rootWorld = scene.worldTransform(of: root)
        // A thing made a character is its own body (Q2): the root counts as a piece when it has a job.
        pieces = scene.subtree(of: root).compactMap { id -> Piece? in
            guard let child = scene.objects[id], let part = child.part else { return nil }
            if id == root { return Piece(id: id, parent: nil, part: part, toRoot: .identity, bounds: shapeBounds(child)) }
            let toRoot = Transform.relative(world: scene.worldTransform(of: id), toParent: rootWorld)
            return Piece(id: id, parent: child.parent, part: part, toRoot: toRoot, bounds: shapeBounds(child))
        }
    }

    /// What Core knows of a thing's shape.
    public static func coreBounds(_ object: SceneObject) -> Bounds? {
        if case let .primitive(shape) = object.kind { return PrimitiveMesh.bounds(shape) }
        return PaintSource.mesh(of: object)?.bounds
    }

    public func pieces(_ job: CharacterPart.Job) -> [Piece] {
        pieces.filter { $0.part.job == job }
    }

    public var head: Piece? { pieces(.head).first }
    public var body: Piece? { pieces(.body).first }

    /// The pieces of one limb, upper first.
    public func limb(_ job: CharacterPart.Job, side: CharacterPart.Side, limb: String = "") -> [Piece] {
        pieces.filter { $0.part.job == job && $0.part.side == side && $0.part.limb == limb }.sorted { $0.part.segment < $1.part.segment }
    }

    /// Every limb of a job, as (side, limb name).
    public func limbs(_ job: CharacterPart.Job) -> [(side: CharacterPart.Side, limb: String)] {
        var seen: [(CharacterPart.Side, String)] = []
        for piece in pieces(job) where !seen.contains(where: { $0.0 == piece.part.side && $0.1 == piece.part.limb }) {
            seen.append((piece.part.side, piece.part.limb))
        }
        return seen
    }

    /// The legs stand under a body lying along z (four legs) rather than an upright one.
    public var walksOnFour: Bool {
        limbs(.leg).contains { $0.limb == "front" } || start == .fourLegs
    }

    /// Everything's bounds together, in the character's space.
    public var bounds: Bounds? {
        Bounds(points: pieces.compactMap(\.rootBounds).flatMap { [$0.min, $0.max] })
    }
}

public extension Bounds {
    /// The point on an ellipsoid filling these bounds, seen from the front (+z), at a fraction across (−1…1) and up
    /// (0…1): where a face part sits on a head.
    func front(across u: Double, up v: Double) -> Vec3 {
        let centre = center
        let half = size / 2
        let x = centre.x + u * half.x
        let y = min.y + v * size.y
        let du = u, dv = (y - centre.y) / Swift.max(half.y, 1e-6)
        let depth = (Swift.max(1 - du * du - dv * dv, 0.05)).squareRoot()
        return Vec3(x, y, centre.z + half.z * depth)
    }
}
