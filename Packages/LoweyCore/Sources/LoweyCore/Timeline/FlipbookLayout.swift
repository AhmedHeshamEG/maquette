import Foundation

/// Where a flipbook track sits in a frame of pixels: the anchor's centre and how many pixels one drawing unit is.
public struct FlipbookAnchorFrame: Hashable, Sendable {
    /// Pixels from the top left.
    public var center: Vec2
    public var pixelsPerUnit: Double

    /// A drawing point (units, y up) in pixels (y down).
    public func pixel(_ point: Vec2) -> Vec2 {
        Vec2(center.x + point.x * pixelsPerUnit, center.y - point.y * pixelsPerUnit)
    }

    /// A pixel back in drawing units.
    public func point(_ pixel: Vec2) -> Vec2 {
        Vec2((pixel.x - center.x) / pixelsPerUnit, (center.y - pixel.y) / pixelsPerUnit)
    }
}

/// A stroke ready to draw: pixels, half-widths in pixels, a resolved colour.
public struct FlipbookPixelStroke: Hashable, Sendable {
    public var points: [Vec2]
    public var widths: [Double]
    public var color: RGBA
    public var filled: Bool
    public var alphas: [Double]
    /// The project brush key (nil = Ink Pen) and the jitter's seed.
    public var brush: String?
    public var seed: UInt64

    public init(points: [Vec2], widths: [Double], color: RGBA, filled: Bool, alphas: [Double]? = nil, brush: String? = nil, seed: UInt64 = 0) {
        self.points = points
        self.widths = widths
        self.color = color
        self.filled = filled
        self.alphas = alphas ?? Array(repeating: 1, count: points.count)
        self.brush = brush
        self.seed = seed
    }

    /// The path the brush engine stamps along.
    public var path: BrushPath<Vec2> { BrushPath(points: points, widths: widths, alphas: alphas) }
}

/// One visible flipbook drawing at a moment.
public struct FlipbookDraw: Hashable, Sendable {
    public var track: String
    public var blend: FlipbookBlend
    public var opacity: Double
    public var strokes: [FlipbookPixelStroke]

    public init(track: String, blend: FlipbookBlend, opacity: Double, strokes: [FlipbookPixelStroke]) {
        self.track = track
        self.blend = blend
        self.opacity = opacity
        self.strokes = strokes
    }

    /// Laid out in another frame of pixels: every point × `scale` + `offset` (the stage's points → its pixels).
    public func scaled(by scale: Double, offset: Vec2 = Vec2(0, 0)) -> FlipbookDraw {
        var draw = self
        draw.strokes = strokes.map { stroke in
            var moved = stroke
            moved.points = stroke.points.map { $0 * scale + offset }
            moved.widths = stroke.widths.map { $0 * scale }
            return moved
        }
        return draw
    }
}

/// Lays out the flipbooks of a moment for a frame of `width` × `height` pixels. `project` maps a world point to
/// normalised device coordinates (−1…1, y up) and its distance in front of the camera (nil behind it).
public struct FlipbookLayout {
    public var width: Double
    public var height: Double
    /// Vertical field of view in degrees.
    public var fieldOfView: Double
    public var project: (Vec3) -> (x: Double, y: Double, depth: Double)?

    public init(width: Double, height: Double, fieldOfView: Double, project: @escaping (Vec3) -> (x: Double, y: Double, depth: Double)?) {
        self.width = width
        self.height = height
        self.fieldOfView = fieldOfView
        self.project = project
    }

    /// A frame seen through a camera at `camera` (vertical field of view in degrees).
    public init(width: Double, height: Double, camera: Transform, fieldOfView: Double) {
        let aspect = width / max(height, 1)
        self.init(width: width, height: height, fieldOfView: fieldOfView) { point in
            guard let ndc = OverlayLayout.project(point, camera: camera, fieldOfView: fieldOfView, aspect: aspect) else { return nil }
            return (ndc.0, ndc.1, -camera.rotation.inverse.act(point - camera.position).z)
        }
    }

    /// The pixel frame of a track's anchor in `scene` (nil when its object is gone or behind the camera, and for a
    /// sheet, which has no single frame: its points go through `pixels(of:in:scene:)` one by one).
    public func anchorFrame(_ track: FlipbookTrack, in scene: Scene) -> FlipbookAnchorFrame? {
        switch track.anchor {
        case .sheet:
            return nil
        case .camera:
            let center = Vec2(width / 2 + track.offset.x * height, height / 2 - track.offset.y * height)
            return FlipbookAnchorFrame(center: center, pixelsPerUnit: height)
        case let .object(id):
            guard scene.objects[id] != nil, let ndc = project(scene.worldTransform(of: id).position), ndc.depth > 1e-3 else { return nil }
            let focal = 1 / tan(min(max(fieldOfView, 1), 170) * .pi / 360)
            let pixelsPerMetre = height / 2 * focal / ndc.depth
            let pivot = Vec2((ndc.x + 1) / 2 * width, (1 - ndc.y) / 2 * height)
            let center = Vec2(pivot.x + track.offset.x * pixelsPerMetre, pivot.y - track.offset.y * pixelsPerMetre)
            return FlipbookAnchorFrame(center: center, pixelsPerUnit: pixelsPerMetre)
        }
    }

    /// Every flipbook drawing visible at `time`, bottom track first.
    public func draws(_ timeline: Timeline, scene: Scene, palette: Palette, at time: Double) -> [FlipbookDraw] {
        timeline.flipbooks.compactMap { track in
            guard track.visible, track.opacity > 0.001,
                  let index = track.frameIndex(at: time, fps: timeline.fps, sceneDuration: timeline.duration) else { return nil }
            let strokes = track.frames[index].strokes.flatMap { pixels(of: $0, in: track, scene: scene, palette: palette) }
            return strokes.isEmpty ? nil : FlipbookDraw(track: track.id, blend: track.blend, opacity: track.opacity, strokes: strokes)
        }
    }

    /// A stroke of a track in pixels. A stroke on a sheet goes through the camera point by point (it keeps its
    /// perspective, and a stretch behind the camera splits it); the others through their anchor's one frame.
    public func pixels(of stroke: FlipStroke, in track: FlipbookTrack, scene: Scene, palette: Palette = Look.default.palette) -> [FlipbookPixelStroke] {
        let color = stroke.color.resolved(in: palette)
        func make(_ points: [Vec2], _ widths: [Double], _ alphas: [Double]?) -> FlipbookPixelStroke {
            FlipbookPixelStroke(points: points, widths: widths, color: color, filled: stroke.filled, alphas: alphas, brush: stroke.brush,
                                seed: stroke.seed ?? 0)
        }
        guard let id = track.anchor.sheet else {
            guard let frame = anchorFrame(track, in: scene) else { return [] }
            return [make(stroke.points.map(frame.pixel), stroke.widths.map { $0 * frame.pixelsPerUnit }, stroke.alphas)]
        }
        guard let sheet = scene.sheet(id) else { return [] }
        var runs: [FlipbookPixelStroke] = []
        var points: [Vec2] = [], widths: [Double] = [], alphas: [Double] = []
        func close() {
            if !points.isEmpty, points.count >= 2 || stroke.points.count == 1 {
                runs.append(make(points, widths, stroke.alphas == nil ? nil : alphas))
            }
            points = []
            widths = []
            alphas = []
        }
        let opacities = stroke.opacities
        for index in stroke.points.indices {
            guard let world = sheet.worldPoint(at: stroke.points[index], in: scene), let pixel = pixel(of: world) else {
                close()
                continue
            }
            points.append(pixel.point)
            widths.append(stroke.widths[index] * pixel.pixelsPerMetre)
            alphas.append(opacities[index])
        }
        close()
        // A filled shape only makes sense whole.
        if stroke.filled, runs.count != 1 || runs.first?.points.count != stroke.points.count { return [] }
        return runs
    }

    /// A world point in pixels, and how many pixels a metre is there (nil behind the camera).
    public func pixel(of world: Vec3) -> (point: Vec2, pixelsPerMetre: Double)? {
        guard let ndc = project(world), ndc.depth > 1e-3 else { return nil }
        let focal = 1 / tan(min(max(fieldOfView, 1), 170) * .pi / 360)
        return (Vec2((ndc.x + 1) / 2 * width, (1 - ndc.y) / 2 * height), height / 2 * focal / ndc.depth)
    }

    /// The outline of a pressure stroke in pixels: left side forward, right side back (a closed polygon). Single points
    /// become a small diamond.
    public static func outline(_ stroke: FlipbookPixelStroke) -> [Vec2] {
        let points = stroke.points
        guard points.count >= 2 else {
            guard let p = points.first else { return [] }
            let r = max(stroke.widths.first ?? 1, 0.5)
            return [Vec2(p.x + r, p.y), Vec2(p.x, p.y + r), Vec2(p.x - r, p.y), Vec2(p.x, p.y - r)]
        }
        var left: [Vec2] = []
        var right: [Vec2] = []
        for index in points.indices {
            let previous = points[max(index - 1, 0)]
            let next = points[min(index + 1, points.count - 1)]
            let direction = next - previous
            let length = max(direction.length, 1e-9)
            let normal = Vec2(-direction.y / length, direction.x / length)
            let width = max(stroke.widths[index], 0.35)
            left.append(points[index] + normal * width)
            right.append(points[index] - normal * width)
        }
        return left + right.reversed()
    }
}
