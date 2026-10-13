import Foundation

public extension PropertyKey {
    /// The kept sheet a drawing was drawn on (U5): moving the sheet moves the drawing. Gone when it was drawn on a
    /// surface or before 0.15.
    static let drawnOn: PropertyKey = "drawnOn"
}

/// Moving a sheet moves what is drawn on it (U5, CONTEXT §10.11): each drawing keeps its place on the sheet.
public enum SheetCarry {
    /// The changes that carry every drawing kept on the sheet from where `old` had it to where `new` puts it (the same
    /// sheet, moved: pushed nearer, turned, laid somewhere else). Empty when either is nowhere.
    public static func carrying(from old: DrawingSheet, to new: DrawingSheet, in scene: Scene) -> [PropertyChange] {
        guard old.id == new.id, let from = old.worldFrame(in: scene), let to = new.worldFrame(in: scene) else { return [] }
        let turn = (to.rotation * from.rotation.inverse).normalized
        guard !turn.isApproximately(.identity) || (to.origin - from.origin).length > 1e-9 else { return [] }
        var changes: [PropertyChange] = []
        for id in scene.objects.keys.sorted() {
            guard let object = scene.objects[id], object[.drawnOn]?.stringValue == old.id else { continue }
            let world = scene.worldTransform(of: id)
            let moved = Transform(position: to.origin + turn.act(world.position - from.origin), rotation: (turn * world.rotation).normalized,
                                  scale: world.scale)
            let parent = object.parent.map { scene.worldTransform(of: $0) } ?? .identity
            let local = Transform.relative(world: moved, toParent: parent)
            changes.append(PropertyChange(object: id, key: .position, value: .vec3(local.position)))
            changes.append(PropertyChange(object: id, key: .rotation, value: .quat(local.rotation)))
        }
        return changes
    }
}
