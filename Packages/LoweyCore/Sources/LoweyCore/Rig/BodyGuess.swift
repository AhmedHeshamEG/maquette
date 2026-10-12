import Foundation

/// Where a body's joints are, guessed from its shape alone (rig space, standing on its lowest point, y up, facing +z):
/// a person's dots, a four-legged animal's, a winged creature's. Each guess is the first place for the dots; the person
/// drags the wrong ones. A guess that can't find the body says so (nil), and the dots stand in a standard layout
/// instead (`layout`).
public enum BodyGuess {
    public enum Body: String, CaseIterable, Sendable {
        case person, fourLegs, wings
    }

    /// The shape cut into horizontal bands, its legs found as the separate columns at the bottom.
    struct Shape {
        /// Lowest first, so a band is a slice.
        let vertices: [Vec3]
        let bounds: Bounds
        var height: Double { max(bounds.size.y, 1e-6) }
        var ground: Double { bounds.min.y }

        init(vertices: [Vec3], bounds: Bounds) {
            self.vertices = vertices.sorted { $0.y < $1.y }
            self.bounds = bounds
        }

        /// Vertices whose height is in [low, high) as a fraction of the height.
        func band(_ low: Double, _ high: Double) -> [Vec3] {
            Array(vertices[first(above: ground + low * height) ..< first(above: ground + high * height)])
        }

        /// The index of the first vertex at or above `y`.
        func first(above y: Double) -> Int {
            var low = 0, high = vertices.count
            while low < high {
                let middle = (low + high) / 2
                if vertices[middle].y < y { low = middle + 1 } else { high = middle }
            }
            return low
        }

        /// The separate pieces of a band seen from above (each at least `share` of the band), biggest first. The grid
        /// is cut to the band's own size, so legs standing close together still read as two.
        func pieces(_ points: [Vec3], share: Double = 0.03) -> [[Vec3]] {
            guard let extent = Bounds(points: points)?.size else { return [] }
            // Never finer than the points are spaced, or one piece falls apart into many.
            let cell = max(max(extent.x, extent.z) / 28, max(bounds.size.x, bounds.size.y, bounds.size.z) / Double(BodyGuess.sampling) * 1.6)
            return BodyGuess.pieces(points, cell: max(cell, 1e-6)).filter { Double($0.count) >= Double(points.count) * share }
        }
    }

    /// The points a guess looks at: the mesh's corners, cut finer first so a low-poly leg has points all the way up.
    public static func points(of mesh: MeshData) -> [Vec3] {
        MeshDensify.densified(mesh, cuts: sampling).positions.map { Vec3(Double($0.x), Double($0.y), Double($0.z)) }
    }

    /// How finely a guess samples a shape: points at least this many across its largest side.
    static let sampling = 96

    // MARK: Pieces

    /// Points grouped by touching cells of a grid on the ground plane (eight neighbours), biggest group first.
    static func pieces(_ points: [Vec3], cell: Double) -> [[Vec3]] {
        var cells: [SIMD2<Int>: [Int]] = [:]
        for (index, point) in points.enumerated() {
            cells[SIMD2(Int((point.x / cell).rounded(.down)), Int((point.z / cell).rounded(.down))), default: []].append(index)
        }
        var seen = Set<SIMD2<Int>>()
        var groups: [[Vec3]] = []
        for start in cells.keys where !seen.contains(start) {
            var stack = [start]
            seen.insert(start)
            var group: [Vec3] = []
            while let key = stack.popLast() {
                group += (cells[key] ?? []).map { points[$0] }
                for dx in -1 ... 1 {
                    for dz in -1 ... 1 {
                        let next = key &+ SIMD2(dx, dz)
                        if cells[next] != nil, !seen.contains(next) {
                            seen.insert(next)
                            stack.append(next)
                        }
                    }
                }
            }
            groups.append(group)
        }
        return groups.sorted { $0.count > $1.count }
    }

    static func centre(_ points: [Vec3]) -> Vec3 {
        points.isEmpty ? .zero : points.reduce(Vec3.zero, +) / Double(points.count)
    }

    /// Legs as columns from the ground up: their middles at each height they stay apart, until two of them meet (the
    /// belly or the crotch). `count` legs are looked for in the lowest band.
    static func legs(_ shape: Shape, count: Int) -> (columns: [[Vec3]], top: Double)? {
        let feet = shape.pieces(shape.band(0, 0.06), share: 0.02)
        guard feet.count >= count else { return nil }
        var columns = feet.prefix(count).map { [centre($0)] }
        var top = 0.06
        let step = 0.03
        var low = 0.03
        while low < 0.75 {
            let groups = shape.pieces(shape.band(low, low + step), share: 0.02)
            // One piece spanning two legs: they've met.
            let met = groups.contains { group in
                guard let box = Bounds(points: group) else { return false }
                return columns.count { box.contains(Vec3($0[$0.count - 1].x, box.center.y, $0[$0.count - 1].z)) } >= 2
            }
            guard !met else { break }
            let pieces = groups.map(centre)
            // A leg moves little from one band to the next; a hand hanging beside it is farther off.
            let reach = shape.height * 0.08
            let matched = columns.map { column in
                pieces.indices.min { pieces[$0].groundDistance(to: column[column.count - 1]) < pieces[$1].groundDistance(to: column[column.count - 1]) }
                    .flatMap { pieces[$0].groundDistance(to: column[column.count - 1]) < reach ? $0 : nil }
            }
            guard matched.allSatisfy({ $0 != nil }), Set(matched.compactMap(\.self)).count == count else { break }
            for (index, piece) in matched.enumerated() {
                if let piece { columns[index].append(pieces[piece]) }
            }
            top = low + step
            low += step
        }
        return top > 0.1 ? (columns, top) : nil
    }

    /// A leg's middle at a fraction of the way up its column.
    static func along(_ column: [Vec3], _ fraction: Double) -> Vec3 {
        column[min(max(Int((Double(column.count - 1) * fraction).rounded()), 0), column.count - 1)]
    }

    // MARK: A person

    /// A person's dots on the plane through the middle (z), or nil when two legs and two arms can't be told apart.
    public static func person(_ vertices: [Vec3], bounds: Bounds) -> [HumanRig.Dot: Vec3]? {
        let shape = Shape(vertices: vertices, bounds: bounds)
        guard let (columns, crotch) = legs(shape, count: 2) else { return nil }
        let height = shape.height, ground = shape.ground, centreX = bounds.center.x
        let neck = neckHeight(shape, from: crotch)
        let waist = torso(shape, from: crotch, to: neck).halfWidth
        let shoulderY = ground + (neck - 0.05) * height
        var dots: [HumanRig.Dot: Vec3] = [.head: Vec3(centreX, bounds.max.y, 0), .chin: Vec3(centreX, ground + (neck + 0.03) * height, 0)]
        let sides = columns.sorted { $0[0].x > $1[0].x }
        for (index, side) in ["left", "right"].enumerated() {
            let sign = index == 0 ? 1.0 : -1.0
            let column = sides[index]
            let shoulder = Vec3(centreX + sign * waist * 0.95, shoulderY, 0)
            guard let arm = arm(shape, shoulder: shoulder, sign: sign, outside: waist * 1.25, to: neck) else { return nil }
            func set(_ name: String, _ point: Vec3) {
                if let dot = HumanRig.Dot(rawValue: side + name) { dots[dot] = Vec3(point.x, point.y, 0) }
            }
            set("Shoulder", shoulder)
            set("Elbow", arm.elbow)
            set("Wrist", arm.wrist)
            // The leg's lower half places it across: higher up, a hand hanging beside the thigh can join its piece.
            let legX = column.prefix(max(column.count / 2, 1)).map(\.x).sorted()[max(column.count / 2, 1) / 2]
            // Where the legs part is below the hip joint: well below on a grown-up's long legs (thighs touch), hardly
            // at all on a short-legged toy figure.
            let hip = crotch + 0.15 * min(max((crotch - 0.25) / 0.1, 0), 1), ankle = 0.05
            set("Hip", Vec3(legX, ground + hip * height, 0))
            set("Knee", Vec3(legX, ground + (hip + ankle) / 2 * height, 0))
            set("Ankle", Vec3(column[0].x, ground + ankle * height, 0))
        }
        return dots.mapValues { Vec3($0.x, $0.y, bounds.center.z) }
    }

    /// The neck (a fraction of the height): coming down from the top, the middle widens over the head, narrows, and
    /// widens again into the shoulders; the neck is the narrowest place before that. 0.86 when there's none to see.
    static func neckHeight(_ shape: Shape, from crotch: Double) -> Double {
        var head = 0.0
        var narrowest: (height: Double, width: Double)?
        for low in stride(from: 0.96, to: crotch + 0.1, by: -0.02) {
            guard let middle = middlePiece(shape, low, low + 0.02) else { continue }
            let width = spread(middle)
            if let neck = narrowest {
                if width < neck.width {
                    narrowest = (low, width)
                } else if width > neck.width * 1.25 {
                    return neck.height
                }
            } else if width > head {
                head = width
            } else if width < head * 0.85 {
                narrowest = (low, width)
            }
        }
        return 0.86
    }

    /// The waist: half the narrowest width of the body between the legs and the neck (a little more, for the
    /// chest), and its height.
    static func torso(_ shape: Shape, from crotch: Double, to neck: Double) -> (halfWidth: Double, height: Double) {
        var narrowest = (width: Double.infinity, height: (crotch + neck) / 2)
        for low in stride(from: crotch + 0.04, to: neck - 0.04, by: 0.03) {
            if let middle = middlePiece(shape, low, low + 0.03), spread(middle) < narrowest.width { narrowest = (spread(middle), low + 0.015) }
        }
        return (narrowest.width.isFinite ? narrowest.width / 2 * 1.15 : shape.bounds.size.x * 0.15, narrowest.height)
    }

    /// The piece of a band nearest the middle.
    static func middlePiece(_ shape: Shape, _ low: Double, _ high: Double) -> [Vec3]? {
        shape.pieces(shape.band(low, high), share: 0.05).min { abs(centre($0).x - shape.bounds.center.x) < abs(centre($1).x - shape.bounds.center.x) }
    }

    static func spread(_ points: [Vec3]) -> Double {
        (points.map(\.x).max() ?? 0) - (points.map(\.x).min() ?? 0)
    }

    /// An arm on one side. Its hand is among the points farthest out sideways (an arm reaches out further than a
    /// thigh does): of those, the one farthest from the shoulder. The wrist sits a little back from it, the elbow
    /// halfway, on the arm.
    static func arm(_ shape: Shape, shoulder: Vec3, sign: Double, outside: Double, to neck: Double) -> (elbow: Vec3, wrist: Vec3)? {
        let centreX = shape.bounds.center.x
        let candidates = shape.band(0.1, neck).filter { ($0.x - centreX) * sign > outside }
        let farthest = candidates.map { ($0.x - centreX) * sign }.max() ?? 0
        let lateral = candidates.filter { ($0.x - centreX) * sign > outside + (farthest - outside) * 0.8 }
        guard let hand = lateral.max(by: { $0.distance(to: shoulder) < $1.distance(to: shoulder) }) else { return nil }
        let flat = Vec3(hand.x, hand.y, shoulder.z)
        let reach = flat.distance(to: shoulder)
        guard reach > shape.height * 0.15 else { return nil }
        let wrist = flat + (shoulder - flat).normalized * min(shape.height * 0.06, reach * 0.3)
        let middle = shoulder.lerp(to: wrist, 0.5)
        let near = candidates.filter { Vec3($0.x, $0.y, shoulder.z).distance(to: middle) < shape.height * 0.08 }
        let elbow = near.count >= 3 ? Vec3(centre(near).x, centre(near).y, shoulder.z) : middle
        return (elbow, wrist)
    }
}

extension Vec3 {
    /// Distance seen from above (x and z).
    func groundDistance(to other: Vec3) -> Double {
        ((x - other.x) * (x - other.x) + (z - other.z) * (z - other.z)).squareRoot()
    }
}
