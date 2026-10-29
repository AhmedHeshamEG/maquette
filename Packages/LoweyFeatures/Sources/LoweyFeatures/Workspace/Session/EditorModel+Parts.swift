import CoreGraphics
import Foundation
import HmmDesign
import LoweyCore
import LoweyEngine

/// Name its parts (Q2 step 3, his words: "being able to choose face, eyes etc."): on a character, the parts the app
/// knows wear a small label; a tap on a piece names it, a circle with the Pencil names an area of a one-piece model. From
/// then on his eye blinks, his mouth makes the 14 mouth shapes and his brows move, bent from his own geometry; our
/// ready-made parts only fill what's missing.
extension EditorModel {
    /// Starts naming the parts of the selected character (or of the thing, made a character first).
    func startNamingParts() {
        guard let id = singleSelection?.id else {
            app.show("Pick the character first")
            return
        }
        if makerCharacter == nil {
            guard let adopt = CharacterMaker.adopt(id, in: baseScene), perform(adopt) else { return }
        }
        guard let root = CharacterMaker.character(of: id, in: baseScene) else { return }
        select(root)
        rigging.person = nil
        rigging.guessing = nil
        rigging.target = root
        rigging.mode = .parts
        rigging.naming = nil
        tool = .rig
        openPanel = nil
        if AppIdentity.isUITesting { trail("naming=\(baseScene.objects[root]?.name ?? "")") }
    }

    /// The character whose parts are being named.
    var namingCharacter: ObjectID? {
        guard tool == .rig, rigging.mode == .parts, let root = rigging.target, baseScene.objects[root]?[.characterStart] != nil else { return nil }
        return root
    }

    /// A tap on the stage with Rig on that a person's dots or naming parts takes (false: it picks as usual).
    func rigTap(at point: CGPoint) -> Bool {
        if rigging.person != nil {
            personTap(at: point)
            return true
        }
        guard rigging.mode == .parts else { return false }
        partsTap(at: point)
        return true
    }

    /// A tap: the piece under it waits for its name. A model in one piece is circled instead.
    func partsTap(at point: CGPoint) {
        guard let root = namingCharacter, let stage, let (id, _) = stage.pickObject(at: point) else { return }
        guard CharacterMaker.character(of: id, in: baseScene) == root else {
            app.show("Tap a piece of \(baseScene.objects[root]?.name ?? "the character")")
            return
        }
        if id == root {
            app.show("Circle its eye or its mouth with the Pencil")
            return
        }
        rigging.naming = PartNaming(piece: id, points: nil)
        HmmHaptics.play(.selection)
    }

    /// A circle with the Pencil: the area of the piece inside it waits for its name (the points of its surface there,
    /// in the piece's own space).
    func circlePart(along path: [CGPoint]) {
        guard let root = namingCharacter, let stage, path.count >= 3 else { return }
        var hits: [ObjectID: [Vec3]] = [:]
        for point in Self.pointsInside(path) {
            guard let (id, hit) = stage.pickObject(at: point), CharacterMaker.character(of: id, in: baseScene) == root else { continue }
            hits[id, default: []].append(hit.point)
        }
        guard let (piece, points) = hits.max(by: { $0.value.count < $1.value.count }), points.count >= 3 else {
            app.show("Circle an area on \(baseScene.objects[root]?.name ?? "the character")")
            return
        }
        let world = baseScene.worldTransform(of: piece)
        rigging.naming = PartNaming(piece: piece, points: points.map(world.inverseApply(to:)))
        HmmHaptics.play(.selection)
    }

    /// The jobs a piece or an area can be named.
    var namingJobs: [CharacterPart.Job] {
        guard let naming = rigging.naming else { return [] }
        return naming.points == nil ? [.head, .eye, .mouth, .brow, .nose, .ear, .hair, .arm, .leg, .tail, .wing] : CharacterRegion.jobs
    }

    /// Names what's waiting: a piece gets its job (it rides its joint), an area becomes a region. The side is where it
    /// sits: right of the character's middle is its right.
    func nameWaitingPart(_ job: CharacterPart.Job) {
        guard let naming = rigging.naming, let root = namingCharacter else { return }
        rigging.naming = nil
        let side = side(of: naming, job: job, root: root)
        let command: EditCommand? = if let points = naming.points {
            CharacterRegion.around(points, job: job, side: side).flatMap { CharacterMaker.nameRegion($0, on: naming.piece, in: baseScene) }
        } else {
            CharacterMaker.assign(naming.piece, as: job, side: side, character: root, in: baseScene)
        }
        guard let command else { return }
        let label = "Name its \(job.title.lowercased())"
        guard perform(CharacterAutoRig.rigging(after: command, root: root, in: document, label: label)) else { return }
        HmmHaptics.play(.commit)
        if AppIdentity.isUITesting { trail("named=\(job.rawValue).\(side.rawValue)") }
    }

    /// Left, right or the middle, from where the piece or area sits in the character's space (it faces +z, so its left
    /// is +x).
    private func side(of naming: PartNaming, job: CharacterPart.Job, root: ObjectID) -> CharacterPart.Side {
        guard job.isPaired else { return .middle }
        let toRoot = Transform.relative(world: baseScene.worldTransform(of: naming.piece), toParent: baseScene.worldTransform(of: root))
        let centre: Vec3 = if let points = naming.points, let area = Bounds(points: points) {
            toRoot.apply(to: area.center)
        } else {
            toRoot.apply(to: baseScene.objects[naming.piece].flatMap { makerBounds($0)?.center } ?? .zero)
        }
        let whole = CharacterAnatomy(root, in: baseScene, shapeBounds: { self.makerBounds($0) })?.bounds
        let middle = whole?.center.x ?? 0
        if abs(centre.x - middle) < (whole?.size.x ?? 1) * 0.04 { return .middle }
        return centre.x > middle ? .left : .right
    }

    /// The face parts it still has none of, for "No mouth yet: add one?".
    var missingFaceParts: [CharacterPart.Job] {
        guard let root = namingCharacter else { return [] }
        let has = CharacterMaker.faceJobs(of: root, in: baseScene)
        return [CharacterPart.Job.eye, .mouth].filter { !has.contains($0) }
    }

    /// The labels on the stage: each named piece and area where it is.
    func partLabelsOnScreen() -> [(label: CharacterMaker.PartLabel, point: CGPoint)] {
        guard let root = namingCharacter, let stage else { return [] }
        let world = baseScene.worldTransform(of: root)
        return CharacterMaker.labels(of: root, in: baseScene, shapeBounds: { self.makerBounds($0) }).compactMap { label in
            stage.screenPoint(of: world.apply(to: label.at)).map { (label, $0) }
        }
    }

    /// Stage points inside a circled path: its outline and a grid inside it (every 8 points), enough to find the area's
    /// surface without looking through every pixel.
    static func pointsInside(_ path: [CGPoint]) -> [CGPoint] {
        guard let minX = path.map(\.x).min(), let maxX = path.map(\.x).max(), let minY = path.map(\.y).min(), let maxY = path.map(\.y).max() else { return [] }
        var points = path
        let step: CGFloat = 8
        var y = minY + step / 2
        while y < maxY {
            var x = minX + step / 2
            while x < maxX {
                if contains(path, CGPoint(x: x, y: y)) { points.append(CGPoint(x: x, y: y)) }
                x += step
            }
            y += step
        }
        return points
    }

    /// Whether a closed path (its last point joined to its first) holds a point (even–odd).
    static func contains(_ path: [CGPoint], _ point: CGPoint) -> Bool {
        var inside = false
        var j = path.count - 1
        for i in path.indices {
            let a = path[i], b = path[j]
            if (a.y > point.y) != (b.y > point.y), point.x < (b.x - a.x) * (point.y - a.y) / (b.y - a.y) + a.x { inside.toggle() }
            j = i
        }
        return inside
    }
}
