import Foundation

/// Pointing at a character's own parts (Q2 step 3): an area of a piece named as its eye, mouth or brow (a region), and
/// what the character already has, so the panel can say what's missing.
public extension CharacterMaker {
    /// Names an area of a piece of a character: a region with that job and side replaces the old one (naming the
    /// left eye again moves it). Nil when the piece isn't part of a character or the job has no face states.
    static func nameRegion(_ region: CharacterRegion, on piece: ObjectID, in scene: Scene) -> EditCommand? {
        guard CharacterRegion.jobs.contains(region.job), let object = scene.objects[piece], character(of: piece, in: scene) != nil else { return nil }
        var part = object.part ?? CharacterPart(job: .extra, style: "modelled")
        part.regions.removeAll { $0.job == region.job && $0.side == region.side }
        part.regions.append(region)
        return .setPart(piece, part)
    }

    /// Takes a named region away (the area goes back to being just the model).
    static func removeRegion(_ job: CharacterPart.Job, side: CharacterPart.Side, on piece: ObjectID, in scene: Scene) -> EditCommand? {
        guard var part = scene.objects[piece]?.part, part.regions.contains(where: { $0.job == job && $0.side == side }) else { return nil }
        part.regions.removeAll { $0.job == job && $0.side == side }
        return .setPart(piece, part)
    }

    /// The face jobs a character has, from its pieces and its named regions.
    static func faceJobs(of root: ObjectID, in scene: Scene) -> Set<CharacterPart.Job> {
        var jobs: Set<CharacterPart.Job> = []
        for id in scene.subtree(of: root) {
            guard let part = scene.objects[id]?.part else { continue }
            if part.job.isFace, part.shows == nil { jobs.insert(part.job) }
            jobs.formUnion(part.regions.map(\.job))
        }
        return jobs
    }

    /// A label a character's part wears on the stage (Q2): a piece with a job, or a named region.
    struct PartLabel: Hashable, Sendable {
        public var piece: ObjectID
        public var job: CharacterPart.Job
        public var side: CharacterPart.Side
        /// Where it is, in the character's own space.
        public var at: Vec3
        public var isRegion: Bool
    }

    /// The labels of a character's parts: each piece with a job (not a model that is its own body), and each region.
    static func labels(of root: ObjectID, in scene: Scene, shapeBounds: (SceneObject) -> Bounds? = CharacterAnatomy.coreBounds) -> [PartLabel] {
        guard let anatomy = CharacterAnatomy(root, in: scene, shapeBounds: shapeBounds) else { return [] }
        var result: [PartLabel] = []
        for piece in anatomy.pieces where piece.part.shows == nil {
            if piece.part.style != ownBodyStyle, let bounds = piece.rootBounds {
                result.append(PartLabel(piece: piece.id, job: piece.part.job, side: piece.part.side, at: bounds.center, isRegion: false))
            }
            for region in piece.part.regions {
                result.append(PartLabel(piece: piece.id, job: region.job, side: region.side, at: piece.toRoot.apply(to: region.bounds.center), isRegion: true))
            }
        }
        return result
    }
}
