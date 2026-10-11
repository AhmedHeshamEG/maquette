import CoreGraphics
import Foundation
import HmmDesign
import LoweyCore
import LoweyEngine

/// Sketching talks back (CONTEXT §4.4): drawn with the Pencil, a shape's next point follows the tip, its length and
/// angle float beside it, and it snaps softly (a corner, a middle, a round angle, parallel or perpendicular to a line
/// already drawn) with the snap named on a ghost line and felt in the Pencil. Lifting places the point, as a tap would.
extension EditorModel {
    /// The Pencil pressed down while sketching: the first point lands there, as a tap would.
    func sketchDragBegan(at point: CGPoint) {
        if modeling.pending == nil { sketchTap(at: point) }
        sketchDragMoved(to: point)
    }

    /// The tip moved: where the next point would land, and what it snapped to.
    func sketchDragMoved(to point: CGPoint) {
        guard let kind = modeling.mode.sketchKind, kind != .offset, let pending = modeling.pending, let start = pending.points.last,
              let stage, let ray = stage.worldRay(at: point), let local = Self.hit(ray, on: pending.plane) else { return }
        let reach = stage.worldPerPoint(at: pending.plane.lift(start)) * 12
        let guess = SketchAssist.guess(from: start, to: local, edges: sketchEdges(pending), reach: reach, snapping: snapping.magnet)
        if guess.snap != nil, guess.snap != modeling.guess?.snap {
            HmmHaptics.play(.selection)
            HmmPencilHaptics.snapped(at: point, in: stage)
        }
        modeling.guess = guess
        viewRevision &+= 1
    }

    /// Lifted: the point lands where the guess said (or nowhere, when the gesture was cancelled).
    func sketchDragEnded(commit: Bool) {
        let guess = modeling.guess
        modeling.guess = nil
        guard commit, let guess, let kind = modeling.mode.sketchKind, guess.length > 1e-6 else { return }
        addPoint(guess.point, kind: kind)
    }

    /// The lines already on the shape's plane (and the shape's own), for parallel, perpendicular and middles.
    private func sketchEdges(_ pending: PendingSketch) -> [(Vec2, Vec2)] {
        var edges: [(Vec2, Vec2)] = zip(pending.points, pending.points.dropFirst()).map { ($0, $1) }
        guard let id = pending.sketch, let sketch = sketch(id) else { return edges }
        for curve in sketch.curves {
            switch curve {
            case .line, .rectangle, .polyline:
                let points = curve.points
                edges += zip(points, points.dropFirst()).map { ($0, $1) }
                if curve.isClosed, let first = points.first, let last = points.last { edges.append((last, first)) }
            default:
                continue
            }
        }
        return edges
    }

    static func hit(_ ray: Ray, on plane: PlaneFrame) -> Vec2? {
        let denominator = ray.direction.dot(plane.normal)
        guard abs(denominator) > 1e-9 else { return nil }
        let distance = (plane.origin - ray.origin).dot(plane.normal) / denominator
        guard distance > 0 else { return nil }
        return plane.project(ray.point(at: distance))
    }

    // MARK: On the stage

    /// The shape as it would land, and the ghost line naming the snap.
    func sketchGuessOverlays(_ stage: StageView) -> [EditorOverlay] {
        guard let pending = modeling.pending, let guess = modeling.guess, let kind = modeling.mode.sketchKind,
              let preview = Self.previewCurve(kind, points: pending.points, end: guess.point) else { return [] }
        let width = stage.worldPerPoint(at: pending.plane.lift(guess.point)) * 1.5
        var overlays = [EditorOverlay(mesh: ModelOverlay.sketchLines(Sketch(plane: pending.plane, curves: [preview]), width: width),
                                      color: Self.modelAccent, onTop: true)]
        if guess.ghost.count >= 2 {
            var ghost = MeshData()
            ModelOverlay.line(pending.plane.lift(guess.ghost[0]), pending.plane.lift(guess.ghost[1]), width: width * 0.6, into: &ghost)
            overlays.append(EditorOverlay(mesh: ghost, color: RGBA(0.98, 0.98, 1), opacity: 0.5, onTop: true))
        }
        return overlays
    }

    /// The shape from the points so far to where the tip is.
    static func previewCurve(_ kind: SketchKind, points: [Vec2], end: Vec2) -> SketchCurve? {
        guard let first = points.first, let last = points.last else { return nil }
        switch kind {
        case .rectangle: return .rectangle(first, end)
        case .circle: return .circle(center: first, radius: (end - first).length)
        case .arc: return points.count >= 2 ? .arc(points[0], end, points[1]) : .line(last, end)
        case .line, .spline: return .line(last, end)
        case .offset: return nil
        }
    }

    /// The length and angle beside the tip ("25 cm · 30°"), with the snap's name.
    func sketchReadout(_ stage: StageView) -> DimensionLabel? {
        guard let pending = modeling.pending, let guess = modeling.guess, let screen = stage.screenPoint(of: pending.plane.lift(guess.point)) else {
            return nil
        }
        var text = "\(format(guess.length)) · \(Int(guess.angle.rounded()) % 360)°"
        if let snap = guess.snap {
            if case .angle = snap {} else { text += " · " + String(localized: String.LocalizationValue(snap.label)) }
        }
        return DimensionLabel(field: .sketching, point: CGPoint(x: screen.x + 28, y: screen.y - 34), text: text)
    }
}
