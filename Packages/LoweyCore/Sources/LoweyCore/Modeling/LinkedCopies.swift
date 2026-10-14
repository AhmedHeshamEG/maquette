import Foundation

/// Linked copies: things that share one shape. Make a linked copy and every change to the shape of either (a pull, a
/// bevel, smoothing, a bend, brush strokes) happens to all of them; where each one stands, its size and its look stay
/// its own.
public enum LinkedCopies {
    /// What a linked copy shares.
    static let sharedKeys: Set<PropertyKey> = [.subdivision, .smoothAngle, .deform, .deformAmount, .deformAxis, .bendDetail, .symmetry]

    /// A copy of the thing beside it, linked to it (the original joins the link too).
    public static func makeCopy(of id: ObjectID, in scene: Scene, offset: Vec3, ids: inout IDFactory) -> EditCommand? {
        guard let object = scene.objects[id], ModelingOperations.canModel(object) || object.kind.assetID != nil else { return nil }
        let link = object[.linked]?.stringValue ?? "link-\(id.raw)"
        var copy = object
        copy.id = ids.next()
        copy.children = []
        copy[.linked] = .string(link)
        copy.transform.position += offset
        var commands: [EditCommand] = []
        if object[.linked] == nil { commands.append(.setProperties([PropertyChange(object: id, key: .linked, value: .string(link))])) }
        commands.append(.insert(SceneFragment(object: copy), parent: object.parent, index: nil))
        return .batch("Linked copy", commands)
    }

    /// The things linked with this one (itself excluded).
    public static func partners(of id: ObjectID, in scene: Scene) -> [ObjectID] {
        guard let link = scene.objects[id]?[.linked]?.stringValue else { return [] }
        return scene.objects.values.filter { $0.id != id && $0[.linked]?.stringValue == link }.map(\.id).sorted { $0.raw < $1.raw }
    }

    /// The command with its shape changes made to every linked partner too (in the same step). `scene` is the scene
    /// before the command. A shape whose own scale was baked into it in the same step reaches the partners at the
    /// size it had in its own space, so each keeps its size.
    public static func propagate(_ command: EditCommand, in scene: Scene) -> EditCommand {
        guard scene.objects.values.contains(where: { $0[.linked] != nil }) else { return command }
        var extra: [EditCommand] = []
        let baked = bakedScales(in: command, scene: scene)
        visit(command) { leaf in
            extra += partnerCommands(for: leaf, baked: baked, in: scene)
        }
        guard !extra.isEmpty else { return command }
        return .batch(command.label, [command] + extra)
    }

    private static func visit(_ command: EditCommand, _ body: (EditCommand) -> Void) {
        if case let .batch(_, commands) = command {
            for inner in commands { visit(inner, body) }
        } else {
            body(command)
        }
    }

    /// Objects whose scale goes back to one in the command (it was baked into their shape), with the scale they had.
    private static func bakedScales(in command: EditCommand, scene: Scene) -> [ObjectID: Vec3] {
        var result: [ObjectID: Vec3] = [:]
        visit(command) { leaf in
            guard case let .setProperties(changes) = leaf else { return }
            for change in changes where change.key == .scale && change.value == .vec3(.one) {
                if let old = scene.objects[change.object]?.transform.scale, !old.isApproximately(.one, tolerance: 1e-12) { result[change.object] = old }
            }
        }
        return result
    }

    private static func partnerCommands(for leaf: EditCommand, baked: [ObjectID: Vec3], in scene: Scene) -> [EditCommand] {
        switch leaf {
        case let .setKind(id, kind):
            var shared = kind
            if case let .mesh(mesh) = kind, let scale = baked[id] {
                shared = .mesh(mesh.scaled(by: Vec3(1 / scale.x, 1 / scale.y, 1 / scale.z)))
            }
            return partners(of: id, in: scene).map { .setKind($0, shared) }
        case let .setShaping(id, shaping):
            return partners(of: id, in: scene).map { .setShaping($0, shaping) }
        case let .setProperties(changes):
            let shared = changes.filter { sharedKeys.contains($0.key) }
            let mirrored = shared.flatMap { change in
                partners(of: change.object, in: scene).map { PropertyChange(object: $0, key: change.key, value: change.value) }
            }
            return mirrored.isEmpty ? [] : [.setProperties(mirrored)]
        default:
            return []
        }
    }

    /// Breaks the link: the thing keeps its shape and goes its own way.
    public static func unlink(_ id: ObjectID) -> EditCommand {
        .batch("Unlink", [.setProperties([PropertyChange(object: id, key: .linked, value: nil)])])
    }
}
