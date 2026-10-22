import Foundation

/// How a drawing looks at the world: straight along a direction (plans, elevations, a technical sheet's views; sizes
/// stay true) or through a camera (a frame's ink as vectors).
public enum DrawingView: Hashable, Sendable {
    /// Looking along `direction` with `up` on the paper's up. Drawing units are metres.
    case orthographic(direction: Vec3, up: Vec3)
    /// Through a camera at `eye` looking along `forward`; drawing units are pixels of a `width` × `height` frame.
    case perspective(eye: Vec3, forward: Vec3, up: Vec3, fieldOfView: Double, width: Double, height: Double)

    /// The plan: from above, north (−z) up the paper.
    public static let top = DrawingView.orthographic(direction: Vec3(0, -1, 0), up: Vec3(0, 0, -1))
    /// From the front (+z) looking back.
    public static let front = DrawingView.orthographic(direction: Vec3(0, 0, -1), up: .unitY)
    public static let back = DrawingView.orthographic(direction: Vec3(0, 0, 1), up: .unitY)
    /// From the right (+x) looking left.
    public static let right = DrawingView.orthographic(direction: Vec3(-1, 0, 0), up: .unitY)
    public static let left = DrawingView.orthographic(direction: Vec3(1, 0, 0), up: .unitY)
    /// The classic isometric: from front-right and above.
    public static let isometric = DrawingView.orthographic(direction: Vec3(-1, -0.8165, -1).normalized, up: .unitY)

    struct Frame {
        var right: Vec3
        var up: Vec3
        var forward: Vec3
    }

    var frame: Frame {
        switch self {
        case let .orthographic(direction, up), let .perspective(_, direction, up, _, _, _):
            let forward = direction.normalized
            var right = forward.cross(up)
            if right.length < 1e-9 { right = forward.cross(abs(forward.y) < 0.9 ? Vec3.unitY : Vec3.unitZ) }
            right = right.normalized
            return Frame(right: right, up: right.cross(forward).normalized, forward: forward)
        }
    }

    static let near = 0.01

    /// A point on the drawing and how near it is (larger is nearer; for a camera, one over the distance, which is
    /// straight across the frame). Nil behind the camera.
    func project(_ point: Vec3, frame: Frame) -> (point: Vec2, nearness: Double)? {
        switch self {
        case .orthographic:
            return (Vec2(point.dot(frame.right), point.dot(frame.up)), -point.dot(frame.forward))
        case let .perspective(eye, _, _, fieldOfView, width, height):
            let q = point - eye
            let depth = q.dot(frame.forward)
            guard depth >= Self.near * 0.999 else { return nil }
            let half = tan(fieldOfView * .pi / 360)
            let aspect = width / max(height, 1)
            let x = q.dot(frame.right) / (depth * half * aspect), y = q.dot(frame.up) / (depth * half)
            return (Vec2((x * 0.5 + 0.5) * width, (y * 0.5 + 0.5) * height), 1 / depth)
        }
    }

    /// How far in front of the viewer a point is (for clipping at the camera).
    func depth(_ point: Vec3, frame: Frame) -> Double {
        switch self {
        case .orthographic: .infinity
        case let .perspective(eye, _, _, _, _, _): (point - eye).dot(frame.forward)
        }
    }

    /// Whether a triangle with this normal at this point faces the viewer.
    func faces(_ normal: Vec3, at point: Vec3, frame: Frame) -> Bool {
        switch self {
        case .orthographic: normal.dot(frame.forward) < 0
        case let .perspective(eye, _, _, _, _, _): normal.dot(point - eye) < 0
        }
    }
}

/// The lines a draughtsman would draw of a shape (G1): outlines where a surface turns away, creases sharper than
/// `crease`, open edges, each split into what is seen and what is hidden behind a surface, found against a depth
/// picture of every triangle.
public enum HiddenLines {
    public struct Options: Sendable {
        /// Edges where the surface bends more than this (degrees) are drawn.
        public var crease: Double
        /// The depth picture's long side in pixels.
        public var resolution: Int
        /// Draw hidden lines (dashed) too.
        public var hidden: Bool
        /// Pens for outlines and creases.
        public var outline: LineArt.Pen
        public var creasePen: LineArt.Pen

        public init(crease: Double = 30, resolution: Int = 1400, hidden: Bool = false, outline: LineArt.Pen = .outline,
                    creasePen: LineArt.Pen = .thin) {
            self.crease = crease
            self.resolution = resolution
            self.hidden = hidden
            self.outline = outline
            self.creasePen = creasePen
        }
    }

    public static func draw(_ soup: TriangleSoup, view: DrawingView, options: Options = Options()) -> LineArt {
        guard !soup.isEmpty else { return LineArt() }
        let frame = view.frame
        let normals = soup.triangles.indices.map { soup.normal($0) }
        let facing = soup.triangles.indices.map { index in
            let (a, b, c) = soup.corners(index)
            return view.faces(normals[index], at: (a + b + c) / 3, frame: frame)
        }
        guard var raster = DepthRaster(soup, view: view, frame: frame, resolution: options.resolution) else { return LineArt() }
        raster.fill(soup, view: view, frame: frame)
        let threshold = cos(options.crease * .pi / 180)
        var art = LineArt()
        for (edge, owners) in soup.edges() {
            let pen: LineArt.Pen
            if owners.count != 2 {
                pen = options.outline
            } else if facing[owners[0]] != facing[owners[1]] {
                pen = options.outline
            } else if normals[owners[0]].dot(normals[owners[1]]) < threshold {
                guard facing[owners[0]] || options.hidden else { continue }
                pen = options.creasePen
            } else {
                continue
            }
            let (seen, hidden) = raster.split(soup.positions[edge.a], soup.positions[edge.b], view: view, frame: frame)
            art.strokes += seen.map { LineArt.Stroke([$0.0, $0.1], pen: pen) }
            if options.hidden { art.strokes += hidden.map { LineArt.Stroke([$0.0, $0.1], pen: .hidden) } }
        }
        art.strokes = Self.joined(art.strokes)
        return art
    }

    /// Lines that continue each other (same pen, end meets start, same direction) joined into one.
    static func joined(_ strokes: [LineArt.Stroke]) -> [LineArt.Stroke] {
        var sorted = strokes.sorted { lhs, rhs in
            (lhs.pen.rawValue, lhs.points[0].x, lhs.points[0].y) < (rhs.pen.rawValue, rhs.points[0].x, rhs.points[0].y)
        }
        guard !sorted.isEmpty else { return [] }
        var result: [LineArt.Stroke] = []
        var current = sorted.removeFirst()
        for stroke in sorted {
            if let last = current.points.last, stroke.pen == current.pen, current.points.count == 2, stroke.points.count == 2,
               last.distance(to: stroke.points[0]) < 1e-6,
               abs((last - current.points[0]).normalizedVector.cross((stroke.points[1] - stroke.points[0]).normalizedVector)) < 1e-6,
               (last - current.points[0]).dot(stroke.points[1] - stroke.points[0]) > 0 {
                current.points[1] = stroke.points[1]
            } else {
                result.append(current)
                current = stroke
            }
        }
        result.append(current)
        return result
    }
}

/// The nearest surface at every pixel of a drawing.
struct DepthRaster {
    let width: Int
    let height: Int
    let origin: Vec2
    /// Drawing units a pixel.
    let cell: Double
    var nearness: [Float]
    /// How much nearer than a surface an edge may be and still count as on it.
    let slack: Double

    init?(_ soup: TriangleSoup, view: DrawingView, frame: DrawingView.Frame, resolution: Int) {
        var lo = Vec2(.infinity, .infinity), hi = Vec2(-.infinity, -.infinity)
        var nearLo = Double.infinity, nearHi = -Double.infinity
        switch view {
        case .orthographic:
            for position in soup.positions {
                guard let projected = view.project(position, frame: frame) else { continue }
                lo = Vec2(min(lo.x, projected.point.x), min(lo.y, projected.point.y))
                hi = Vec2(max(hi.x, projected.point.x), max(hi.y, projected.point.y))
                nearLo = min(nearLo, projected.nearness)
                nearHi = max(nearHi, projected.nearness)
            }
        case let .perspective(_, _, _, _, width, height):
            lo = .zero
            hi = Vec2(width, height)
            nearLo = 0
            nearHi = 1 / DrawingView.near
        }
        guard lo.x.isFinite, hi.x > lo.x || hi.y > lo.y else { return nil }
        let span = max(hi.x - lo.x, hi.y - lo.y, 1e-9)
        let margin = span * 0.01
        origin = lo - Vec2(margin, margin)
        cell = (span + margin * 2) / Double(max(resolution, 16))
        width = Int(((hi.x - lo.x) + margin * 2) / cell) + 2
        height = Int(((hi.y - lo.y) + margin * 2) / cell) + 2
        nearness = [Float](repeating: -.infinity, count: width * height)
        switch view {
        case .orthographic: slack = max(nearHi - nearLo, span) * 2e-3
        case .perspective: slack = 0
        }
    }

    func pixel(_ point: Vec2) -> (Double, Double) {
        ((point.x - origin.x) / cell, (point.y - origin.y) / cell)
    }

    mutating func fill(_ soup: TriangleSoup, view: DrawingView, frame: DrawingView.Frame) {
        for index in soup.triangles.indices {
            let (a, b, c) = soup.corners(index)
            var polygon = [a, b, c]
            if case .perspective = view {
                polygon = TriangleSoup.clip(polygon) { view.depth($0, frame: frame) - DrawingView.near }
            }
            let projected = polygon.compactMap { view.project($0, frame: frame) }
            guard projected.count >= 3 else { continue }
            for corner in 1 ..< projected.count - 1 {
                draw(projected[0], projected[corner], projected[corner + 1])
            }
        }
    }

    private mutating func draw(_ a: (point: Vec2, nearness: Double), _ b: (point: Vec2, nearness: Double), _ c: (point: Vec2, nearness: Double)) {
        let pa = pixel(a.point), pb = pixel(b.point), pc = pixel(c.point)
        let area = (pb.0 - pa.0) * (pc.1 - pa.1) - (pb.1 - pa.1) * (pc.0 - pa.0)
        guard abs(area) > 1e-12 else { return }
        let minX = max(Int(min(pa.0, pb.0, pc.0).rounded(.down)), 0), maxX = min(Int(max(pa.0, pb.0, pc.0).rounded(.up)), width - 1)
        let minY = max(Int(min(pa.1, pb.1, pc.1).rounded(.down)), 0), maxY = min(Int(max(pa.1, pb.1, pc.1).rounded(.up)), height - 1)
        guard minX <= maxX, minY <= maxY else { return }
        for y in minY ... maxY {
            let py = Double(y) + 0.5
            for x in minX ... maxX {
                let px = Double(x) + 0.5
                let w0 = ((pb.0 - px) * (pc.1 - py) - (pb.1 - py) * (pc.0 - px)) / area
                let w1 = ((pc.0 - px) * (pa.1 - py) - (pc.1 - py) * (pa.0 - px)) / area
                let w2 = 1 - w0 - w1
                guard w0 >= -1e-9, w1 >= -1e-9, w2 >= -1e-9 else { continue }
                let near = Float(w0 * a.nearness + w1 * b.nearness + w2 * c.nearness)
                let at = y * width + x
                if near > nearness[at] { nearness[at] = near }
            }
        }
    }

    /// Whether a point of an edge this near is in front of (or on) the surface at its pixel. The surface's own slope
    /// around the pixel is allowed for, so an edge isn't hidden by the face it bounds.
    func shows(_ near: Double, x: Int, y: Int, tolerance: Double) -> Bool {
        guard x >= 0, y >= 0, x < width, y < height else { return true }
        let own = nearness[y * width + x]
        guard own > -.infinity else { return true }
        var slope: Float = 0
        for (dx, dy) in [(-1, 0), (1, 0), (0, -1), (0, 1)] {
            let px = x + dx, py = y + dy
            guard px >= 0, py >= 0, px < width, py < height else { continue }
            let other = nearness[py * width + px]
            if other > -.infinity { slope = max(slope, abs(other - own)) }
        }
        return near + tolerance + Double(slope) >= Double(own)
    }

    /// An edge split into its seen and hidden stretches, on the drawing.
    func split(_ a: Vec3, _ b: Vec3, view: DrawingView, frame: DrawingView.Frame) -> (seen: [(Vec2, Vec2)], hidden: [(Vec2, Vec2)]) {
        var p = a, q = b
        if case .perspective = view {
            let da = view.depth(a, frame: frame) - DrawingView.near, db = view.depth(b, frame: frame) - DrawingView.near
            if da < 0, db < 0 { return ([], []) }
            if da < 0 { p = a.lerp(to: b, da / (da - db)) }
            if db < 0 { q = b.lerp(to: a, db / (db - da)) }
        }
        guard let pp = view.project(p, frame: frame), let pq = view.project(q, frame: frame) else { return ([], []) }
        let length = pp.point.distance(to: pq.point) / cell
        let steps = max(Int(length.rounded(.up)), 1)
        var seen: [(Vec2, Vec2)] = [], hidden: [(Vec2, Vec2)] = []
        var runStart: Vec2?, runSeen = true
        var previous = pp.point
        for step in 0 ... steps {
            let t = Double(step) / Double(steps)
            // Straight on the drawing; for a camera one over the distance is straight across the frame too.
            let point = pp.point.lerp(pq.point, t)
            let near = pp.nearness + (pq.nearness - pp.nearness) * t
            let (fx, fy) = pixel(point)
            let isSeen = shows(near, x: Int(fx), y: Int(fy), tolerance: slack > 0 ? slack : near * 0.004)
            if runStart == nil {
                runStart = point
                runSeen = isSeen
            } else if isSeen != runSeen {
                let stretch = (runStart ?? point, previous)
                if stretch.0.distance(to: stretch.1) > 1e-12 {
                    if runSeen { seen.append(stretch) } else { hidden.append(stretch) }
                }
                runStart = previous
                runSeen = isSeen
            }
            previous = point
        }
        if let start = runStart, start.distance(to: previous) > 1e-12 {
            if runSeen { seen.append((start, previous)) } else { hidden.append((start, previous)) }
        }
        return (seen, hidden)
    }
}

extension Vec2 {
    func lerp(_ other: Vec2, _ t: Double) -> Vec2 { Vec2(x + (other.x - x) * t, y + (other.y - y) * t) }
}
