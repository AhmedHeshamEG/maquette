import Foundation

/// Changing parts that are there: another style from the set, taking a part away, and making any thing a part (a
/// drawing becomes the mouth, a modelled horn becomes an extra, a drawn "oh" becomes the mouth's Oh).
public extension CharacterMaker {
    /// The pieces of the part a piece belongs to (every piece of its limb), and of its mirror when `mirrored`.
    static func partPieces(of id: ObjectID, in scene: Scene, mirrored: Bool) -> [ObjectID] {
        guard let part = scene.objects[id]?.part, let root = character(of: id, in: scene) else { return [id] }
        guard part.job.segments > 1 || (mirrored && part.job.isPaired) else { return [id] }
        return scene.subtree(of: root).filter { other in
            guard let candidate = scene.objects[other]?.part, candidate.shows == nil else { return false }
            if part.job.segments > 1 { return candidate.sameLimb(as: part, mirrored: mirrored) }
            return candidate.job == part.job && candidate.side == part.side.mirror && scene.objects[other]?.parent == scene.objects[id]?.parent
        } + (part.job.segments > 1 ? [] : [id])
    }

    /// Another style for a part (and its mirror): each piece takes the style's mesh, the pieces below a joint follow the new
    /// lengths, and an eye's pupil comes or goes with the style.
    static func restyle(_ id: ObjectID, to style: String, mirrored: Bool, in scene: Scene, ids: inout IDFactory) -> EditCommand? {
        let pieces = partPieces(of: id, in: scene, mirrored: mirrored)
        var commands: [EditCommand] = []
        var byLimb: [String: [(ObjectID, CharacterPart)]] = [:]
        for piece in pieces {
            guard let object = scene.objects[piece], var part = object.part, part.style != "drawn", part.style != "modelled" else { continue }
            let mesh = PartSet.mesh(part.job, style: style, segment: part.segment, side: part.side)
            commands.append(.setKind(piece, .mesh(savable(mesh))))
            part.style = style
            commands.append(.setPart(piece, part))
            byLimb["\(part.side.rawValue)|\(part.limb)", default: []].append((piece, part))
            if part.job == .eye { commands += pupilChange(of: object, part: part, style: style, in: scene, ids: &ids) }
        }
        // The pieces of a limb hang again from where the new upper ends.
        for (_, limb) in byLimb {
            let sorted = limb.sorted { $0.1.segment < $1.1.segment }
            guard sorted.count > 1, var place = scene.objects[sorted[0].0]?.transform else { continue }
            for (index, (piece, part)) in sorted.enumerated() where index > 0 {
                place.position = place.apply(to: PartSet.nextPivot(part.job, style: style, segment: index - 1, side: part.side))
                place.rotation = scene.objects[piece]?.transform.rotation ?? place.rotation
                commands.append(.setProperties([PropertyChange(object: piece, key: .position, value: .vec3(place.position))]))
            }
        }
        return commands.isEmpty ? nil : .batch("Change \(scene.objects[id]?.part?.job.title.lowercased() ?? "part")", commands)
    }

    internal static func pupilChange(of eye: SceneObject, part: CharacterPart, style: String, in scene: Scene, ids: inout IDFactory) -> [EditCommand] {
        let pupils = eye.children.filter { scene.objects[$0]?[.faceRole]?.stringValue?.hasPrefix("pupil.") == true }
        var commands: [EditCommand] = pupils.isEmpty ? [] : [.delete(pupils)]
        if let pupil = PartSet.pupil(for: style) {
            let range = PartSet.mesh(.eye, style: style).bounds?.size.x ?? 0.1
            let object = object(Piece(id: ids.next(), parent: eye.id, name: "Pupil", part: nil, mesh: pupil, transform: .identity,
                                      colour: RGBA.hex("#1E1A1C"), role: part.pupilRole, range: range))
            commands.append(.insert(SceneFragment(objects: [object], roots: [object.id]), parent: eye.id, index: nil))
        }
        return commands
    }

    /// Takes a part away (every piece of its limb, and its mirror when `mirrored`).
    static func remove(_ id: ObjectID, mirrored: Bool, in scene: Scene) -> EditCommand {
        .delete(partPieces(of: id, in: scene, mirrored: mirrored))
    }

    /// Makes a thing a part of the character nearest it (or of `character`): it moves under the head for a face part, an
    /// ear, hair or an extra, else under the character, keeping where it is. `shows` makes it the drawing of a face state.
    static func assign(_ id: ObjectID, as job: CharacterPart.Job, side: CharacterPart.Side = .middle, shows: String? = nil,
                       character: ObjectID, in scene: Scene) -> EditCommand? {
        guard let object = scene.objects[id], scene.objects[character] != nil, id != character else { return nil }
        let anatomy = CharacterAnatomy(character, in: scene)
        let onHead = job.isFace || [.ear, .hair, .extra].contains(job)
        let host = onHead ? (anatomy?.head?.id ?? anatomy?.body?.id ?? character) : character
        let style = object.kind.isDrawing ? "drawn" : "modelled"
        var part = object.part ?? CharacterPart(job: job, side: side, style: style)
        part.job = job
        part.side = side
        part.shows = shows
        var commands: [EditCommand] = []
        if object.parent != host {
            let local = Transform.relative(world: scene.worldTransform(of: id), toParent: scene.worldTransform(of: host))
            commands.append(.reparent([ReparentEntry(object: id, parent: host, transform: local)]))
        }
        commands.append(.setPart(id, part))
        if let role = part.faceRole, shows == nil {
            commands.append(.setProperties([PropertyChange(object: id, key: .faceRole, value: .string(role))]))
        }
        let title = shows.map { "Draw \(FaceStates.title($0))" } ?? "Make it the \(job.title.lowercased())"
        return .batch(title, commands)
    }

    /// Changes one face state of a part (and its mirror's): the bend the person set, or back to the default (nil).
    static func setState(_ state: String, of id: ObjectID, to bend: FaceBend?, mirrored: Bool, in scene: Scene) -> EditCommand? {
        let pieces = partPieces(of: id, in: scene, mirrored: mirrored)
        let commands = pieces.compactMap { piece -> EditCommand? in
            guard var part = scene.objects[piece]?.part else { return nil }
            part.states[state] = bend
            return .setPart(piece, part)
        }
        return commands.isEmpty ? nil : .batch("\(FaceStates.title(state)) face", commands)
    }
}

extension ObjectKind {
    var isDrawing: Bool {
        if case .drawing = self { return true }
        return false
    }
}
