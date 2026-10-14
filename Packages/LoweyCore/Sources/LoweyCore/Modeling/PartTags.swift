import Foundation

/// Stable names for the faces of a modelled shape (H1, D-327), so a step recorded on "this face" finds the same face
/// when the steps before it are replayed with other numbers.
///
/// Every face carries a tag. A step hands the tags on by where the new faces lie: a face that lies in the plane of a
/// face before the step, inside it, is (a piece of) that face and keeps its tag; one that lies on a face of the step's
/// tool (the prism a hole is cut with, the solid it was combined with) takes that tool face's tag; a face the step
/// moved names the plane it moved to. Anything else is new and is named by the step and its place among the new
/// faces. Booleans, bevels and shells only ever trim faces inside their own planes, which is why this holds through
/// them. Tags stay under 2^53 so any JSON reader keeps them exact.
public enum PartTags {
    public typealias Tag = UInt64

    static let mask: Tag = (1 << 53) - 1

    /// A tag made from two others (FNV-1a over both).
    public static func derive(_ seed: Tag, _ value: Tag) -> Tag {
        var hash: Tag = 0xCBF2_9CE4_8422_2325
        for word in [seed, value] {
            for shift in stride(from: 0, to: 64, by: 8) {
                hash ^= (word >> Tag(shift)) & 0xFF
                hash = hash &* 0x0000_0100_0000_01B3
            }
        }
        return hash & mask
    }

    /// The tags of a shape a history starts from.
    public static func base(count: Int) -> [Tag] {
        (0 ..< count).map { derive(0, Tag($0)) }
    }

    /// A key for a shape that survives saving: the corners rounded the way the file rounds them.
    public static func shapeKey(_ mesh: EditableMesh) -> Tag {
        let rounded = mesh.vertices.map { $0.map(EditableMesh.rounded) }
        return EditableMesh.fingerprint(vertices: rounded, faces: mesh.faces) & mask
    }

    /// Where tags may come from.
    struct Source {
        var mesh: EditableMesh
        var tags: [Tag]
        /// The tool was cut away, so the faces it leaves face the other way.
        var flipped = false
    }

    /// A plane a step moved a face to: a face of the result lying in it keeps the face's tag.
    struct MovedPlane {
        var normal: Vec3
        var offset: Double
        var tag: Tag
    }

    /// The tags of `mesh`, the result of a step named `seed`, handed on from its sources (earlier first: the shape
    /// before the step wins over its tool where both hold a face).
    static func carry(from sources: [Source], moved: [MovedPlane] = [], to mesh: EditableMesh, seed: Tag) -> [Tag] {
        let size = max(sources.compactMap { $0.mesh.bounds?.size.maxComponent }.max() ?? 1, 1e-3)
        let tolerance = size * 1e-6
        let flats = sources.map { source in source.mesh.faces.indices.map { FlatFace(source.mesh, face: $0) } }
        var tags = [Tag?](repeating: nil, count: mesh.faces.count)
        var unnamed: [(face: Int, point: Vec3)] = []
        for face in mesh.faces.indices {
            let normal = mesh.normal(of: face)
            let point = innerPoint(of: face, in: mesh)
            tags[face] = match(normal, point, sources: sources, flats: flats, moved: moved, tolerance: tolerance)
            if tags[face] == nil { unnamed.append((face, point)) }
        }
        let ordered = unnamed.sorted { lexicographic($0.point, $1.point, step: tolerance * 100) }
        for (ordinal, entry) in ordered.enumerated() {
            tags[entry.face] = derive(seed, Tag(ordinal) | 0x100000)
        }
        return tags.map { $0 ?? seed }
    }

    private static func match(_ normal: Vec3, _ point: Vec3, sources: [Source], flats: [[FlatFace]], moved: [MovedPlane],
                              tolerance: Double) -> Tag? {
        for (index, source) in sources.enumerated() {
            let sign = source.flipped ? -1.0 : 1.0
            for (face, flat) in flats[index].enumerated() where flat.normal.dot(normal) * sign > 1 - 1e-6 {
                if abs(flat.normal.dot(point) - flat.offset) < tolerance, flat.contains(point, tolerance: tolerance) {
                    return source.tags.indices.contains(face) ? source.tags[face] : nil
                }
            }
            if index == 0, let plane = moved.first(where: {
                $0.normal.dot(normal) > 1 - 1e-6 && abs($0.normal.dot(point) - $0.offset) < tolerance
            }) {
                return plane.tag
            }
        }
        return nil
    }

    /// A point well inside a face: the middle of its largest triangle.
    static func innerPoint(of face: Int, in mesh: EditableMesh) -> Vec3 {
        let triangles = mesh.triangulate(face: face)
        var best = mesh.centroid(of: face)
        var largest = -1.0
        for (a, b, c) in triangles {
            let pa = mesh.vertices[a], pb = mesh.vertices[b], pc = mesh.vertices[c]
            let area = (pb - pa).cross(pc - pa).length
            if area > largest {
                largest = area
                best = (pa + pb + pc) / 3
            }
        }
        return best
    }

    static func lexicographic(_ lhs: Vec3, _ rhs: Vec3, step: Double) -> Bool {
        let a = [lhs.x, lhs.y, lhs.z].map { ($0 / step).rounded() }
        let b = [rhs.x, rhs.y, rhs.z].map { ($0 / step).rounded() }
        return a.lexicographicallyPrecedes(b)
    }

    /// A face laid flat in its own plane, for "is this point inside it".
    struct FlatFace {
        let normal: Vec3
        let offset: Double
        let frame: PlaneFrame
        let loops: [[Vec2]]

        init(_ mesh: EditableMesh, face: Int) {
            normal = mesh.normal(of: face)
            let origin = mesh.vertices[mesh.faces[face].outline[0]]
            offset = normal.dot(origin)
            let flat = PlaneFrame(normal: normal, origin: origin)
            frame = flat
            loops = mesh.faces[face].loops.map { loop in loop.map { flat.project(mesh.vertices[$0]) } }
        }

        /// Inside the outline and outside every hole (even-odd), or within `tolerance` of an edge.
        func contains(_ point: Vec3, tolerance: Double) -> Bool {
            let flat = frame.project(point)
            var inside = false
            for loop in loops {
                for index in loop.indices {
                    let a = loop[index], b = loop[(index + 1) % loop.count]
                    if Self.distance(flat, a, b) < tolerance { return true }
                    if (a.y > flat.y) != (b.y > flat.y), flat.x < a.x + (flat.y - a.y) / (b.y - a.y) * (b.x - a.x) {
                        inside.toggle()
                    }
                }
            }
            return inside
        }

        static func distance(_ point: Vec2, _ a: Vec2, _ b: Vec2) -> Double {
            let edge = b - a
            let length = edge.dot(edge)
            let t = length > 0 ? min(max((point - a).dot(edge) / length, 0), 1) : 0
            return point.distance(to: a + edge * t)
        }
    }
}

// MARK: References

/// A face a step points at: its tag, and where it was (to choose among pieces of a face split in two).
public struct FaceRef: Codable, Hashable, Sendable {
    public var tag: PartTags.Tag
    public var at: Vec3

    public init(tag: PartTags.Tag, at: Vec3) {
        self.tag = tag
        self.at = at
    }
}

/// An edge a step points at: the two faces it runs between, and its middle.
public struct EdgeRef: Codable, Hashable, Sendable {
    public var faces: [PartTags.Tag]
    public var at: Vec3

    public init(faces: [PartTags.Tag], at: Vec3) {
        self.faces = faces.sorted()
        self.at = at
    }
}

extension PartTags {
    static func faceRef(_ face: Int, in mesh: EditableMesh, tags: [Tag]) -> FaceRef? {
        guard mesh.faces.indices.contains(face), tags.indices.contains(face) else { return nil }
        return FaceRef(tag: tags[face], at: mesh.centroid(of: face))
    }

    static func edgeRef(_ edge: MeshEdge, in mesh: EditableMesh, topology: MeshTopology, tags: [Tag]) -> EdgeRef? {
        let sides = topology.halfEdges.filter { MeshEdge($0.from, $0.to) == edge }.map(\.face)
        guard sides.count == 2, sides.allSatisfy(tags.indices.contains) else { return nil }
        let middle = (mesh.vertices[edge.a] + mesh.vertices[edge.b]) / 2
        return EdgeRef(faces: sides.map { tags[$0] }, at: middle)
    }

    /// The face a reference names on this shape: of the faces with its tag, the one nearest where it was.
    static func resolve(_ ref: FaceRef, in mesh: EditableMesh, tags: [Tag]) -> Int? {
        tags.indices.filter { tags[$0] == ref.tag && mesh.faces.indices.contains($0) }
            .min { mesh.centroid(of: $0).distance(to: ref.at) < mesh.centroid(of: $1).distance(to: ref.at) }
    }

    /// The edge a reference names: of the edges between faces with its two tags, the one nearest where it was.
    static func resolve(_ ref: EdgeRef, in mesh: EditableMesh, topology: MeshTopology, tags: [Tag]) -> MeshEdge? {
        var sides: [MeshEdge: [Tag]] = [:]
        for half in topology.halfEdges where tags.indices.contains(half.face) {
            sides[MeshEdge(half.from, half.to), default: []].append(tags[half.face])
        }
        let candidates = sides.filter { $0.value.count == 2 && $0.value.sorted() == ref.faces }.map(\.key)
        func gap(_ edge: MeshEdge) -> Double {
            ((mesh.vertices[edge.a] + mesh.vertices[edge.b]) / 2).distance(to: ref.at)
        }
        return candidates.min { gap($0) < gap($1) || (gap($0) == gap($1) && ($0.a, $0.b) < ($1.a, $1.b)) }
    }
}
