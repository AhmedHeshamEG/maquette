import Foundation

/// Placing the sheet on a face, precise (Q1): the sheet lies on the face's own flat plane, sized to the face with a
/// small margin, lined up with its longest edge, and snaps to the face's middle and edges while it slides. On a curved
/// surface it lies on the tangent plane under the tip. Everything here is in world space, on the mesh the stage draws.
public enum SheetFit {
    /// A flat face of a mesh (the connected triangles on one plane), or the patch of a curved surface under the tip.
    public struct Face: Hashable, Sendable {
        /// The triangles it's made of (their numbers in the mesh).
        public var triangles: [Int]
        /// Its plane's normal, facing the eye.
        public var normal: Vec3
        /// Along the face, square to each other: `right` × `up` = `normal`. Lined up with the longest edge, `up` as
        /// close to the world's up as that allows.
        public var right: Vec3
        public var up: Vec3
        /// The middle of its box (along `right` and `up`), on its plane.
        public var middle: Vec3
        /// Half the box's size along `right` and `up`.
        public var halfWidth: Double
        public var halfHeight: Double
        /// A curved surface: the sheet lies on the tangent plane where the tip is, and doesn't snap.
        public var curved: Bool
    }

    /// What snapped while sliding (for the haptic tick).
    public enum Snap: String, Hashable, Sendable {
        case middle, edge
    }

    /// Where the sheet goes on a face.
    public struct Placement: Hashable, Sendable {
        public var center: Vec3
        public var rotation: Quat
        public var width: Double
        public var height: Double
        public var snaps: Set<Snap>
    }

    /// Faces closer than this to one plane are one face: 0.5° and a hair of the mesh's size.
    static let flatCosine = cos(0.5 * Double.pi / 180)
    /// A neighbour this close in angle continues a curved surface (a crisp edge is sharper).
    static let smoothCosine = cos(25 * Double.pi / 180)

    // MARK: The face

    /// The face around `triangle`, seen from `eye`. `limit` caps how many triangles a face may gather (a flat ground
    /// of thousands is still one face, but the scan stays quick).
    public static func face(around triangle: Int, in mesh: MeshData, eye: Vec3, limit: Int = 200_000) -> Face? {
        let count = mesh.triangleCount
        guard triangle >= 0, triangle < count else { return nil }
        guard let seed = corners(triangle, in: mesh) else { return nil }
        var normal = (seed.1 - seed.0).cross(seed.2 - seed.0).normalized
        guard normal.lengthSquared > 0.5 else { return nil }
        if normal.dot(eye - seed.0) < 0 { normal = -normal }
        let size = max(mesh.bounds?.size.length ?? 1, 1e-6)
        let planeTolerance = size * 1e-5
        let offset = normal.dot(seed.0)
        let welder = Welder(cell: size * 1e-6)

        // The triangles on the same plane (either winding: a face seen from either side), then the ones connected to
        // the seed by shared edges.
        var onPlane = Set<Int>()
        var edgesOfPlane: [Welder.Edge: [Int]] = [:]
        for index in 0 ..< count {
            guard let (a, b, c) = corners(index, in: mesh) else { continue }
            let n = (b - a).cross(c - a).normalized
            guard abs(n.dot(normal)) >= flatCosine, abs(normal.dot(a) - offset) <= planeTolerance,
                  abs(normal.dot(b) - offset) <= planeTolerance, abs(normal.dot(c) - offset) <= planeTolerance else { continue }
            onPlane.insert(index)
            for edge in welder.edges(a, b, c) {
                edgesOfPlane[edge, default: []].append(index)
            }
        }
        var region = Set([triangle])
        var queue = [triangle]
        while let next = queue.popLast(), region.count < limit {
            guard let (a, b, c) = corners(next, in: mesh) else { continue }
            for edge in welder.edges(a, b, c) {
                for other in edgesOfPlane[edge] ?? [] where !region.contains(other) && onPlane.contains(other) {
                    region.insert(other)
                    queue.append(other)
                }
            }
        }

        // Its outline: the edges used once. The longest lines the sheet up.
        var uses: [Welder.Edge: (Vec3, Vec3, Int)] = [:]
        var area = 0.0
        for index in region {
            guard let (a, b, c) = corners(index, in: mesh) else { continue }
            area += (b - a).cross(c - a).length / 2
            for (edge, ends) in zip(welder.edges(a, b, c), [(a, b), (b, c), (c, a)]) {
                let seen = uses[edge]
                uses[edge] = (ends.0, ends.1, (seen?.2 ?? 0) + 1)
            }
        }
        let outline = uses.filter { $0.value.2 == 1 }
        let longest = outline.values.max { ($0.1 - $0.0).lengthSquared < ($1.1 - $1.0).lengthSquared }
        let curved = isCurved(region: region, outline: Set(outline.keys), normal: normal, area: area, mesh: mesh, welder: welder)

        let (right, up) = axes(normal: normal, along: curved ? nil : longest.map { $0.1 - $0.0 }, eye: eye, point: seed.0)
        // A face's box is its own; on a curved surface the sheet may be as big as the whole shape seen on that plane.
        var points: [Vec3] = []
        if curved {
            points = mesh.positions.map { Vec3($0) }
        } else {
            for index in region {
                guard let (a, b, c) = corners(index, in: mesh) else { continue }
                points += [a, b, c]
            }
        }
        var low = (u: Double.infinity, v: Double.infinity), high = (u: -Double.infinity, v: -Double.infinity)
        for point in points {
            let u = (point - seed.0).dot(right), v = (point - seed.0).dot(up)
            low = (min(low.u, u), min(low.v, v))
            high = (max(high.u, u), max(high.v, v))
        }
        let middle = seed.0 + right * ((low.u + high.u) / 2) + up * ((low.v + high.v) / 2)
        return Face(triangles: region.sorted(), normal: normal, right: right, up: up, middle: middle,
                    halfWidth: (high.u - low.u) / 2, halfHeight: (high.v - low.v) / 2, curved: curved)
    }

    /// A small patch whose outline mostly runs on into neighbours at a shallow angle is part of a curved surface
    /// (a sphere's facet, a cylinder's side); a face with crisp edges, or a big one, is a face.
    static func isCurved(region: Set<Int>, outline: Set<Welder.Edge>, normal: Vec3, area: Double, mesh: MeshData, welder: Welder) -> Bool {
        var total = 0.0
        var areaAll = 0.0
        var neighbours: [Welder.Edge: [Int]] = [:]
        for index in 0 ..< mesh.triangleCount {
            guard let (a, b, c) = corners(index, in: mesh) else { continue }
            areaAll += (b - a).cross(c - a).length / 2
            guard !region.contains(index) else { continue }
            for edge in welder.edges(a, b, c) where outline.contains(edge) {
                neighbours[edge, default: []].append(index)
            }
        }
        guard areaAll > 0, area / areaAll < 0.05 else { return false }
        var smooth = 0.0
        for edge in outline {
            let length = welder.length(edge)
            total += length
            let continues = (neighbours[edge] ?? []).contains { index in
                guard let (a, b, c) = corners(index, in: mesh) else { return false }
                return abs((b - a).cross(c - a).normalized.dot(normal)) >= smoothCosine
            }
            if continues { smooth += length }
        }
        return total > 0 && smooth / total > 0.5
    }

    /// Right and up on a plane: up from the longest edge's direction (or across it), whichever is nearest the
    /// world's up the way the sheet would have it; without an edge, the sheet's own preferred up.
    static func axes(normal: Vec3, along edge: Vec3?, eye: Vec3, point: Vec3) -> (right: Vec3, up: Vec3) {
        let preferred = DrawingSheet.preferredUp(normal: normal, eye: eye, point: point)
        var up = preferred
        if let edge {
            let along = (edge - normal * edge.dot(normal)).normalized
            if along.lengthSquared > 0.5 {
                let across = normal.cross(along).normalized
                up = [along, -along, across, -across].max { $0.dot(preferred) < $1.dot(preferred) } ?? preferred
            }
        }
        let rotation = DrawingSheet.frame(normal: normal, up: up)
        return (rotation.act(.unitX), rotation.act(.unitY))
    }

    // MARK: The sheet on it

    /// Where the sheet goes on `face` with the tip at `tip`: no bigger than `maximum` (width, height) nor than the
    /// face less its margin; on a flat face it stays inside, snapping to the middle and to the edges within `snap`
    /// metres; turned by `turn` degrees about the normal.
    public static func placement(on face: Face, tip: Vec3, maximum: (width: Double, height: Double), snap: Double,
                                 turn: Double = 0) -> Placement {
        let base = DrawingSheet.frame(normal: face.normal, up: face.up)
        let rotation = turn == 0 ? base : (Quat(angle: turn * .pi / 180, axis: face.normal) * base).normalized
        let onPlane = tip - face.normal * (tip - face.middle).dot(face.normal)
        guard !face.curved else {
            let width = min(maximum.width, face.halfWidth * 2), height = min(maximum.height, face.halfHeight * 2)
            return Placement(center: onPlane, rotation: rotation, width: max(width, 0.01), height: max(height, 0.01), snaps: [])
        }
        let margin = 0.04 * min(face.halfWidth, face.halfHeight) * 2
        let width = max(min(maximum.width, face.halfWidth * 2 - margin * 2), 0.01)
        let height = max(min(maximum.height, face.halfHeight * 2 - margin * 2), 0.01)
        var snaps = Set<Snap>()
        func slide(_ value: Double, half: Double, room: Double) -> Double {
            let reach = max(room - margin - half, 0)
            if abs(value) <= snap || reach == 0 {
                snaps.insert(.middle)
                return 0
            }
            let clamped = min(max(value, -reach), reach)
            if reach - abs(clamped) <= snap {
                snaps.insert(.edge)
                return clamped < 0 ? -reach : reach
            }
            return clamped
        }
        let u = slide((onPlane - face.middle).dot(face.right), half: width / 2, room: face.halfWidth)
        let v = slide((onPlane - face.middle).dot(face.up), half: height / 2, room: face.halfHeight)
        let center = face.middle + face.right * u + face.up * v
        return Placement(center: center, rotation: rotation, width: width, height: height, snaps: snaps)
    }

    /// The angle, snapped to 15° within 4° of a step (the chip's turn while dragging).
    public static func snappedTurn(_ degrees: Double) -> (degrees: Double, snapped: Bool) {
        let step = (degrees / 15).rounded() * 15
        return abs(step - degrees) <= 4 ? (step, true) : (degrees, false)
    }

    /// How far above the surface the sheet sits so it never flickers against it: a hair, more for a big sheet.
    public static func lift(for size: Double) -> Double {
        min(max(size * 0.001, 0.0005), 0.005)
    }
}

public extension DrawingSheet {
    /// A flat sheet where `placement` puts it, a hair above the surface, in `object`'s space when there is one (it
    /// rides with it).
    static func fitted(_ placement: SheetFit.Placement, object: ObjectID?, in scene: Scene, id: String, name: String) -> DrawingSheet {
        let normal = placement.rotation.act(.unitZ)
        let lifted = placement.center + normal * SheetFit.lift(for: max(placement.width, placement.height))
        var sheet = DrawingSheet(id: id, name: name, origin: lifted, rotation: placement.rotation, width: placement.width,
                                 height: placement.height, radius: max(placement.width, placement.height) / 2)
        if let object, scene.objects[object] != nil {
            let carrier = scene.worldTransform(of: object)
            sheet.object = object
            sheet.origin = carrier.inverseApply(to: lifted)
            sheet.rotation = (carrier.rotation.inverse * placement.rotation).normalized
        }
        return sheet
    }
}

/// Vertices that share a place are one (meshes drawn flat repeat each corner per face).
struct Welder {
    struct Edge: Hashable {
        var a: SIMD3<Int64>
        var b: SIMD3<Int64>
    }

    let cell: Double

    func key(_ point: Vec3) -> SIMD3<Int64> {
        SIMD3(Int64((point.x / cell).rounded()), Int64((point.y / cell).rounded()), Int64((point.z / cell).rounded()))
    }

    func edge(_ p: Vec3, _ q: Vec3) -> Edge {
        let a = key(p), b = key(q)
        return (a.x, a.y, a.z) < (b.x, b.y, b.z) ? Edge(a: a, b: b) : Edge(a: b, b: a)
    }

    func edges(_ a: Vec3, _ b: Vec3, _ c: Vec3) -> [Edge] {
        [edge(a, b), edge(b, c), edge(c, a)]
    }

    func length(_ edge: Edge) -> Double {
        let d = edge.b &- edge.a
        return (Double(d.x * d.x + d.y * d.y + d.z * d.z)).squareRoot() * cell
    }
}

private func corners(_ triangle: Int, in mesh: MeshData) -> (Vec3, Vec3, Vec3)? {
    let base = triangle * 3
    guard base + 2 < mesh.indices.count else { return nil }
    let indices = (Int(mesh.indices[base]), Int(mesh.indices[base + 1]), Int(mesh.indices[base + 2]))
    guard indices.0 < mesh.positions.count, indices.1 < mesh.positions.count, indices.2 < mesh.positions.count else { return nil }
    return (Vec3(mesh.positions[indices.0]), Vec3(mesh.positions[indices.1]), Vec3(mesh.positions[indices.2]))
}
