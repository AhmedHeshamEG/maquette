import Foundation

public extension PropertyKey {
    /// Stick to the camera (U5): the thing's place is in the shot camera's frame, so it stays put on the picture while
    /// the camera moves (titles are 3D text that sticks; the timeline's overlays went).
    static let sticksToCamera: PropertyKey = "sticksToCamera"
}

/// Things that stick to the camera ride the shot camera: their own place is read in its frame.
public enum StickToCamera {
    /// Puts every sticking, top-level thing in `scene` where the camera `camera` carries it.
    static func apply(to scene: inout Scene, camera: ObjectID?, animated: inout Set<ObjectID>) {
        guard let camera, scene.objects[camera] != nil else { return }
        let carrier = scene.worldTransform(of: camera)
        for (id, object) in scene.objects where object.parent == nil && object[.sticksToCamera]?.boolValue == true && id != camera {
            var placed = object
            placed.transform = carrier * object.transform
            scene.objects[id] = placed
            animated.insert(id)
        }
    }

    /// A thing's place in the camera's frame, from its place in the world (sticking it without it jumping).
    public static func local(_ world: Transform, camera: Transform) -> Transform {
        Transform.relative(world: world, toParent: camera)
    }
}
