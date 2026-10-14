import Foundation

/// A loop cut: new edges run around the shape through a ring of four-sided faces, across the edge that was touched.
/// It's how a modeller adds the lines a shape needs to bend, bevel or pull in one place. The ring stops where it meets
/// a face that isn't four-sided (or the shape's open border), so it never tears a face.
public enum LoopCut {
    /// The ring of edges a cut across `edge` passes through, in order (each crossing a quad to the opposite side).
    public static func ring(from edge: MeshEdge, in mesh: EditableMesh) -> [MeshEdge] {
        let faces = mesh.faces.map(\.outline)
        let around = Subdivision.adjacency(faces)
        let sides = around[edge] ?? []
        guard !sides.isEmpty else { return [] }
        var seen: Set<MeshEdge> = [edge]
        // Walk out through each face beside the touched edge; a closed ring comes back to it and stops.
        let walks = sides.prefix(2).map { start in walk(from: edge, through: start, faces: faces, around: around, seen: &seen) }
        return (walks.count > 1 ? walks[1].reversed() : []) + [edge] + walks[0]
    }

    private static func walk(from edge: MeshEdge, through start: Int, faces: [[Int]], around: [MeshEdge: [Int]],
                             seen: inout Set<MeshEdge>) -> [MeshEdge] {
        var walked: [MeshEdge] = []
        var current = edge, face = start
        while let next = opposite(of: current, in: faces[face]), !seen.contains(next) {
            seen.insert(next)
            walked.append(next)
            guard let beyond = (around[next] ?? []).first(where: { $0 != face }) else { break }
            current = next
            face = beyond
        }
        return walked
    }

    /// The side across a quad from `edge` (nil when the face isn't four-sided or doesn't have the edge).
    static func opposite(of edge: MeshEdge, in outline: [Int]) -> MeshEdge? {
        guard outline.count == 4 else { return nil }
        for index in 0 ..< 4 where MeshEdge(outline[index], outline[(index + 1) % 4]) == edge {
            return MeshEdge(outline[(index + 2) % 4], outline[(index + 3) % 4])
        }
        return nil
    }

    /// Cuts the ring `cuts` times, evenly (at `position`, 0…1 along each edge from its first corner, for one cut).
    public static func cut(_ mesh: EditableMesh, across edge: MeshEdge, cuts: Int = 1, position: Double = 0.5) -> EditableMesh {
        let ring = ring(from: edge, in: mesh)
        guard !ring.isEmpty, cuts >= 1 else { return mesh }
        var vertices = mesh.vertices
        // Each ring edge gets its new points, measured from a consistent side so the cuts line up around the loop.
        var points: [MeshEdge: [Int]] = [:]
        var reference = ring[0].a
        for (index, ringEdge) in ring.enumerated() {
            if index > 0 { reference = side(of: ringEdge, matching: reference, previous: ring[index - 1], in: mesh) }
            let start = reference, end = ringEdge.a == reference ? ringEdge.b : ringEdge.a
            points[ringEdge] = (1 ... cuts).map { step in
                let t = cuts == 1 ? position : Double(step) / Double(cuts + 1)
                vertices.append(mesh.vertices[start].lerp(to: mesh.vertices[end], t))
                return vertices.count - 1
            }
            if start != ringEdge.a { points[ringEdge]?.reverse() }
        }
        return EditableMesh(vertices: vertices, faces: rebuilt(mesh, points: points))
    }

    /// Which end of `edge` sits on the same side of the ring as `reference` on `previous` (they share a quad side).
    private static func side(of edge: MeshEdge, matching reference: Int, previous: MeshEdge, in mesh: EditableMesh) -> Int {
        for face in mesh.faces {
            let outline = face.outline
            guard outline.count == 4, outline.contains(edge.a), outline.contains(edge.b), outline.contains(previous.a),
                  outline.contains(previous.b) else { continue }
            // In the quad, `reference` is joined by a side to one end of `edge`.
            for index in 0 ..< 4 where outline[index] == reference {
                let neighbours = [outline[(index + 1) % 4], outline[(index + 3) % 4]]
                if let joined = neighbours.first(where: { $0 == edge.a || $0 == edge.b }) { return joined }
            }
        }
        return edge.a
    }

    /// Every face with the new points put into its sides; quads crossed by the ring split into strips.
    private static func rebuilt(_ mesh: EditableMesh, points: [MeshEdge: [Int]]) -> [EditableMesh.Face] {
        var faces: [EditableMesh.Face] = []
        for face in mesh.faces {
            let outline = face.outline
            let crossed = outline.count == 4 ? (0 ..< 4).filter { points[MeshEdge(outline[$0], outline[($0 + 1) % 4])] != nil } : []
            if crossed.count == 2, crossed[1] - crossed[0] == 2 {
                faces += strips(outline, from: crossed[0], points: points)
            } else {
                faces.append(EditableMesh.Face(loops: face.loops.map { inserting(points, into: $0) }))
            }
        }
        return faces
    }

    /// A quad whose sides `first` and `first + 2` are cut, as strips between the cuts.
    private static func strips(_ outline: [Int], from first: Int, points: [MeshEdge: [Int]]) -> [EditableMesh.Face] {
        let a = outline[first], b = outline[(first + 1) % 4], c = outline[(first + 2) % 4], d = outline[(first + 3) % 4]
        // Side a→b and side c→d run opposite ways around the quad.
        let along = [a] + ordered(points[MeshEdge(a, b)] ?? [], from: a, edge: MeshEdge(a, b)) + [b]
        let back = [d] + ordered(points[MeshEdge(c, d)] ?? [], from: d, edge: MeshEdge(c, d)) + [c]
        guard along.count == back.count else { return [EditableMesh.Face(outline)] }
        return (0 ..< along.count - 1).map { index in
            EditableMesh.Face([along[index], along[index + 1], back[index + 1], back[index]])
        }
    }

    /// An edge's new points listed from `start` (they're stored from the edge's first corner).
    private static func ordered(_ points: [Int], from start: Int, edge: MeshEdge) -> [Int] {
        start == edge.a ? points : points.reversed()
    }

    /// A loop with the new points of any cut side placed between its corners (neighbours of the ring stay closed).
    private static func inserting(_ points: [MeshEdge: [Int]], into loop: [Int]) -> [Int] {
        var result: [Int] = []
        for index in loop.indices {
            let from = loop[index], to = loop[(index + 1) % loop.count]
            result.append(from)
            let edge = MeshEdge(from, to)
            if let added = points[edge] { result += ordered(added, from: from, edge: edge) }
        }
        return result
    }
}
