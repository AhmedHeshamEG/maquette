import Foundation

/// Reads SVG files as filled shapes: paths, rectangles (rounded too), circles, ellipses, polygons, groups with
/// transforms and inherited paint, `<use>` of defined parts, nested `<svg>`, CSS classes from `<style>`, and
/// gradients as one flat colour (the average of their stops). Strokes, text and pictures can't become filled outlines,
/// so they are counted in `skipped` instead of guessed at. Pure Swift.
public enum SVG {
    public enum Failure: Error, Equatable, CustomStringConvertible {
        case notSVG
        case nothingFilled

        public var description: String {
            switch self {
            case .notSVG: "That file isn't an SVG drawing."
            case .nothingFilled: "The drawing has no filled shapes. Outlines drawn with a pen need converting to shapes first."
            }
        }
    }

    /// The drawing's filled shapes. `tolerance` is how far a flattened curve may stray, in the drawing's units; by default
    /// a thousandth of the drawing's size.
    public static func read(_ data: Data, tolerance: Double? = nil) throws(Failure) -> VectorDrawing {
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1),
              let root = XMLReader.parse(text), root.localName == "svg" else { throw .notSVG }
        var walker = SVGWalker(root: root)
        walker.tolerance = tolerance ?? walker.defaultTolerance
        walker.walk(root, transform: .identity, paint: SVGPaintState(), depth: 0)
        let drawing = VectorDrawing(shapes: walker.shapes, skipped: walker.skipped)
        guard !drawing.shapes.isEmpty else { throw .nothingFilled }
        return drawing
    }
}

/// Walks the tree, carrying the transform and the paint down to each shape.
struct SVGWalker {
    let sheet: SVGStyleSheet
    let byID: [String: SVGNode]
    let size: VectorPoint?
    var tolerance = 0.25
    var shapes: [VectorShape] = []
    var skipped = VectorSkipped()

    /// Elements that only define things (drawn by reference, or never).
    static let definitions: Set = ["defs", "clipPath", "mask", "pattern", "symbol", "marker", "title", "desc", "metadata", "style",
                                   "linearGradient", "radialGradient", "filter", "script"]

    init(root: SVGNode) {
        let all = [root] + root.descendants
        sheet = SVGStyleSheet(all.filter { $0.localName == "style" }.map(\.text).joined(separator: "\n"))
        var byID: [String: SVGNode] = [:]
        for element in all {
            if let id = element.attributes["id"] { byID[id] = element }
        }
        self.byID = byID
        size = Self.size(of: root)
    }

    /// The viewBox's size, else the width and height.
    static func size(of root: SVGNode) -> VectorPoint? {
        if let box = root.attributes["viewBox"].map(numbers), box.count == 4, box[2] > 0, box[3] > 0 { return VectorPoint(box[2], box[3]) }
        guard let width = root.attributes["width"].flatMap(PathScannerNumber.first),
              let height = root.attributes["height"].flatMap(PathScannerNumber.first) else { return nil }
        return VectorPoint(width, height)
    }

    static func numbers(_ text: String) -> [Double] {
        var scanner = PathScanner(text)
        var values: [Double] = []
        while let value = scanner.number() {
            values.append(value)
        }
        return values
    }

    var defaultTolerance: Double {
        guard let size else { return 0.25 }
        return max((size.x * size.x + size.y * size.y).squareRoot() / 1000, 1e-4)
    }

    /// The paint of `element`: inherited, then its presentation attributes, the style sheet, its `style`.
    func paint(of element: SVGNode, inherited: SVGPaintState) -> SVGPaintState {
        var paint = inherited
        for name in ["fill", "fill-opacity", "opacity", "stroke", "stroke-width", "color", "display", "visibility"] {
            if let value = element.attributes[name] { paint.set(name, value) }
        }
        for (name, value) in sheet.declarations(for: element) {
            paint.set(name, value)
        }
        for (name, value) in SVGStyleSheet.declarations(element.attributes["style"] ?? "") {
            paint.set(name, value)
        }
        return paint
    }

    mutating func walk(_ element: SVGNode, transform: VectorTransform, paint inherited: SVGPaintState, depth: Int) {
        let name = element.localName
        guard depth < 64, !Self.definitions.contains(name) else { return }
        let paint = paint(of: element, inherited: inherited)
        guard !paint.hidden else { return }
        var local = transform.concatenating(VectorTransform.parse(element.attributes["transform"] ?? ""))
        switch name {
        case "svg" where depth > 0:
            local = local.concatenating(.translate(number(element, "x"), number(element, "y")))
            walkChildren(element, transform: local, paint: paint, depth: depth)
        case "svg", "g", "a", "switch":
            walkChildren(element, transform: local, paint: paint, depth: depth)
        case "use":
            guard let href = (element.attributes["href"] ?? element.attributes["xlink:href"])?.trimmingCharacters(in: CharacterSet(charactersIn: "#")),
                  let target = byID[href] else { return }
            local = local.concatenating(.translate(number(element, "x"), number(element, "y")))
            let shown = target.localName == "symbol" ? SVGNode(name: "g", children: target.children) : target
            walk(shown, transform: local, paint: paint, depth: depth + 1)
        case "text":
            skipped.texts += 1
        case "image":
            skipped.images += 1
        case "line":
            // A line has no inside: only its stroke ever shows.
            if paint.strokes { skipped.strokes += 1 }
        default:
            let outlines = SVGShapes.polylines(element, tolerance: tolerance / max(local.scale, 1e-9))
            guard !outlines.isEmpty else { return }
            add(outlines, element: element, transform: local, paint: paint)
        }
    }

    private mutating func walkChildren(_ element: SVGNode, transform: VectorTransform, paint: SVGPaintState, depth: Int) {
        for child in element.children {
            walk(child, transform: transform, paint: paint, depth: depth + 1)
        }
    }

    private func number(_ element: SVGNode, _ name: String) -> Double {
        element.attributes[name].flatMap(PathScannerNumber.first) ?? 0
    }

    private mutating func add(_ outlines: [[VectorPoint]], element: SVGNode, transform: VectorTransform, paint: SVGPaintState) {
        if paint.strokes { skipped.strokes += 1 }
        guard var color = fill(paint) else { return }
        color.alpha *= paint.fillOpacity * paint.opacity
        guard color.alpha > 0.001 else { return }
        let contours = outlines.map { $0.map(transform.apply) }.filter { $0.count >= 3 }
        guard !contours.isEmpty else { return }
        shapes.append(VectorShape(fill: color, contours: contours, name: element.attributes["id"]))
    }

    /// The fill's colour: a gradient's average stop colour, `currentColor` the inherited `color`.
    private func fill(_ paint: SVGPaintState) -> VectorColor? {
        switch paint.fill {
        case .none: return nil
        case let .color(color): return color
        case .current: return paint.color
        case let .reference(id): return byID[id].flatMap { gradientColor($0) }
        }
    }

    private func gradientColor(_ gradient: SVGNode, depth: Int = 0) -> VectorColor? {
        let stops = gradient.children.filter { $0.localName == "stop" }.compactMap { stop -> VectorColor? in
            let style = Dictionary(SVGStyleSheet.declarations(stop.attributes["style"] ?? ""), uniquingKeysWith: { _, last in last })
            guard var color = (style["stop-color"] ?? stop.attributes["stop-color"]).flatMap(SVGColor.parse) else { return nil }
            color.alpha *= (style["stop-opacity"] ?? stop.attributes["stop-opacity"]).flatMap(SVGPaintState.fraction) ?? 1
            return color
        }
        if stops.isEmpty, depth < 4, let href = (gradient.attributes["href"] ?? gradient.attributes["xlink:href"])?.dropFirst(),
           let linked = byID[String(href)] {
            return gradientColor(linked, depth: depth + 1)
        }
        guard !stops.isEmpty else { return nil }
        let count = Double(stops.count)
        return VectorColor(red: stops.map(\.red).reduce(0, +) / count, green: stops.map(\.green).reduce(0, +) / count,
                           blue: stops.map(\.blue).reduce(0, +) / count, alpha: stops.map(\.alpha).reduce(0, +) / count)
    }
}

/// The basic shapes as polylines in their own units.
enum SVGShapes {
    static func polylines(_ element: SVGNode, tolerance: Double) -> [[VectorPoint]] {
        func value(_ name: String) -> Double { element.attributes[name].flatMap(PathScannerNumber.first) ?? 0 }
        switch element.localName {
        case "path":
            return SVGPathReader.polylines(element.attributes["d"] ?? "", tolerance: tolerance)
        case "rect":
            return rect(x: value("x"), y: value("y"), width: value("width"), height: value("height"),
                        rx: element.attributes["rx"].flatMap(PathScannerNumber.first), ry: element.attributes["ry"].flatMap(PathScannerNumber.first),
                        tolerance: tolerance)
        case "circle":
            return ellipse(cx: value("cx"), cy: value("cy"), rx: value("r"), ry: value("r"), tolerance: tolerance)
        case "ellipse":
            return ellipse(cx: value("cx"), cy: value("cy"), rx: value("rx"), ry: value("ry"), tolerance: tolerance)
        case "polygon", "polyline":
            let numbers = SVGWalker.numbers(element.attributes["points"] ?? "")
            let points = stride(from: 0, to: numbers.count - 1, by: 2).map { VectorPoint(numbers[$0], numbers[$0 + 1]) }
            return points.count >= 3 ? [points] : []
        default:
            return []
        }
    }

    static func rect(x: Double, y: Double, width: Double, height: Double, rx: Double?, ry: Double?, tolerance: Double) -> [[VectorPoint]] {
        guard width > 0, height > 0 else { return [] }
        let radiusX = min(max(rx ?? ry ?? 0, 0), width / 2), radiusY = min(max(ry ?? rx ?? 0, 0), height / 2)
        guard radiusX > 0, radiusY > 0 else {
            return [[VectorPoint(x, y), VectorPoint(x + width, y), VectorPoint(x + width, y + height), VectorPoint(x, y + height)]]
        }
        let d = "M\(x + radiusX),\(y) H\(x + width - radiusX) A\(radiusX),\(radiusY) 0 0 1 \(x + width),\(y + radiusY) "
            + "V\(y + height - radiusY) A\(radiusX),\(radiusY) 0 0 1 \(x + width - radiusX),\(y + height) H\(x + radiusX) "
            + "A\(radiusX),\(radiusY) 0 0 1 \(x),\(y + height - radiusY) V\(y + radiusY) A\(radiusX),\(radiusY) 0 0 1 \(x + radiusX),\(y) Z"
        return SVGPathReader.polylines(d, tolerance: tolerance)
    }

    static func ellipse(cx: Double, cy: Double, rx: Double, ry: Double, tolerance: Double) -> [[VectorPoint]] {
        guard rx > 0, ry > 0 else { return [] }
        let d = "M\(cx - rx),\(cy) A\(rx),\(ry) 0 1 0 \(cx + rx),\(cy) A\(rx),\(ry) 0 1 0 \(cx - rx),\(cy) Z"
        return SVGPathReader.polylines(d, tolerance: tolerance)
    }
}
