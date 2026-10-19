import Foundation

/// Stereo for Vision Pro (F1): two cameras side by side, parallel, as a person's eyes are. Parallel eyes keep straight
/// lines straight (no keystone, which toed-in eyes give); the screen's depth is set by shifting the two pictures, which
/// the spatial file records instead of baking in.
public enum StereoRig {
    /// A person's eyes are about 63 mm apart. `depth` scales it (0.5 flatter … 2 deeper): a model on a desk reads better
    /// a little deeper than life, a city a little flatter.
    public static let humanBaseline = 0.063

    public static func eyes(_ camera: Transform, baseline: Double = humanBaseline) -> (left: Transform, right: Transform) {
        let right = camera.rotation.act(.unitX) * (baseline / 2)
        var left = camera
        left.position = camera.position - right
        var rightEye = camera
        rightEye.position = camera.position + right
        return (left, rightEye)
    }
}

/// 360° pictures and video (F1): six square views around the camera (a cube), then laid flat as an equirectangular
/// picture (2:1, the format YouTube, Quest and every 360 viewer reads). The cube is level whatever the camera's tilt,
/// facing where the camera faces, so the picture's middle is the shot's direction and the horizon is straight.
public enum Panorama {
    /// The cube's six faces in Metal's order (+x, −x, +y, −y, +z, −z), as turns of a camera that looks down −z.
    public enum Face: Int, CaseIterable, Sendable {
        case positiveX, negativeX, positiveY, negativeY, positiveZ, negativeZ

        /// The face's view direction and up, in the cube's own space.
        public var axes: (forward: Vec3, up: Vec3) {
            switch self {
            case .positiveX: (Vec3(1, 0, 0), Vec3(0, 1, 0))
            case .negativeX: (Vec3(-1, 0, 0), Vec3(0, 1, 0))
            case .positiveY: (Vec3(0, 1, 0), Vec3(0, 0, 1))
            case .negativeY: (Vec3(0, -1, 0), Vec3(0, 0, -1))
            case .positiveZ: (Vec3(0, 0, 1), Vec3(0, 1, 0))
            case .negativeZ: (Vec3(0, 0, -1), Vec3(0, 1, 0))
            }
        }
    }

    /// The level turn the cube takes from the camera (its heading only).
    public static func heading(of camera: Transform) -> Quat {
        let forward = camera.rotation.act(Vec3(0, 0, -1))
        let yaw = atan2(-forward.x, -forward.z)
        return Quat(angle: yaw, axis: .unitY)
    }

    /// The rotation of the camera that draws `face` (90° field of view, square).
    public static func rotation(_ face: Face, heading: Quat) -> Quat {
        let (forward, up) = face.axes
        return (heading * look(forward: forward, up: up)).normalized
    }

    /// The world direction a pixel of the flat picture shows (u, v in 0…1 from the top left), in the cube's space.
    public static func direction(u: Double, v: Double) -> Vec3 {
        let azimuth = (u - 0.5) * 2 * .pi
        let polar = v * .pi
        return Vec3(sin(polar) * sin(azimuth), cos(polar), -sin(polar) * cos(azimuth))
    }

    /// Which face a direction lands on and where (s, t in 0…1 from the face's top left).
    public static func faceCoordinate(_ direction: Vec3) -> (face: Face, s: Double, t: Double) {
        let ax = abs(direction.x)
        let ay = abs(direction.y)
        let az = abs(direction.z)
        let face: Face = if ax >= ay, ax >= az {
            direction.x > 0 ? .positiveX : .negativeX
        } else if ay >= az {
            direction.y > 0 ? .positiveY : .negativeY
        } else {
            direction.z > 0 ? .positiveZ : .negativeZ
        }
        let (forward, up) = face.axes
        let right = forward.cross(up)
        let depth = direction.dot(forward)
        let x = direction.dot(right) / depth
        let y = direction.dot(up) / depth
        return (face, (x + 1) / 2, (1 - y) / 2)
    }

    /// A camera rotation looking along `forward` with `up` (the camera looks down its −z).
    static func look(forward: Vec3, up: Vec3) -> Quat {
        let back = -forward.normalized
        let right = up.cross(back).normalized
        let trueUp = back.cross(right)
        return Quat(rotationColumns: right, trueUp, back)
    }
}

extension Quat {
    /// The rotation whose matrix has these columns (an orthonormal, right-handed basis).
    init(rotationColumns x: Vec3, _ y: Vec3, _ z: Vec3) {
        let trace = x.x + y.y + z.z
        if trace > 0 {
            let s = sqrt(trace + 1) * 2
            self.init(x: (y.z - z.y) / s, y: (z.x - x.z) / s, z: (x.y - y.x) / s, w: s / 4)
        } else if x.x > y.y, x.x > z.z {
            let s = sqrt(1 + x.x - y.y - z.z) * 2
            self.init(x: s / 4, y: (y.x + x.y) / s, z: (z.x + x.z) / s, w: (y.z - z.y) / s)
        } else if y.y > z.z {
            let s = sqrt(1 + y.y - x.x - z.z) * 2
            self.init(x: (y.x + x.y) / s, y: s / 4, z: (z.y + y.z) / s, w: (z.x - x.z) / s)
        } else {
            let s = sqrt(1 + z.z - x.x - y.y) * 2
            self.init(x: (z.x + x.z) / s, y: (z.y + y.z) / s, z: s / 4, w: (x.y - y.x) / s)
        }
    }
}
