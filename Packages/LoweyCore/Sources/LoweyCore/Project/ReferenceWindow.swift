import Foundation

/// The Reference window (Q1, made like Procreate's Actions ▸ Canvas ▸ Reference): one floating window over the stage,
/// kept per project in `workspace.json`. It shows the whole scene from its own camera (Canvas), a picture (Image) or
/// the front camera (Face). Reopened, it comes back where and as big as it was.
public struct ReferenceWindow: Codable, Hashable, Sendable {
    public enum Mode: String, Codable, CaseIterable, Identifiable, Sendable {
        /// The whole scene, live, from the window's own fixed camera.
        case canvas
        /// A picture from Photos, Files or the clipboard, panned and zoomed inside the window.
        case image
        /// The front camera, for drawing expressions.
        case face

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .canvas: "Canvas"
            case .image: "Image"
            case .face: "Face"
            }
        }

        public var systemImage: String {
            switch self {
            case .canvas: "cube"
            case .image: "photo"
            case .face: "face.smiling"
            }
        }
    }

    public var open: Bool
    public var mode: Mode
    /// The window's middle, as fractions of the stage's width and height.
    public var x: Double
    public var y: Double
    /// What it shows, in points (the bar above it is extra). Content keeps its own shape inside: never stretched.
    public var width: Double
    public var height: Double
    /// Image: the picture's file in the project's assets (`references/<hash>.png`) and its height over its width.
    public var image: String?
    public var imageAspect: Double?
    /// Image: 1 fits the whole picture in the window; more zooms in about the window's middle.
    public var zoom: Double
    /// Image: how far the picture's middle sits from the window's middle, as fractions of the window's width and height.
    public var panX: Double
    public var panY: Double
    /// Canvas: its own camera. Nil frames the whole scene from the front three-quarter view.
    public var view: Viewpoint?

    public static let widthRange = 160.0 ... 900.0
    public static let heightRange = 120.0 ... 900.0
    public static let zoomRange = 1.0 ... 12.0
    /// The bar above the content (grab, modes, close), in points.
    public static let barHeight = 44.0
    /// How far it keeps from the stage's edges and from the clusters, in points.
    public static let margin = 12.0

    public init(open: Bool = false, mode: Mode = .canvas, x: Double = 0.8, y: Double = 0.34, width: Double = 320, height: Double = 240,
                image: String? = nil, imageAspect: Double? = nil, zoom: Double = 1, panX: Double = 0, panY: Double = 0, view: Viewpoint? = nil) {
        self.open = open
        self.mode = mode
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.image = image
        self.imageAspect = imageAspect
        self.zoom = zoom
        self.panX = panX
        self.panY = panY
        self.view = view
        self = clamped
    }

    private enum CodingKeys: String, CodingKey {
        case open, mode, x, y, width, height, image, imageAspect, zoom, panX, panY, view
    }

    /// Missing or damaged values fall back to the defaults, and everything is brought back in range.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let base = ReferenceWindow()
        self.init(open: (try? container.decodeIfPresent(Bool.self, forKey: .open)) ?? base.open,
                  mode: (try? container.decodeIfPresent(Mode.self, forKey: .mode)) ?? base.mode,
                  x: (try? container.decodeIfPresent(Double.self, forKey: .x)) ?? base.x,
                  y: (try? container.decodeIfPresent(Double.self, forKey: .y)) ?? base.y,
                  width: (try? container.decodeIfPresent(Double.self, forKey: .width)) ?? base.width,
                  height: (try? container.decodeIfPresent(Double.self, forKey: .height)) ?? base.height,
                  image: try? container.decodeIfPresent(String.self, forKey: .image),
                  imageAspect: try? container.decodeIfPresent(Double.self, forKey: .imageAspect),
                  zoom: (try? container.decodeIfPresent(Double.self, forKey: .zoom)) ?? base.zoom,
                  panX: (try? container.decodeIfPresent(Double.self, forKey: .panX)) ?? base.panX,
                  panY: (try? container.decodeIfPresent(Double.self, forKey: .panY)) ?? base.panY,
                  view: try? container.decodeIfPresent(Viewpoint.self, forKey: .view))
    }

    /// Inside the stage, a size a hand can hold, a zoom that shows something.
    public var clamped: ReferenceWindow {
        var window = self
        window.x = Self.finite(x, or: 0.8, in: 0 ... 1)
        window.y = Self.finite(y, or: 0.34, in: 0 ... 1)
        window.width = Self.finite(width, or: 320, in: Self.widthRange)
        window.height = Self.finite(height, or: 240, in: Self.heightRange)
        window.imageAspect = imageAspect.map { Self.finite($0, or: 1, in: 0.05 ... 20) }
        window.zoom = Self.finite(zoom, or: 1, in: Self.zoomRange)
        let limit = Self.panLimit(zoom: window.zoom)
        window.panX = Self.finite(panX, or: 0, in: -limit ... limit)
        window.panY = Self.finite(panY, or: 0, in: -limit ... limit)
        if image == nil {
            window.imageAspect = nil
            window.zoom = 1
            window.panX = 0
            window.panY = 0
        }
        return window
    }

    private static func finite(_ value: Double, or fallback: Double, in range: ClosedRange<Double>) -> Double {
        value.isFinite ? min(max(value, range.lowerBound), range.upperBound) : fallback
    }

    /// How far the picture's middle may move from the window's middle: at 1× not at all past half the window, so some of
    /// the picture always shows.
    static func panLimit(zoom: Double) -> Double {
        max(zoom, 1) / 2
    }

    /// The whole window on screen (bar included), in the stage's points.
    public func frame(in stage: CGSize) -> CGRect {
        let outer = CGSize(width: width, height: height + Self.barHeight)
        return CGRect(x: x * stage.width - outer.width / 2, y: y * stage.height - outer.height / 2, width: outer.width, height: outer.height)
    }
}

// MARK: Where it settles

public extension ReferenceWindow {
    /// The window let go with its middle at `center` (stage points): it keeps `margin` from the stage's edges and
    /// moves off the clusters by the shortest way out, so it never covers them. Too big to fit, it's made smaller.
    func settled(at center: CGPoint, in stage: CGSize, avoiding clusters: [CGRect] = []) -> ReferenceWindow {
        var window = self
        let margin = Self.margin
        let room = CGSize(width: max(stage.width - margin * 2, 1), height: max(stage.height - margin * 2, 1))
        window.width = min(window.width, max(room.width, Self.widthRange.lowerBound))
        window.height = min(window.height, max(room.height - Self.barHeight, Self.heightRange.lowerBound))
        let outer = CGSize(width: window.width, height: window.height + Self.barHeight)
        var rect = CGRect(x: center.x - outer.width / 2, y: center.y - outer.height / 2, width: outer.width, height: outer.height)
        rect = Self.inside(rect, stage: stage, margin: margin)
        for _ in 0 ..< 3 {
            var moved = false
            for cluster in clusters {
                let keep = cluster.insetBy(dx: -margin, dy: -margin)
                guard rect.intersects(keep) else { continue }
                rect = Self.out(of: keep, rect: rect, stage: stage, margin: margin)
                moved = true
            }
            if !moved { break }
        }
        window.x = stage.width > 0 ? rect.midX / stage.width : 0.5
        window.y = stage.height > 0 ? rect.midY / stage.height : 0.5
        return window.clamped
    }

    /// The same window as big as asked (a corner drag or a pinch on the bar), still inside the stage.
    func sized(width: Double, height: Double, in stage: CGSize, avoiding clusters: [CGRect] = []) -> ReferenceWindow {
        var window = self
        window.width = width
        window.height = height
        window = window.clamped
        let frame = frame(in: stage)
        // A corner drag grows it from its top-left corner, which stays where it was.
        let center = CGPoint(x: frame.minX + window.width / 2, y: frame.minY + (window.height + Self.barHeight) / 2)
        return window.settled(at: center, in: stage, avoiding: clusters)
    }

    private static func inside(_ rect: CGRect, stage: CGSize, margin: Double) -> CGRect {
        var rect = rect
        rect.origin.x = min(max(rect.minX, margin), max(stage.width - margin - rect.width, margin))
        rect.origin.y = min(max(rect.minY, margin), max(stage.height - margin - rect.height, margin))
        return rect
    }

    /// The shortest move that takes `rect` off `keep` and still fits on the stage (tried in order of distance).
    private static func out(of keep: CGRect, rect: CGRect, stage: CGSize, margin: Double) -> CGRect {
        let moves = [
            CGPoint(x: keep.maxX - rect.minX, y: 0), CGPoint(x: keep.minX - rect.maxX, y: 0),
            CGPoint(x: 0, y: keep.maxY - rect.minY), CGPoint(x: 0, y: keep.minY - rect.maxY)
        ].sorted { abs($0.x) + abs($0.y) < abs($1.x) + abs($1.y) }
        for move in moves {
            let moved = rect.offsetBy(dx: move.x, dy: move.y)
            if moved.minX >= margin - 0.5, moved.maxX <= stage.width - margin + 0.5, moved.minY >= margin - 0.5,
               moved.maxY <= stage.height - margin + 0.5 {
                return moved
            }
        }
        return rect
    }
}

// MARK: The picture inside

public extension ReferenceWindow {
    /// Where the picture is drawn inside the window's content (points, from its top-left): fitted whole at 1×, the
    /// picture's own shape, zoomed about the middle and moved by the pan.
    func pictureRect() -> CGRect? {
        guard let aspect = imageAspect, image != nil else { return nil }
        let fit = min(width, height / aspect)
        let size = CGSize(width: fit * zoom, height: fit * aspect * zoom)
        let middle = CGPoint(x: width / 2 + panX * width, y: height / 2 + panY * height)
        return CGRect(x: middle.x - size.width / 2, y: middle.y - size.height / 2, width: size.width, height: size.height)
    }

    /// The point in the picture under a point of the window's content, 0…1 across and down (nil off the picture).
    func picturePoint(at point: CGPoint) -> CGPoint? {
        guard let rect = pictureRect(), rect.width > 0, rect.height > 0, rect.contains(point) else { return nil }
        return CGPoint(x: (point.x - rect.minX) / rect.width, y: (point.y - rect.minY) / rect.height)
    }

    /// One finger moved the picture by a drag in points.
    func panned(by drag: CGSize) -> ReferenceWindow {
        var window = self
        window.panX += drag.width / max(width, 1)
        window.panY += drag.height / max(height, 1)
        return window.clamped
    }

    /// Two fingers zoomed by `scale` about `focus` (a point of the window's content): the picture under the fingers
    /// stays under them.
    func zoomed(by scale: Double, about focus: CGPoint) -> ReferenceWindow {
        guard scale.isFinite, scale > 0 else { return self }
        var window = self
        window.zoom = min(max(zoom * scale, Self.zoomRange.lowerBound), Self.zoomRange.upperBound)
        let applied = window.zoom / zoom
        let middle = CGPoint(x: width / 2 + panX * width, y: height / 2 + panY * height)
        let next = CGPoint(x: focus.x + (middle.x - focus.x) * applied, y: focus.y + (middle.y - focus.y) * applied)
        window.panX = (next.x - width / 2) / max(width, 1)
        window.panY = (next.y - height / 2) / max(height, 1)
        return window.clamped
    }

    /// A new picture: fitted whole again.
    func showing(image file: String, aspect: Double) -> ReferenceWindow {
        var window = self
        window.image = file
        window.imageAspect = aspect
        window.zoom = 1
        window.panX = 0
        window.panY = 0
        window.mode = .image
        window.open = true
        return window.clamped
    }

    /// Clear: the picture is gone (its file stays in the project, like any media).
    var cleared: ReferenceWindow {
        var window = self
        window.image = nil
        return window.clamped
    }
}

// MARK: Canvas

public extension ReferenceWindow {
    /// The camera that shows all of `bounds` from `angle`'s side (yaw and pitch kept), nil bounds the default view.
    static func canvasView(framing bounds: Bounds?, from angle: Viewpoint = Viewpoint(), aspect: Double) -> Viewpoint {
        var view = angle
        view.projection = .perspective
        guard let bounds else {
            view.target = Viewpoint().target
            view.distance = Viewpoint().distance
            return view
        }
        view.target = bounds.center
        let radius = max(bounds.size.length / 2, 0.01)
        // The narrower of the two fields of view decides: a tall window still shows the whole width.
        let vertical = view.fieldOfView * .pi / 180
        let horizontal = 2 * atan(tan(vertical / 2) * max(aspect, 0.05))
        view.distance = radius / sin(min(vertical, horizontal) / 2) * 1.08
        return view
    }
}

// MARK: Older projects

public extension ReferenceWindow {
    /// Before 0.27 the window was a card opened from Actions (`ReferenceCard.window`); the newest open one becomes
    /// the window's picture, the rest stay floating cards.
    static func migrating(_ cards: [ReferenceCard]) -> (window: ReferenceWindow?, cards: [ReferenceCard]) {
        guard let index = cards.lastIndex(where: \.isWindow) else { return (nil, cards) }
        let card = cards[index]
        var window = ReferenceWindow(open: !card.isFolded, mode: .image, x: card.x, y: card.y, width: card.width,
                                     height: card.width * card.aspect, image: card.image, imageAspect: card.aspect)
        window = window.clamped
        var rest = cards
        rest.remove(at: index)
        return (window, rest)
    }
}
