import CoreGraphics
import Foundation
import HmmDesign
import LoweyCore
import LoweyEngine

/// Model ▸ Bend and Model ▸ Cage (U6): a whole-shape bend with one handle (it animates: keys add themselves like any
/// move), and a box of points around the thing that reshapes it smoothly when a point is dragged.
extension EditorModel {
    // MARK: Bend

    func bend(of object: SceneObject) -> (kind: Deform, amount: Double, axis: CoreAxis)? {
        guard let kind = object[.deform]?.stringValue.flatMap(Deform.init(rawValue:)) else { return nil }
        return (kind, object[.deformAmount]?.floatValue ?? 0, object[.deformAxis]?.stringValue.flatMap(CoreAxis.init(rawValue:)) ?? .y)
    }

    /// Chooses the kind of bend (nil takes it off), starting at an amount that shows.
    func setBend(_ kind: Deform?) {
        guard let object = shapedSelection else { return }
        let changes: [PropertyChange] = if let kind {
            [PropertyChange(object: object.id, key: .deform, value: .enumeration(kind.rawValue)),
             PropertyChange(
                 object: object.id,
                 key: .deformAmount,
                 value: .float(bend(of: object)?.kind == kind ? bend(of: object)?.amount ?? kind.starting : kind.starting)
             )]
        } else {
            [PropertyChange(object: object.id, key: .deform, value: nil), PropertyChange(object: object.id, key: .deformAmount, value: nil),
             PropertyChange(object: object.id, key: .deformAxis, value: nil)]
        }
        perform(.setProperties(changes))
        HmmHaptics.play(.selection)
    }

    func setBendAmount(_ amount: Double, gesture: String? = nil) {
        guard let object = shapedSelection, let current = bend(of: object) else { return }
        let value = min(max(amount, current.kind.range.lowerBound), current.kind.range.upperBound)
        perform(.setProperties([PropertyChange(object: object.id, key: .deformAmount, value: .float(value))]), coalesceKey: gesture)
    }

    func setBendAxis(_ axis: CoreAxis) {
        guard let object = shapedSelection else { return }
        perform(.setProperties([PropertyChange(object: object.id, key: .deformAxis, value: axis == .y ? nil : .enumeration(axis.rawValue))]))
    }

    /// Where the bend's handle sits on screen: past the far end of the thing along its bend axis.
    var bendHandlePoint: CGPoint? {
        guard modeling.verb == .bend, let object = shapedSelection, let current = bend(of: object), let stage,
              let bounds = unshapedBounds(of: object) else { return nil }
        var tip = bounds.center
        tip[current.axis] = bounds.max[current.axis] + bounds.size[current.axis] * 0.15
        return stage.screenPoint(of: scene.worldTransform(of: object.id).apply(to: tip))
    }

    /// The handle dragged by `delta` points since the drag began from `start` (up and right add).
    func dragBendHandle(from start: Double, by delta: CGSize, gesture: String) {
        guard let object = shapedSelection, let current = bend(of: object) else { return }
        let span = current.kind.range.upperBound - current.kind.range.lowerBound
        setBendAmount(start + Double(delta.width - delta.height) * span / 600, gesture: gesture)
    }

    // MARK: Cage

    /// The thing's own box before its strokes, cage and bend.
    func unshapedBounds(of object: SceneObject) -> Bounds? {
        if let mesh = PaintSource.unshaped(of: object) {
            guard let factor = PaintSource.toObjectSpace(of: object), let bounds = mesh.bounds else { return mesh.bounds }
            let scale = Vec3(Double(factor.x), Double(factor.y), Double(factor.z))
            return Bounds(points: [bounds.min.scaled(by: scale), bounds.max.scaled(by: scale)])
        }
        return operations.bounds.localBounds(of: object)
    }

    func addCage(counts: [Int] = [3, 3, 3]) {
        guard let object = shapedSelection, let bounds = unshapedBounds(of: object) else { return }
        var shaping = object.shaping ?? ObjectShaping()
        shaping.cage = DeformCage.around(bounds, counts: counts)
        perform(.setShaping(object.id, shaping))
        HmmHaptics.play(.commit)
    }

    /// The cage off: the thing goes back to its shape without it.
    func removeCage() {
        guard let object = shapedSelection, var shaping = object.shaping, shaping.cage != nil else { return }
        shaping.cage = nil
        perform(.setShaping(object.id, shaping.isEmpty ? nil : shaping))
    }

    /// Every point back where it started.
    func resetCage() {
        guard let object = shapedSelection, var shaping = object.shaping, let cage = shaping.cage else { return }
        shaping.cage = DeformCage(counts: cage.counts, bounds: cage.bounds)
        perform(.setShaping(object.id, shaping))
    }

    /// The cage's points on screen, in order (nil when there's no cage to show).
    var cagePoints: [CGPoint]? {
        guard modeling.verb == .cage, let object = shapedSelection, let cage = object.shaping?.cage, let stage else { return nil }
        let world = scene.worldTransform(of: object.id)
        let points = cage.points.compactMap { stage.screenPoint(of: world.apply(to: $0)) }
        return points.count == cage.points.count ? points : nil
    }

    /// Drags a cage point: across the plane facing you through where it was when the drag began.
    func dragCagePoint(_ index: Int, startOffset: Vec3, from start: CGPoint, to point: CGPoint, gesture: String) {
        guard let object = shapedSelection, var shaping = object.shaping, var cage = shaping.cage, cage.offsets.indices.contains(index),
              let stage, let ray = stage.worldRay(at: point), let first = stage.worldRay(at: start) else { return }
        let world = scene.worldTransform(of: object.id)
        let rest = cage.points[index] - cage.offsets[index] + startOffset
        let facing = GuideSurface.plane(origin: world.apply(to: rest), normal: -ray.direction)
        guard let now = facing.intersect(ray)?.point, let then = facing.intersect(first)?.point else { return }
        var delta = world.inverseApplyDirection(now - then)
        let scale = world.scale
        delta = Vec3(delta.x / max(abs(scale.x), 1e-9), delta.y / max(abs(scale.y), 1e-9), delta.z / max(abs(scale.z), 1e-9))
        cage.offsets[index] = startOffset + delta
        shaping.cage = cage
        perform(.setShaping(object.id, shaping), coalesceKey: gesture)
    }

    /// The cage's lines (world space), for the stage's marks.
    func cageOverlay(width: Double) -> MeshData? {
        guard modeling.verb == .cage, let object = shapedSelection, let cage = object.shaping?.cage else { return nil }
        let world = scene.worldTransform(of: object.id)
        let points = cage.points.map { world.apply(to: $0) }
        var mesh = MeshData()
        let n = cage.counts
        for k in 0 ..< n[2] {
            for j in 0 ..< n[1] {
                for i in 0 ..< n[0] {
                    let here = points[cage.index(i, j, k)]
                    if i + 1 < n[0] { ModelOverlay.line(here, points[cage.index(i + 1, j, k)], width: width, into: &mesh) }
                    if j + 1 < n[1] { ModelOverlay.line(here, points[cage.index(i, j + 1, k)], width: width, into: &mesh) }
                    if k + 1 < n[2] { ModelOverlay.line(here, points[cage.index(i, j, k + 1)], width: width, into: &mesh) }
                }
            }
        }
        return mesh
    }
}
