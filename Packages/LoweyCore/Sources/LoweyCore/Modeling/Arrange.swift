import Foundation

/// A thing's own placing (U6; lining things up is `Operations.align` and `distribute`): move its pivot (where it turns
/// and sizes from), and type a side's length.
public enum Arrange {
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
