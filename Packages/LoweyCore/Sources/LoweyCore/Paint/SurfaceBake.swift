import Foundation

/// The surface under each texel of an unwrap: where it is on the object and which way it faces. Fills, wear and
/// normal bakes walk it. `paintMesh` is the unwrap's mesh over the object's surface (`PaintUnwrap.mesh(over:)`).
public enum SurfaceTexels {
    /// Calls `body` for every texel of a `size` texture a triangle covers, with its position and normal (object space).
    public static func visit(_ paintMesh: MeshData, size: Int, _ body: (_ x: Int, _ y: Int, _ position: SIMD3<Float>, _ normal: SIMD3<Float>) -> Void) {
        let scale = Float(size)
        let hasNormals = paintMesh.normals.count == paintMesh.positions.count
        for face in 0 ..< paintMesh.triangleCount {
            let i = (Int(paintMesh.indices[face * 3]), Int(paintMesh.indices[face * 3 + 1]), Int(paintMesh.indices[face * 3 + 2]))
            let pa = paintMesh.positions[i.0], pb = paintMesh.positions[i.1], pc = paintMesh.positions[i.2]
            let flat = normalize3(cross3(pb - pa, pc - pa), fallback: SIMD3<Float>(0, 1, 0))
            let na = hasNormals ? paintMesh.normals[i.0] : flat
            let nb = hasNormals ? paintMesh.normals[i.1] : flat
            let nc = hasNormals ? paintMesh.normals[i.2] : flat
            PaintRaster.triangle(paintMesh.uvs[i.0] * scale, paintMesh.uvs[i.1] * scale, paintMesh.uvs[i.2] * scale, width: size, height: size) { x, y, w in
                let position = pa * w.x + pb * w.y + pc * w.z
                let normal = normalize3(na * w.x + nb * w.y + nc * w.z, fallback: flat)
                body(x, y, position, normal)
            }
        }
    }

    /// The length of the box around a mesh's corners (1 when it has none), the yardstick bakes measure by.
    public static func diagonal(_ mesh: MeshData) -> Float {
        guard let first = mesh.positions.first else { return 1 }
        var low = first, high = first
        for position in mesh.positions {
            low = pointwiseMin(low, position)
            high = pointwiseMax(high, position)
        }
        return max(length3(high - low), 1e-4)
    }
}

/// What automatic wear is made from (D-345): how open each texel is to the sky around it (ambient occlusion), and how
/// close it is to a sharp outer edge or an inner crease. Baked at a modest size (it's soft by nature) and sampled
/// smoothly at the paint's size.
public struct WearBake: Sendable {
    public let size: Int
    /// 1 open … 0 enclosed.
    public var occlusion: [Float]
    /// 1 on a sharp outer edge … 0 away from one.
    public var convex: [Float]
    /// 1 in an inner crease … 0 away from one.
    public var concave: [Float]

    public static let defaultSize = 256

    /// Bakes the paint mesh. `rays` per texel for the occlusion; edges are sharper than `angle` degrees.
    public static func make(_ paintMesh: MeshData, size: Int = WearBake.defaultSize, rays: Int = 24, angle: Float = 25) -> WearBake {
        let count = size * size
        var occlusion = [Float](repeating: 1, count: count)
        var convex = [Float](repeating: 0, count: count)
        var concave = [Float](repeating: 0, count: count)
        var covered = [UInt8](repeating: 0, count: count)
        let diagonal = SurfaceTexels.diagonal(paintMesh)
        let bvh = TriangleBVH(paintMesh)
        let directions = hemisphere(rays)
        let edges = SharpEdges(paintMesh, angle: angle, reach: diagonal * 0.03)
        let reach = diagonal * 0.25
        SurfaceTexels.visit(paintMesh, size: size) { x, y, position, normal in
            let index = y * size + x
            covered[index] = 1
            let (tangent, bitangent) = basis(normal)
            let origin = position + normal * diagonal * 1e-3
            var blocked = 0
            for direction in directions {
                let ray = tangent * direction.x + bitangent * direction.y + normal * direction.z
                if bvh.anyHit(origin: origin, direction: ray, start: diagonal * 1e-4, limit: reach) { blocked += 1 }
            }
            occlusion[index] = 1 - Float(blocked) / Float(max(directions.count, 1))
            (convex[index], concave[index]) = edges.nearness(position)
        }
        for _ in 0 ..< 3 {
            Self.spread(&occlusion, &convex, &concave, covered: &covered, size: size)
        }
        return WearBake(size: size, occlusion: occlusion, convex: convex, concave: concave)
    }

    /// The three values at a uv (bilinear, clamped at the picture's edge).
    public func sample(u: Float, v: Float) -> (occlusion: Float, convex: Float, concave: Float) {
        let x = min(max(u * Float(size) - 0.5, 0), Float(size - 1))
        let y = min(max(v * Float(size) - 0.5, 0), Float(size - 1))
        let x0 = Int(x), y0 = Int(y)
        let x1 = min(x0 + 1, size - 1), y1 = min(y0 + 1, size - 1)
        let fx = x - Float(x0), fy = y - Float(y0)
        func at(_ values: [Float]) -> Float {
            let top = values[y0 * size + x0] * (1 - fx) + values[y0 * size + x1] * fx
            let bottom = values[y1 * size + x0] * (1 - fx) + values[y1 * size + x1] * fx
            return top * (1 - fy) + bottom * fy
        }
        return (at(occlusion), at(convex), at(concave))
    }

    /// Fills texels no triangle covers from their covered neighbours, so sampling at a chart's edge stays true.
    private static func spread(_ a: inout [Float], _ b: inout [Float], _ c: inout [Float], covered: inout [UInt8], size: Int) {
        var next = covered
        for y in 0 ..< size {
            for x in 0 ..< size where covered[y * size + x] == 0 {
                var sum = SIMD3<Float>.zero, count: Float = 0
                for (dx, dy) in [(-1, 0), (1, 0), (0, -1), (0, 1)] {
                    let nx = x + dx, ny = y + dy
                    guard nx >= 0, ny >= 0, nx < size, ny < size, covered[ny * size + nx] != 0 else { continue }
                    let n = ny * size + nx
                    sum += SIMD3<Float>(a[n], b[n], c[n])
                    count += 1
                }
                guard count > 0 else { continue }
                let index = y * size + x
                (a[index], b[index], c[index]) = (sum.x / count, sum.y / count, sum.z / count)
                next[index] = 1
            }
        }
        covered = next
    }

    /// Cosine-weighted directions over a hemisphere around +z (a Fibonacci spiral: even, and the same every time).
    static func hemisphere(_ count: Int) -> [SIMD3<Float>] {
        let golden = Float.pi * (3 - Float(5).squareRoot())
        return (0 ..< max(count, 1)).map { index in
            let r = ((Float(index) + 0.5) / Float(max(count, 1))).squareRoot()
            let angle = golden * Float(index)
            return SIMD3<Float>(r * cos(angle), r * sin(angle), (1 - r * r).squareRoot())
        }
    }

    /// Two directions square to `normal` and each other.
    static func basis(_ normal: SIMD3<Float>) -> (SIMD3<Float>, SIMD3<Float>) {
        let up = abs(normal.y) < 0.9 ? SIMD3<Float>(0, 1, 0) : SIMD3<Float>(1, 0, 0)
        let tangent = normalize3(cross3(up, normal), fallback: SIMD3<Float>(1, 0, 0))
        return (tangent, cross3(normal, tangent))
    }
}

/// A mesh's sharp edges (where its faces meet at more than an angle), outer and inner, bucketed for "how near is the
/// closest one" questions.
struct SharpEdges {
    private var convex: [(SIMD3<Float>, SIMD3<Float>)] = []
    private var concave: [(SIMD3<Float>, SIMD3<Float>)] = []
    private var buckets: [SIMD3<Int32>: [Int32]] = [:]
    private let cell: Float
    private let reach: Float

    init(_ mesh: MeshData, angle: Float, reach: Float) {
        self.reach = max(reach, 1e-5)
        cell = self.reach
        let limit = cos(angle * .pi / 180)
        // Corners welded by position, so an unwrap's seams don't count as edges.
        var welded: [SIMD3<Int32>: Int] = [:]
        func key(_ p: SIMD3<Float>) -> Int {
            let q = SIMD3<Int32>(Int32((p.x * 1e4).rounded()), Int32((p.y * 1e4).rounded()), Int32((p.z * 1e4).rounded()))
            if let known = welded[q] { return known }
            welded[q] = welded.count
            return welded.count - 1
        }
        var faces: [SIMD2<Int>: [(normal: SIMD3<Float>, centre: SIMD3<Float>)]] = [:]
        var ends: [SIMD2<Int>: (SIMD3<Float>, SIMD3<Float>)] = [:]
        for face in 0 ..< mesh.triangleCount {
            let p = (0 ..< 3).map { mesh.positions[Int(mesh.indices[face * 3 + $0])] }
            let normal = normalize3(cross3(p[1] - p[0], p[2] - p[0]), fallback: .zero)
            guard normal != .zero else { continue }
            let centre = (p[0] + p[1] + p[2]) / 3
            let k = p.map(key)
            for (a, b) in [(0, 1), (1, 2), (2, 0)] {
                let edge = SIMD2<Int>(min(k[a], k[b]), max(k[a], k[b]))
                faces[edge, default: []].append((normal, centre))
                ends[edge] = (p[a], p[b])
            }
        }
        for (edge, pair) in faces where pair.count == 2 {
            guard dot3(pair[0].normal, pair[1].normal) < limit, let (a, b) = ends[edge] else { continue }
            // Outer when the other face's middle lies below this face's plane.
            if dot3(pair[0].normal, pair[1].centre - pair[0].centre) < 0 { convex.append((a, b)) } else { concave.append((a, b)) }
        }
        for (index, segment) in (convex + concave).enumerated() {
            let steps = max(Int(length3(segment.1 - segment.0) / cell) + 1, 1)
            var seen = Set<SIMD3<Int32>>()
            for step in 0 ... steps {
                let point = segment.0 + (segment.1 - segment.0) * (Float(step) / Float(steps))
                let c = cellOf(point)
                for dx in Int32(-1) ... 1 {
                    for dy in Int32(-1) ... 1 {
                        for dz in Int32(-1) ... 1 where seen.insert(c &+ SIMD3<Int32>(dx, dy, dz)).inserted {
                            buckets[c &+ SIMD3<Int32>(dx, dy, dz), default: []].append(Int32(index))
                        }
                    }
                }
            }
        }
    }

    private func cellOf(_ p: SIMD3<Float>) -> SIMD3<Int32> {
        SIMD3<Int32>(Int32((p.x / cell).rounded(.down)), Int32((p.y / cell).rounded(.down)), Int32((p.z / cell).rounded(.down)))
    }

    /// How near the closest outer and inner edges are: 1 on one, 0 at `reach` or farther.
    func nearness(_ p: SIMD3<Float>) -> (convex: Float, concave: Float) {
        guard let candidates = buckets[cellOf(p)] else { return (0, 0) }
        var nearestConvex = reach, nearestConcave = reach
        for index in candidates {
            let isConvex = Int(index) < convex.count
            let segment = isConvex ? convex[Int(index)] : concave[Int(index) - convex.count]
            let distance = Self.distance(p, segment.0, segment.1)
            if isConvex { nearestConvex = min(nearestConvex, distance) } else { nearestConcave = min(nearestConcave, distance) }
        }
        return (1 - nearestConvex / reach, 1 - nearestConcave / reach)
    }

    static func distance(_ p: SIMD3<Float>, _ a: SIMD3<Float>, _ b: SIMD3<Float>) -> Float {
        let ab = b - a
        let t = min(max(dot3(p - a, ab) / max(dot3(ab, ab), 1e-12), 0), 1)
        return length3(p - (a + ab * t))
    }
}
