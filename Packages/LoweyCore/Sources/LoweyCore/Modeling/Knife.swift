import Foundation

/// The knife: a line drawn across a shape cuts the faces under it in two, along the plane the line sweeps away from
/// the eye. Faces stay whole on either side (no loose edges), and a neighbour the cut ends on gets the new corner in its
/// side, so the surface stays closed.
public enum Knife {
    /// Cuts every face the plane crosses where `within` says the crossing is under the drawn line (it's handed the
    /// middle of the cut through that face). Object space.
    public static func cut(_ mesh: EditableMesh, planePoint: Vec3, planeNormal: Vec3, within: (Vec3) -> Bool) -> EditableMesh {
        let normal = planeNormal.normalized
        let tolerance = max(mesh.bounds?.size.maxComponent ?? 1, 1e-6) * 1e-7
        let distances = mesh.vertices.map { ($0 - planePoint).dot(normal) }
        let prepared = triangulatingCrossedHoles(mesh, distances: distances, tolerance: tolerance)
        var vertices = prepared.vertices
        var edgePoints: [MeshEdge: Int] = [:]
        func point(on edge: MeshEdge) -> Int {
            if let known = edgePoints[edge] { return known }
            let t = distances[edge.a] / (distances[edge.a] - distances[edge.b])
            vertices.append(vertices[edge.a].lerp(to: vertices[edge.b], t))
            edgePoints[edge] = vertices.count - 1
            return vertices.count - 1
        }
        var faces: [EditableMesh.Face] = []
        var cutFaces: Set<Int> = []
        for (index, face) in prepared.faces.enumerated() {
            guard face.loops.count == 1, let events = crossings(face.outline, distances: distances, tolerance: tolerance) else { continue }
            let middle = (position(events.0, outline: face.outline, mesh: prepared, distances: distances)
                + position(events.1, outline: face.outline, mesh: prepared, distances: distances)) / 2
            guard within(middle) else { continue }
            faces += split(face.outline, at: events, point: point)
            cutFaces.insert(index)
        }
        for (index, face) in prepared.faces.enumerated() where !cutFaces.contains(index) {
            faces.append(EditableMesh.Face(loops: face.loops.map { inserting(edgePoints, into: $0) }))
        }
        return EditableMesh(vertices: vertices, faces: faces)
    }

    /// Where the plane meets a face's outline: a corner on the plane, or the side between two corners on either side.
    enum Event: Equatable {
        case corner(Int)
        case side(Int)
    }

    /// The face's two crossings, nil when the plane misses it or crosses it more than twice (a hooked face).
    static func crossings(_ outline: [Int], distances: [Double], tolerance: Double) -> (Event, Event)? {
        var events: [Event] = []
        for index in outline.indices {
            let here = distances[outline[index]], next = distances[outline[(index + 1) % outline.count]]
            if abs(here) <= tolerance {
                events.append(.corner(index))
            } else if abs(next) > tolerance, (here < 0) != (next < 0) {
                events.append(.side(index))
            }
        }
        guard events.count == 2 else { return nil }
        // Two corners next to each other: the plane runs along a side, nothing to cut.
        if case let .corner(a) = events[0], case let .corner(b) = events[1],
           (b - a == 1 || (a == 0 && b == outline.count - 1)) { return nil }
        return (events[0], events[1])
    }

    private static func position(_ event: Event, outline: [Int], mesh: EditableMesh, distances: [Double]) -> Vec3 {
        switch event {
        case let .corner(index):
            return mesh.vertices[outline[index]]
        case let .side(index):
            let a = outline[index], b = outline[(index + 1) % outline.count]
            return mesh.vertices[a].lerp(to: mesh.vertices[b], distances[a] / (distances[a] - distances[b]))
        }
    }

    /// The two halves: from the first crossing round to the second, and from the second round to the first.
    private static func split(_ outline: [Int], at events: (Event, Event), point: (MeshEdge) -> Int) -> [EditableMesh.Face] {
        func vertex(_ event: Event) -> Int {
            switch event {
            case let .corner(index): outline[index]
            case let .side(index): point(MeshEdge(outline[index], outline[(index + 1) % outline.count]))
            }
        }
        func next(after event: Event) -> Int {
            switch event {
            case let .corner(index), let .side(index): (index + 1) % outline.count
            }
        }
        let first = vertex(events.0), second = vertex(events.1)
        func run(from start: Event, to end: Event, startVertex: Int, endVertex: Int) -> [Int] {
            var loop = [startVertex]
            var index = next(after: start)
            let stop: Int = switch end {
            case let .corner(corner): corner
            case let .side(side): (side + 1) % outline.count
            }
            while index != stop {
                loop.append(outline[index])
                index = (index + 1) % outline.count
            }
            loop.append(endVertex)
            return loop
        }
        let one = run(from: events.0, to: events.1, startVertex: first, endVertex: second)
        let two = run(from: events.1, to: events.0, startVertex: second, endVertex: first)
        return [one, two].filter { Set($0).count >= 3 }.map { EditableMesh.Face($0) }
    }

    /// A loop with each cut side's new corner placed between its two corners.
    private static func inserting(_ points: [MeshEdge: Int], into loop: [Int]) -> [Int] {
        var result: [Int] = []
        for index in loop.indices {
            result.append(loop[index])
            if let added = points[MeshEdge(loop[index], loop[(index + 1) % loop.count])] { result.append(added) }
        }
        return result
    }

    /// Faces with holes that the plane crosses become triangles first (a cut can't keep a hole whole).
    private static func triangulatingCrossedHoles(_ mesh: EditableMesh, distances: [Double], tolerance: Double) -> EditableMesh {
        let crossed = mesh.faces.indices.filter { index in
            let face = mesh.faces[index]
            guard face.loops.count > 1 else { return false }
            let values = face.vertices.map { distances[$0] }
            return (values.min() ?? 0) < -tolerance && (values.max() ?? 0) > tolerance
        }
        guard !crossed.isEmpty else { return mesh }
        var faces: [EditableMesh.Face] = []
        for index in mesh.faces.indices {
            if crossed.contains(index) {
                faces += mesh.triangulate(face: index).map { EditableMesh.Face([$0.0, $0.1, $0.2]) }
            } else {
                faces.append(mesh.faces[index])
            }
        }
        return EditableMesh(vertices: mesh.vertices, faces: faces)
    }
}
