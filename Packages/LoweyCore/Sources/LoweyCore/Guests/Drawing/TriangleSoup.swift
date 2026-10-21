import Foundation

/// Triangles in world space with their corners shared where they meet (G1's drawings, papercraft and print tools):
/// the input every line drawing and slice starts from. Each triangle remembers which thing it came from.
public struct TriangleSoup: Sendable {
    public private(set) var positions: [Vec3]
    public private(set) var triangles: [(Int, Int, Int)]
    /// The thing (an index into `names`) each triangle belongs to.
    public private(set) var owners: [Int]
    public private(set) var names: [String]

    public init() {
        positions = []
        triangles = []
        owners = []
        names = []
    }

    /// The meshes as placed in the world (what `SceneExport.meshes` gives, Kit models included).
    public init(_ meshes: [ExportMesh]) {
        self.init()
        for mesh in meshes {
            add(mesh.mesh, transform: mesh.transform, name: mesh.name)
        }
    }

    /// One modelled shape in world space.
    public init(_ mesh: EditableMesh, transform: Transform = .identity, name: String = "") {
        self.init()
        add(mesh, transform: transform, name: name)
    }

    public var isEmpty: Bool { triangles.isEmpty }

    public var bounds: Bounds? { Bounds(points: positions) }

    private var lookup: [SIMD3<Int64>: Int] = [:]

    private mutating func index(of point: Vec3) -> Int {
        let key = SIMD3<Int64>(Int64((point.x * 1e6).rounded()), Int64((point.y * 1e6).rounded()), Int64((point.z * 1e6).rounded()))
        if let known = lookup[key] { return known }
        lookup[key] = positions.count
        positions.append(point)
        return positions.count - 1
    }

    public mutating func add(_ mesh: MeshData, transform: Transform, name: String) {
        let owner = names.count
        names.append(name)
        let mirrored = transform.scale.x * transform.scale.y * transform.scale.z < 0
        let corners = mesh.positions.map { index(of: transform.apply(to: Vec3(Double($0.x), Double($0.y), Double($0.z)))) }
        for start in stride(from: 0, to: mesh.indices.count - 2, by: 3) {
            let a = corners[Int(mesh.indices[start])], b = corners[Int(mesh.indices[start + 1])], c = corners[Int(mesh.indices[start + 2])]
            guard a != b, b != c, a != c else { continue }
            triangles.append(mirrored ? (a, c, b) : (a, b, c))
            owners.append(owner)
        }
    }

    public mutating func add(_ mesh: EditableMesh, transform: Transform, name: String) {
        let owner = names.count
        names.append(name)
        let corners = mesh.vertices.map { index(of: transform.apply(to: $0)) }
        let mirrored = transform.scale.x * transform.scale.y * transform.scale.z < 0
        for (a, b, c) in mesh.triangulated().triangles {
            let (i, j, k) = (corners[a], corners[b], corners[c])
            guard i != j, j != k, i != k else { continue }
            triangles.append(mirrored ? (i, k, j) : (i, j, k))
            owners.append(owner)
        }
    }

    /// Adds a triangle by its corners (for clipped pieces).
    mutating func addTriangle(_ a: Vec3, _ b: Vec3, _ c: Vec3, owner: Int) {
        let i = index(of: a), j = index(of: b), k = index(of: c)
        guard i != j, j != k, i != k else { return }
        triangles.append((i, j, k))
        owners.append(owner)
    }

    public func corners(_ triangle: Int) -> (Vec3, Vec3, Vec3) {
        let (a, b, c) = triangles[triangle]
        return (positions[a], positions[b], positions[c])
    }

    public func normal(_ triangle: Int) -> Vec3 {
        let (a, b, c) = corners(triangle)
        return (b - a).cross(c - a).normalized
    }

    /// Each edge (smaller corner first) and the triangles that share it.
    public func edges() -> [MeshEdge: [Int]] {
        var result: [MeshEdge: [Int]] = [:]
        for (index, (a, b, c)) in triangles.enumerated() {
            result[MeshEdge(a, b), default: []].append(index)
            result[MeshEdge(b, c), default: []].append(index)
            result[MeshEdge(c, a), default: []].append(index)
        }
        return result
    }

    /// Only the triangles below `height` (those crossing it cut along it): what a plan sees beyond its cut.
    public func below(_ height: Double) -> TriangleSoup {
        var result = TriangleSoup()
        result.names = names
        for index in triangles.indices {
            let (a, b, c) = corners(index)
            let clipped = Self.clip([a, b, c]) { height - $0.y }
            guard clipped.count >= 3 else { continue }
            for corner in 1 ..< clipped.count - 1 {
                result.addTriangle(clipped[0], clipped[corner], clipped[corner + 1], owner: owners[index])
            }
        }
        return result
    }

    /// A convex polygon cut to the side of a plane where `plane` is zero or more (Sutherland–Hodgman).
    static func clip(_ polygon: [Vec3], _ plane: (Vec3) -> Double) -> [Vec3] {
        var result: [Vec3] = []
        for index in polygon.indices {
            let p = polygon[index], q = polygon[(index + 1) % polygon.count]
            let dp = plane(p), dq = plane(q)
            if dp >= 0 { result.append(p) }
            if (dp >= 0) != (dq >= 0) {
                let t = dp / (dp - dq)
                result.append(p.lerp(to: q, t))
            }
        }
        return result
    }
}
