import Foundation

/// One shape becoming another (Morph into…): every corner of the first shape, cut finer so it can bend, is matched to a
/// point on the second by looking out from the middle of each in the same direction (measured against each shape's own
/// box, so a cube reaches the ends of a long bar). Halfway, the corners are halfway there. The second shape needn't have
/// the same corners, or as many: it only has to be reachable from its middle, which holds for most things people morph
/// (a logo, a ball, a box, a letter). Pure: tested on Linux, cached by the renderer.
public struct MorphPair: Sendable {
    /// The first shape, cut finer.
    public let source: MeshData
    /// Where each of its corners ends up, and the surface's direction there.
    public let destinations: [SIMD3<Float>]
    public let destinationNormals: [SIMD3<Float>]

    /// Corners a first shape is cut to before it bends (fewer stay as they are).
    static let fineCorners = 4000

    /// Matches `source` to `target` (both in the first thing's space).
    public init(source: MeshData, target: MeshData) {
        var fine = source
        if fine.normals.count != fine.positions.count { fine.computeSmoothNormals() }
        if fine.positions.count < Self.fineCorners { fine = MeshDensify.densified(fine, cuts: 24) }
        self.source = fine
        guard let from = fine.bounds, let to = target.bounds, !target.isEmpty else {
            destinations = fine.positions
            destinationNormals = fine.normals
            return
        }
        var targetMesh = target
        if targetMesh.normals.count != targetMesh.positions.count { targetMesh.computeSmoothNormals() }
        let bvh = TriangleBVH(targetMesh)
        let fromHalf = Self.half(from), toHalf = Self.half(to)
        let reach = Float(max(to.size.x, to.size.y, to.size.z) * 4 + 1)
        var points: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        points.reserveCapacity(fine.positions.count)
        for (index, position) in fine.positions.enumerated() {
            let unit = (Vec3(position) - from.center).divided(by: fromHalf)
            var direction = unit.scaled(by: toHalf).normalized
            if direction.length < 0.5 { direction = Vec3(fine.normals[index]).normalized }
            let centre = to.center.floats
            let origin = centre + direction.floats * reach
            if let hit = bvh.nearest(origin: origin, direction: -direction.floats) {
                points.append(origin - direction.floats * hit.t)
                normals.append(Self.normal(of: targetMesh, triangle: hit.triangle, weights: hit.weights))
            } else {
                points.append((to.center + unit.scaled(by: toHalf)).floats)
                normals.append(fine.normals[index])
            }
        }
        destinations = points
        destinationNormals = normals
    }

    private static func half(_ bounds: Bounds) -> Vec3 {
        Vec3(max(bounds.size.x / 2, 1e-4), max(bounds.size.y / 2, 1e-4), max(bounds.size.z / 2, 1e-4))
    }

    private static func normal(of mesh: MeshData, triangle: Int, weights: SIMD3<Float>) -> SIMD3<Float> {
        let a = Int(mesh.indices[triangle * 3]), b = Int(mesh.indices[triangle * 3 + 1]), c = Int(mesh.indices[triangle * 3 + 2])
        let mixed = mesh.normals[a] * weights.x + mesh.normals[b] * weights.y + mesh.normals[c] * weights.z
        let length = length3(mixed)
        return length > 1e-9 ? mixed / length : SIMD3<Float>(0, 1, 0)
    }

    /// The shape `amount` (0…1) of the way there, eased in and out.
    public func mesh(at amount: Double) -> MeshData {
        let eased = Float(CloneField.smooth(amount))
        var mesh = source
        for index in mesh.positions.indices {
            mesh.positions[index] += (destinations[index] - mesh.positions[index]) * eased
            let normal = mesh.normals[index] + (destinationNormals[index] - mesh.normals[index]) * eased
            let length = length3(normal)
            mesh.normals[index] = length > 1e-9 ? normal / length : mesh.normals[index]
        }
        return mesh
    }
}

private extension Vec3 {
    func divided(by other: Vec3) -> Vec3 { Vec3(x / other.x, y / other.y, z / other.z) }
}
