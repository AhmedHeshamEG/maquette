import Foundation

/// Match a photo (G1, Room): two lines along one direction of the room in the photo and two along the direction square
/// to it meet at two vanishing points, and those two points give the camera that took it: its lens (where the
/// directions are square) and how it was turned. With the ground's origin tapped on the photo and the camera's height,
/// the 3D sits in the photo. The photo's middle is taken as the lens's centre, as it is for every phone camera.
public enum PhotoMatch {
    public enum Failure: Error, Equatable, CustomStringConvertible {
        case parallel
        case notSquare
        case originAboveHorizon

        public var description: String {
            switch self {
            case .parallel: "Two of the lines are parallel in the photo: pick lines that run away from the camera."
            case .notSquare: "The two directions don't look square to each other: draw each pair along one wall's edges."
            case .originAboveHorizon: "The origin has to be on the ground, below the horizon."
            }
        }
    }

    /// A line on the photo, in pixels (x right, y down).
    public struct Line: Hashable, Sendable, Codable {
        public var a: Vec2
        public var b: Vec2

        public init(_ a: Vec2, _ b: Vec2) {
            self.a = a
            self.b = b
        }
    }

    public struct Camera: Hashable, Sendable {
        public var position: Vec3
        public var rotation: Quat
        /// The vertical field of view, degrees.
        public var fieldOfView: Double
        /// The lens's focal length in pixels of the photo.
        public var focal: Double
    }

    /// The camera that took a `width` × `height` photo in which `first` pair runs along x, `second` along z, the ground's
    /// origin is at `origin`, and the camera stood `height` metres above the ground.
    public static func solve(width: Double, height: Double, first: (Line, Line), second: (Line, Line), origin: Vec2,
                             cameraHeight: Double = 1.6) throws(Failure) -> Camera {
        let centre = Vec2(width / 2, height / 2)
        guard let v1 = meet(first.0, first.1), let v2 = meet(second.0, second.1) else { throw .parallel }
        // On the image plane with y up.
        let d1 = Vec2(v1.x - centre.x, centre.y - v1.y), d2 = Vec2(v2.x - centre.x, centre.y - v2.y)
        let focalSquared = -d1.dot(d2)
        guard focalSquared > 1 else { throw .notSquare }
        let focal = focalSquared.squareRoot()
        let xAxis = Vec3(d1.x, d1.y, -focal).normalized
        var zAxis = Vec3(d2.x, d2.y, -focal).normalized
        var yAxis = zAxis.cross(xAxis)
        if yAxis.y < 0 {
            zAxis = -zAxis
            yAxis = -yAxis
        }
        // The camera's axes in the world: the transpose of the world's axes in the camera.
        let right = Vec3(xAxis.x, yAxis.x, zAxis.x), up = Vec3(xAxis.y, yAxis.y, zAxis.y), back = Vec3(xAxis.z, yAxis.z, zAxis.z)
        let toOrigin = Vec3(origin.x - centre.x, centre.y - origin.y, -focal).normalized
        let world = right * toOrigin.x + up * toOrigin.y + back * toOrigin.z
        guard world.y < -1e-6 else { throw .originAboveHorizon }
        let distance = cameraHeight / -world.y
        let position = world * -distance
        let fieldOfView = 2 * atan(height / 2 / focal) * 180 / .pi
        return Camera(position: position, rotation: rotation(right: right, up: up, back: back), fieldOfView: fieldOfView, focal: focal)
    }

    /// Where two lines meet (nil when they're parallel).
    static func meet(_ p: Line, _ q: Line) -> Vec2? {
        let r = p.b - p.a, s = q.b - q.a
        let denominator = r.cross(s)
        guard abs(denominator) > 1e-9 * max(r.length * s.length, 1) else { return nil }
        let t = (q.a - p.a).cross(s) / denominator
        return p.a + r * t
    }

    /// The rotation whose columns are these axes.
    static func rotation(right: Vec3, up: Vec3, back: Vec3) -> Quat {
        let m00 = right.x, m11 = up.y, m22 = back.z
        let trace = m00 + m11 + m22
        let q: Quat
        if trace > 0 {
            let s = (trace + 1).squareRoot() * 2
            q = Quat(x: (up.z - back.y) / s, y: (back.x - right.z) / s, z: (right.y - up.x) / s, w: s / 4)
        } else if m00 > m11, m00 > m22 {
            let s = (1 + m00 - m11 - m22).squareRoot() * 2
            q = Quat(x: s / 4, y: (up.x + right.y) / s, z: (back.x + right.z) / s, w: (up.z - back.y) / s)
        } else if m11 > m22 {
            let s = (1 + m11 - m00 - m22).squareRoot() * 2
            q = Quat(x: (up.x + right.y) / s, y: s / 4, z: (back.y + up.z) / s, w: (back.x - right.z) / s)
        } else {
            let s = (1 + m22 - m00 - m11).squareRoot() * 2
            q = Quat(x: (back.x + right.z) / s, y: (back.y + up.z) / s, z: s / 4, w: (right.y - up.x) / s)
        }
        return q.normalized
    }
}
