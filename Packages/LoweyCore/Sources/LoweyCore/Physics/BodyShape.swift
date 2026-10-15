import Foundation

/// The shape a real thing has in the simulation, built from its real mesh: exact boxes, balls and cylinders where the
/// thing is one, the convex hull of anything else that moves, the triangles themselves for what stays or follows its
/// keys (stairs, a glass), and a group's parts as glued hulls.
public struct BodyShape: Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        case box(half: Vec3)
        case sphere(radius: Double)
        case cylinder(radius: Double, halfHeight: Double)
        case hull([Vec3])
        case mesh(points: [Vec3], indices: [UInt32])
        case compound([[Vec3]])
    }

    public var kind: Kind
    /// Where the body's origin sits in the thing's own space, scaled (a box's centre); the body turns with the thing.
    public var offset: Vec3

    public init(kind: Kind, offset: Vec3 = .zero) {
        self.kind = kind
        self.offset = offset
    }

    /// At most this many points go into a hull (evenly picked; Jolt's hull keeps the outermost).
    static let hullPoints = 1500

    /// The shape of a thing with its local mesh and its world scale, for a body that moves this way.
    public static func make(kind object: ObjectKind, mesh: MeshData, scale: Vec3, motion: ObjectPhysics.Motion) -> BodyShape? {
        guard let bounds = mesh.bounds, bounds.size.maxComponent > 1e-6 else { return nil }
        let size = bounds.size.scaled(by: scale.map(abs))
        let centre = bounds.center.scaled(by: scale)
        let uniformXZ = abs(abs(scale.x) - abs(scale.z)) < 1e-6 * max(abs(scale.x), 1)
        if case let .primitive(shape) = object {
            switch shape {
            case .cube:
                return BodyShape(kind: .box(half: size * 0.5), offset: centre)
            case .sphere where uniformXZ && abs(abs(scale.x) - abs(scale.y)) < 1e-6 * max(abs(scale.x), 1):
                return BodyShape(kind: .sphere(radius: size.x * 0.5), offset: centre)
            case .cylinder where uniformXZ:
                return BodyShape(kind: .cylinder(radius: size.x * 0.5, halfHeight: size.y * 0.5), offset: centre)
            default:
                break
            }
        }
        let points = mesh.positions.map { Vec3($0).scaled(by: scale) }
        if motion != .falls {
            return BodyShape(kind: .mesh(points: points, indices: mesh.indices))
        }
        return BodyShape(kind: .hull(sampled(points)))
    }

    /// A group's parts glued into one body: each part's hull, in the group's own space (scaled).
    public static func compound(_ parts: [(mesh: MeshData, transform: Transform)], scale: Vec3) -> BodyShape? {
        let hulls = parts.compactMap { part -> [Vec3]? in
            let points = part.mesh.positions.map { part.transform.apply(to: Vec3($0)).scaled(by: scale) }
            return points.count >= 4 ? sampled(points) : nil
        }
        guard !hulls.isEmpty else { return nil }
        return hulls.count == 1 ? BodyShape(kind: .hull(hulls[0])) : BodyShape(kind: .compound(hulls))
    }

    static func sampled(_ points: [Vec3]) -> [Vec3] {
        guard points.count > hullPoints else { return points }
        let step = Double(points.count) / Double(hullPoints)
        return (0 ..< hullPoints).map { points[Int(Double($0) * step)] }
    }

    /// The volume a shape holds (m³), for the mass shown before a run.
    public var volume: Double {
        switch kind {
        case let .box(half): 8 * half.x * half.y * half.z
        case let .sphere(radius): 4 / 3 * .pi * radius * radius * radius
        case let .cylinder(radius, halfHeight): .pi * radius * radius * 2 * halfHeight
        case let .hull(points): ConvexVolume.volume(of: points)
        case .mesh: 0
        case let .compound(hulls): hulls.reduce(0) { $0 + ConvexVolume.volume(of: $1) }
        }
    }
}

/// The volume inside the convex hull of a point set: the hull's triangles as tetrahedra from a point inside.
public enum ConvexVolume {
    public static func volume(of points: [Vec3]) -> Double {
        let hull = QuickHull3D.hull(points)
        guard hull.count >= 4 else { return 0 }
        let centre = points.reduce(.zero, +) / Double(points.count)
        return hull.reduce(0) { total, face in
            total + abs((face.0 - centre).dot((face.1 - centre).cross(face.2 - centre))) / 6
        }
    }
}

/// A small, robust 3D convex hull (incremental, with an epsilon), enough for volumes, support polygons and settling
/// faces. Returns triangles whose corners run counter-clockwise seen from outside.
public enum QuickHull3D {
    public static func hull(_ input: [Vec3]) -> [(Vec3, Vec3, Vec3)] {
        let points = BodyShape.sampled(input)
        guard points.count >= 4, let bounds = Bounds(points: points) else { return [] }
        let epsilon = max(bounds.size.maxComponent, 1e-9) * 1e-9
        guard let start = initialTetrahedron(points, epsilon: epsilon) else { return [] }
        var faces: [(Int, Int, Int)] = start
        let centre = (points[start[0].0] + points[start[0].1] + points[start[0].2] + points[start[1].2]) / 4
        func normal(_ f: (Int, Int, Int)) -> Vec3 { (points[f.1] - points[f.0]).cross(points[f.2] - points[f.0]) }
        for (index, point) in points.enumerated() {
            let visible = faces.indices.filter { normal(faces[$0]).dot(point - points[faces[$0].0]) > epsilon * normal(faces[$0]).length }
            guard !visible.isEmpty else { continue }
            var edges: [Edge: Int] = [:]
            for faceIndex in visible {
                let f = faces[faceIndex]
                for (a, b) in [(f.0, f.1), (f.1, f.2), (f.2, f.0)] {
                    let key = Edge(a: min(a, b), b: max(a, b))
                    edges[key, default: 0] += 1
                }
            }
            var horizon: [(Int, Int)] = []
            for faceIndex in visible {
                let f = faces[faceIndex]
                for (a, b) in [(f.0, f.1), (f.1, f.2), (f.2, f.0)] where edges[Edge(a: min(a, b), b: max(a, b))] == 1 {
                    horizon.append((a, b))
                }
            }
            let hidden = Set(visible)
            faces = faces.indices.filter { !hidden.contains($0) }.map { faces[$0] }
            for (a, b) in horizon {
                var face = (a, b, index)
                if normal(face).dot(points[a] - centre) < 0 { face = (b, a, index) }
                faces.append(face)
            }
        }
        return faces.map { (points[$0.0], points[$0.1], points[$0.2]) }
    }

    private struct Edge: Hashable {
        var a: Int
        var b: Int
    }

    private static func initialTetrahedron(_ points: [Vec3], epsilon: Double) -> [(Int, Int, Int)]? {
        let a = 0
        guard let b = points.indices.max(by: { points[$0].distance(to: points[a]) < points[$1].distance(to: points[a]) }),
              points[b].distance(to: points[a]) > epsilon else { return nil }
        let line = (points[b] - points[a]).normalized
        func lineDistance(_ i: Int) -> Double {
            let offset = points[i] - points[a]
            return (offset - line * offset.dot(line)).length
        }
        guard let c = points.indices.max(by: { lineDistance($0) < lineDistance($1) }), lineDistance(c) > epsilon else { return nil }
        let planeNormal = (points[b] - points[a]).cross(points[c] - points[a]).normalized
        func planeDistance(_ i: Int) -> Double { abs((points[i] - points[a]).dot(planeNormal)) }
        guard let d = points.indices.max(by: { planeDistance($0) < planeDistance($1) }), planeDistance(d) > epsilon else { return nil }
        let centre = (points[a] + points[b] + points[c] + points[d]) / 4
        var faces = [(a, b, c), (a, c, d), (a, d, b), (b, d, c)]
        for index in faces.indices {
            let f = faces[index]
            let n = (points[f.1] - points[f.0]).cross(points[f.2] - points[f.0])
            if n.dot(points[f.0] - centre) < 0 { faces[index] = (f.0, f.2, f.1) }
        }
        return faces
    }
}
