import Foundation

/// DXF, the drawing exchange every CAD program opens (G1). Written as AutoCAD R12 ASCII (the version everything
/// reads), in millimetres at full size, one layer a pen. Read back for underlays: lines, polylines, circles and arcs
/// from the model space, in the file's units (millimetres when it doesn't say).
public enum DXF {
    // MARK: Writing

    /// The drawing at full size in millimetres (a drawing in metres is multiplied by 1000).
    public static func data(_ art: LineArt) -> Data {
        var out = DXFOut()
        out.pair(0, "SECTION")
        out.pair(2, "HEADER")
        out.pair(9, "$ACADVER")
        out.pair(1, "AC1009")
        out.pair(9, "$INSUNITS")
        out.pair(70, "4")
        out.pair(0, "ENDSEC")
        out.pair(0, "SECTION")
        out.pair(2, "TABLES")
        out.pair(0, "TABLE")
        out.pair(2, "LAYER")
        out.pair(70, "\(LineArt.Pen.allCases.count + 1)")
        for pen in LineArt.Pen.allCases {
            out.layer(pen.layer, colour: colour(of: pen))
        }
        out.layer("TEXT", colour: 7)
        out.pair(0, "ENDTAB")
        out.pair(0, "ENDSEC")
        out.pair(0, "SECTION")
        out.pair(2, "ENTITIES")
        for stroke in art.strokes {
            for loop in [stroke.points] + stroke.holes where loop.count >= 2 {
                out.polyline(loop.map { $0 * 1000 }, closed: stroke.closed || !stroke.holes.isEmpty, layer: stroke.pen.layer)
            }
        }
        for label in art.labels {
            out.text(label.text, at: label.at * 1000, height: label.size, anchor: label.anchor)
        }
        out.pair(0, "ENDSEC")
        out.pair(0, "EOF")
        return Data(out.text.utf8)
    }

    /// AutoCAD's colour index for a pen: cuts white, hidden lines grey, folds and dimensions in colour.
    static func colour(of pen: LineArt.Pen) -> Int {
        switch pen {
        case .cut, .outline: 7
        case .thin: 8
        case .hidden: 9
        case .dimension: 3
        case .mountain: 1
        case .valley: 5
        case .cutLine: 1
        }
    }

    struct DXFOut {
        var text = ""

        mutating func pair(_ code: Int, _ value: String) {
            text += "\(String(repeating: " ", count: max(0, 3 - String(code).count)))\(code)\n\(value)\n"
        }

        mutating func number(_ code: Int, _ value: Double) {
            pair(code, String(format: "%.4f", value))
        }

        mutating func layer(_ name: String, colour: Int) {
            pair(0, "LAYER")
            pair(2, name)
            pair(70, "0")
            pair(62, "\(colour)")
            pair(6, "CONTINUOUS")
        }

        mutating func polyline(_ points: [Vec2], closed: Bool, layer: String) {
            if points.count == 2, !closed {
                pair(0, "LINE")
                pair(8, layer)
                number(10, points[0].x)
                number(20, points[0].y)
                number(30, 0)
                number(11, points[1].x)
                number(21, points[1].y)
                number(31, 0)
                return
            }
            pair(0, "POLYLINE")
            pair(8, layer)
            pair(66, "1")
            number(10, 0)
            number(20, 0)
            number(30, 0)
            pair(70, closed ? "1" : "0")
            for point in points {
                pair(0, "VERTEX")
                pair(8, layer)
                number(10, point.x)
                number(20, point.y)
                number(30, 0)
            }
            pair(0, "SEQEND")
            pair(8, layer)
        }

        mutating func text(_ value: String, at point: Vec2, height: Double, anchor: LineArt.Label.Anchor) {
            pair(0, "TEXT")
            pair(8, "TEXT")
            number(10, point.x)
            number(20, point.y)
            number(30, 0)
            number(40, height)
            pair(1, value.unicodeScalars.map { $0.value < 128 ? String($0) : "?" }.joined())
            let justify = switch anchor {
            case .start: 0
            case .middle: 1
            case .end: 2
            }
            if justify != 0 {
                pair(72, "\(justify)")
                number(11, point.x)
                number(21, point.y)
                number(31, 0)
            }
        }
    }

    // MARK: Reading

    public enum Failure: Error, Equatable, CustomStringConvertible {
        case notADrawing
        case empty

        public var description: String {
            switch self {
            case .notADrawing: "This file isn't a DXF drawing Maquette can read."
            case .empty: "The drawing has no lines, circles or arcs to trace."
            }
        }
    }

    /// What an underlay keeps from a DXF: lines in metres on the drawing's plane.
    public struct Drawing: Hashable, Sendable {
        public var curves: [SketchCurve]
        /// Entities left out (blocks placed by reference, hatches, text, splines): counted, not drawn.
        public var skipped: Int
        /// The file's unit, as its header names it.
        public var unit: LengthUnit

        public var bounds: (min: Vec2, max: Vec2)? {
            LineArt(strokes: curves.map { LineArt.Stroke(SketchCurveSampler.points($0), pen: .thin) }).bounds
        }
    }

    public static func read(_ data: Data) throws(Failure) -> Drawing {
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else { throw .notADrawing }
        let lines = text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
        var pairs: [(Int, String)] = []
        var index = 0
        while index + 1 < lines.count {
            guard let code = Int(lines[index]) else { throw .notADrawing }
            pairs.append((code, lines[index + 1]))
            index += 2
        }
        guard pairs.contains(where: { $0.0 == 0 && $0.1 == "SECTION" }) else { throw .notADrawing }
        let unit = Self.unit(in: pairs)
        let toMetres = unit.metres
        var reader = EntityReader(pairs: pairs, scale: toMetres)
        let (curves, skipped) = reader.entities()
        guard !curves.isEmpty else { throw .empty }
        return Drawing(curves: curves, skipped: skipped, unit: unit)
    }

    /// `$INSUNITS`: 1 inches, 2 feet, 4 millimetres, 5 centimetres, 6 metres; unitless drawings are read as millimetres.
    static func unit(in pairs: [(Int, String)]) -> LengthUnit {
        guard let at = pairs.firstIndex(where: { $0.0 == 9 && $0.1 == "$INSUNITS" }), at + 1 < pairs.count,
              let code = Int(pairs[at + 1].1) else { return .millimetre }
        return switch code {
        case 1: .inch
        case 2: .foot
        case 5: .centimetre
        case 6: .metre
        default: .millimetre
        }
    }

    struct EntityReader {
        let pairs: [(Int, String)]
        let scale: Double

        /// The model space's entities (inside ENTITIES, never inside BLOCKS).
        mutating func entities() -> ([SketchCurve], Int) {
            guard let start = pairs.indices.first(where: { pairs[$0].0 == 2 && pairs[$0].1 == "ENTITIES" }) else { return ([], 0) }
            var curves: [SketchCurve] = []
            var skipped = 0
            var index = start + 1
            while index < pairs.count {
                let (code, value) = pairs[index]
                guard code == 0 else {
                    index += 1
                    continue
                }
                if value == "ENDSEC" { break }
                let end = nextEntity(after: index)
                let fields = Array(pairs[(index + 1) ..< end])
                switch value {
                case "LINE": curves += line(fields)
                case "LWPOLYLINE": curves += lightPolyline(fields)
                case "POLYLINE":
                    let (curve, after) = heavyPolyline(fields, from: end)
                    curves += curve
                    index = after
                    continue
                case "CIRCLE": curves += circle(fields)
                case "ARC": curves += arc(fields)
                default: skipped += 1
                }
                index = end
            }
            return (curves, skipped)
        }

        func nextEntity(after index: Int) -> Int {
            var next = index + 1
            while next < pairs.count, pairs[next].0 != 0 {
                next += 1
            }
            return next
        }

        func value(_ code: Int, in fields: [(Int, String)]) -> Double? {
            fields.first { $0.0 == code }.flatMap { Double($0.1) }
        }

        func point(_ x: Int, _ y: Int, in fields: [(Int, String)]) -> Vec2? {
            guard let px = value(x, in: fields), let py = value(y, in: fields) else { return nil }
            return Vec2(px * scale, py * scale)
        }

        func line(_ fields: [(Int, String)]) -> [SketchCurve] {
            guard let a = point(10, 20, in: fields), let b = point(11, 21, in: fields), a.distance(to: b) > 1e-9 else { return [] }
            return [.line(a, b)]
        }

        func lightPolyline(_ fields: [(Int, String)]) -> [SketchCurve] {
            var points: [Vec2] = []
            var x: Double?
            for (code, text) in fields {
                if code == 10 { x = Double(text) }
                if code == 20, let px = x, let py = Double(text) {
                    points.append(Vec2(px * scale, py * scale))
                    x = nil
                }
            }
            let closed = (Int(fields.first { $0.0 == 70 }?.1 ?? "0") ?? 0) & 1 == 1
            return points.count >= 2 ? [.polyline(points, closed: closed)] : []
        }

        /// POLYLINE, then its VERTEX entities, then SEQEND.
        func heavyPolyline(_ fields: [(Int, String)], from start: Int) -> ([SketchCurve], Int) {
            let closed = (Int(fields.first { $0.0 == 70 }?.1 ?? "0") ?? 0) & 1 == 1
            var points: [Vec2] = []
            var index = start
            while index < pairs.count, pairs[index].0 == 0, pairs[index].1 == "VERTEX" {
                let end = nextEntity(after: index)
                if let p = point(10, 20, in: Array(pairs[(index + 1) ..< end])) { points.append(p) }
                index = end
            }
            if index < pairs.count, pairs[index].1 == "SEQEND" { index = nextEntity(after: index) }
            return (points.count >= 2 ? [.polyline(points, closed: closed)] : [], index)
        }

        func circle(_ fields: [(Int, String)]) -> [SketchCurve] {
            guard let centre = point(10, 20, in: fields), let radius = value(40, in: fields), radius > 0 else { return [] }
            return [.circle(center: centre, radius: radius * scale)]
        }

        /// An arc by its centre, radius and angles (degrees, counter-clockwise), kept as the three points sketches use.
        func arc(_ fields: [(Int, String)]) -> [SketchCurve] {
            guard let centre = point(10, 20, in: fields), let radius = value(40, in: fields), radius > 0,
                  let from = value(50, in: fields), let to = value(51, in: fields) else { return [] }
            var end = to
            while end <= from {
                end += 360
            }
            let r = radius * scale
            func at(_ degrees: Double) -> Vec2 {
                let angle = degrees * .pi / 180
                return centre + Vec2(cos(angle), sin(angle)) * r
            }
            return [.arc(at(from), at((from + end) / 2), at(end))]
        }
    }
}

/// Points along a sketch curve, for drawing it as lines.
public enum SketchCurveSampler {
    public static func points(_ curve: SketchCurve) -> [Vec2] {
        switch curve {
        case let .line(a, b): return [a, b]
        case let .rectangle(a, b): return [a, Vec2(b.x, a.y), b, Vec2(a.x, b.y), a]
        case let .circle(centre, radius):
            return (0 ... 48).map { index in
                let angle = Double(index) / 48 * 2 * .pi
                return centre + Vec2(cos(angle), sin(angle)) * radius
            }
        case let .arc(a, mid, b):
            guard let (centre, radius, start, sweep) = arcCircle(a, mid, b) else { return [a, mid, b] }
            let steps = max(4, Int(abs(sweep) / (.pi / 24)))
            return (0 ... steps).map { index in
                let angle = start + sweep * Double(index) / Double(steps)
                return centre + Vec2(cos(angle), sin(angle)) * radius
            }
        case let .spline(points, closed), let .polyline(points, closed):
            return closed && !points.isEmpty ? points + [points[0]] : points
        }
    }

    /// The circle through three points: its centre, radius, the start angle and the signed sweep through `mid` to `b`.
    static func arcCircle(_ a: Vec2, _ mid: Vec2, _ b: Vec2) -> (Vec2, Double, Double, Double)? {
        let d = 2 * (a.x * (mid.y - b.y) + mid.x * (b.y - a.y) + b.x * (a.y - mid.y))
        guard abs(d) > 1e-12 else { return nil }
        let a2 = a.x * a.x + a.y * a.y, m2 = mid.x * mid.x + mid.y * mid.y, b2 = b.x * b.x + b.y * b.y
        let centre = Vec2((a2 * (mid.y - b.y) + m2 * (b.y - a.y) + b2 * (a.y - mid.y)) / d,
                          (a2 * (b.x - mid.x) + m2 * (a.x - b.x) + b2 * (mid.x - a.x)) / d)
        let radius = a.distance(to: centre)
        func angle(_ p: Vec2) -> Double { atan2(p.y - centre.y, p.x - centre.x) }
        let start = angle(a)
        func ccw(_ p: Vec2) -> Double {
            var value = angle(p) - start
            while value < 0 {
                value += 2 * .pi
            }
            return value
        }
        let sweep = ccw(mid) <= ccw(b) ? ccw(b) : ccw(b) - 2 * .pi
        return (centre, radius, start, sweep)
    }
}
