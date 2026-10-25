import Foundation

/// Where the scene stands in the room in the AR view (M12): a spot on a found floor or table, a turn about the up axis
/// and a size, life size (1) or small enough to stand on a table. The renderer keeps drawing the scene in its own space;
/// the device's camera is carried into that space instead, so every Look, light and effect looks as it does on the stage.
public struct ARPlacement: Hashable, Sendable {
    /// The scene's origin in the room (metres, ARKit's world).
    public var position: Vec3
    /// Radians about the room's up.
    public var yaw: Double
    /// Room metres per scene metre: 1 is life size.
    public var scale: Double

    public init(position: Vec3 = .zero, yaw: Double = 0, scale: Double = 1) {
        self.position = position
        self.yaw = yaw
        self.scale = scale
    }

    /// The smallest and largest sizes a pinch reaches.
    public static let scales = 0.002 ... 4.0
    /// How wide the scene stands on a table (metres across its widest side).
    public static let tableWidth = 0.4
    /// A pinch within this of life size snaps to it.
    public static let snap = 0.08

    /// The size that stands `bounds` on a table, never bigger than life.
    public static func tableScale(for bounds: Bounds?) -> Double {
        guard let bounds else { return 1 }
        let size = bounds.max - bounds.min
        let widest = max(size.x, size.z, size.y * 0.5, 1e-3)
        return min(max(tableWidth / widest, scales.lowerBound), 1)
    }

    /// `scale` after a pinch of `factor`, kept in range and snapped to life size.
    public func pinched(_ factor: Double) -> Double {
        let next = min(max(scale * factor, Self.scales.lowerBound), Self.scales.upperBound)
        return abs(next - 1) < Self.snap ? 1 : next
    }

    /// Whether this is life size.
    public var isLifeSize: Bool {
        abs(scale - 1) < 1e-9
    }

    /// The scene's rotation in the room.
    public var rotation: Quat {
        Quat(angle: yaw, axis: .unitY)
    }

    /// A point of the scene, in the room.
    public func room(_ point: Vec3) -> Vec3 {
        position + rotation.act(point * scale)
    }

    /// The device's camera (its pose in the room) carried into the scene's space: the camera the renderer draws from.
    /// Lengths shrink with the scene, so a camera 1 m from a table-sized model stands 1/scale m from the full one.
    public func sceneCamera(_ camera: Transform) -> Transform {
        let inverse = rotation.conjugate
        let local = inverse.act(camera.position - position) * (1 / max(scale, 1e-6))
        return Transform(position: local, rotation: (inverse * camera.rotation).normalized)
    }

    /// A camera's near and far planes (metres in the room) in the scene's space.
    public func sceneDepth(near: Double, far: Double) -> (near: Double, far: Double) {
        let inverse = 1 / max(scale, 1e-6)
        return (near * inverse, far * inverse)
    }
}
