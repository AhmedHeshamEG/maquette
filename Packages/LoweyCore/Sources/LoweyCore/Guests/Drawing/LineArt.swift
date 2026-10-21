import Foundation

/// A drawing made of lines (G1): a plan, an elevation, a technical sheet's view, a papercraft net, a frame's ink as
/// vectors. Coordinates are in metres on the drawing's own plane (x right, y up); the writers scale it onto paper.
public struct LineArt: Hashable, Sendable {
    /// How a line is drawn, as a draughtsman would: a heavy line for what a plan cuts, a medium one for what is seen,
    /// thin ones for what is beyond or measured, dashes for what is hidden or folded.
    public enum Pen: String, Hashable, Sendable, CaseIterable {
        /// Cut through (walls in a plan): heavy, filled.
        case cut
        /// A visible outline.
        case outline
        /// A visible line of lesser weight (beyond the cut, a crease).
        case thin
        /// Behind something: dashed.
        case hidden
        /// Dimension lines and their ticks.
        case dimension
        /// A fold that comes towards you (papercraft): dash-dot.
        case mountain
        /// A fold that goes away from you: dashed.
        case valley
        /// A line a cutter follows (papercraft, laser).
        case cutLine

        /// Its width on paper, in millimetres.
        public var weight: Double {
            switch self {
            case .cut: 0.5
            case .outline: 0.35
            case .thin, .dimension, .valley, .mountain: 0.18
            case .hidden: 0.18
            case .cutLine: 0.25
            }
        }

        /// The dash pattern on paper (millimetres on, off…), empty for a solid line.
        public var dashes: [Double] {
            switch self {
            case .hidden: [2, 1.2]
            case .valley: [3, 1.5]
            case .mountain: [4, 1.2, 0.6, 1.2]
            default: []
            }
        }

        /// Grey on paper (0 black).
        public var grey: Double {
            switch self {
            case .thin, .hidden, .dimension, .valley, .mountain: 0.25
            default: 0
            }
        }

        /// The layer a DXF puts it on.
        public var layer: String { rawValue.uppercased() }
    }

    public struct Stroke: Hashable, Sendable {
        public var points: [Vec2]
        public var closed: Bool
        public var pen: Pen
        /// A closed stroke filled (cut walls are filled solid, as plans draw them), even-odd with its holes.
        public var filled: Bool
        /// Loops cut out of a filled stroke (the inside of a ring of walls).
        public var holes: [[Vec2]]

        public init(_ points: [Vec2], closed: Bool = false, pen: Pen, filled: Bool = false, holes: [[Vec2]] = []) {
            self.points = points
            self.closed = closed
            self.pen = pen
            self.filled = filled
            self.holes = holes
        }
    }

    public struct Label: Hashable, Sendable {
        public enum Anchor: String, Hashable, Sendable { case start, middle, end }
        public var text: String
        public var at: Vec2
        /// The letters' height on paper, in millimetres (labels keep their size whatever the scale).
        public var size: Double
        public var anchor: Anchor
        public var bold: Bool

        public init(_ text: String, at: Vec2, size: Double = 2.5, anchor: Anchor = .middle, bold: Bool = false) {
            self.text = text
            self.at = at
            self.size = size
            self.anchor = anchor
            self.bold = bold
        }
    }

    public var strokes: [Stroke]
    public var labels: [Label]

    public init(strokes: [Stroke] = [], labels: [Label] = []) {
        self.strokes = strokes
        self.labels = labels
    }

    public var isEmpty: Bool { strokes.isEmpty && labels.isEmpty }

    /// The box around every line (labels don't count: they keep their size on paper).
    public var bounds: (min: Vec2, max: Vec2)? {
        var lo = Vec2(.infinity, .infinity), hi = Vec2(-.infinity, -.infinity)
        for point in strokes.flatMap(\.points) {
            lo = Vec2(min(lo.x, point.x), min(lo.y, point.y))
            hi = Vec2(max(hi.x, point.x), max(hi.y, point.y))
        }
        return lo.x.isFinite ? (lo, hi) : nil
    }

    public mutating func append(_ other: LineArt, offset: Vec2 = .zero) {
        strokes += other.strokes.map { stroke in
            var moved = stroke
            moved.points = stroke.points.map { $0 + offset }
            moved.holes = stroke.holes.map { $0.map { $0 + offset } }
            return moved
        }
        labels += other.labels.map { label in
            var moved = label
            moved.at = label.at + offset
            return moved
        }
    }

    /// The drawing moved and scaled (a view placed on a sheet).
    public func placed(scale: Double, offset: Vec2) -> LineArt {
        LineArt(strokes: strokes.map { stroke in
            var moved = stroke
            moved.points = stroke.points.map { Vec2($0.x * scale, $0.y * scale) + offset }
            moved.holes = stroke.holes.map { $0.map { Vec2($0.x * scale, $0.y * scale) + offset } }
            return moved
        }, labels: labels.map { label in
            var moved = label
            moved.at = Vec2(label.at.x * scale, label.at.y * scale) + offset
            return moved
        })
    }

    /// A measured line with ticks at its ends and its length written above it, `offset` metres to its left side.
    public static func dimension(from a: Vec2, to b: Vec2, offset: Double, text: String) -> LineArt {
        let along = b - a
        let length = max(along.length, 1e-9)
        let left = Vec2(-along.y / length, along.x / length)
        let p = a + left * offset, q = b + left * offset
        let direction = Vec2(along.x / length, along.y / length)
        // A short slash across each end, as architects tick a dimension.
        let slash = (direction + left) * (abs(offset) * 0.12)
        let gap = left * (offset * 0.15)
        var art = LineArt()
        art.strokes.append(Stroke([p, q], pen: .dimension))
        art.strokes.append(Stroke([a + gap, p + gap * 0.5], pen: .dimension))
        art.strokes.append(Stroke([b + gap, q + gap * 0.5], pen: .dimension))
        art.strokes.append(Stroke([p - slash, p + slash], pen: .dimension))
        art.strokes.append(Stroke([q - slash, q + slash], pen: .dimension))
        let outward = left * (offset < 0 ? -1 : 1)
        // Beside an upright dimension the text sits off the line's side; along a level one, above or below it.
        let upright = abs(direction.y) > abs(direction.x)
        let anchor: Label.Anchor = upright ? (outward.x < 0 ? .end : .start) : .middle
        art.labels.append(Label(text, at: (p + q) * 0.5 + outward * (abs(offset) * (upright ? 0.2 : 0.35)), size: 2.5, anchor: anchor))
        return art
    }
}

public extension Vec2 {
    static func * (lhs: Double, rhs: Vec2) -> Vec2 { rhs * lhs }
    var normalizedVector: Vec2 {
        let l = length
        return l > 1e-12 ? Vec2(x / l, y / l) : .zero
    }
}

// MARK: - Paper

/// A drawing placed on paper: the drawing's metres become millimetres on the page at `scale` (1:50 is 0.02), with
/// `origin` the drawing point that lands at the page's `at` (millimetres from the bottom-left corner).
public struct PaperPlacement: Hashable, Sendable {
    public var scale: Double
    public var origin: Vec2
    public var at: Vec2

    public init(scale: Double, origin: Vec2, at: Vec2) {
        self.scale = scale
        self.origin = origin
        self.at = at
    }

    /// A drawing point on the page, in millimetres.
    public func page(_ point: Vec2) -> Vec2 {
        Vec2((point.x - origin.x) * scale * 1000 + at.x, (point.y - origin.y) * scale * 1000 + at.y)
    }

    /// The architects' scales, largest first: the drawing takes the first that fits.
    public static let standardScales: [Double] = [5, 2, 1, 1.0 / 2, 1.0 / 5, 1.0 / 10, 1.0 / 20, 1.0 / 25, 1.0 / 50, 1.0 / 100, 1.0 / 200,
                                                  1.0 / 500, 1.0 / 1000, 1.0 / 2000]

    /// The largest standard scale at which a drawing `size` metres across fits `room` millimetres.
    public static func fitting(_ size: Vec2, into room: Vec2) -> Double {
        for scale in standardScales where size.x * scale * 1000 <= room.x && size.y * scale * 1000 <= room.y {
            return scale
        }
        return min(room.x / max(size.x * 1000, 1e-9), room.y / max(size.y * 1000, 1e-9))
    }

    /// "1:50", "2:1".
    public static func title(of scale: Double) -> String {
        if scale >= 1 { return "\(Int(scale.rounded())):1" }
        return "1:\(Int((1 / scale).rounded()))"
    }
}

public extension LineArt {
    /// The drawing as PDF items on a page (points), at a placement in millimetres.
    func pdfItems(_ placement: PaperPlacement) -> [PDFWriter.Item] {
        let mm = 72 / 25.4
        func point(_ p: Vec2) -> Vec2 {
            let page = placement.page(p)
            return Vec2(page.x * mm, page.y * mm)
        }
        var items: [PDFWriter.Item] = strokes.map { stroke in
            .path([stroke.points.map(point)] + (stroke.filled ? stroke.holes.map { $0.map(point) } : []), closed: stroke.closed,
                  width: stroke.pen.weight * mm, grey: stroke.pen.grey, dashes: stroke.pen.dashes.map { $0 * mm },
                  fill: stroke.filled ? 0.15 : nil)
        }
        for label in labels {
            let size = label.size * mm * 1.4
            let at = point(label.at)
            let width = PDFWriter.textWidth(label.text, size: size, bold: label.bold)
            let x = switch label.anchor {
            case .start: at.x
            case .middle: at.x - width / 2
            case .end: at.x - width
            }
            items.append(.text(label.text, x: x, y: at.y - size * 0.35, size: size, bold: label.bold))
        }
        return items
    }

    /// The drawing as an SVG file `width` × `height` millimetres. Laser cutters read red as cut and blue as score.
    func svg(_ placement: PaperPlacement, width: Double, height: Double, laser: Bool = false) -> String {
        func coordinates(_ p: Vec2) -> String {
            let page = placement.page(p)
            return "\(Self.number(page.x)),\(Self.number(height - page.y))"
        }
        var svg = """
        <?xml version="1.0" encoding="UTF-8"?>
        <svg xmlns="http://www.w3.org/2000/svg" width="\(Self.number(width))mm" height="\(Self.number(height))mm" \
        viewBox="0 0 \(Self.number(width)) \(Self.number(height))">

        """
        for pen in Pen.allCases {
            let lines = strokes.filter { $0.pen == pen }
            guard !lines.isEmpty else { continue }
            let colour = laser ? (pen == .cutLine || pen == .cut || pen == .outline ? "#FF0000" : "#0000FF") : Self.hexGrey(pen.grey)
            let dash = !laser && !pen.dashes.isEmpty ? " stroke-dasharray=\"\(pen.dashes.map(Self.number).joined(separator: " "))\"" : ""
            let weight = laser ? 0.01 : pen.weight
            svg += "  <g id=\"\(pen.rawValue)\" fill=\"none\" stroke=\"\(colour)\" stroke-width=\"\(Self.number(weight))\"\(dash) "
                + "stroke-linecap=\"round\" stroke-linejoin=\"round\">\n"
            for stroke in lines where stroke.points.count >= 2 {
                if stroke.filled, !laser {
                    let loops = ([stroke.points] + stroke.holes).map { "M " + $0.map(coordinates).joined(separator: " L ") + " Z" }
                    svg += "    <path d=\"\(loops.joined(separator: " "))\" fill=\"#262626\" fill-rule=\"evenodd\"/>\n"
                    continue
                }
                let points = stroke.points.map(coordinates).joined(separator: " ")
                svg += "    <\(stroke.closed ? "polygon" : "polyline") points=\"\(points)\"/>\n"
                for hole in stroke.holes {
                    svg += "    <polygon points=\"\(hole.map(coordinates).joined(separator: " "))\"/>\n"
                }
            }
            svg += "  </g>\n"
        }
        if !laser, !labels.isEmpty {
            svg += "  <g id=\"labels\" font-family=\"Helvetica, Arial, sans-serif\" fill=\"#000000\">\n"
            for label in labels {
                let page = placement.page(label.at)
                let anchor = label.anchor == .start ? "start" : label.anchor == .end ? "end" : "middle"
                svg += "    <text x=\"\(Self.number(page.x))\" y=\"\(Self.number(height - page.y + label.size * 0.35))\" "
                    + "font-size=\"\(Self.number(label.size))\" text-anchor=\"\(anchor)\"\(label.bold ? " font-weight=\"bold\"" : "")>"
                    + "\(Self.escaped(label.text))</text>\n"
            }
            svg += "  </g>\n"
        }
        return svg + "</svg>\n"
    }

    static func number(_ value: Double) -> String {
        let rounded = (value * 1000).rounded() / 1000
        return rounded == rounded.rounded() ? String(Int(rounded)) : String(format: "%.3f", rounded)
    }

    static func hexGrey(_ grey: Double) -> String {
        let byte = Int((min(max(grey, 0), 1) * 255).rounded())
        return String(format: "#%02X%02X%02X", byte, byte, byte)
    }

    static func escaped(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }
}
