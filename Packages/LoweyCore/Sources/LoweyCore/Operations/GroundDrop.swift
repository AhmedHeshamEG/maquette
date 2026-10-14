import Foundation

/// "To the ground" by the real shape (U5: things were left hovering because a box was measured, not the thing): how
/// far a thing must move up or down so its lowest real points sit on the highest surface under them, or on the ground.
public enum GroundDrop {
    /// The lowest points of a thing: every corner within `band` of its lowest one (world space).
    public static func lowest(of mesh: MeshData, band: Double = 0.002) -> [Vec3] {
        guard let bottom = mesh.positions.map({ Double($0.y) }).min() else { return [] }
        return mesh.positions.filter { Double($0.y) <= bottom + band }.map { Vec3($0) }
    }

    /// The move (along y) that lands `points` (the thing's lowest corners) on the highest of `surfaces` under them, or on
    /// the ground at `ground` when nothing is under them. Rays start at `top` (the thing's highest point), so a thing
    /// sunk into a table comes up onto it.
    public static func rise(lowest points: [Vec3], top: Double, surfaces: [MeshData], ground: Double = 0) -> Double {
        guard let bottom = points.map(\.y).min() else { return 0 }
        var floor = ground
        let samples = points.count > 64 ? stride(from: 0, to: points.count, by: points.count / 64).map { points[$0] } : points
        for point in samples {
            let ray = Ray(origin: Vec3(point.x, top + 0.01, point.z), direction: Vec3(0, -1, 0))
            for surface in surfaces {
                guard let hit = MeshRaycast.intersect(ray, mesh: surface), hit.point.y <= top + 1e-6 else { continue }
                floor = max(floor, hit.point.y)
            }
        }
        return floor - bottom
    }
}
