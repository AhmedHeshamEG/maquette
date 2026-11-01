import Foundation

/// SVG path data (`d`) flattened into polylines: every command (M L H V C S Q T A Z, absolute and relative), curves
/// split until they sit within `tolerance` of the true curve, arcs by the angle that keeps the same error.
struct SVGPathReader {
    private var numbers: PathScanner
    private let tolerance: Double
    private var subpaths: [[VectorPoint]] = []
    private var current: [VectorPoint] = []
    private var point = VectorPoint(0, 0)
    private var start = VectorPoint(0, 0)
    /// The last curve's second control point, for the smooth commands (S, T).
    private var lastControl: VectorPoint?
    private var lastCommand: Character = " "

    init(_ data: String, tolerance: Double) {
        numbers = PathScanner(data)
        self.tolerance = max(tolerance, 1e-6)
    }

    /// Each subpath as a polyline (closed or not; a fill closes them all).
    static func polylines(_ data: String, tolerance: Double) -> [[VectorPoint]] {
        var reader = SVGPathReader(data, tolerance: tolerance)
        reader.read()
        return reader.subpaths
    }

    private mutating func read() {
        var command: Character?
        while let next = numbers.command() ?? command.map(Self.repeated) {
            guard run(next) else { break }
            // A close takes no numbers, so it never repeats.
            command = next == "Z" || next == "z" ? nil : next
        }
        finish()
    }

    /// After a moveto, further pairs are linetos.
    private static func repeated(_ command: Character) -> Character {
        command == "M" ? "L" : command == "m" ? "l" : command
    }

    private mutating func finish() {
        if current.count > 1 { subpaths.append(current) }
        current = []
    }

    /// One command with its numbers; false when the numbers ran out.
    private mutating func run(_ command: Character) -> Bool {
        let relative = command.isLowercase
        let origin = relative ? point : VectorPoint(0, 0)
        switch command.uppercased().first ?? " " {
        case "M":
            guard let target = numbers.point() else { return false }
            finish()
            point = origin + target
            start = point
            current = [point]
        case "L":
            guard let target = numbers.point() else { return false }
            line(to: origin + target)
        case "H":
            guard let x = numbers.number() else { return false }
            line(to: VectorPoint(relative ? point.x + x : x, point.y))
        case "V":
            guard let y = numbers.number() else { return false }
            line(to: VectorPoint(point.x, relative ? point.y + y : y))
        case "C", "S", "Q", "T":
            guard curve(command, origin: origin) else { return false }
        case "A":
            guard arc(origin: origin) else { return false }
        case "Z":
            if let first = current.first, first != point { current.append(first) }
            point = start
            finish()
            current = [point]
            lastCommand = "Z"
            return true
        default:
            return false
        }
        lastCommand = command
        return true
    }

    private mutating func line(to target: VectorPoint) {
        if current.isEmpty { current = [point] }
        current.append(target)
        point = target
        lastControl = nil
    }

    private mutating func curve(_ command: Character, origin: VectorPoint) -> Bool {
        let kind = command.uppercased().first ?? "C"
        let reflected = point * 2 - (lastControl ?? point)
        let cubicBefore = "CcSs".contains(lastCommand)
        let quadBefore = "QqTt".contains(lastCommand)
        if current.isEmpty { current = [point] }
        switch kind {
        case "C":
            guard let c1 = numbers.point(), let c2 = numbers.point(), let end = numbers.point() else { return false }
            cubic(origin + c1, origin + c2, origin + end)
        case "S":
            guard let c2 = numbers.point(), let end = numbers.point() else { return false }
            cubic(cubicBefore ? reflected : point, origin + c2, origin + end)
        case "Q":
            guard let control = numbers.point(), let end = numbers.point() else { return false }
            quadratic(origin + control, origin + end)
        default:
            guard let end = numbers.point() else { return false }
            quadratic(quadBefore ? reflected : point, origin + end)
        }
        return true
    }

    private mutating func quadratic(_ control: VectorPoint, _ end: VectorPoint) {
        let c1 = point + (control - point) * (2.0 / 3)
        let c2 = end + (control - end) * (2.0 / 3)
        cubic(c1, c2, end)
        lastControl = control
    }

    private mutating func cubic(_ c1: VectorPoint, _ c2: VectorPoint, _ end: VectorPoint) {
        current += CurveFlattener.cubic(point, c1, c2, end, tolerance: tolerance)
        point = end
        lastControl = c2
    }

    private mutating func arc(origin: VectorPoint) -> Bool {
        guard let rx = numbers.number(), let ry = numbers.number(), let turn = numbers.number(),
              let large = numbers.flag(), let sweep = numbers.flag(), let target = numbers.point() else { return false }
        let end = origin + target
        if current.isEmpty { current = [point] }
        current += CurveFlattener.arc(from: point, to: end, radii: VectorPoint(abs(rx), abs(ry)), rotation: turn,
                                      large: large, sweep: sweep, tolerance: tolerance)
        point = end
        lastControl = nil
        return true
    }
}

/// Numbers, flags and command letters of path data: `1.5.5` is two numbers, `1e-3` one, `-` starts a new one.
struct PathScanner {
    private let scalars: [Unicode.Scalar]
    private var index = 0

    init(_ text: String) {
        scalars = Array(text.unicodeScalars)
    }

    private mutating func skipSeparators() {
        while index < scalars.count, scalars[index].properties.isWhitespace || scalars[index] == "," {
            index += 1
        }
    }

    /// The next command letter, if one comes before the next number.
    mutating func command() -> Character? {
        skipSeparators()
        guard index < scalars.count, "MmLlHhVvCcSsQqTtAaZz".unicodeScalars.contains(scalars[index]) else { return nil }
        defer { index += 1 }
        return Character(scalars[index])
    }

    /// An arc flag: one digit, which may touch the next number (`a10 10 0 015 5`).
    mutating func flag() -> Bool? {
        skipSeparators()
        guard index < scalars.count, scalars[index] == "0" || scalars[index] == "1" else { return nil }
        defer { index += 1 }
        return scalars[index] == "1"
    }

    mutating func point() -> VectorPoint? {
        guard let x = number(), let y = number() else { return nil }
        return VectorPoint(x, y)
    }

    mutating func number() -> Double? {
        skipSeparators()
        let begin = index
        if index < scalars.count, scalars[index] == "-" || scalars[index] == "+" { index += 1 }
        var seenDot = false
        var seenDigit = false
        while index < scalars.count {
            let scalar = scalars[index]
            if scalar.properties.numericType != nil, scalar.isASCII {
                seenDigit = true
            } else if scalar == ".", !seenDot {
                seenDot = true
            } else {
                break
            }
            index += 1
        }
        guard seenDigit else {
            index = begin
            return nil
        }
        readExponent()
        return Double(String(String.UnicodeScalarView(scalars[begin ..< index])))
    }

    private mutating func readExponent() {
        guard index < scalars.count, scalars[index] == "e" || scalars[index] == "E" else { return }
        var look = index + 1
        if look < scalars.count, scalars[look] == "-" || scalars[look] == "+" { look += 1 }
        guard look < scalars.count, scalars[look].properties.numericType != nil else { return }
        index = look
        while index < scalars.count, scalars[index].properties.numericType != nil, scalars[index].isASCII {
            index += 1
        }
    }
}

/// Curves and arcs into points (the start point left out, the end point included).
enum CurveFlattener {
    static func cubic(_ p0: VectorPoint, _ p1: VectorPoint, _ p2: VectorPoint, _ p3: VectorPoint, tolerance: Double,
                      depth: Int = 0) -> [VectorPoint] {
        // Flat enough when both control points sit within the tolerance of the chord.
        let flatness = max(distance(p1, toLine: p0, p3), distance(p2, toLine: p0, p3))
        if flatness <= tolerance || depth >= 12 { return [p3] }
        let a = (p0 + p1) * 0.5, b = (p1 + p2) * 0.5, c = (p2 + p3) * 0.5
        let ab = (a + b) * 0.5, bc = (b + c) * 0.5
        let middle = (ab + bc) * 0.5
        return cubic(p0, a, ab, middle, tolerance: tolerance, depth: depth + 1)
            + cubic(middle, bc, c, p3, tolerance: tolerance, depth: depth + 1)
    }

    static func distance(_ point: VectorPoint, toLine a: VectorPoint, _ b: VectorPoint) -> Double {
        let dx = b.x - a.x, dy = b.y - a.y
        let length = (dx * dx + dy * dy).squareRoot()
        guard length > 1e-12 else { return point.distance(to: a) }
        return abs((point.x - a.x) * dy - (point.y - a.y) * dx) / length
    }

    /// An elliptical arc in SVG's endpoint form, converted to its centre and swept in steps (SVG 1.1 appendix F.6).
    static func arc(from p0: VectorPoint, to p1: VectorPoint, radii: VectorPoint, rotation degrees: Double, large: Bool, sweep: Bool,
                    tolerance: Double) -> [VectorPoint] {
        guard radii.x > 1e-12, radii.y > 1e-12, p0 != p1 else { return [p1] }
        let phi = degrees * .pi / 180
        let cosPhi = cos(phi), sinPhi = sin(phi)
        let half = (p0 - p1) * 0.5
        let x1 = cosPhi * half.x + sinPhi * half.y
        let y1 = -sinPhi * half.x + cosPhi * half.y
        var rx = radii.x, ry = radii.y
        let scale = (x1 * x1) / (rx * rx) + (y1 * y1) / (ry * ry)
        if scale > 1 {
            rx *= scale.squareRoot()
            ry *= scale.squareRoot()
        }
        let numerator = max(rx * rx * ry * ry - rx * rx * y1 * y1 - ry * ry * x1 * x1, 0)
        let denominator = rx * rx * y1 * y1 + ry * ry * x1 * x1
        let factor = (large == sweep ? -1.0 : 1.0) * (denominator > 0 ? (numerator / denominator).squareRoot() : 0)
        let cx1 = factor * rx * y1 / ry, cy1 = -factor * ry * x1 / rx
        let centre = VectorPoint(cosPhi * cx1 - sinPhi * cy1 + (p0.x + p1.x) / 2, sinPhi * cx1 + cosPhi * cy1 + (p0.y + p1.y) / 2)
        let theta = atan2((y1 - cy1) / ry, (x1 - cx1) / rx)
        var delta = atan2((-y1 - cy1) / ry, (-x1 - cx1) / rx) - theta
        if sweep, delta < 0 { delta += 2 * .pi }
        if !sweep, delta > 0 { delta -= 2 * .pi }
        let radius = max(rx, ry)
        let step = 2 * acos(max(1 - tolerance / radius, -1))
        let count = max(Int((abs(delta) / max(step, 1e-3)).rounded(.up)), 1)
        return (1 ... count).map { index in
            if index == count { return p1 }
            let angle = theta + delta * Double(index) / Double(count)
            let x = rx * cos(angle), y = ry * sin(angle)
            return VectorPoint(centre.x + cosPhi * x - sinPhi * y, centre.y + sinPhi * x + cosPhi * y)
        }
    }
}
