import Foundation

/// Where a plane cuts through things (G1): the walls a plan cuts at 1.2 m, a part's cross-section where it's split for
/// printing. Each thing's cut is its loops (closed: the outline and holes of what's cut) and any open chains (from
/// surfaces that aren't closed, like a single plane).
public enum Section {
    public struct Cut: Sendable {
        /// Which thing (`TriangleSoup.names`).
        public var owner: Int
        public var loops: [[Vec3]]
        public var open: [[Vec3]]
    }

    /// The cut of every thing by the plane through `point` square to `normal`.
    public static func cut(_ soup: TriangleSoup, point: Vec3, normal: Vec3) -> [Cut] {
        let n = normal.normalized
        // A hair off the plane, so corners lying exactly on it don't make zero-length pieces.
        let offset = point.dot(n) + 1e-7
        var segments: [Int: [(Vec3, Vec3)]] = [:]
        for index in soup.triangles.indices {
            let (a, b, c) = soup.corners(index)
            let da = a.dot(n) - offset, db = b.dot(n) - offset, dc = c.dot(n) - offset
            var crossings: [Vec3] = []
            for (p, q, dp, dq) in [(a, b, da, db), (b, c, db, dc), (c, a, dc, da)] where (dp < 0) != (dq < 0) {
                crossings.append(p.lerp(to: q, dp / (dp - dq)))
            }
            guard crossings.count == 2, crossings[0].distance(to: crossings[1]) > 1e-9 else { continue }
            segments[soup.owners[index], default: []].append((crossings[0], crossings[1]))
        }
        return segments.keys.sorted().map { owner in
            let (loops, open) = chain(segments[owner] ?? [])
            return Cut(owner: owner, loops: loops, open: open)
        }
    }

    /// Segments joined end to end into loops (and chains that don't close).
    static func chain(_ segments: [(Vec3, Vec3)]) -> (loops: [[Vec3]], open: [[Vec3]]) {
        func key(_ p: Vec3) -> SIMD3<Int64> {
            SIMD3(Int64((p.x * 1e6).rounded()), Int64((p.y * 1e6).rounded()), Int64((p.z * 1e6).rounded()))
        }
        var touching: [SIMD3<Int64>: [Int]] = [:]
        for (index, segment) in segments.enumerated() {
            touching[key(segment.0), default: []].append(index)
            touching[key(segment.1), default: []].append(index)
        }
        var used = [Bool](repeating: false, count: segments.count)
        var loops: [[Vec3]] = [], open: [[Vec3]] = []
        func next(from point: Vec3) -> (Int, Vec3)? {
            for candidate in touching[key(point)] ?? [] where !used[candidate] {
                let (p, q) = segments[candidate]
                return (candidate, key(p) == key(point) ? q : p)
            }
            return nil
        }
        for start in segments.indices where !used[start] {
            used[start] = true
            var chain = [segments[start].0, segments[start].1]
            while let (index, point) = next(from: chain[chain.count - 1]) {
                used[index] = true
                chain.append(point)
            }
            while let (index, point) = next(from: chain[0]) {
                used[index] = true
                chain.insert(point, at: 0)
            }
            if chain.count > 3, key(chain[0]) == key(chain[chain.count - 1]) {
                chain.removeLast()
                loops.append(simplified(chain))
            } else {
                open.append(chain)
            }
        }
        return (loops, open)
    }

    /// A loop without corners that lie on a straight line (a triangulated face cuts into many collinear pieces).
    static func simplified(_ loop: [Vec3]) -> [Vec3] {
        guard loop.count > 3 else { return loop }
        var result: [Vec3] = []
        for index in loop.indices {
            let previous = loop[(index + loop.count - 1) % loop.count], here = loop[index], next = loop[(index + 1) % loop.count]
            let turn = (here - previous).normalized.cross((next - here).normalized).length
            if turn > 1e-6 { result.append(here) }
        }
        return result.count >= 3 ? result : loop
    }
}
