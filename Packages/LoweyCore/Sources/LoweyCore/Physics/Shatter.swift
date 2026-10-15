import Foundation

/// A thing cut into pieces the way glass and ice break: Voronoi cells around seeded points, each intersected with the
/// thing by Manifold, so the pieces fit back together exactly. A thing that isn't a closed solid is split by its
/// triangles instead (shards of a surface).
public enum Shatter {
    public struct Piece: Sendable {
        /// Around its own centre.
        public var mesh: MeshData
        /// Where its centre sits in the thing's space.
        public var centre: Vec3
    }

    public static func pieces(of mesh: MeshData, count: Int, seed: UInt64) -> [Piece] {
        guard let bounds = mesh.bounds, count > 1 else { return [] }
        var random = SeededRandom(seed: seed)
        let seeds = (0 ..< count).map { _ in
            Vec3(random.range(bounds.min.x, bounds.max.x), random.range(bounds.min.y, bounds.max.y), random.range(bounds.min.z, bounds.max.z))
        }
        let solid = MeshBuilder.mesh(from: SoftMesh.weld(mesh))
        if MeshBoolean.isSolid(solid) {
            let cut = seeds.indices.compactMap { index -> MeshData? in
                let cell = Self.cell(index, seeds: seeds, bounds: bounds)
                guard let piece = try? MeshBoolean.combine(solid, MeshBuilder.mesh(positions: cell.positions, triangles: cell.triangles), .intersect)
                else { return nil }
                let data = piece.renderMesh()
                return data.isEmpty ? nil : data
            }
            if cut.count > 1 { return cut.map(centred) }
        }
        return shards(of: mesh, seeds: seeds).map(centred)
    }

    static func centred(_ mesh: MeshData) -> Piece {
        let centre = mesh.bounds?.center ?? .zero
        let shift = SIMD3<Float>(Float(centre.x), Float(centre.y), Float(centre.z))
        var moved = mesh
        moved.positions = mesh.positions.map { $0 - shift }
        return Piece(mesh: moved, centre: centre)
    }

    /// The triangles closest to each seed, as open pieces.
    static func shards(of mesh: MeshData, seeds: [Vec3]) -> [MeshData] {
        var groups = [MeshData](repeating: MeshData(), count: seeds.count)
        for triangle in stride(from: 0, to: mesh.indices.count - 2, by: 3) {
            let corners = (0 ..< 3).map { mesh.positions[Int(mesh.indices[triangle + $0])] }
            let centre = Vec3(corners[0] + corners[1] + corners[2]) / 3
            let nearest = seeds.indices.min { seeds[$0].distance(to: centre) < seeds[$1].distance(to: centre) } ?? 0
            let start = UInt32(groups[nearest].positions.count)
            groups[nearest].positions += corners
            groups[nearest].indices += [start, start + 1, start + 2]
        }
        return groups.filter { $0.positions.count >= 4 }
    }

    /// The Voronoi cell of `index` inside the box around the thing: the box cut by the plane halfway to every other seed.
    static func cell(_ index: Int, seeds: [Vec3], bounds: Bounds) -> (positions: [Vec3], triangles: [(Int, Int, Int)]) {
        let grown = Bounds(min: bounds.min - Vec3(0.01, 0.01, 0.01), max: bounds.max + Vec3(0.01, 0.01, 0.01))
        var polyhedron = ConvexPolyhedron.box(grown)
        for (other, point) in seeds.enumerated() where other != index {
            let normal = (point - seeds[index]).normalized
            let middle = (point + seeds[index]) * 0.5
            polyhedron.clip(keepingBelow: normal, through: middle)
        }
        return polyhedron.triangles()
    }
}

/// A convex solid as outward faces, cut by planes.
struct ConvexPolyhedron {
    var faces: [[Vec3]]

    static func box(_ bounds: Bounds) -> ConvexPolyhedron {
        func p(_ x: Int, _ y: Int, _ z: Int) -> Vec3 {
            Vec3(x == 0 ? bounds.min.x : bounds.max.x, y == 0 ? bounds.min.y : bounds.max.y, z == 0 ? bounds.min.z : bounds.max.z)
        }
        return ConvexPolyhedron(faces: [
            [p(0, 0, 0), p(0, 0, 1), p(0, 1, 1), p(0, 1, 0)],
            [p(1, 0, 0), p(1, 1, 0), p(1, 1, 1), p(1, 0, 1)],
            [p(0, 0, 0), p(1, 0, 0), p(1, 0, 1), p(0, 0, 1)],
            [p(0, 1, 0), p(0, 1, 1), p(1, 1, 1), p(1, 1, 0)],
            [p(0, 0, 0), p(0, 1, 0), p(1, 1, 0), p(1, 0, 0)],
            [p(0, 0, 1), p(1, 0, 1), p(1, 1, 1), p(0, 1, 1)]
        ])
    }

    /// Keeps the part where (x - point)·normal ≤ 0 and closes the cut with a new face.
    mutating func clip(keepingBelow normal: Vec3, through point: Vec3) {
        var kept: [[Vec3]] = []
        var cut: [Vec3] = []
        for face in faces {
            var result: [Vec3] = []
            for index in face.indices {
                let a = face[index]
                let b = face[(index + 1) % face.count]
                let da = (a - point).dot(normal)
                let db = (b - point).dot(normal)
                if da <= 0 { result.append(a) }
                if (da < 0 && db > 0) || (da > 0 && db < 0) {
                    let crossing = a + (b - a) * (da / (da - db))
                    result.append(crossing)
                    cut.append(crossing)
                }
            }
            if result.count >= 3 { kept.append(result) }
        }
        if cut.count >= 3 {
            let centre = cut.reduce(.zero, +) / Double(cut.count)
            let u = (abs(normal.y) < 0.9 ? Vec3.unitY : Vec3.unitX).cross(normal).normalized
            let v = normal.cross(u)
            let ordered = cut.sorted { atan2(($0 - centre).dot(v), ($0 - centre).dot(u)) < atan2(($1 - centre).dot(v), ($1 - centre).dot(u)) }
            // Seen from outside (along +normal) the cap runs counter-clockwise.
            kept.append(ordered)
        }
        faces = kept
    }

    func triangles() -> (positions: [Vec3], triangles: [(Int, Int, Int)]) {
        var positions: [Vec3] = []
        var triangles: [(Int, Int, Int)] = []
        for face in faces where face.count >= 3 {
            let start = positions.count
            positions += face
            for index in 1 ..< face.count - 1 {
                triangles.append((start, start + index, start + index + 1))
            }
        }
        return (positions, triangles)
    }
}
