import Foundation

/// Meshes made ready to bend: corners in the same place welded (flat shading splits them), long edges cut until the
/// surface is fine enough to drape or wobble, within a vertex budget.
public enum SoftMesh {
    public static func prepare(_ mesh: MeshData, edge: Double, maxVertices: Int) -> MeshData {
        var welded = weld(mesh)
        var target = edge
        // Refine while it's coarser than the target, then loosen the target until it fits the budget.
        for _ in 0 ..< 6 {
            let refined = refine(welded, edge: target)
            if refined.positions.count > maxVertices {
                target *= 1.5
                continue
            }
            if refined.positions.count == welded.positions.count { break }
            welded = refined
        }
        return welded
    }

    /// One vertex per place (within a tenth of a millimetre), triangles that collapse dropped.
    public static func weld(_ mesh: MeshData) -> MeshData {
        var lookup: [SIMD3<Int32>: UInt32] = [:]
        var positions: [SIMD3<Float>] = []
        var remap: [UInt32] = []
        remap.reserveCapacity(mesh.positions.count)
        for position in mesh.positions {
            let key = SIMD3<Int32>(Int32((position.x * 10000).rounded()), Int32((position.y * 10000).rounded()), Int32((position.z * 10000).rounded()))
            if let existing = lookup[key] {
                remap.append(existing)
            } else {
                lookup[key] = UInt32(positions.count)
                remap.append(UInt32(positions.count))
                positions.append(position)
            }
        }
        var indices: [UInt32] = []
        for triangle in stride(from: 0, to: mesh.indices.count - 2, by: 3) {
            let a = remap[Int(mesh.indices[triangle])]
            let b = remap[Int(mesh.indices[triangle + 1])]
            let c = remap[Int(mesh.indices[triangle + 2])]
            if a != b, b != c, a != c { indices += [a, b, c] }
        }
        return MeshData(positions: positions, indices: indices)
    }

    /// Every edge of a triangle with an edge longer than `edge` is split at its middle; each triangle is then cut along
    /// the middles of its split edges (one, two or three), so neighbours always agree and no crack opens.
    static func refine(_ mesh: MeshData, edge: Double) -> MeshData {
        func key(_ a: UInt32, _ b: UInt32) -> UInt64 { UInt64(min(a, b)) << 32 | UInt64(max(a, b)) }
        var positions = mesh.positions
        var middles: [UInt64: UInt32] = [:]
        let limit = Float(edge)
        for triangle in stride(from: 0, to: mesh.indices.count - 2, by: 3) {
            let corners = [mesh.indices[triangle], mesh.indices[triangle + 1], mesh.indices[triangle + 2]]
            let longest = (0 ..< 3).map { length3(positions[Int(corners[$0])] - positions[Int(corners[($0 + 1) % 3])]) }.max() ?? 0
            guard longest > limit else { continue }
            for side in 0 ..< 3 {
                let a = corners[side]
                let b = corners[(side + 1) % 3]
                guard middles[key(a, b)] == nil else { continue }
                positions.append((positions[Int(a)] + positions[Int(b)]) * 0.5)
                middles[key(a, b)] = UInt32(positions.count - 1)
            }
        }
        guard !middles.isEmpty else { return mesh }
        var indices: [UInt32] = []
        for triangle in stride(from: 0, to: mesh.indices.count - 2, by: 3) {
            indices += cut([mesh.indices[triangle], mesh.indices[triangle + 1], mesh.indices[triangle + 2]]) { middles[key($0, $1)] }
        }
        return MeshData(positions: positions, indices: indices)
    }

    /// One triangle cut along the middles of its split sides.
    private static func cut(_ corners: [UInt32], middle: (UInt32, UInt32) -> UInt32?) -> [UInt32] {
        let mids = (0 ..< 3).map { middle(corners[$0], corners[($0 + 1) % 3]) }
        if case let (ab?, bc?, ca?) = (mids[0], mids[1], mids[2]) {
            return [corners[0], ab, ca, ab, corners[1], bc, ca, bc, corners[2], ab, bc, ca]
        }
        switch mids.compactMap({ $0 }).count {
        case 0:
            return corners
        default:
            // Rotate so the first side is split, then fan from its middle.
            guard let first = mids.firstIndex(where: { $0 != nil }) else { return corners }
            let a = corners[first]
            let b = corners[(first + 1) % 3]
            let c = corners[(first + 2) % 3]
            let ab = mids[first] ?? a
            let bc = mids[(first + 1) % 3]
            let ca = mids[(first + 2) % 3]
            var result: [UInt32] = []
            if let bc {
                result += [ab, b, bc, ab, bc, c]
            } else {
                result += [ab, b, c]
            }
            if let ca {
                result += [a, ab, ca, ca, ab, c]
            } else {
                result += [a, ab, c]
            }
            return result
        }
    }

    public static func area(_ mesh: MeshData) -> Double {
        var total = 0.0
        for triangle in stride(from: 0, to: mesh.indices.count - 2, by: 3) {
            let a = Vec3(mesh.positions[Int(mesh.indices[triangle])])
            let b = Vec3(mesh.positions[Int(mesh.indices[triangle + 1])])
            let c = Vec3(mesh.positions[Int(mesh.indices[triangle + 2])])
            total += (b - a).cross(c - a).length / 2
        }
        return total
    }

    /// The volume a closed mesh holds (by the divergence theorem); an open one falls back to its hull's.
    public static func volume(_ mesh: MeshData) -> Double {
        var total = 0.0
        for triangle in stride(from: 0, to: mesh.indices.count - 2, by: 3) {
            let a = Vec3(mesh.positions[Int(mesh.indices[triangle])])
            let b = Vec3(mesh.positions[Int(mesh.indices[triangle + 1])])
            let c = Vec3(mesh.positions[Int(mesh.indices[triangle + 2])])
            total += a.dot(b.cross(c)) / 6
        }
        let closed = abs(total)
        return closed > 1e-9 ? closed : ConvexVolume.volume(of: mesh.positions.map { Vec3($0) })
    }

    /// The vertices along a hanging cloth's top edge (empty when it lies flat).
    public static func topEdge(_ vertices: [Vec3]) -> [Int] {
        guard let bounds = Bounds(points: vertices) else { return [] }
        let height = bounds.size.y
        guard height > bounds.size.maxComponent * 0.05 else { return [] }
        return vertices.indices.filter { vertices[$0].y >= bounds.max.y - height * 0.02 }
    }
}
