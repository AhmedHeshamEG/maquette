import Foundation

/// Solids made from a drawn profile: swept along a path (a pipe, a rail, a picture frame), revolved around a line (a
/// vase, a bowl, a chess piece) or lofted through several profiles (a boat's hull, a bottle's neck). All three are
/// rings of the profile placed in the world and joined side to side, closed with the profile at each open end.
public enum ProfileSolids {
    public enum Failure: Error, Equatable, CustomStringConvertible {
        case shortPath
        case onAxis
        case needsTwo

        public var description: String {
            switch self {
            case .shortPath: "The path needs at least two points"
            case .onAxis: "The shape lies on the line it would turn around"
            case .needsTwo: "Pick two or more closed shapes to loft through"
            }
        }
    }

    /// Profile loops (outline first, then holes) as world points.
    public typealias Loops = [[Vec3]]

    /// A region lifted onto its sketch's plane.
    public static func loops(of region: SketchRegion, on plane: PlaneFrame) -> Loops {
        ([region.outline] + region.holes).map { $0.map { plane.lift($0) } }
    }

    // MARK: Sweep

    /// The profile carried along the path, turning with it (the turn that twists least).
    public static func sweep(_ profile: Loops, plane: PlaneFrame, along path: [Vec3], closed: Bool) throws(Failure) -> EditableMesh {
        let path = deduplicated(path)
        guard path.count >= 2 else { throw .shortPath }
        let tangents = tangents(of: path, closed: closed)
        let oriented = orient(profile, around: tangents[0], normal: plane.normal)
        var rings: [Loops] = []
        var turn = Quat.identity
        for index in path.indices {
            if index > 0 { turn = Quat.rotation(from: tangents[index - 1], to: tangents[index]) * turn }
            rings.append(oriented.map { loop in loop.map { path[index] + turn.act($0 - path[0]) } })
        }
        return solid(rings, closed: closed)
    }

    // MARK: Revolve

    /// The profile turned around the axis line by `degrees` (a full turn closes on itself) in `segments` steps.
    public static func revolve(_ profile: Loops, plane: PlaneFrame, axisPoint: Vec3, axisDirection: Vec3, degrees: Double = 360,
                               segments: Int = 32) throws(Failure) -> EditableMesh {
        let axis = axisDirection.normalized
        let outline = profile.first ?? []
        let centre = outline.reduce(Vec3.zero) { $0 + $1 } / Double(max(outline.count, 1))
        let radial = (centre - axisPoint) - axis * (centre - axisPoint).dot(axis)
        guard radial.length > 1e-9 else { throw .onAxis }
        let full = abs(degrees) >= 359.999
        let steps = max(3, Int((Double(segments) * abs(degrees) / 360).rounded(.up)))
        let oriented = orient(profile, around: axis.cross(radial.normalized) * (degrees < 0 ? -1 : 1), normal: plane.normal)
        let rings: [Loops] = (0 ..< (full ? steps : steps + 1)).map { step in
            let angle = degrees * .pi / 180 * Double(step) / Double(steps)
            let turn = Quat(angle: angle, axis: axis)
            return oriented.map { loop in loop.map { axisPoint + turn.act($0 - axisPoint) } }
        }
        let mesh = solid(rings, closed: full)
        // Corners lying on the axis meet themselves at every step: they become one.
        let size = mesh.bounds?.size.maxComponent ?? 1
        return MeshRepair.merge(within: size * 1e-7, in: mesh)
    }

    // MARK: Loft

    /// A skin through the profiles' outlines in order (holes aren't carried), each walked with the same number of
    /// corners, starting at the corners nearest each other.
    public static func loft(_ outlines: [[Vec3]], normals: [Vec3]) throws(Failure) -> EditableMesh {
        guard outlines.count >= 2, outlines.allSatisfy({ $0.count >= 3 }) else { throw .needsTwo }
        let count = outlines.map(\.count).max() ?? 3
        let centres = outlines.map { $0.reduce(Vec3.zero) { $0 + $1 } / Double($0.count) }
        let direction = (centres[centres.count - 1] - centres[0]).normalized
        var rings: [Loops] = []
        for (index, outline) in outlines.enumerated() {
            var loop = orient([resampled(outline, count: count)], around: direction, normal: normals[index])[0]
            if let previous = rings.last?.first { loop = turned(loop, toMatch: previous) }
            rings.append([loop])
        }
        return solid(rings, closed: false)
    }

    // MARK: Building

    /// Rings of the same loops joined side to side; open ends closed with the first and last ring.
    static func solid(_ rings: [Loops], closed: Bool) -> EditableMesh {
        var vertices: [Vec3] = []
        var indexOf: [[[Int]]] = []
        for ring in rings {
            indexOf.append(ring.map { loop in loop.map { point in
                vertices.append(point)
                return vertices.count - 1
            } })
        }
        var faces: [EditableMesh.Face] = []
        let spans = closed ? rings.count : rings.count - 1
        for ring in 0 ..< spans {
            let next = (ring + 1) % rings.count
            for (loop, corners) in indexOf[ring].enumerated() {
                for corner in corners.indices {
                    let following = (corner + 1) % corners.count
                    faces.append(EditableMesh.Face([corners[corner], corners[following], indexOf[next][loop][following],
                                                    indexOf[next][loop][corner]]))
                }
            }
        }
        if !closed, let first = indexOf.first, let last = indexOf.last {
            faces.append(EditableMesh.Face(loops: first.map { Array($0.reversed()) }))
            faces.append(EditableMesh.Face(loops: last))
        }
        let mesh = EditableMesh(vertices: vertices, faces: faces)
        return mesh.volume < 0 ? mesh.flipped() : mesh
    }

    /// Loops turned so the outline runs counter-clockwise around `direction` (holes the other way).
    static func orient(_ loops: Loops, around direction: Vec3, normal: Vec3) -> Loops {
        guard let outline = loops.first else { return loops }
        let facing = EditableMesh.newellVector(outline).dot(direction)
        let flip = facing == 0 ? normal.dot(direction) < 0 : facing < 0
        return flip ? loops.map { Array($0.reversed()) } : loops
    }

    private static func deduplicated(_ path: [Vec3]) -> [Vec3] {
        var result: [Vec3] = []
        for point in path where result.last.map({ $0.distance(to: point) > 1e-9 }) ?? true {
            result.append(point)
        }
        return result
    }

    /// The direction of travel at each point (the average of the sides on either side).
    private static func tangents(of path: [Vec3], closed: Bool) -> [Vec3] {
        path.indices.map { index in
            let previous = index > 0 ? path[index - 1] : (closed ? path[path.count - 1] : path[index])
            let next = index < path.count - 1 ? path[index + 1] : (closed ? path[0] : path[index])
            let direction = (next - path[index]).normalized + (path[index] - previous).normalized
            return direction.length > 1e-9 ? direction.normalized : (next - previous).normalized
        }
    }

    /// The outline with `count` corners spaced evenly along it.
    static func resampled(_ outline: [Vec3], count: Int) -> [Vec3] {
        guard outline.count != count else { return outline }
        let sides = outline.indices.map { outline[$0].distance(to: outline[($0 + 1) % outline.count]) }
        let total = sides.reduce(0, +)
        guard total > 0 else { return outline }
        var result: [Vec3] = []
        var side = 0, walked = 0.0
        for step in 0 ..< count {
            let target = total * Double(step) / Double(count)
            while side < sides.count - 1, walked + sides[side] < target {
                walked += sides[side]
                side += 1
            }
            let t = sides[side] > 0 ? (target - walked) / sides[side] : 0
            result.append(outline[side].lerp(to: outline[(side + 1) % outline.count], min(max(t, 0), 1)))
        }
        return result
    }

    /// The loop started at the corner nearest `reference`'s first, so the skin doesn't twist.
    private static func turned(_ loop: [Vec3], toMatch reference: [Vec3]) -> [Vec3] {
        guard loop.count == reference.count else { return loop }
        let best = loop.indices.min { lhs, rhs in
            twist(loop, lhs, reference) < twist(loop, rhs, reference)
        } ?? 0
        return loop.indices.map { loop[($0 + best) % loop.count] }
    }

    private static func twist(_ loop: [Vec3], _ shift: Int, _ reference: [Vec3]) -> Double {
        reference.indices.reduce(0) { $0 + reference[$1].distance(to: loop[($1 + shift) % loop.count]) }
    }
}
