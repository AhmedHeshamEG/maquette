import Foundation

/// Lightening a heavy mesh (a sculpt with millions of triangles) to a count this iPad keeps smooth, keeping its shape:
/// edges are collapsed where the surface is flattest first, each corner moved to where it changes the shape least
/// (Garland and Heckbert's quadric error, in the fast threshold form of Sven Forstmann's Fast Quadric Mesh
/// Simplification, MIT). Colours are carried onto the lighter mesh from the nearest corner of the original.
public enum MeshSimplify {
    /// The mesh with about `target` triangles (the mesh itself when it has no more than that), and its colours.
    public static func simplified(_ mesh: MeshData, colors: [SIMD4<Float>] = [], target: Int) -> (mesh: MeshData, colors: [SIMD4<Float>]) {
        guard mesh.triangleCount > target, target >= 4 else { return (mesh, colors) }
        var work = Work(mesh)
        work.simplify(target: target)
        var result = MeshData()
        result.positions = work.vertices.map { SIMD3<Float>(Float($0.p.x), Float($0.p.y), Float($0.p.z)) }
        result.uvs = Array(repeating: .zero, count: result.positions.count)
        result.indices = work.triangles.flatMap { [UInt32($0.v.0), UInt32($0.v.1), UInt32($0.v.2)] }
        result.computeSmoothNormals()
        let carried = colors.count == mesh.positions.count ? carry(colors, from: mesh.positions, to: result.positions) : []
        return (result, carried)
    }

    /// Each new corner's colour: the colour of the nearest corner of the original.
    static func carry(_ colors: [SIMD4<Float>], from old: [SIMD3<Float>], to new: [SIMD3<Float>]) -> [SIMD4<Float>] {
        let points = old.map { Vec3(Double($0.x), Double($0.y), Double($0.z)) }
        guard let bounds = Bounds(points: points) else { return [] }
        // About four original corners a cell, so a lookup touches a few dozen.
        let cell = max(bounds.size.length / max(pow(Double(old.count) / 4, 1.0 / 3), 1), 1e-6)
        let grid = PointGrid(points, cell: cell)
        return new.map { corner in
            let point = Vec3(Double(corner.x), Double(corner.y), Double(corner.z))
            var near = grid.near(point)
            var reach = 1
            while near.isEmpty, reach < 8 {
                reach *= 2
                near = grid.near(point, rings: reach)
            }
            let best = near.min { points[$0].distance(to: point) < points[$1].distance(to: point) }
            return best.map { colors[$0] } ?? SIMD4<Float>(1, 1, 1, 1)
        }
    }

    // MARK: The collapse

    /// A symmetric 4×4 matrix kept as its ten distinct entries: `a` the first eight, `b` the last two.
    struct Quadric {
        var a = SIMD8<Double>(repeating: 0)
        var b = SIMD2<Double>(repeating: 0)

        init() {}

        /// The plane px + qy + rz + s = 0.
        init(plane p: Double, _ q: Double, _ r: Double, _ s: Double) {
            a = SIMD8(p * p, p * q, p * r, p * s, q * q, q * r, q * s, r * r)
            b = SIMD2(r * s, s * s)
        }

        static func + (l: Quadric, r: Quadric) -> Quadric {
            var q = Quadric()
            q.a = l.a + r.a
            q.b = l.b + r.b
            return q
        }

        static func += (l: inout Quadric, r: Quadric) {
            l.a += r.a
            l.b += r.b
        }

        /// The point where the error is least (Cramer's rule on the 3×3 part), nil when that part can't be solved.
        var best: SIMD3<Double>? {
            let m0 = a[0], m1 = a[1], m2 = a[2], m3 = a[3], m4 = a[4], m5 = a[5], m6 = a[6], m7 = a[7], m8 = b[0]
            let det = m0 * m4 * m7 + m2 * m1 * m5 + m1 * m5 * m2 - m2 * m4 * m2 - m0 * m5 * m5 - m1 * m1 * m7
            guard det != 0 else { return nil }
            let x = m1 * m5 * m8 + m3 * m4 * m7 + m2 * m6 * m5 - m3 * m5 * m5 - m1 * m6 * m7 - m2 * m4 * m8
            let y = m0 * m5 * m8 + m3 * m1 * m7 + m2 * m6 * m2 - m3 * m5 * m2 - m0 * m6 * m7 - m2 * m1 * m8
            let z = m0 * m4 * m8 + m3 * m1 * m5 + m1 * m6 * m2 - m3 * m4 * m2 - m0 * m6 * m5 - m1 * m1 * m8
            return SIMD3(-x / det, y / det, -z / det)
        }

        func error(_ p: SIMD3<Double>) -> Double {
            let x = p.x, y = p.y, z = p.z
            return a[0] * x * x + 2 * a[1] * x * y + 2 * a[2] * x * z + 2 * a[3] * x + a[4] * y * y + 2 * a[5] * y * z + 2 * a[6] * y
                + a[7] * z * z + 2 * b[0] * z + b[1]
        }
    }

    struct Triangle {
        var v: (Int, Int, Int)
        var err: SIMD4<Double> = .zero
        var deleted = false
        var dirty = false
        var n = SIMD3<Double>(0, 0, 0)

        func corner(_ index: Int) -> Int {
            switch index {
            case 0: v.0
            case 1: v.1
            default: v.2
            }
        }

        mutating func set(_ index: Int, _ value: Int) {
            switch index {
            case 0: v.0 = value
            case 1: v.1 = value
            default: v.2 = value
            }
        }
    }

    struct Vertex {
        var p: SIMD3<Double>
        var tstart = 0
        var tcount = 0
        var q = Quadric()
        var border = false
    }

    struct Ref {
        var tid: Int
        var tvertex: Int
    }

    struct Work {
        var vertices: [Vertex] = []
        var triangles: [Triangle] = []
        var refs: [Ref] = []

        /// Corners that share a place are welded first, so the surface is one piece and no false border stops it.
        init(_ mesh: MeshData) {
            var index: [SIMD3<Float>: Int] = [:]
            var remap: [Int] = []
            remap.reserveCapacity(mesh.positions.count)
            for position in mesh.positions {
                if let known = index[position] {
                    remap.append(known)
                } else {
                    index[position] = vertices.count
                    remap.append(vertices.count)
                    vertices.append(Vertex(p: SIMD3<Double>(Double(position.x), Double(position.y), Double(position.z))))
                }
            }
            triangles.reserveCapacity(mesh.triangleCount)
            for t in stride(from: 0, to: mesh.indices.count - 2, by: 3) {
                let a = remap[Int(mesh.indices[t])], b = remap[Int(mesh.indices[t + 1])], c = remap[Int(mesh.indices[t + 2])]
                if a != b, b != c, c != a { triangles.append(Triangle(v: (a, b, c))) }
            }
        }

        mutating func simplify(target: Int, aggressiveness: Double = 7) {
            var deletedCount = 0
            var gone0: [Bool] = [], gone1: [Bool] = []
            let start = triangles.count
            for iteration in 0 ..< 100 {
                if start - deletedCount <= target { break }
                if iteration % 5 == 0 { update(iteration: iteration) }
                for t in triangles.indices {
                    triangles[t].dirty = false
                }
                let threshold = 1e-9 * pow(Double(iteration + 3), aggressiveness)
                for t in triangles.indices where !triangles[t].deleted && !triangles[t].dirty && triangles[t].err[3] <= threshold {
                    for j in 0 ..< 3 where triangles[t].err[j] < threshold {
                        if collapse(t, j, gone0: &gone0, gone1: &gone1, deleted: &deletedCount) { break }
                    }
                    if start - deletedCount <= target { break }
                }
            }
            compact()
        }

        /// Collapses edge `j` of triangle `t` onto its first corner, when that doesn't fold the surface over.
        mutating func collapse(_ t: Int, _ j: Int, gone0: inout [Bool], gone1: inout [Bool], deleted: inout Int) -> Bool {
            let i0 = triangles[t].corner(j), i1 = triangles[t].corner((j + 1) % 3)
            guard vertices[i0].border == vertices[i1].border else { return false }
            let (_, p) = error(i0, i1)
            gone0 = Array(repeating: false, count: vertices[i0].tcount)
            gone1 = Array(repeating: false, count: vertices[i1].tcount)
            if flipped(p, i0, i1, &gone0) || flipped(p, i1, i0, &gone1) { return false }
            vertices[i0].p = p
            vertices[i0].q += vertices[i1].q
            let tstart = refs.count
            update(i0, from: i0, gone: gone0, deleted: &deleted)
            update(i0, from: i1, gone: gone1, deleted: &deleted)
            let tcount = refs.count - tstart
            if tcount <= vertices[i0].tcount {
                for k in 0 ..< tcount {
                    refs[vertices[i0].tstart + k] = refs[tstart + k]
                }
                refs.removeLast(tcount)
            } else {
                vertices[i0].tstart = tstart
            }
            vertices[i0].tcount = tcount
            return true
        }

        /// Whether moving `i0` to `p` would turn one of its triangles over (or make it a sliver).
        func flipped(_ p: SIMD3<Double>, _ i0: Int, _ i1: Int, _ gone: inout [Bool]) -> Bool {
            let v = vertices[i0]
            for k in 0 ..< v.tcount {
                let ref = refs[v.tstart + k]
                let triangle = triangles[ref.tid]
                if triangle.deleted { continue }
                let id1 = triangle.corner((ref.tvertex + 1) % 3), id2 = triangle.corner((ref.tvertex + 2) % 3)
                if id1 == i1 || id2 == i1 {
                    gone[k] = true
                    continue
                }
                let d1 = unit(vertices[id1].p - p), d2 = unit(vertices[id2].p - p)
                if abs(dot(d1, d2)) > 0.999 { return true }
                let n = unit(cross(d1, d2))
                if dot(n, triangle.n) < 0.2 { return true }
            }
            return false
        }

        /// `source`'s triangles now use `i0` (the ones on the collapsed edge go).
        mutating func update(_ i0: Int, from source: Int, gone: [Bool], deleted: inout Int) {
            let v = vertices[source]
            for k in 0 ..< v.tcount {
                let ref = refs[v.tstart + k]
                if triangles[ref.tid].deleted { continue }
                if gone[k] {
                    triangles[ref.tid].deleted = true
                    deleted += 1
                    continue
                }
                triangles[ref.tid].set(ref.tvertex, i0)
                triangles[ref.tid].dirty = true
                errors(ref.tid)
                refs.append(ref)
            }
        }

        mutating func errors(_ t: Int) {
            let triangle = triangles[t]
            let e0 = error(triangle.v.0, triangle.v.1).error, e1 = error(triangle.v.1, triangle.v.2).error
            let e2 = error(triangle.v.2, triangle.v.0).error
            triangles[t].err = SIMD4(e0, e1, e2, min(e0, e1, e2))
        }

        /// The cost of collapsing an edge and where its corner goes.
        func error(_ a: Int, _ b: Int) -> (error: Double, point: SIMD3<Double>) {
            let q = vertices[a].q + vertices[b].q
            let border = vertices[a].border && vertices[b].border
            if !border, let p = q.best { return (q.error(p), p) }
            let p1 = vertices[a].p, p2 = vertices[b].p, p3 = (p1 + p2) / 2
            let candidates = [(q.error(p1), p1), (q.error(p2), p2), (q.error(p3), p3)]
            return candidates.min { $0.0 < $1.0 } ?? (q.error(p3), p3)
        }

        /// Drops deleted triangles, rebuilds which triangles meet at each corner, and (first time) the quadrics and
        /// the open edges.
        mutating func update(iteration: Int) {
            if iteration > 0 { triangles.removeAll { $0.deleted } }
            if iteration == 0 { startQuadrics() }
            for v in vertices.indices {
                vertices[v].tstart = 0
                vertices[v].tcount = 0
            }
            for triangle in triangles {
                vertices[triangle.v.0].tcount += 1
                vertices[triangle.v.1].tcount += 1
                vertices[triangle.v.2].tcount += 1
            }
            var start = 0
            for v in vertices.indices {
                vertices[v].tstart = start
                start += vertices[v].tcount
                vertices[v].tcount = 0
            }
            refs = Array(repeating: Ref(tid: 0, tvertex: 0), count: triangles.count * 3)
            for (t, triangle) in triangles.enumerated() {
                for j in 0 ..< 3 {
                    let v = triangle.corner(j)
                    refs[vertices[v].tstart + vertices[v].tcount] = Ref(tid: t, tvertex: j)
                    vertices[v].tcount += 1
                }
            }
            if iteration == 0 { markBorders() }
        }

        mutating func startQuadrics() {
            for t in triangles.indices {
                let triangle = triangles[t]
                let p0 = vertices[triangle.v.0].p, p1 = vertices[triangle.v.1].p, p2 = vertices[triangle.v.2].p
                let n = unit(cross(p1 - p0, p2 - p0))
                triangles[t].n = n.x.isFinite ? n : SIMD3<Double>(0, 1, 0)
                let plane = Quadric(plane: n.x, n.y, n.z, -dot(n, p0))
                for v in [triangle.v.0, triangle.v.1, triangle.v.2] {
                    vertices[v].q += plane
                }
            }
            for t in triangles.indices {
                errors(t)
            }
        }

        /// A corner on an open edge (one triangle only) stays on it.
        mutating func markBorders() {
            for v in vertices.indices {
                var seen: [Int: Int] = [:]
                let corner = vertices[v]
                for k in 0 ..< corner.tcount {
                    let triangle = triangles[refs[corner.tstart + k].tid]
                    for j in 0 ..< 3 where triangle.corner(j) != v {
                        seen[triangle.corner(j), default: 0] += 1
                    }
                }
                for (other, count) in seen where count == 1 {
                    vertices[v].border = true
                    vertices[other].border = true
                }
            }
        }

        /// Only the triangles left and the corners they use.
        mutating func compact() {
            triangles.removeAll { $0.deleted }
            var used = Array(repeating: -1, count: vertices.count)
            var kept: [Vertex] = []
            for t in triangles.indices {
                for j in 0 ..< 3 {
                    let v = triangles[t].corner(j)
                    if used[v] < 0 {
                        used[v] = kept.count
                        kept.append(vertices[v])
                    }
                    triangles[t].set(j, used[v])
                }
            }
            vertices = kept
        }
    }
}

private func dot(_ a: SIMD3<Double>, _ b: SIMD3<Double>) -> Double { a.x * b.x + a.y * b.y + a.z * b.z }

private func cross(_ a: SIMD3<Double>, _ b: SIMD3<Double>) -> SIMD3<Double> {
    SIMD3(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x)
}

private func unit(_ a: SIMD3<Double>) -> SIMD3<Double> {
    let length = dot(a, a).squareRoot()
    return length > 0 ? a / length : a
}

extension PointGrid {
    /// Points within `rings` cells of `point`'s cell.
    func near(_ point: Vec3, rings: Int) -> [Int] {
        let centre = key(point)
        var result: [Int] = []
        for x in -rings ... rings {
            for y in -rings ... rings {
                for z in -rings ... rings {
                    result += buckets[centre &+ SIMD3<Int64>(Int64(x), Int64(y), Int64(z))] ?? []
                }
            }
        }
        return result
    }
}
