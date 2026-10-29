import Foundation

/// Adding, restyling, removing and naming parts (K1 step 1): parts are optional and repeatable, and they attach to any
/// thing (a teapot gets hands, a rock gets eyes: the thing becomes the body of a new character).
public extension CharacterMaker {
    /// A change the maker made: one command, the character it's on, and the things it made.
    struct Change {
        public var command: EditCommand
        public var root: ObjectID
        public var made: [ObjectID]
    }

    /// The made character a thing belongs to (itself, or the nearest group above it that was started in the maker).
    static func character(of id: ObjectID, in scene: Scene) -> ObjectID? {
        var current: ObjectID? = id
        while let at = current, let object = scene.objects[at] {
            if object[.characterStart] != nil { return at }
            current = object.parent
        }
        return nil
    }

    /// Adds a part to a character, or to any thing (which becomes the body of a new character). Paired jobs come as a
    /// mirrored pair when `symmetric`; a part added again is another one (a third eye, a second pair of arms).
    static func add(_ job: CharacterPart.Job, style: String? = nil, to target: ObjectID, symmetric: Bool = true, in scene: Scene,
                    ids: inout IDFactory, shapeBounds: (SceneObject) -> Bounds? = CharacterAnatomy.coreBounds) -> Change? {
        let styleChosen = style != nil
        let style = style ?? PartSet.defaultStyle(for: job)
        var commands: [EditCommand] = []
        var working = scene
        let root: ObjectID
        if let existing = character(of: target, in: scene) {
            root = existing
        } else {
            guard let wrap = wrap(target, in: scene, ids: &ids) else { return nil }
            root = wrap.root
            commands += wrap.commands
            working = wrap.scene
        }
        guard let anatomy = CharacterAnatomy(root, in: working, shapeBounds: shapeBounds) else { return nil }
        var builder = Builder(ids: ids)
        var plans: [(parent: ObjectID, made: [ObjectID])] = []
        var rise = 0.0
        if job.segments > 1 {
            let (made, lift) = addLimbs(job, style: style, symmetric: symmetric, anatomy: anatomy, builder: &builder)
            plans.append((root, made))
            rise = lift
        } else {
            plans += addSingles(job, style: style, styleChosen: styleChosen, symmetric: symmetric, anatomy: anatomy, builder: &builder)
        }
        ids = builder.ids
        for plan in plans where !plan.made.isEmpty {
            let objects = builder.objects.filter { object in plan.made.contains(object.id) || plan.made.contains { builder.isAncestor($0, of: object.id) } }
            commands.append(.insert(SceneFragment(objects: objects, roots: plan.made), parent: plan.parent, index: nil))
        }
        if rise > 1e-6 { commands.append(raising(anatomy, by: rise, except: job)) }
        let made = plans.flatMap(\.made)
        guard !made.isEmpty else { return nil }
        return Change(command: .batch("Add \(job.title.lowercased())", commands), root: root, made: made)
    }

    /// A thing that isn't a character yet becomes one: a new group where it stands (its turn kept), with the thing as its
    /// body. Returns the commands and the scene as it will be after them.
    internal static func wrap(_ target: ObjectID, in scene: Scene, ids: inout IDFactory) -> (root: ObjectID, commands: [EditCommand], scene: Scene)? {
        guard let thing = scene.objects[target] else { return nil }
        let world = scene.worldTransform(of: target)
        let parentWorld = thing.parent.map { scene.worldTransform(of: $0) } ?? .identity
        var group = SceneObject(id: ids.next(), name: thing.name, kind: .group, parent: thing.parent,
                                transform: Transform.relative(world: Transform(position: world.position, rotation: world.rotation), toParent: parentWorld))
        group[.characterStart] = .enumeration(CharacterStart.nothing.rawValue)
        group[.mouth] = .enumeration(Viseme.X.rawValue)
        group[.mouthShape] = .enumeration(MouthShape.neutral.rawValue)
        let index = thing.parent.flatMap { scene.objects[$0]?.children.firstIndex(of: target) } ?? scene.roots.firstIndex(of: target)
        let local = Transform(scale: world.scale)
        let part = CharacterPart(job: .body, style: "thing")
        let commands: [EditCommand] = [
            .insert(SceneFragment(objects: [group], roots: [group.id]), parent: thing.parent, index: index),
            .reparent([ReparentEntry(object: target, parent: group.id, transform: local)]),
            .setPart(target, part)
        ]
        var after = scene
        group.children = [target]
        after.objects[group.id] = group
        var moved = thing
        moved.parent = group.id
        moved.transform = local
        moved.part = part
        after.objects[target] = moved
        return (group.id, commands, after)
    }

    /// The style of a body that is the thing itself (Make it a character, Q2): the model is the character, not a part
    /// of a new group around it.
    static let ownBodyStyle = "own"

    /// Make it a character (Q2 step 2): the thing itself becomes the character, whole, where it stands. Its rig is its
    /// own (guessed from its shape, the wrong dots dragged), so the maker never rebuilds it; parts added later ride its
    /// joints. Nil when it's already a character or part of one, or isn't something a character can be.
    static func adopt(_ target: ObjectID, in scene: Scene) -> EditCommand? {
        guard let thing = scene.objects[target], character(of: target, in: scene) == nil else { return nil }
        switch thing.kind {
        case .primitive, .mesh, .group, .asset, .drawing: break
        default: return nil
        }
        let properties = [PropertyChange(object: target, key: .characterStart, value: .enumeration(CharacterStart.nothing.rawValue)),
                          PropertyChange(object: target, key: .mouth, value: .enumeration(Viseme.X.rawValue)),
                          PropertyChange(object: target, key: .mouthShape, value: .enumeration(MouthShape.neutral.rawValue)),
                          PropertyChange(object: target, key: .autoBlink, value: .bool(true))]
        return .batch("Make \(thing.name) a character", [.setProperties(properties), .setPart(target, CharacterPart(job: .body, style: ownBodyStyle))])
    }

    /// Lifts everything but the new legs so the feet reach the ground.
    internal static func raising(_ anatomy: CharacterAnatomy, by rise: Double, except job: CharacterPart.Job) -> EditCommand {
        // Only the character's own children move; what hangs from them follows.
        let changes = anatomy.pieces.filter { $0.parent == anatomy.root && $0.part.job != job }.map { piece in
            PropertyChange(object: piece.id, key: .position, value: .vec3(piece.toRoot.position + Vec3(0, rise, 0)))
        }
        return .setProperties(changes)
    }
}

extension CharacterMaker.Builder {
    func isAncestor(_ ancestor: ObjectID, of id: ObjectID) -> Bool {
        var current = objects.first { $0.id == id }?.parent
        while let parent = current {
            if parent == ancestor { return true }
            current = objects.first { $0.id == parent }?.parent
        }
        return false
    }
}
