import Foundation

/// Catmull–Clark subdivision: every face becomes a quad per corner and the surface rounds toward a smooth limit. A
/// cube becomes a soft pebble, a blocked-out character a smooth one. Open edges stay where they are (they keep their
/// line, rounded along it), so a half-built shape doesn't shrink away from its border.
public enum Subdivision {
    /// Most levels a shape may ask for (each one has four times the faces of the last).
    public static let maximumLevels = 3

    /// The mesh subdivided `levels` times (holes are cut into triangles first: a face with a hole has no centre).
    public static func subdivide(_ mesh: EditableMesh, levels: Int) -> EditableMesh {
        var result = mesh.withoutHoles()
        for _ in 0 ..< min(max(levels, 0), maximumLevels) {
            result = once(result)
        }
        return result
    }

    /// One level.
    public static func once(_ mesh: EditableMesh) -> EditableMesh {
        let faces = mesh.faces.map(\.outline)
        guard !faces.isEmpty else { return mesh }
        let facePoints = faces.map { outline in outline.reduce(Vec3.zero) { $0 + mesh.vertices[$1] } / Double(outline.count) }
        // An edge's point: halfway between its middle and its two faces' points; a border edge keeps its middle.
        var edgePoints: [MeshEdge: (point: Vec3, border: Bool)] = [:]
        for (edge, around) in adjacency(faces) {
            let middle = (mesh.vertices[edge.a] + mesh.vertices[edge.b]) / 2
            if around.count == 2 {
                edgePoints[edge] = ((middle + (facePoints[around[0]] + facePoints[around[1]]) / 2) / 2, false)
            } else {
                edgePoints[edge] = (middle, true)
            }
        }
        let moved = movedVertices(mesh, faces: faces, facePoints: facePoints, edgePoints: edgePoints)
        return rebuild(faces: faces, moved: moved, facePoints: facePoints, edgePoints: edgePoints)
    }

    /// The faces around each edge.
    static func adjacency(_ faces: [[Int]]) -> [MeshEdge: [Int]] {
        var result: [MeshEdge: [Int]] = [:]
        for (index, outline) in faces.enumerated() {
            for corner in outline.indices {
                result[MeshEdge(outline[corner], outline[(corner + 1) % outline.count]), default: []].append(index)
            }
        }
        return result
    }

    /// Each original corner's new place: (F + 2R + (n − 3)P) / n inside, ¾P + ⅛ of its two border neighbours on a
    /// border, unmoved at a border's corner (only its two border edges meet there) or where the surface isn't a simple
    /// border (more than two border edges meet).
    private static func movedVertices(_ mesh: EditableMesh, faces: [[Int]], facePoints: [Vec3],
                                      edgePoints: [MeshEdge: (point: Vec3, border: Bool)]) -> [Vec3] {
        var aroundFaces = [[Int]](repeating: [], count: mesh.vertices.count)
        for (index, outline) in faces.enumerated() {
            for corner in outline { aroundFaces[corner].append(index) }
        }
        var aroundEdges = [[MeshEdge]](repeating: [], count: mesh.vertices.count)
        for edge in edgePoints.keys {
            aroundEdges[edge.a].append(edge)
            aroundEdges[edge.b].append(edge)
        }
        return mesh.vertices.indices.map { vertex in
            let point = mesh.vertices[vertex]
            let edges = aroundEdges[vertex]
            guard !edges.isEmpty else { return point }
            let border = edges.filter { edgePoints[$0]?.border == true }
            if !border.isEmpty {
                guard border.count == 2, edges.count > 2 else { return point }
                let ends = border.map { mesh.vertices[$0.a == vertex ? $0.b : $0.a] }
                return point * 0.75 + (ends[0] + ends[1]) * 0.125
            }
            let n = Double(edges.count)
            let f = aroundFaces[vertex].reduce(Vec3.zero) { $0 + facePoints[$1] } / Double(max(aroundFaces[vertex].count, 1))
            let r = edges.reduce(Vec3.zero) { $0 + (mesh.vertices[$1.a] + mesh.vertices[$1.b]) / 2 } / n
            return (f + r * 2 + point * (n - 3)) / n
        }
    }

    /// The new mesh: moved corners first, then a point per edge, then a point per face; a quad per old corner.
    private static func rebuild(faces: [[Int]], moved: [Vec3], facePoints: [Vec3],
                                edgePoints: [MeshEdge: (point: Vec3, border: Bool)]) -> EditableMesh {
        var vertices = moved
        var edgeIndex: [MeshEdge: Int] = [:]
        for edge in edgePoints.keys.sorted(by: { ($0.a, $0.b) < ($1.a, $1.b) }) {
            edgeIndex[edge] = vertices.count
            vertices.append(edgePoints[edge]?.point ?? .zero)
        }
        var quads: [EditableMesh.Face] = []
        quads.reserveCapacity(faces.reduce(0) { $0 + $1.count })
        for (index, outline) in faces.enumerated() {
            let centre = vertices.count
            vertices.append(facePoints[index])
            for corner in outline.indices {
                let previous = outline[(corner + outline.count - 1) % outline.count], current = outline[corner]
                let next = outline[(corner + 1) % outline.count]
                guard let incoming = edgeIndex[MeshEdge(previous, current)], let outgoing = edgeIndex[MeshEdge(current, next)] else { continue }
                quads.append(EditableMesh.Face([current, outgoing, centre, incoming]))
            }
        }
        return EditableMesh(vertices: vertices, faces: quads)
    }
}
