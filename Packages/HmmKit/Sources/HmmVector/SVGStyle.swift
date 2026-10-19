import Foundation

/// An affine transform `[a c e; b d f]`, SVG's `matrix(a b c d e f)`.
struct VectorTransform: Hashable, Sendable {
    var a = 1.0, b = 0.0, c = 0.0, d = 1.0, e = 0.0, f = 0.0

    static let identity = VectorTransform()

    func apply(_ point: VectorPoint) -> VectorPoint {
        VectorPoint(a * point.x + c * point.y + e, b * point.x + d * point.y + f)
    }

    /// `self` after `other` (other's points are transformed by self next).
    func concatenating(_ other: VectorTransform) -> VectorTransform {
        VectorTransform(a: a * other.a + c * other.b, b: b * other.a + d * other.b,
                        c: a * other.c + c * other.d, d: b * other.c + d * other.d,
                        e: a * other.e + c * other.f + e, f: b * other.e + d * other.f + f)
    }

    /// How much it scales lengths (the square root of the area it scales by).
    var scale: Double { abs(a * d - b * c).squareRoot() }

    static func translate(_ x: Double, _ y: Double) -> VectorTransform { VectorTransform(e: x, f: y) }

    /// A `transform` attribute: a list of matrix, translate, scale, rotate, skewX, skewY.
    static func parse(_ text: String) -> VectorTransform {
        var result = VectorTransform.identity
        var rest = Substring(text)
        while let open = rest.firstIndex(of: "("), let close = rest[open...].firstIndex(of: ")") {
            let name = rest[..<open].trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: ",")))
            var scanner = PathScanner(String(rest[rest.index(after: open) ..< close]))
            var values: [Double] = []
            while let value = scanner.number() {
                values.append(value)
            }
            result = result.concatenating(make(name, values))
            rest = rest[rest.index(after: close)...]
        }
        return result
    }

    private static func make(_ name: String, _ v: [Double]) -> VectorTransform {
        func at(_ index: Int, _ fallback: Double) -> Double { index < v.count ? v[index] : fallback }
        switch name {
        case "matrix" where v.count >= 6:
            return VectorTransform(a: v[0], b: v[1], c: v[2], d: v[3], e: v[4], f: v[5])
        case "translate":
            return translate(at(0, 0), at(1, 0))
        case "scale":
            return VectorTransform(a: at(0, 1), d: at(1, at(0, 1)))
        case "rotate":
            let angle = at(0, 0) * .pi / 180
            let turn = VectorTransform(a: cos(angle), b: sin(angle), c: -sin(angle), d: cos(angle))
            guard v.count >= 3 else { return turn }
            return translate(v[1], v[2]).concatenating(turn).concatenating(translate(-v[1], -v[2]))
        case "skewX":
            return VectorTransform(c: tan(at(0, 0) * .pi / 180))
        case "skewY":
            return VectorTransform(b: tan(at(0, 0) * .pi / 180))
        default:
            return .identity
        }
    }
}

/// The paint of an element as it inherits: fill, its opacity, the stroke, whether it shows.
struct SVGPaintState: Sendable {
    enum Paint: Sendable, Equatable {
        case none
        case color(VectorColor)
        /// `url(#id)`: a gradient (or pattern) defined elsewhere.
        case reference(String)
        case current
    }

    var fill: Paint = .color(.black)
    var fillOpacity = 1.0
    var opacity = 1.0
    var stroke: Paint = .none
    var strokeWidth = 1.0
    var color: VectorColor = .black
    var hidden = false

    /// One property from an attribute or a style declaration. `opacity` multiplies down the tree, the rest replace.
    mutating func set(_ name: String, _ raw: String) {
        let value = raw.trimmingCharacters(in: .whitespaces)
        guard value != "inherit" else { return }
        switch name {
        case "fill": fill = Self.paint(value) ?? fill
        case "fill-opacity": fillOpacity = Self.fraction(value) ?? fillOpacity
        case "opacity": opacity *= Self.fraction(value) ?? 1
        case "stroke": stroke = Self.paint(value) ?? stroke
        case "stroke-width": strokeWidth = PathScannerNumber.first(value) ?? strokeWidth
        case "color": color = SVGColor.parse(value) ?? color
        case "display": hidden = hidden || value == "none"
        case "visibility": hidden = value == "hidden" || value == "collapse"
        default: break
        }
    }

    static func paint(_ value: String) -> Paint? {
        if value == "none" || value == "transparent" { return Paint.none }
        if value == "currentColor" { return .current }
        if value.hasPrefix("url(") {
            let inside = value.dropFirst(4).prefix { $0 != ")" }.trimmingCharacters(in: CharacterSet(charactersIn: "#'\" "))
            return .reference(inside)
        }
        return SVGColor.parse(value).map { .color($0) }
    }

    static func fraction(_ value: String) -> Double? {
        if value.hasSuffix("%") { return Double(value.dropLast()).map { $0 / 100 } }
        return Double(value).map { min(max($0, 0), 1) }
    }

    /// Whether a stroke would be seen.
    var strokes: Bool { stroke != .none && strokeWidth > 0 }
}

enum PathScannerNumber {
    static func first(_ text: String) -> Double? {
        var scanner = PathScanner(text)
        return scanner.number()
    }
}

/// CSS colours: hex, rgb()/rgba(), hsl()/hsla() and the common names.
enum SVGColor {
    static func parse(_ raw: String) -> VectorColor? {
        let value = raw.trimmingCharacters(in: .whitespaces).lowercased()
        if value.hasPrefix("#") { return hex(String(value.dropFirst())) }
        if value.hasPrefix("rgb") { return rgb(arguments(value)) }
        if value.hasPrefix("hsl") { return hsl(arguments(value)) }
        return named[value].flatMap { hex($0) }
    }

    private static func arguments(_ value: String) -> [String] {
        guard let open = value.firstIndex(of: "("), let close = value.lastIndex(of: ")"), open < close else { return [] }
        return value[value.index(after: open) ..< close].split { $0 == "," || $0 == " " || $0 == "/" }.map(String.init)
    }

    private static func hex(_ digits: String) -> VectorColor? {
        let expanded = digits.count == 3 || digits.count == 4 ? digits.map { "\($0)\($0)" }.joined() : digits
        guard expanded.count == 6 || expanded.count == 8, let number = UInt64(expanded, radix: 16) else { return nil }
        let hasAlpha = expanded.count == 8
        let shift = hasAlpha ? 8 : 0
        func channel(_ offset: Int) -> Double { Double((number >> UInt64(offset + shift)) & 0xFF) / 255 }
        return VectorColor(red: channel(16), green: channel(8), blue: channel(0), alpha: hasAlpha ? Double(number & 0xFF) / 255 : 1)
    }

    private static func component(_ text: String, scale: Double) -> Double {
        if text.hasSuffix("%") { return (Double(text.dropLast()) ?? 0) / 100 }
        return (Double(text) ?? 0) / scale
    }

    private static func rgb(_ parts: [String]) -> VectorColor? {
        guard parts.count >= 3 else { return nil }
        let alpha = parts.count >= 4 ? component(parts[3], scale: 1) : 1
        return VectorColor(red: component(parts[0], scale: 255), green: component(parts[1], scale: 255),
                           blue: component(parts[2], scale: 255), alpha: alpha)
    }

    private static func hsl(_ parts: [String]) -> VectorColor? {
        guard parts.count >= 3 else { return nil }
        let hue = (Double(parts[0].replacingOccurrences(of: "deg", with: "")) ?? 0) / 360
        let saturation = component(parts[1], scale: 100), lightness = component(parts[2], scale: 100)
        let q = lightness < 0.5 ? lightness * (1 + saturation) : lightness + saturation - lightness * saturation
        let p = 2 * lightness - q
        func channel(_ shift: Double) -> Double {
            var t = hue + shift
            t -= t.rounded(.down)
            if t < 1.0 / 6 { return p + (q - p) * 6 * t }
            if t < 0.5 { return q }
            if t < 2.0 / 3 { return p + (q - p) * (2.0 / 3 - t) * 6 }
            return p
        }
        let alpha = parts.count >= 4 ? component(parts[3], scale: 1) : 1
        return VectorColor(red: channel(1.0 / 3), green: channel(0), blue: channel(-1.0 / 3), alpha: alpha)
    }

    static let named: [String: String] = [
        "black": "000000", "white": "ffffff", "red": "ff0000", "green": "008000", "blue": "0000ff", "yellow": "ffff00",
        "orange": "ffa500", "purple": "800080", "gray": "808080", "grey": "808080", "silver": "c0c0c0", "maroon": "800000",
        "olive": "808000", "lime": "00ff00", "aqua": "00ffff", "cyan": "00ffff", "teal": "008080", "navy": "000080",
        "fuchsia": "ff00ff", "magenta": "ff00ff", "pink": "ffc0cb", "brown": "a52a2a", "gold": "ffd700", "indigo": "4b0082",
        "violet": "ee82ee", "crimson": "dc143c", "coral": "ff7f50", "salmon": "fa8072", "tomato": "ff6347", "khaki": "f0e68c",
        "beige": "f5f5dc", "ivory": "fffff0", "lavender": "e6e6fa", "turquoise": "40e0d0", "tan": "d2b48c", "chocolate": "d2691e",
        "darkgray": "a9a9a9", "darkgrey": "a9a9a9", "lightgray": "d3d3d3", "lightgrey": "d3d3d3", "darkblue": "00008b",
        "darkred": "8b0000", "darkgreen": "006400", "skyblue": "87ceeb", "steelblue": "4682b4", "royalblue": "4169e1",
        "dodgerblue": "1e90ff", "deepskyblue": "00bfff", "hotpink": "ff69b4", "deeppink": "ff1493", "orangered": "ff4500",
        "forestgreen": "228b22", "seagreen": "2e8b57", "limegreen": "32cd32", "slategray": "708090", "dimgray": "696969",
        "whitesmoke": "f5f5f5", "gainsboro": "dcdcdc", "firebrick": "b22222", "goldenrod": "daa520", "sienna": "a0522d"
    ]
}

/// The simple CSS of a `<style>` element: rules whose selectors are `.class`, `#id`, a tag or `*`, comma-separated.
struct SVGStyleSheet: Sendable {
    struct Rule: Sendable {
        var selector: String
        var declarations: [(String, String)]
    }

    var rules: [Rule] = []

    init(_ css: String) {
        var text = css
        while let open = text.range(of: "/*"), let close = text.range(of: "*/", range: open.upperBound ..< text.endIndex) {
            text.removeSubrange(open.lowerBound ..< close.upperBound)
        }
        for block in text.split(separator: "}") {
            let parts = block.split(separator: "{", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let declarations = Self.declarations(String(parts[1]))
            for selector in parts[0].split(separator: ",") {
                rules.append(Rule(selector: selector.trimmingCharacters(in: .whitespacesAndNewlines), declarations: declarations))
            }
        }
    }

    /// `name: value; …` pairs.
    static func declarations(_ text: String) -> [(String, String)] {
        text.split(separator: ";").compactMap { declaration in
            let pair = declaration.split(separator: ":", maxSplits: 1)
            guard pair.count == 2 else { return nil }
            let value = pair[1].replacingOccurrences(of: "!important", with: "")
            return (pair[0].trimmingCharacters(in: .whitespacesAndNewlines), value.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    /// The declarations that apply to an element, in the sheet's order.
    func declarations(for element: SVGNode) -> [(String, String)] {
        let classes = Set((element.attributes["class"] ?? "").split(separator: " ").map(String.init))
        let id = element.attributes["id"]
        return rules.filter { rule in
            let selector = rule.selector
            if selector == "*" || selector == element.localName { return true }
            if selector.hasPrefix(".") { return classes.contains(String(selector.dropFirst())) }
            if selector.hasPrefix("#") { return id == String(selector.dropFirst()) }
            return false
        }.flatMap(\.declarations)
    }
}
