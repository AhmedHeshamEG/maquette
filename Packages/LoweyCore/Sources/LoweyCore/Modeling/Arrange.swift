import Foundation

/// Placing things relative to each other and to themselves: line them up, space them out, move a thing's pivot (where
/// it turns and sizes from), and type a side's length.
public enum Arrange {
    public enum Edge: String, Codable, Sendable, CaseIterable {
        case min, middle, max
    }

    /// Lines the things up on one axis: their low sides, middles or high sides at the first one's (world space).
    public static func align(_ ids: [ObjectID], axis: Axis, to edge: Edge, in scene: Scene, bounds: SceneBounds) -> EditCommand? {
        let boxes = ids.compactMap { id in bounds.worldBounds(of: id, in: scene).map { (id, $0) } }
        guard let anchor = boxes.first, boxes.count >= 2 else { return nil }
        let target = value(of: anchor.1, axis: axis, edge: edge)
        let changes = boxes.dropFirst().compactMap { id, box -> PropertyChange? in
            moved(id, by: target - value(of: box, axis: axis, edge: edge), along: axis, in: scene)
        }
        return changes.isEmpty ? nil : .batch("Align", [.setProperties(changes)])
    }

    /// Spaces the things out evenly between the two furthest apart on one axis (equal gaps between them).
    public static func distribute(_ ids: [ObjectID], axis: Axis, in scene: Scene, bounds: SceneBounds) -> EditCommand? {
        let boxes = ids.compactMap { id in bounds.worldBounds(of: id, in: scene).map { (id, $0) } }
            .sorted { $0.1.center[axis] < $1.1.center[axis] }
        guard boxes.count >= 3, let first = boxes.first, let last = boxes.last else { return nil }
        let sizes = boxes.map { $0.1.size[axis] }
        let span = last.1.max[axis] - first.1.min[axis]
        let gap = (span - sizes.reduce(0, +)) / Double(boxes.count - 1)
        var cursor = first.1.max[axis] + gap
        var changes: [PropertyChange] = []
        for (id, box) in boxes.dropFirst().dropLast() {
            if let change = moved(id, by: cursor - box.min[axis], along: axis, in: scene) { changes.append(change) }
            cursor += box.size[axis] + gap
        }
        return changes.isEmpty ? nil : .batch("Distribute", [.setProperties(changes)])
    }

    static func value(of box: Bounds, axis: Axis, edge: Edge) -> Double {
        switch edge {
        case .min: box.min[axis]
        case .middle: box.center[axis]
        case .max: box.max[axis]
        }
    }

    /// The position change that moves a thing by `distance` along a world axis (through its parent's space).
    static func moved(_ id: ObjectID, by distance: Double, along axis: Axis, in scene: Scene) -> PropertyChange? {
        guard abs(distance) > 1e-12, let object = scene.objects[id] else { return nil }
        let world = axis.unit * distance
        let parent = object.parent.map { scene.worldTransform(of: $0) } ?? .identity
        let local = parent.inverseApplyDirection(world)
        let scale = parent.scale
        let unscaled = Vec3(local.x / nonZero(scale.x), local.y / nonZero(scale.y), local.z / nonZero(scale.z))
        return PropertyChange(object: id, key: .position, value: .vec3(object.transform.position + unscaled))
    }

    private static func nonZero(_ value: Double) -> Double { abs(value) < 1e-12 ? 1 : value }

    // MARK: Pivot

    /// Moves a thing's pivot to a world point without moving the thing: a modelled shape's corners (or a group's
    /// children) shift the other way. A blockout shape becomes a modelled one first.
    public static func movePivot(_ id: ObjectID, to point: Vec3, in scene: Scene) throws(ModelingOperations.Failure) -> EditCommand {
        guard let object = scene.objects[id] else { throw .notEditable }
        let world = scene.worldTransform(of: id)
        // The shift in the thing's own (scaled) space.
        let local = world.inverseApply(to: point)
        guard local.length > 1e-12 else { return .batch("Move pivot", []) }
        let newPosition = object.transform.position + object.transform.rotation.act(local.scaled(by: object.transform.scale))
        var commands: [EditCommand] = []
        if case .group = object.kind {
            let changes = object.children.compactMap { child -> PropertyChange? in
                guard let childObject = scene.objects[child] else { return nil }
                return PropertyChange(object: child, key: .position, value: .vec3(childObject.transform.position - local))
            }
            commands.append(.setProperties(changes))
        } else {
            guard let mesh = ModelingOperations.editableMesh(of: object) else { throw .notEditable }
            commands.append(.setKind(id, .mesh(EditableMesh(vertices: mesh.vertices.map { $0 - local }, faces: mesh.faces))))
            commands += object.children.compactMap { child -> EditCommand? in
                guard let childObject = scene.objects[child] else { return nil }
                return .setProperties([PropertyChange(object: child, key: .position, value: .vec3(childObject.transform.position - local))])
            }
        }
        commands.append(.setProperties([PropertyChange(object: id, key: .position, value: .vec3(newPosition))]))
        return .batch("Move pivot", commands)
    }

    /// Where a pivot preset sits on a thing (world space): the middle of its box, or the middle of its base.
    public static func pivotPoint(_ preset: PivotPreset, of id: ObjectID, in scene: Scene, bounds: SceneBounds) -> Vec3? {
        guard let box = bounds.worldBounds(of: id, in: scene) else { return nil }
        switch preset {
        case .middle: return box.center
        case .base: return Vec3(box.center.x, box.min.y, box.center.z)
        }
    }

    public enum PivotPreset: String, Codable, Sendable, CaseIterable {
        case middle, base
    }

    // MARK: Lengths

    /// A side of the thing typed to a length (world metres): it stretches along that axis of its own space, its base
    /// staying on the ground (y) or its middle staying put (x, z).
    public static func setLength(_ id: ObjectID, axis: Axis, to length: Double, in scene: Scene) throws(ModelingOperations.Failure) -> EditCommand {
        guard length > 1e-9, let object = scene.objects[id] else { throw .notEditable }
        switch object.kind {
        case .primitive, .asset, .prefab, .text, .card, .drawing:
            guard let box = SceneBounds().localBounds(of: object), box.size[axis] > 1e-12 else { throw .notEditable }
            var scale = object.transform.scale
            scale[axis] = length / box.size[axis] * (scale[axis] < 0 ? -1 : 1)
            return .batch("Size", [.setProperties([PropertyChange(object: id, key: .scale, value: .vec3(scale))])])
        case let .mesh(mesh):
            guard let box = mesh.bounds, box.size[axis] > 1e-12 else { throw .notEditable }
            let factor = length / (box.size[axis] * abs(object.transform.scale[axis]))
            let anchor = axis == .y ? box.min[axis] : box.center[axis]
            let stretched = mesh.vertices.map { vertex -> Vec3 in
                var moved = vertex
                moved[axis] = anchor + (vertex[axis] - anchor) * factor
                return moved
            }
            return .batch("Size", [.setKind(id, .mesh(EditableMesh(vertices: stretched, faces: mesh.faces)))])
        default:
            throw .notEditable
        }
    }
}
