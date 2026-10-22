import Foundation

/// The rest of a building (G1, Room): roofs over an outline, columns, beams, railings, scale people and a terrain.
/// Each is an editable solid, so push/pull, booleans and bevels work on it afterwards.
public enum RoomParts {
    public enum RoofKind: String, CaseIterable, Sendable, Codable {
        case gable, hip, shed, flat

        public var title: String {
            switch self {
            case .gable: "Gable roof"
            case .hip: "Hipped roof"
            case .shed: "Shed roof"
            case .flat: "Flat roof"
            }
        }

        public var systemImage: String {
            switch self {
            case .gable: "house"
            case .hip: "triangle"
            case .shed: "line.diagonal"
            case .flat: "rectangle"
            }
        }
    }

    /// A roof over an outline (the walls' tops, tapped round): `pitch` degrees, reaching `overhang` past the walls.
    /// Gable and hipped roofs cover the outline's smallest enclosing rectangle (an L-shaped house takes two roofs);
    /// shed and flat roofs follow any outline.
    public static func roof(_ kind: RoofKind, outline: [Vec3], pitch: Double = 30, overhang: Double = 0.3,
                            thickness: Double = 0.2) throws(Architecture.Failure) -> EditableMesh {
        guard outline.count >= 3 else { throw .tooShort }
        let base = outline.map(\.y).max() ?? 0
        let flat = outline.map { Vec2($0.x, $0.z) }
        guard abs(PolygonTriangulator.signedArea(flat)) > 1e-6 else { throw .tooShort }
        let slope = tan(min(max(pitch, 0), 75) * .pi / 180)
        switch kind {
        case .flat, .shed:
            let grown = grow(flat, by: overhang)
            let loop = grown.map { Vec3($0.x, base, $0.y) }
            var mesh = Prism.make(outline: Architecture.upward(loop), holes: [], normal: .unitY, from: 0, to: thickness)
            guard kind == .shed else { return mesh }
            // Up from the longest side, across the outline.
            let (a, b) = longestSide(grown)
            let inward = inwardNormal(of: (a, b), in: grown)
            let moves = Dictionary(uniqueKeysWithValues: mesh.vertices.enumerated().compactMap { index, vertex -> (Int, Vec3)? in
                guard vertex.y > base + thickness * 0.5 else { return nil }
                let across = (Vec2(vertex.x, vertex.z) - a).dot(inward)
                return (index, vertex + Vec3(0, max(across, 0) * slope, 0))
            })
            mesh = mesh.moving(moves)
            return mesh
        case .gable, .hip:
            let rectangle = smallestRectangle(flat)
            return pitched(kind, rectangle: rectangle, base: base, slope: slope, overhang: overhang)
        }
    }

    /// A gable or hip over a rectangle (its corners counter-clockwise from above, the first side along its length).
    static func pitched(_ kind: RoofKind, rectangle: [Vec2], base: Double, slope: Double, overhang: Double) -> EditableMesh {
        let centre = rectangle.reduce(Vec2.zero, +) * 0.25
        let along = (rectangle[1] - rectangle[0]).normalizedVector, across = (rectangle[3] - rectangle[0]).normalizedVector
        let length = rectangle[0].distance(to: rectangle[1]) + overhang * 2, width = rectangle[0].distance(to: rectangle[3]) + overhang * 2
        func corner(_ a: Double, _ b: Double) -> Vec2 { centre + along * (a * length / 2) + across * (b * width / 2) }
        let c = [corner(-1, -1), corner(1, -1), corner(1, 1), corner(-1, 1)].map { Vec3($0.x, base, $0.y) }
        let rise = slope * width / 2
        let inset = kind == .hip ? min(width / 2, length / 2) : 0
        let r0 = centre + along * (-length / 2 + inset), r1 = centre + along * (length / 2 - inset)
        let ridge = [Vec3(r0.x, base + rise, r0.y), Vec3(r1.x, base + rise, r1.y)]
        var builder = SolidBuilder(points: c + ridge)
        builder.face([0, 1, 2, 3])
        if r0.distance(to: r1) < 1e-9 {
            // A square hip: a pyramid.
            for index in 0 ..< 4 {
                builder.face([index, (index + 1) % 4, 4])
            }
        } else {
            builder.face([0, 1, 5, 4])
            builder.face([2, 3, 4, 5])
            builder.face([1, 2, 5])
            builder.face([3, 0, 4])
        }
        return builder.convexMesh()
    }

    /// A column standing on `point`: round (24 sides) or square, `size` across.
    public static func column(at point: Vec3, height: Double = Architecture.wallHeight, size: Double = 0.3, round: Bool = true) -> EditableMesh {
        if round { return EditableMesh.cylinder(base: point, radius: size / 2, height: height, segments: 24) }
        return EditableMesh.box(min: point - Vec3(size / 2, 0, size / 2), max: point + Vec3(size / 2, height, size / 2))
    }

    /// A beam from `a` to `b`, its top at their height, `width` wide and `depth` deep.
    public static func beam(from a: Vec3, to b: Vec3, width: Double = 0.2, depth: Double = 0.3) throws(Architecture.Failure) -> EditableMesh {
        let run = Vec3(b.x - a.x, 0, b.z - a.z)
        guard run.length > 1e-6 else { throw .tooShort }
        let direction = run.normalized
        let side = direction.cross(.unitY).normalized
        let top = Vec3(a.x, max(a.y, b.y), a.z)
        var section = [top - side * (width / 2), top + side * (width / 2), top + side * (width / 2) - Vec3(0, depth, 0),
                       top - side * (width / 2) - Vec3(0, depth, 0)]
        if EditableMesh.newellVector(section).dot(direction) < 0 { section.reverse() }
        return Prism.make(outline: section, holes: [], normal: direction, from: 0, to: run.length)
    }

    /// A railing along a path: posts at the corners and at most `spacing` apart, a handrail on top and a rail halfway.
    public static func railing(along path: [Vec3], height: Double = 1.0, spacing: Double = 1.2) throws(Architecture.Failure) -> EditableMesh {
        guard path.count >= 2, zip(path, path.dropFirst()).contains(where: { $0.distance(to: $1) > 1e-6 }) else { throw .tooShort }
        var builder = MultiBox()
        let post = 0.05, rail = 0.06
        var posts: [Vec3] = [path[0]]
        for (a, b) in zip(path, path.dropFirst()) {
            let steps = max(Int((a.distance(to: b) / spacing).rounded(.up)), 1)
            for step in 1 ... steps {
                posts.append(a.lerp(to: b, Double(step) / Double(steps)))
            }
        }
        for point in posts {
            builder.box(from: point, to: point + Vec3(0, height - rail, 0), width: post, depth: post)
        }
        for (a, b) in zip(path, path.dropFirst()) where a.distance(to: b) > 1e-6 {
            builder.box(from: a + Vec3(0, height - rail, 0), to: b + Vec3(0, height - rail, 0), width: rail, depth: rail, along: true)
            builder.box(from: a + Vec3(0, height / 2, 0), to: b + Vec3(0, height / 2, 0), width: 0.03, depth: 0.03, along: true)
        }
        return builder.mesh
    }

    /// A flat figure 1.75 m tall standing at `point` (architects' scale people: a cut-out, not a character), facing +z.
    public static func person(at point: Vec3, height: Double = 1.75) -> EditableMesh {
        let half: [Vec2] = [
            Vec2(0, 1.75), Vec2(0.075, 1.72), Vec2(0.1, 1.64), Vec2(0.085, 1.56), Vec2(0.065, 1.5), Vec2(0.2, 1.45), Vec2(0.245, 1.32),
            Vec2(0.26, 0.92), Vec2(0.215, 0.84), Vec2(0.18, 0.86), Vec2(0.17, 0.45), Vec2(0.155, 0.06), Vec2(0.2, 0), Vec2(0.04, 0),
            Vec2(0.035, 0.8), Vec2(0, 0.86)
        ]
        let scale = height / 1.75
        let outline = (half + half.dropFirst().dropLast().reversed().map { Vec2(-$0.x, $0.y) }).map { point + Vec3($0.x * scale, $0.y * scale, 0) }
        let loop = EditableMesh.newellVector(outline).z < 0 ? outline.reversed() : outline
        return Prism.make(outline: loop, holes: [], normal: .unitZ, from: -0.015, to: 0.015)
    }

    /// Ground for a site, `width` × `depth` metres, closed underneath (half a metre thick), with gentle hills `hills`
    /// metres high laid out by `seed`; the touch-up brushes shape it further.
    public static func terrain(width: Double = 20, depth: Double = 20, hills: Double = 1, seed: UInt64 = 1) -> EditableMesh {
        let cell = max(max(width, depth) / 40, 0.25)
        let columns = max(Int((width / cell).rounded()), 2), rows = max(Int((depth / cell).rounded()), 2)
        var random = SeededGenerator(seed: seed)
        let bumps = (0 ..< 5).map { _ in
            (Vec2(Double.random(in: -0.4 ... 0.4, using: &random) * width, Double.random(in: -0.4 ... 0.4, using: &random) * depth),
             Double.random(in: 0.15 ... 0.35, using: &random) * max(width, depth), Double.random(in: 0.4 ... 1.0, using: &random))
        }
        func height(_ x: Double, _ z: Double) -> Double {
            // Hills fade to nothing at the edges, so the site meets whatever is around it.
            let edge = min(1, min(width / 2 - abs(x), depth / 2 - abs(z)) / (cell * 3))
            let lift = bumps.reduce(0.0) { sum, bump in
                let d = Vec2(x, z) - bump.0
                return sum + bump.2 * exp(-(d.x * d.x + d.y * d.y) / (2 * bump.1 * bump.1))
            }
            return hills * lift * max(edge, 0)
        }
        var builder = SolidBuilder(points: [])
        var top: [[Int]] = []
        for column in 0 ... columns {
            var line: [Int] = []
            for row in 0 ... rows {
                let x = -width / 2 + width * Double(column) / Double(columns), z = -depth / 2 + depth * Double(row) / Double(rows)
                line.append(builder.add(Vec3(x, height(x, z), z)))
            }
            top.append(line)
        }
        for column in 0 ..< columns {
            for row in 0 ..< rows {
                builder.face([top[column][row], top[column][row + 1], top[column + 1][row + 1]], facing: .unitY)
                builder.face([top[column][row], top[column + 1][row + 1], top[column + 1][row]], facing: .unitY)
            }
        }
        let floor = -0.5
        let corners = [Vec3(-width / 2, floor, -depth / 2), Vec3(width / 2, floor, -depth / 2), Vec3(width / 2, floor, depth / 2),
                       Vec3(-width / 2, floor, depth / 2)].map { builder.add($0) }
        builder.face(corners, facing: Vec3(0, -1, 0))
        builder.face([corners[0], corners[1]] + (0 ... columns).reversed().map { top[$0][0] }, facing: Vec3(0, 0, -1))
        builder.face([corners[2], corners[3]] + (0 ... columns).map { top[$0][rows] }, facing: .unitZ)
        builder.face([corners[1], corners[2]] + (0 ... rows).reversed().map { top[columns][$0] }, facing: .unitX)
        builder.face([corners[3], corners[0]] + (0 ... rows).map { top[0][$0] }, facing: Vec3(-1, 0, 0))
        return builder.mesh
    }

    // MARK: Helpers

    /// A polygon grown outward by `distance` (mitred).
    static func grow(_ polygon: [Vec2], by distance: Double) -> [Vec2] {
        guard distance > 0 else { return polygon }
        let a = Architecture.offset(polygon, by: distance, closed: true), b = Architecture.offset(polygon, by: -distance, closed: true)
        return abs(PolygonTriangulator.signedArea(a)) > abs(PolygonTriangulator.signedArea(b)) ? a : b
    }

    static func longestSide(_ polygon: [Vec2]) -> (Vec2, Vec2) {
        let index = polygon.indices.max { polygon[$0].distance(to: polygon[($0 + 1) % polygon.count])
            < polygon[$1].distance(to: polygon[($1 + 1) % polygon.count])
        } ?? 0
        return (polygon[index], polygon[(index + 1) % polygon.count])
    }

    static func inwardNormal(of side: (Vec2, Vec2), in polygon: [Vec2]) -> Vec2 {
        let d = (side.1 - side.0).normalizedVector
        let left = Vec2(-d.y, d.x)
        let centre = polygon.reduce(Vec2.zero, +) * (1 / Double(polygon.count))
        return (centre - side.0).dot(left) >= 0 ? left : left * -1
    }

    /// The smallest rectangle around a polygon (one side along a side of its hull), corners counter-clockwise, the
    /// first side the longer.
    static func smallestRectangle(_ polygon: [Vec2]) -> [Vec2] {
        let hull = convexHull(polygon)
        var best: (area: Double, corners: [Vec2])?
        for index in hull.indices {
            let a = hull[index], b = hull[(index + 1) % hull.count]
            let u = (b - a).normalizedVector
            guard u.length > 0.5 else { continue }
            let v = Vec2(-u.y, u.x)
            let us = hull.map { $0.dot(u) }, vs = hull.map { $0.dot(v) }
            guard let uLo = us.min(), let uHi = us.max(), let vLo = vs.min(), let vHi = vs.max() else { continue }
            let area = (uHi - uLo) * (vHi - vLo)
            guard best == nil || area < (best?.area ?? .infinity) - 1e-9 else { continue }
            var corners = [u * uLo + v * vLo, u * uHi + v * vLo, u * uHi + v * vHi, u * uLo + v * vHi]
            if uHi - uLo < vHi - vLo { corners = [corners[1], corners[2], corners[3], corners[0]] }
            best = (area, corners)
        }
        return best?.corners ?? polygon
    }

    /// The convex hull, counter-clockwise (Andrew's monotone chain).
    static func convexHull(_ points: [Vec2]) -> [Vec2] {
        let sorted = points.sorted { ($0.x, $0.y) < ($1.x, $1.y) }
        guard sorted.count > 2 else { return sorted }
        func half(_ list: [Vec2]) -> [Vec2] {
            var chain: [Vec2] = []
            for point in list {
                while chain.count >= 2, (chain[chain.count - 1] - chain[chain.count - 2]).cross(point - chain[chain.count - 2]) <= 0 {
                    chain.removeLast()
                }
                chain.append(point)
            }
            return chain
        }
        let lower = half(sorted), upper = half(sorted.reversed())
        return Array(lower.dropLast() + upper.dropLast())
    }
}

/// Faces put together corner by corner, each turned to face outward.
struct SolidBuilder {
    var points: [Vec3]
    var faces: [EditableMesh.Face] = []

    init(points: [Vec3]) {
        self.points = points
    }

    mutating func add(_ point: Vec3) -> Int {
        points.append(point)
        return points.count - 1
    }

    /// A face facing the way it's given (or `facing`, when it says).
    mutating func face(_ loop: [Int], facing: Vec3? = nil) {
        var corners = loop
        if let facing, EditableMesh.newellVector(corners.map { points[$0] }).dot(facing) < 0 { corners.reverse() }
        faces.append(EditableMesh.Face(corners))
    }

    var mesh: EditableMesh { EditableMesh(vertices: points, faces: faces) }

    /// For a convex solid: every face turned away from the middle.
    func convexMesh() -> EditableMesh {
        let centre = points.reduce(Vec3.zero, +) / Double(max(points.count, 1))
        let turned = faces.map { face -> EditableMesh.Face in
            let corners = face.outline.map { points[$0] }
            let middle = corners.reduce(Vec3.zero, +) / Double(corners.count)
            return EditableMesh.newellVector(corners).dot(middle - centre) < 0 ? EditableMesh.Face(Array(face.outline.reversed())) : face
        }
        return EditableMesh(vertices: points, faces: turned)
    }
}

/// Boxes along lines (posts and rails), each its own closed piece in one mesh.
struct MultiBox {
    var builder = SolidBuilder(points: [])

    var mesh: EditableMesh { builder.mesh }

    /// A box from `a` to `b`: upright (a post) or lying along the line (`along`), `width` × `depth` across.
    mutating func box(from a: Vec3, to b: Vec3, width: Double, depth: Double, along: Bool = false) {
        let axis = (b - a).normalized
        let side: Vec3, up: Vec3
        if along {
            side = axis.cross(.unitY).normalized
            up = Vec3.unitY
        } else {
            side = Vec3.unitX
            up = Vec3.unitZ
        }
        var corners: [Vec3] = []
        for (s, t) in [(-1.0, 0.0), (1.0, 0.0), (1.0, 1.0), (-1.0, 1.0)] {
            let height: Double = along ? t * depth : (t - 0.5) * depth
            corners.append(side * (s * width / 2) + up * height)
        }
        var start: [Int] = [], end: [Int] = []
        for corner in corners {
            start.append(builder.add(a + corner))
            end.append(builder.add(b + corner))
        }
        let centre = (a + b) * 0.5 + up * (along ? depth / 2 : 0)
        var loops = [start, end]
        for index in 0 ..< 4 {
            loops.append([start[index], start[(index + 1) % 4], end[(index + 1) % 4], end[index]])
        }
        for loop in loops {
            let middle = loop.map { builder.points[$0] }.reduce(Vec3.zero, +) / Double(loop.count)
            builder.face(loop, facing: middle - centre)
        }
    }
}
