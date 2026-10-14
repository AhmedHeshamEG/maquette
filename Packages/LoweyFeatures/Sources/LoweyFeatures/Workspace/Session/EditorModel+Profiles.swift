import CoreGraphics
import Foundation
import HmmDesign
import LoweyCore
import LoweyEngine

/// Solids from a drawn profile (sweep, revolve, loft: the region's chip asks for one more tap) and a sketch's rules
/// (U6): tap a line or a circle, then a second, and the chip offers what can hold between them; a size's lock keeps it.
extension EditorModel {
    // MARK: Sweep, revolve, loft

    func startSweep() { waitForProfile(.sweep) }
    func startRevolve() { waitForProfile(.revolve) }
    func startLoft() { waitForProfile(.loft) }

    private enum ProfileKind { case sweep, revolve, loft }

    private func waitForProfile(_ kind: ProfileKind) {
        guard let region = modeling.region else { return }
        let wait: ProfileWait = switch kind {
        case .sweep: .sweep(region)
        case .revolve: .revolve(region)
        case .loft: .loft([region])
        }
        modeling.awaiting = wait
        app.show(String.LocalizationValue(wait.hint))
        HmmHaptics.play(.selection)
    }

    /// A tap while a profile waits: the path, the axis or the next profile. True when the tap was used.
    func profileTap(at point: CGPoint) -> Bool {
        guard let wait = modeling.awaiting else { return false }
        switch wait {
        case let .sweep(region):
            guard let curve = sketchCurve(at: point), let path = sketch(curve.sketch)?.path(of: curve.index) else { return true }
            makeProfileSolid(sweeping: region, along: path.points, closed: path.closed)
        case let .revolve(region):
            guard let curve = sketchCurve(at: point), let sketch = sketch(curve.sketch), case let .line(a, b) = sketch.curves[curve.index] else {
                app.show("Tap a straight line to turn around")
                return true
            }
            revolve(region, axisPoint: sketch.plane.lift(a), direction: sketch.plane.lift(b) - sketch.plane.lift(a))
        case let .loft(regions):
            guard let next = sketchRegion(at: point), !regions.contains(next) else { return true }
            modeling.awaiting = .loft(regions + [next])
            HmmHaptics.play(.selection)
        }
        return true
    }

    /// Lofts through the regions picked so far.
    func finishLoft() {
        guard case let .loft(regions) = modeling.awaiting, regions.count >= 2 else {
            app.show("Tap one more closed shape to loft through")
            return
        }
        var ids = operations.ids
        let done = runModeling { try ModelingOperations.loft(regions.map { ($0.sketch, $0.index) }, in: baseScene, ids: &ids) }
        operations.ids = ids
        if done { finishProfile() }
    }

    /// Revolves around the region's own left side, upright on its sketch (no line needed).
    func revolveAroundSide() {
        guard case let .revolve(region) = modeling.awaiting, let sketch = sketch(region.sketch),
              let shape = sketch.regions[safe: region.index], let left = shape.outline.min(by: { $0.x < $1.x }) else { return }
        revolve(region, axisPoint: sketch.plane.lift(Vec2(left.x, 0)), direction: sketch.plane.v)
    }

    private func revolve(_ region: SketchRegionRef, axisPoint: Vec3, direction: Vec3) {
        var ids = operations.ids
        let done = runModeling {
            try ModelingOperations.revolve(sketch: region.sketch, region: region.index, axisPoint: axisPoint, axisDirection: direction,
                                           degrees: 360, in: baseScene, ids: &ids)
        }
        operations.ids = ids
        if done { finishProfile() }
    }

    private func makeProfileSolid(sweeping region: SketchRegionRef, along path: [Vec3], closed: Bool) {
        var ids = operations.ids
        let done = runModeling {
            try ModelingOperations.sweep(sketch: region.sketch, region: region.index, along: path, closed: closed, in: baseScene, ids: &ids)
        }
        operations.ids = ids
        if done { finishProfile() }
    }

    private func finishProfile() {
        modeling.awaiting = nil
        modeling.region = nil
        modeling.lastCurve = nil
        refreshModelOverlay()
    }

    // MARK: Rules

    /// The sketch curve nearest a screen point (within 16 points).
    func sketchCurve(at point: CGPoint) -> SketchCurveRef? {
        guard let stage else { return nil }
        var best: (ref: SketchCurveRef, distance: CGFloat)?
        for (id, sketch) in sketches {
            for (index, curve) in sketch.curves.enumerated() {
                let screen = curve.points.compactMap { stage.screenPoint(of: sketch.plane.lift($0)) }
                let distance = Self.distance(from: point, toPolyline: screen, closed: curve.isClosed)
                if distance < (best?.distance ?? 16) { best = (SketchCurveRef(sketch: id, index: index), distance) }
            }
        }
        return best?.ref
    }

    /// A tap on a sketch's line or circle picks it for its rules (a second one on the same sketch pairs with it).
    @discardableResult
    func pickRuleCurve(at point: CGPoint) -> Bool {
        guard let curve = sketchCurve(at: point) else { return false }
        if let first = modeling.ruleCurves.first, first.sketch == curve.sketch, first != curve, modeling.ruleCurves.count == 1 {
            modeling.ruleCurves.append(curve)
        } else {
            modeling.ruleCurves = [curve]
            modeling.lastCurve = curve
        }
        modeling.region = nil
        HmmHaptics.play(.selection)
        refreshModelOverlay()
        return true
    }

    /// The rules the picked curves can take, in the chip's order.
    var availableRules: [SketchRule] {
        guard let sketch = modeling.ruleCurves.first.flatMap({ sketch($0.sketch) }) else { return [] }
        let curves = modeling.ruleCurves.compactMap { sketch.curves[safe: $0.index] }
        switch curves.count {
        case 1: return curves[0].isLine ? [.lockLength, .lockAngle, .horizontal] : (curves[0].isRound ? [.lockLength] : [])
        case 2:
            if curves.allSatisfy(\.isLine) { return [.parallel, .perpendicular, .equal, .twice] }
            if curves.contains(where: \.isLine), curves.contains(where: \.isRound) { return [.tangent] }
            return curves.allSatisfy(\.isRound) ? [.equal, .twice] : []
        default: return []
        }
    }

    func applyRule(_ rule: SketchRule) {
        guard let first = modeling.ruleCurves.first, let sketch = sketch(first.sketch) else { return }
        let indices = modeling.ruleCurves.map(\.index)
        guard let constraint = rule.constraint(indices, in: sketch) else { return }
        do {
            let solved = try sketch.constraining(constraint)
            perform(.batch(rule.title, [.setKind(first.sketch, .sketch(solved))]))
            HmmHaptics.play(.commit)
            modeling.ruleCurves = []
        } catch {
            app.show(String.LocalizationValue(String(describing: error)), kind: .error)
            HmmHaptics.play(.error)
        }
    }

    /// Whether a size of the shape just drawn is locked (a lock beside its number).
    func isLocked(_ field: DimensionField) -> Bool {
        guard let ref = modeling.lastCurve, let sketch = sketch(ref.sketch) else { return false }
        return sketch.constraints.contains { constraint in
            if case let .length(index, _, side) = constraint { return index == ref.index && side == Self.side(of: field) }
            return false
        }
    }

    /// Locks a size at its value now, or unlocks it.
    func toggleLock(_ field: DimensionField) {
        guard let ref = modeling.lastCurve, var sketch = sketch(ref.sketch), let value = dimensionValue(field) else { return }
        let side = Self.side(of: field)
        if isLocked(field) {
            sketch.constraints.removeAll {
                if case let .length(index, _, s) = $0 {
                    index == ref.index && s == side
                } else { false }
            }
        } else {
            sketch.constraints.append(.length(ref.index, value, side: side))
        }
        perform(.batch("Lock", [.setKind(ref.sketch, .sketch(sketch))]))
        HmmHaptics.play(.selection)
    }

    static func side(of field: DimensionField) -> Int {
        if case .rectangleSide(false) = field { return 1 }
        return 0
    }
}

/// What two picked sketch curves (or one) can keep.
enum SketchRule: String, CaseIterable, Identifiable, Sendable {
    case lockLength, lockAngle, horizontal, parallel, perpendicular, equal, tangent, twice

    var id: String { rawValue }

    var title: String {
        switch self {
        case .lockLength: "Lock its size"
        case .lockAngle: "Lock its angle"
        case .horizontal: "Level"
        case .parallel: "Parallel"
        case .perpendicular: "Square"
        case .equal: "Same size"
        case .tangent: "Touching"
        case .twice: "Twice that"
        }
    }

    var systemImage: String {
        switch self {
        case .lockLength: "lock"
        case .lockAngle: "angle"
        case .horizontal: "level"
        case .parallel: "equal"
        case .perpendicular: "square"
        case .equal: "equal.square"
        case .tangent: "circle.and.line.horizontal"
        case .twice: "multiply"
        }
    }

    /// The rule for curves at these places in the sketch (nil when it can't be measured).
    func constraint(_ curves: [Int], in sketch: Sketch) -> SketchConstraint? {
        guard let first = curves.first, let curve = sketch.curves[safe: first] else { return nil }
        switch self {
        case .lockLength: return curve.size.map { .length(first, $0) }
        case .lockAngle: return curve.angle.map { .angle(first, $0) }
        case .horizontal: return .angle(first, 0)
        case .parallel: return curves.count == 2 ? .parallel(curves[0], curves[1]) : nil
        case .perpendicular: return curves.count == 2 ? .perpendicular(curves[0], curves[1]) : nil
        case .equal: return curves.count == 2 ? .equal(curves[0], curves[1]) : nil
        case .twice: return curves.count == 2 ? .ratio(curves[0], curves[1], factor: 2) : nil
        case .tangent:
            guard curves.count == 2, let line = curves.first(where: { sketch.curves[safe: $0]?.isLine == true }),
                  let round = curves.first(where: { sketch.curves[safe: $0]?.isRound == true }) else { return nil }
            return .tangent(line: line, circle: round)
        }
    }
}

extension SketchCurve {
    var isLine: Bool {
        if case .line = self { return true }
        return false
    }

    var isRound: Bool {
        switch self {
        case .circle, .arc: true
        default: false
        }
    }

    /// A line's length, a circle's diameter, a rectangle's width.
    var size: Double? {
        switch self {
        case let .line(a, b): (b - a).length
        case let .circle(_, radius): radius * 2
        case let .rectangle(a, b): abs(b.x - a.x)
        default: nil
        }
    }

    /// A line's angle from the sketch's first axis (degrees).
    var angle: Double? {
        guard case let .line(a, b) = self else { return nil }
        return atan2(b.y - a.y, b.x - a.x) * 180 / .pi
    }
}
