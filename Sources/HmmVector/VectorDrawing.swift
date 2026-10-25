import Foundation

/// A point of a vector drawing, in the drawing's own units (SVG: user units, y pointing down).
public struct VectorPoint: Hashable, Sendable {
    public var x: Double
    public var y: Double

    public init(_ x: Double, _ y: Double) {
        self.x = x
        self.y = y
    }

    static func + (lhs: VectorPoint, rhs: VectorPoint) -> VectorPoint { VectorPoint(lhs.x + rhs.x, lhs.y + rhs.y) }
    static func - (lhs: VectorPoint, rhs: VectorPoint) -> VectorPoint { VectorPoint(lhs.x - rhs.x, lhs.y - rhs.y) }
    static func * (lhs: VectorPoint, rhs: Double) -> VectorPoint { VectorPoint(lhs.x * rhs, lhs.y * rhs) }

    func distance(to other: VectorPoint) -> Double { ((x - other.x) * (x - other.x) + (y - other.y) * (y - other.y)).squareRoot() }
}

/// A colour with straight alpha, each channel 0…1 (sRGB).
public struct VectorColor: Hashable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    public static let black = VectorColor(red: 0, green: 0, blue: 0)

    /// `#rrggbb`, for names and tests.
    public var hex: String {
        let channels = [red, green, blue].map { Int((min(max($0, 0), 1) * 255).rounded()) }
        return "#" + channels.map { String(format: "%02x", $0) }.joined()
    }
}

/// One filled shape: closed contours (outlines and holes, flattened into polylines) and its fill.
public struct VectorShape: Hashable, Sendable {
    public var fill: VectorColor
    public var contours: [[VectorPoint]]
    /// The element's `id`, when it had one.
    public var name: String?

    public init(fill: VectorColor, contours: [[VectorPoint]], name: String? = nil) {
        self.fill = fill
        self.contours = contours
        self.name = name
    }
}

/// What a drawing had that a filled outline can't carry, counted so an app can say what was left out.
public struct VectorSkipped: Hashable, Sendable {
    /// Visible strokes (lines drawn with a pen rather than filled).
    public var strokes = 0
    /// Text not converted to outlines.
    public var texts = 0
    /// Embedded pictures.
    public var images = 0

    public init() {}

    public var isEmpty: Bool { strokes == 0 && texts == 0 && images == 0 }
}

/// A vector drawing as filled shapes, back to front, in its own units (y down), with its bounds.
public struct VectorDrawing: Sendable {
    public var shapes: [VectorShape]
    public var skipped: VectorSkipped

    public init(shapes: [VectorShape], skipped: VectorSkipped = VectorSkipped()) {
        self.shapes = shapes
        self.skipped = skipped
    }

    /// The box around every contour point (nil without shapes).
    public var bounds: (min: VectorPoint, max: VectorPoint)? {
        let points = shapes.flatMap { $0.contours.flatMap(\.self) }
        guard let first = points.first else { return nil }
        var low = first
        var high = first
        for point in points {
            low = VectorPoint(min(low.x, point.x), min(low.y, point.y))
            high = VectorPoint(max(high.x, point.x), max(high.y, point.y))
        }
        return (low, high)
    }

    /// The fills used, in the order they first appear.
    public var colors: [VectorColor] {
        var seen: [VectorColor] = []
        for shape in shapes where !seen.contains(shape.fill) {
            seen.append(shape.fill)
        }
        return seen
    }
}
