import Foundation

/// Closing and joining surfaces: fill a hole with a face, merge corners into one, bridge two faces with a tunnel.
public enum MeshRepair {
    // MARK: Holes

    /// The open borders, each as the loop a new face would walk to close it.
    public static func holes(in mesh: EditableMesh) -> [[Int]] {
        let topology = MeshTopology(mesh)
        var next: [Int: Int] = [:]
        for index in topology.halfEdges.indices where topology.twin(of: index) == nil {
            let edge = topology.halfEdges[index]
            // The hole's face walks each border side the other way.
            next[edge.to] = edge.from
        }
        var loops: [[Int]] = []
        var visited: Set<Int> = []
        for start in next.keys.sorted() where !visited.contains(start) {
            var loop: [Int] = []
            var current = start
            while !visited.contains(current), let following = next[current] {
                visited.insert(current)
                loop.append(current)
                current = following
            }
            if current == start, loop.count >= 3 { loops.append(loop) }
        }
        return loops
    }

    /// Closes the holes (only those touching `near`'s corners when given), each with one face.
    public static func fillHoles(_ mesh: EditableMesh, near corners: Set<Int>? = nil) -> EditableMesh {
        let loops = holes(in: mesh).filter { loop in corners.map { !$0.isDisjoint(with: loop) } ?? true }
        guard !loops.isEmpty else { return mesh }
        return EditableMesh(vertices: mesh.vertices, faces: mesh.faces + loops.map { EditableMesh.Face($0) })
    }

    // MARK: Merging

    /// The corners merged into one at their middle; faces that collapse go, the rest lose the repeated corner.
    public static func merge(_ corners: Set<Int>, in mesh: EditableMesh) -> EditableMesh {
        let picked = corners.filter(mesh.vertices.indices.contains).sorted()
        guard let keep = picked.first, picked.count >= 2 else { return mesh }
        var vertices = mesh.vertices
        vertices[keep] = picked.reduce(Vec3.zero) { $0 + mesh.vertices[$1] } / Double(picked.count)
        let remap = Dictionary(uniqueKeysWithValues: picked.map { ($0, keep) })
        return collapsed(EditableMesh(vertices: vertices, faces: mesh.faces), remap: remap)
    }

    /// Corners closer than `distance` become one (a scan's or an import's doubled corners).
    public static func merge(within distance: Double, in mesh: EditableMesh) -> EditableMesh {
        let (welded, remap) = MeshBuilder.weld(mesh.vertices, tolerance: max(distance, 1e-12))
        guard welded.count < mesh.vertices.count else { return mesh }
        let faces = mesh.faces.map { face in EditableMesh.Face(loops: face.loops.map { $0.map { remap[$0] } }) }
        return collapsed(EditableMesh(vertices: welded, faces: faces), remap: [:])
    }

    /// Applies a corner remap, drops repeated corners in each loop and faces left with fewer than three.
    private static func collapsed(_ mesh: EditableMesh, remap: [Int: Int]) -> EditableMesh {
        var faces: [EditableMesh.Face] = []
        for face in mesh.faces {
            let loops = face.loops.map { loop -> [Int] in
                var result: [Int] = []
                for corner in loop.map({ remap[$0] ?? $0 }) where result.last != corner {
                    result.append(corner)
                }
                if result.count > 1, result.first == result.last { result.removeLast() }
                return result
            }
            guard let outline = loops.first, Set(outline).count >= 3 else { continue }
            faces.append(EditableMesh.Face(loops: [outline] + loops.dropFirst().filter { Set($0).count >= 3 }))
        }
        return MeshBuilder.compact(EditableMesh(vertices: mesh.vertices, faces: faces))
    }

    // MARK: Bridging

    public enum BridgeFailure: Error, Equatable, CustomStringConvertible {
        case sameFace
        case holes
        case touching

        public var description: String {
            switch self {
            case .sameFace: "Pick two different faces to bridge"
            case .holes: "A face with a hole in it can't be bridged"
            case .touching: "These faces share a corner: pick two apart"
            }
        }
    }

    /// Two faces removed and joined by a tunnel of four-sided faces. The face with fewer corners gets more along its
    /// longest sides first (and so do the neighbours of those sides), so each corner meets one across.
    public static func bridge(_ first: Int, _ second: Int, in mesh: EditableMesh) throws(BridgeFailure) -> EditableMesh {
        guard first != second, mesh.faces.indices.contains(first), mesh.faces.indices.contains(second) else { throw .sameFace }
        guard mesh.faces[first].loops.count == 1, mesh.faces[second].loops.count == 1 else { throw .holes }
        guard Set(mesh.faces[first].outline).isDisjoint(with: mesh.faces[second].outline) else { throw .touching }
        var working = mesh
        let target = max(mesh.faces[first].outline.count, mesh.faces[second].outline.count)
        for face in [first, second] {
            working = adding(target - working.faces[face].outline.count, cornersTo: face, in: working)
        }
        let loopA = working.faces[first].outline
        let loopB = aligned(Array(working.faces[second].outline.reversed()), to: loopA, vertices: working.vertices)
        var faces = working.faces.enumerated().filter { $0.offset != first && $0.offset != second }.map(\.element)
        for index in loopA.indices {
            let next = (index + 1) % loopA.count
            // Each side is walked the way the removed face walked it.
            faces.append(EditableMesh.Face([loopA[index], loopA[next], loopB[next], loopB[index]]))
        }
        return EditableMesh(vertices: working.vertices, faces: faces)
    }

    /// The loop turned so the sum of distances to `reference`'s corners is least.
    private static func aligned(_ loop: [Int], to reference: [Int], vertices: [Vec3]) -> [Int] {
        guard loop.count == reference.count else { return loop }
        let best = loop.indices.min { lhs, rhs in
            cost(loop, shift: lhs, reference, vertices) < cost(loop, shift: rhs, reference, vertices)
        } ?? 0
        return loop.indices.map { loop[($0 + best) % loop.count] }
    }

    private static func cost(_ loop: [Int], shift: Int, _ reference: [Int], _ vertices: [Vec3]) -> Double {
        reference.indices.reduce(0) { $0 + vertices[reference[$1]].distance(to: vertices[loop[($1 + shift) % loop.count]]) }
    }

    /// `count` new corners on a face's longest sides (each split side's other face gets the corner too).
    private static func adding(_ count: Int, cornersTo face: Int, in mesh: EditableMesh) -> EditableMesh {
        guard count > 0 else { return mesh }
        var vertices = mesh.vertices
        var faces = mesh.faces
        for _ in 0 ..< count {
            let outline = faces[face].outline
            guard let longest = outline.indices.max(by: { lhs, rhs in
                vertices[outline[lhs]].distance(to: vertices[outline[(lhs + 1) % outline.count]])
                    < vertices[outline[rhs]].distance(to: vertices[outline[(rhs + 1) % outline.count]])
            }) else { break }
            let a = outline[longest], b = outline[(longest + 1) % outline.count]
            vertices.append((vertices[a] + vertices[b]) / 2)
            let middle = vertices.count - 1
            faces = faces.map { face in
                EditableMesh.Face(loops: face.loops.map { loop in splitting(loop, a, b, with: middle) })
            }
        }
        return EditableMesh(vertices: vertices, faces: faces)
    }

    /// A loop with `middle` placed between `a` and `b` wherever they're consecutive (either way round).
    private static func splitting(_ loop: [Int], _ a: Int, _ b: Int, with middle: Int) -> [Int] {
        var result: [Int] = []
        for index in loop.indices {
            let here = loop[index], next = loop[(index + 1) % loop.count]
            result.append(here)
            if (here == a && next == b) || (here == b && next == a) { result.append(middle) }
        }
        return result
    }
}
