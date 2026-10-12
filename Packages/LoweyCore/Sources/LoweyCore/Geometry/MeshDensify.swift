import Foundation

public extension PropertyKey {
    /// How finely a rigged shape is cut so it can bend (an Int: cuts across its largest side). Set by rigging when the
    /// shape has too few corners to bend where its joints are (a cube is eight corners); every place that draws or
    /// exports the shape cuts it the same way (`MeshDensify`).
    static let bendDetail: PropertyKey = "bendDetail"
}

/// Cutting a mesh finer without changing its shape: every edge longer than the target is split at its middle, the
/// triangles around it split to match, until none is longer. Splits are shared by both triangles of an edge, so the
/// surface stays closed.
public enum MeshDensify {
    /// Most cuts a shape is given across its largest side.
    public static let maximumCuts = 48

    /// The object's mesh cut as its `bendDetail` asks (the mesh itself when it asks for none).
    public static func apply(_ mesh: MeshData, for object: SceneObject) -> MeshData {
        guard let cuts = object[.bendDetail]?.floatValue, cuts >= 1 else { return mesh }
        return densified(mesh, cuts: Int(cuts))
    }

    /// The cuts a shape needs to bend at its joints: about three across the shortest bone, when its edges are
    /// longer than that (nil when it bends well as it is). Positions in the mesh's own space.
    public static func cuts(for mesh: MeshData, bones: [(head: Vec3, tail: Vec3)]) -> Int? {
        guard let bounds = mesh.bounds, !mesh.isEmpty else { return nil }
        let size = max(bounds.size.x, bounds.size.y, bounds.size.z)
        let lengths = bones.map { $0.head.distance(to: $0.tail) }.filter { $0 > size * 0.01 }
        guard let shortest = lengths.min(), size > 0 else { return nil }
        let target = max(shortest / 3, size / Double(maximumCuts))
        guard longestEdge(mesh) > target * 1.5 else { return nil }
        return min(Int((size / target).rounded(.up)), maximumCuts)
    }

    static func longestEdge(_ mesh: MeshData) -> Double {
        var longest: Float = 0
        for triangle in stride(from: 0, to: mesh.indices.count - 2, by: 3) {
            let a = mesh.positions[Int(mesh.indices[triangle])]
            let b = mesh.positions[Int(mesh.indices[triangle + 1])]
            let c = mesh.positions[Int(mesh.indices[triangle + 2])]
            longest = max(longest, length3(a - b), length3(b - c), length3(c - a))
        }
        return Double(longest)
    }

    /// The mesh with no edge longer than its largest side over `cuts`.
    public static func densified(_ mesh: MeshData, cuts: Int) -> MeshData {
        guard let bounds = mesh.bounds, cuts >= 1 else { return mesh }
        let target = Float(max(bounds.size.x, bounds.size.y, bounds.size.z) / Double(cuts))
        guard target > 0 else { return mesh }
        var result = mesh
        if result.normals.count != result.positions.count { result.computeSmoothNormals() }
        if result.uvs.count != result.positions.count { result.uvs = Array(repeating: .zero, count: result.positions.count) }
        // Each pass at least halves the longest edge; a few passes reach any target the cap allows.
        for _ in 0 ..< 12 {
            guard split(&result, longerThan: target) else { break }
        }
        return result
    }

    private struct EdgeKey: Hashable {
        let low: UInt32
        let high: UInt32
        init(_ a: UInt32, _ b: UInt32) {
            low = min(a, b)
            high = max(a, b)
        }
    }

    /// One pass: every edge longer than `target` gets its middle; false when none was.
    private static func split(_ mesh: inout MeshData, longerThan target: Float) -> Bool {
        var middles: [EdgeKey: UInt32] = [:]
        func middle(_ a: UInt32, _ b: UInt32) -> UInt32? {
            let key = EdgeKey(a, b)
            if let known = middles[key] { return known }
            let pa = mesh.positions[Int(a)], pb = mesh.positions[Int(b)]
            guard length3(pa - pb) > target else { return nil }
            let normal = normalize3(mesh.normals[Int(a)] + mesh.normals[Int(b)], fallback: mesh.normals[Int(a)])
            let index = mesh.addVertex((pa + pb) / 2, normal: normal, uv: (mesh.uvs[Int(a)] + mesh.uvs[Int(b)]) / 2)
            middles[key] = index
            return index
        }
        var indices: [UInt32] = []
        indices.reserveCapacity(mesh.indices.count * 2)
        let old = mesh.indices
        for triangle in stride(from: 0, to: old.count - 2, by: 3) {
            let corners = [old[triangle], old[triangle + 1], old[triangle + 2]]
            let mids = (0 ..< 3).map { middle(corners[$0], corners[($0 + 1) % 3]) }
            indices += pieces(corners, mids)
        }
        guard !middles.isEmpty else { return false }
        mesh.indices = indices
        return true
    }

    /// A triangle (a, b, c) cut where its edges ab, bc, ca have middles; the pieces keep its winding.
    private static func pieces(_ corners: [UInt32], _ mids: [UInt32?]) -> [UInt32] {
        switch mids.compactMap(\.self).count {
        case 0:
            return corners
        case 3:
            guard let ab = mids[0], let bc = mids[1], let ca = mids[2] else { return corners }
            return [corners[0], ab, ca, ab, corners[1], bc, ca, bc, corners[2], ab, bc, ca]
        default:
            // Turn the triangle so its first edge is cut, then cut the rest of it.
            guard let first = (0 ..< 3).first(where: { mids[$0] != nil && mids[($0 + 2) % 3] == nil }) else { return corners }
            let a = corners[first], b = corners[(first + 1) % 3], c = corners[(first + 2) % 3]
            guard let ab = mids[first] else { return corners }
            if let bc = mids[(first + 1) % 3] {
                return [ab, b, bc, a, ab, bc, a, bc, c]
            }
            return [a, ab, c, ab, b, c]
        }
    }
}
