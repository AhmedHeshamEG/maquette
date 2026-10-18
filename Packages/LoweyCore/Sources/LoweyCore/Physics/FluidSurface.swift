import Foundation

/// The surface of water from its particles: a smooth blob field (each drop a soft ball about its spacing wide) cut at
/// one level by marching tetrahedra, corners shared between neighbouring cells, normals from the faces around them.
public enum FluidSurface {
    /// `detail` 2 draws it twice as finely (a Final export): cells half a drop, eight times as many allowed.
    public static func mesh(_ particles: [SIMD3<Float>], spacing: Double, detail: Double = 1) -> MeshData {
        guard !particles.isEmpty, let bounds = Bounds(points: particles.map { Vec3($0) }) else { return MeshData() }
        let radius = Float(spacing * 2)
        // A cell of about a drop, coarser when the water has spread wide: at most a quarter of a million cells.
        let padded = bounds.size + Vec3(spacing * 6, spacing * 6, spacing * 6)
        let budget = 250_000 * detail * detail * detail
        let cell = Float(max(spacing / detail, pow(padded.x * padded.y * padded.z / budget, 1.0 / 3.0)))
        let cap = Int(160 * detail)
        let origin = SIMD3<Float>(Float(bounds.min.x), Float(bounds.min.y), Float(bounds.min.z)) - SIMD3<Float>(repeating: radius + cell)
        let extent = SIMD3<Float>(Float(bounds.size.x), Float(bounds.size.y), Float(bounds.size.z)) + SIMD3<Float>(repeating: 2 * (radius + cell))
        let nx = min(Int(extent.x / cell) + 2, cap)
        let ny = min(Int(extent.y / cell) + 2, cap)
        let nz = min(Int(extent.z / cell) + 2, cap)
        let step = SIMD3<Float>(extent.x / Float(nx - 1), extent.y / Float(ny - 1), extent.z / Float(nz - 1))
        var field = [Float](repeating: 0, count: nx * ny * nz)
        let r2 = radius * radius
        for particle in particles {
            let low = (particle - SIMD3<Float>(repeating: radius) - origin) / step
            let high = (particle + SIMD3<Float>(repeating: radius) - origin) / step
            let x0 = max(Int(low.x), 0)
            let y0 = max(Int(low.y), 0)
            let z0 = max(Int(low.z), 0)
            let x1 = min(Int(high.x) + 1, nx - 1)
            let y1 = min(Int(high.y) + 1, ny - 1)
            let z1 = min(Int(high.z) + 1, nz - 1)
            guard x0 <= x1, y0 <= y1, z0 <= z1 else { continue }
            for z in z0 ... z1 {
                for y in y0 ... y1 {
                    for x in x0 ... x1 {
                        let point = origin + SIMD3<Float>(Float(x), Float(y), Float(z)) * step
                        let d = point - particle
                        let q = 1 - (d.x * d.x + d.y * d.y + d.z * d.z) / r2
                        if q > 0 { field[(z * ny + y) * nx + x] += q * q * q }
                    }
                }
            }
        }
        // A lone drop's surface sits a spacing out, half its reach: (1 - ½²)³ ≈ 0.42.
        var surface = Tetrahedra(field: field, nx: nx, ny: ny, nz: nz, origin: origin, step: step, level: 0.42)
        return surface.surface()
    }

    private struct Tetrahedra {
        var field: [Float]
        var nx: Int
        var ny: Int
        var nz: Int
        var origin: SIMD3<Float>
        var step: SIMD3<Float>
        var level: Float
        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var indices: [UInt32] = []
        var corners: [UInt64: UInt32] = [:]

        /// The six tetrahedra of a cube, all sharing the diagonal from corner 0 to corner 6.
        static let cube: [SIMD3<Int>] = [
            SIMD3(0, 0, 0), SIMD3(1, 0, 0), SIMD3(1, 1, 0), SIMD3(0, 1, 0), SIMD3(0, 0, 1), SIMD3(1, 0, 1), SIMD3(1, 1, 1), SIMD3(0, 1, 1)
        ]
        static let tetrahedra: [[Int]] = [[0, 5, 1, 6], [0, 1, 2, 6], [0, 2, 3, 6], [0, 3, 7, 6], [0, 7, 4, 6], [0, 4, 5, 6]]

        func index(_ x: Int, _ y: Int, _ z: Int) -> Int { (z * ny + y) * nx + x }

        mutating func surface() -> MeshData {
            guard nx > 1, ny > 1, nz > 1 else { return MeshData() }
            for z in 0 ..< nz - 1 {
                for y in 0 ..< ny - 1 {
                    for x in 0 ..< nx - 1 {
                        march(x, y, z)
                    }
                }
            }
            let normalized = normals.map { n -> SIMD3<Float> in
                let length = length3(n)
                return length > 1e-12 ? n / length : SIMD3<Float>(0, 1, 0)
            }
            return MeshData(positions: positions, normals: normalized, uvs: Array(repeating: .zero, count: positions.count), indices: indices)
        }

        private mutating func march(_ x: Int, _ y: Int, _ z: Int) {
            var values = [Float](repeating: 0, count: 8)
            var ids = [Int](repeating: 0, count: 8)
            var anyIn = false
            var anyOut = false
            for corner in 0 ..< 8 {
                let c = Self.cube[corner]
                ids[corner] = index(x + c.x, y + c.y, z + c.z)
                values[corner] = field[ids[corner]]
                if values[corner] >= level { anyIn = true } else { anyOut = true }
            }
            guard anyIn, anyOut else { return }
            for tetrahedron in Self.tetrahedra {
                let inside = tetrahedron.filter { values[$0] >= level }
                let outside = tetrahedron.filter { values[$0] < level }
                guard !inside.isEmpty, !outside.isEmpty else { continue }
                var points: [UInt32] = []
                if inside.count == 1 || outside.count == 1 {
                    let lone = inside.count == 1 ? inside[0] : outside[0]
                    for other in inside.count == 1 ? outside : inside {
                        points.append(vertex(ids[lone], ids[other], values[lone], values[other]))
                    }
                    emit(points, inside: inside.map { ids[$0] }, outside: outside.map { ids[$0] })
                } else {
                    let a = vertex(ids[inside[0]], ids[outside[0]], values[inside[0]], values[outside[0]])
                    let b = vertex(ids[inside[0]], ids[outside[1]], values[inside[0]], values[outside[1]])
                    let c = vertex(ids[inside[1]], ids[outside[1]], values[inside[1]], values[outside[1]])
                    let d = vertex(ids[inside[1]], ids[outside[0]], values[inside[1]], values[outside[0]])
                    emit([a, b, c], inside: inside.map { ids[$0] }, outside: outside.map { ids[$0] })
                    emit([a, c, d], inside: inside.map { ids[$0] }, outside: outside.map { ids[$0] })
                }
            }
        }

        private func point(_ id: Int) -> SIMD3<Float> {
            let x = id % nx
            let y = (id / nx) % ny
            let z = id / (nx * ny)
            return origin + SIMD3<Float>(Float(x), Float(y), Float(z)) * step
        }

        private mutating func vertex(_ a: Int, _ b: Int, _ va: Float, _ vb: Float) -> UInt32 {
            let key = UInt64(min(a, b)) << 32 | UInt64(max(a, b))
            if let found = corners[key] { return found }
            let t = abs(vb - va) > 1e-9 ? (level - va) / (vb - va) : 0.5
            positions.append(point(a) + (point(b) - point(a)) * min(max(t, 0), 1))
            normals.append(.zero)
            let index = UInt32(positions.count - 1)
            corners[key] = index
            return index
        }

        /// A triangle facing out of the water (from the corners inside toward those outside).
        private mutating func emit(_ triangle: [UInt32], inside: [Int], outside: [Int]) {
            guard triangle.count == 3 else { return }
            let p0 = positions[Int(triangle[0])]
            let p1 = positions[Int(triangle[1])]
            let p2 = positions[Int(triangle[2])]
            var normal = cross3(p1 - p0, p2 - p0)
            var away = SIMD3<Float>.zero
            for corner in outside {
                away += point(corner) / Float(outside.count)
            }
            for corner in inside {
                away -= point(corner) / Float(inside.count)
            }
            let outward = away
            var order = triangle
            if dot3(normal, outward) < 0 {
                order = [triangle[0], triangle[2], triangle[1]]
                normal = -normal
            }
            guard length3(normal) > 1e-14 else { return }
            indices += order
            for corner in order {
                normals[Int(corner)] += normal
            }
        }
    }
}
