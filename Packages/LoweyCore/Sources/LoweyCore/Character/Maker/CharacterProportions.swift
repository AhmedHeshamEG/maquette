import Foundation

/// Proportions by hand (K1 step 4): drag the head bigger, the legs longer, pinch the waist. Each change is made to the
/// parts as they stand (so a part moved or remodelled by hand stays as it is), the limbs keep hanging from their joints,
/// and longer legs lift the body so the feet stay on the ground. Symmetry changes both sides; off, only the side touched.
public enum CharacterProportions {
    public enum Measure: String, CaseIterable, Sendable, Identifiable {
        case height, head, body, waist, arms, legs

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .height: "Height"
            case .head: "Head"
            case .body: "Body"
            case .waist: "Waist"
            case .arms: "Arms"
            case .legs: "Legs"
            }
        }
    }

    /// Each measure in metres as the character stands (the whole height; the head's and body's heights; the body's
    /// width; an arm's and a leg's reach). A measure the character has no part for is missing.
    public static func measure(_ anatomy: CharacterAnatomy, rootScale: Double = 1) -> [Measure: Double] {
        var result: [Measure: Double] = [:]
        if let bounds = anatomy.bounds { result[.height] = bounds.size.y * rootScale }
        if let head = anatomy.head?.rootBounds { result[.head] = head.size.y * rootScale }
        if let body = anatomy.body?.rootBounds {
            result[.body] = body.size.y * rootScale
            result[.waist] = body.size.x * rootScale
        }
        for (job, measure) in [(CharacterPart.Job.arm, Measure.arms), (.leg, .legs)] {
            if let limb = anatomy.limbs(job).first {
                result[measure] = reach(anatomy.limb(job, side: limb.side, limb: limb.limb)) * rootScale
            }
        }
        return result
    }

    /// From a limb's top to the far end of its last piece.
    static func reach(_ pieces: [CharacterAnatomy.Piece]) -> Double {
        guard let first = pieces.first, let last = pieces.last, let bounds = last.rootBounds else { return 0 }
        return max(first.toRoot.position.y - bounds.min.y, first.toRoot.position.distance(to: bounds.center) * 1.2)
    }

    /// Changes a measure by `factor` (1.2 is a fifth bigger). `side` limits a limb change to one side (symmetry off).
    public static func change(_ measure: Measure, by factor: Double, anatomy: CharacterAnatomy, scene: Scene,
                              side: CharacterPart.Side? = nil) -> EditCommand? {
        let factor = min(max(factor, 0.2), 5)
        guard abs(factor - 1) > 1e-6 else { return nil }
        let changes: [PropertyChange] = switch measure {
        case .height: scaled(anatomy.root, by: Vec3(factor, factor, factor), in: scene)
        case .head: anatomy.head.map { scaled($0.id, by: Vec3(factor, factor, factor), in: scene) } ?? []
        case .body: bodyHeight(anatomy, factor: factor, scene: scene)
        case .waist: waist(anatomy, factor: factor, scene: scene)
        case .arms: limbLength(.arm, anatomy: anatomy, factor: factor, scene: scene, side: side)
        case .legs: limbLength(.leg, anatomy: anatomy, factor: factor, scene: scene, side: side)
        }
        return changes.isEmpty ? nil : .batch("\(measure.title) \(factor > 1 ? "bigger" : "smaller")", [.setProperties(changes)])
    }

    static func scaled(_ id: ObjectID, by factor: Vec3, in scene: Scene) -> [PropertyChange] {
        guard let object = scene.objects[id] else { return [] }
        return [PropertyChange(object: id, key: .scale, value: .vec3(object.transform.scale.scaled(by: factor)))]
    }

    /// The upper pieces of each limb stretch along their length; the pieces below follow; longer legs lift the rest.
    static func limbLength(_ job: CharacterPart.Job, anatomy: CharacterAnatomy, factor: Double, scene: Scene,
                           side: CharacterPart.Side?) -> [PropertyChange] {
        var changes: [PropertyChange] = []
        var lowest = Double.infinity
        let before = anatomy.pieces(job).compactMap(\.rootBounds).map(\.min.y).min() ?? 0
        for limb in anatomy.limbs(job) where side == nil || limb.side == side {
            let pieces = anatomy.limb(job, side: limb.side, limb: limb.limb).compactMap { piece in scene.objects[piece.id].map { (piece, $0) } }
            guard var place = pieces.first?.1.transform else { continue }
            for (index, (piece, object)) in pieces.enumerated() {
                var transform = object.transform
                if index > 0 { transform.position = place.position }
                // The hand or foot keeps its size; the bones between grow.
                if index < pieces.count - 1 { transform.scale.y *= factor }
                let next = PartSet.nextPivot(job, style: piece.part.style, segment: piece.part.segment, side: piece.part.side)
                if let bounds = piece.bounds {
                    lowest = min(lowest, Bounds(points: corners(of: bounds).map(transform.apply(to:)))?.min.y ?? lowest)
                }
                place = transform
                place.position = transform.apply(to: next)
                changes.append(PropertyChange(object: piece.id, key: .scale, value: .vec3(transform.scale)))
                changes.append(PropertyChange(object: piece.id, key: .position, value: .vec3(transform.position)))
            }
        }
        // Legs lift everything by as much as their lowest point went down.
        let rise = lowest.isFinite ? before - lowest : 0
        guard job == .leg, abs(rise) > 1e-9 else { return changes }
        return lifted(changes, anatomy: anatomy, by: rise, scene: scene)
    }

    static func corners(of bounds: Bounds) -> [Vec3] {
        [0, 1].flatMap { x in [0, 1].flatMap { y in [0, 1].map { z in
            Vec3(x == 0 ? bounds.min.x : bounds.max.x, y == 0 ? bounds.min.y : bounds.max.y, z == 0 ? bounds.min.z : bounds.max.z)
        } } }
    }

    /// Everything the character holds up, lifted with the legs' tops (so the feet stay where they stand).
    static func lifted(_ changes: [PropertyChange], anatomy: CharacterAnatomy, by rise: Double, scene: Scene) -> [PropertyChange] {
        var result = changes
        let changed = Set(changes.map(\.object))
        for piece in anatomy.pieces where piece.parent == anatomy.root {
            if piece.part.job == .leg {
                // A leg piece already moved: lift what it was given.
                for index in result.indices where result[index].object == piece.id && result[index].key == .position {
                    if case let .vec3(position)? = result[index].value { result[index].value = .vec3(position + Vec3(0, rise, 0)) }
                }
            } else if !changed.contains(piece.id), let object = scene.objects[piece.id] {
                result.append(PropertyChange(object: piece.id, key: .position, value: .vec3(object.transform.position + Vec3(0, rise, 0))))
            }
        }
        return result
    }

    /// The body grows taller from where it stands; what sits on it rises with the height it sits at.
    static func bodyHeight(_ anatomy: CharacterAnatomy, factor: Double, scene: Scene) -> [PropertyChange] {
        // A model made a character is its own body: it changes by hand, not by the maker's handles.
        guard let body = anatomy.body, body.id != anatomy.root, let bounds = body.rootBounds else { return [] }
        let grow = bounds.size.y * (factor - 1)
        var changes = scaled(body.id, by: Vec3(1, factor, 1), in: scene)
        changes += carried(anatomy, scene: scene, except: [.body, .leg]) { top in
            let t = min(max((top.y - bounds.min.y) / max(bounds.size.y, 1e-6), 0), 1)
            return Vec3(0, grow * t, 0)
        }
        return changes
    }

    /// The body narrows or widens; arms, legs and wings move in or out with its sides.
    static func waist(_ anatomy: CharacterAnatomy, factor: Double, scene: Scene) -> [PropertyChange] {
        // A model made a character is its own body: it changes by hand, not by the maker's handles.
        guard let body = anatomy.body, body.id != anatomy.root, let bounds = body.rootBounds else { return [] }
        var changes = scaled(body.id, by: Vec3(factor, 1, factor), in: scene)
        changes += carried(anatomy, scene: scene, except: [.body, .head, .hair]) { top in
            Vec3((top.x - bounds.center.x) * (factor - 1), 0, 0)
        }
        return changes
    }

    /// Moves the character's other parts (each limb as one, by its top) by what `offset` says for where they hang.
    static func carried(_ anatomy: CharacterAnatomy, scene: Scene, except: Set<CharacterPart.Job>, offset: (Vec3) -> Vec3) -> [PropertyChange] {
        var changes: [PropertyChange] = []
        var tops: [String: Vec3] = [:]
        for piece in anatomy.pieces where piece.parent == anatomy.root && piece.part.segment == 0 {
            tops["\(piece.part.job.rawValue)|\(piece.part.side.rawValue)|\(piece.part.limb)"] = piece.toRoot.position
        }
        for piece in anatomy.pieces where piece.parent == anatomy.root && !except.contains(piece.part.job) {
            guard let object = scene.objects[piece.id] else { continue }
            let top = tops["\(piece.part.job.rawValue)|\(piece.part.side.rawValue)|\(piece.part.limb)"] ?? piece.toRoot.position
            let move = offset(top)
            guard move.length > 1e-9 else { continue }
            changes.append(PropertyChange(object: piece.id, key: .position, value: .vec3(object.transform.position + move)))
        }
        return changes
    }
}
