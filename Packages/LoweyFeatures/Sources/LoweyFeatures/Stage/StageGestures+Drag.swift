import HmmDesign
import LoweyCore
import LoweyEngine
import UIKit

/// One finger: orbit, or (decided where it lands) move the selection, a gizmo handle, a rotate ring, a lasso, a
/// scatter area, a performance, the Director view's camera or an overlay in the frame.
extension StageGestures {
    @objc func handleOneFingerPan(_ recognizer: UIPanGestureRecognizer) {
        guard let editor, let stage else { return }
        let point = recognizer.location(in: stage)
        switch recognizer.state {
        case .began:
            gestureKey = UUID().uuidString
            panStart = (stage.viewpoint, CACurrentMediaTime())
            editor.showChrome()
            let translation = recognizer.translation(in: stage)
            lastFramed = nil
            drag = beginDrag(at: CGPoint(x: point.x - translation.x, y: point.y - translation.y), editor: editor, stage: stage)
            // Moving the view is always the fingers' (CONTEXT §10.10): a Pencil drag that does nothing else does nothing.
            if panTouchIsPencil, case .orbit = drag { drag = .none }
            continueDrag(to: point, translation: translation, editor: editor, stage: stage)
            panTravel = translation
            recognizer.setTranslation(.zero, in: stage)
        case .changed:
            let translation = recognizer.translation(in: stage)
            continueDrag(to: point, translation: translation, editor: editor, stage: stage)
            panTravel = CGPoint(x: panTravel.x + translation.x, y: panTravel.y + translation.y)
            recognizer.setTranslation(.zero, in: stage)
        case .ended, .cancelled, .failed:
            if recognizer.state == .ended, case .orbit = drag, flickedFrame(recognizer, editor: editor, stage: stage) {
                drag = .none
                return
            }
            endDrag(editor: editor, stage: stage, cancelled: recognizer.state != .ended)
            drag = .none
        default:
            break
        }
    }

    // MARK: Press and carry

    /// A thing carried by a finger (U5, CONTEXT §10.11): it lifts a little (its shadow shows the gap), slides over the
    /// surface under it and sits on it when the finger lifts. The other things' surfaces are read once, as it starts.
    private func beginCarry(editor: EditorModel, stage: StageView) {
        let moving = Set(editor.selection.flatMap { id in [id] + editor.scene.orderedIDs().filter { editor.scene.isAncestor(id, of: $0) } })
        guard let bounds = stage.visualBounds(of: editor.selection) else {
            carry = nil
            return
        }
        let surfaces = editor.scene.orderedIDs().filter { !moving.contains($0) && editor.scene.isEffectivelyVisible($0) }.compactMap(stage.worldMesh(of:))
        let lift = max(bounds.size.y * 0.06, 0.01)
        carry = Carry(surfaces: surfaces, bottom: bounds.min.y, lift: lift, centre: Vec2(bounds.center.x, bounds.center.z), reach: max(bounds.size.y, 0.5))
        editor.translateSelection(by: Vec3(0, lift, 0), gesture: gestureKey)
        carry?.bottom += lift
        HmmHaptics.play(.selection)
    }

    /// How far up or down the carried thing goes as it moves by `delta` across: onto the highest surface under its
    /// middle (or the ground), lifted.
    private func carryRise(movedBy delta: Vec3, editor: EditorModel) -> Double {
        guard var state = carry else { return 0 }
        state.centre = Vec2(state.centre.x + delta.x, state.centre.y + delta.z)
        // It climbs onto anything up to its own height under its middle, else it stays on what it was on.
        let landing = GroundDrop.rise(lowest: [Vec3(state.centre.x, 0, state.centre.y)], top: state.bottom + state.reach, surfaces: state.surfaces)
        let target = landing + state.lift
        let rise = target - state.bottom
        if abs(rise) > state.lift, let stage { HmmPencilHaptics.snapped(at: stage.center, in: stage) }
        state.bottom += rise
        carry = state
        return rise
    }

    /// While frames are drawn, a finger's flick turns the frame instead of the view (the turn it began is put back).
    private func flickedFrame(_ recognizer: UIPanGestureRecognizer, editor: EditorModel, stage: StageView) -> Bool {
        guard editor.tool == .flipbook, !panTouchIsPencil, let start = panStart else { return false }
        let travel = recognizer.translation(in: stage)
        let total = CGPoint(x: travel.x + panTravel.x, y: travel.y + panTravel.y)
        guard let flick = Flick.read(dx: Double(total.x), dy: Double(total.y), duration: CACurrentMediaTime() - start.time) else { return false }
        stage.setViewpoint(start.viewpoint)
        editor.flickFlipbook(flick)
        return true
    }

    private func groundHit(at point: CGPoint, planeY: Double, stage: StageView) -> Vec3? {
        guard let ray = stage.worldRay(at: point) else { return nil }
        return GuideSurface.plane(origin: Vec3(0, planeY, 0), normal: .unitY).intersect(ray)?.point
    }

    private func beginDrag(at point: CGPoint, editor: EditorModel, stage: StageView) -> DragKind {
        if editor.performPhase.isArmed, editor.tool == .select, !operatesCamera, let handle = editor.ikHandle(at: point) {
            editor.beginPerformTime()
            editor.chooseJoint(of: handle)
            return .ik(handle)
        }
        if isRecordingPerform {
            let planeY = editor.selectionPivot?.y ?? 0
            editor.performTouchBegan([.position])
            return .perform(planeY: planeY, last: groundHit(at: point, planeY: planeY, stage: stage) ?? .zero)
        }
        if let overlay = editor.selectedOverlay, editor.overlayHit(at: point) == overlay { return .moveOverlay(overlay, last: point) }
        if operatesCamera { return .aimCamera }
        switch editor.tool {
        case .lasso:
            editor.lassoPoints = [point]
            return .lasso
        case .scatter:
            guard !editor.selection.isEmpty, let center = stage.groundPoint(at: point) else { return .orbit }
            editor.scatterPreview = (point, 0)
            return .scatter(center: center)
        case .ink, .draw, .shadowBrush, .flipbook, .paint, .rig:
            return .orbit
        case .model:
            return beginModelDrag(at: point, editor: editor)
        case .select:
            return beginSelectDrag(at: point, editor: editor, stage: stage)
        }
    }

    private func beginSelectDrag(at point: CGPoint, editor: EditorModel, stage: StageView) -> DragKind {
        guard !editor.directorView, InputJob.move.allows(pencil: panTouchIsPencil, fingerMakes: pencilOrHand.fingerMakes) else { return .orbit }
        if let handle = editor.ikHandle(at: point) {
            editor.chooseJoint(of: handle)
            return .ik(handle)
        }
        if let time = editor.motionPathKey(at: point) {
            editor.setTime(time)
            return .pathKey(time: time)
        }
        if editor.gizmoMode == .rotate, let (axis, grab) = stage.pickRotationRing(at: point), let pivot = editor.rotationPivot,
           let ring = ringDrag(axis: axis, pivot: pivot, grab: grab, start: point, stage: stage) {
            return .turn(ring)
        }
        if editor.gizmoMode != .rotate, let handle = stage.pickGizmo(at: point), let pivot = editor.selectionPivot {
            return .gizmo(handle, pivot: pivot, lastPoint: point, accumulated: 0)
        }
        if panTouchIsPencil, InputJob.shape.allows(pencil: true, fingerMakes: false), let part = editor.beginPartDrag(at: point) {
            return .part(part)
        }
        if let (id, hit) = stage.pickObject(at: point), editor.selection.contains(where: { $0 == id || editor.scene.isAncestor($0, of: id) }),
           !editor.selection.contains(where: { editor.scene.isEffectivelyLocked($0) }) {
            let planeY = editor.selectionPivot?.y ?? hit.point.y
            beginCarry(editor: editor, stage: stage)
            return .moveObjects(planeY: planeY, last: groundHit(at: point, planeY: planeY, stage: stage) ?? hit.point)
        }
        return .orbit
    }

    private func continueDrag(to point: CGPoint, translation: CGPoint, editor: EditorModel, stage: StageView) {
        switch drag {
        case .orbit:
            var viewpoint = stage.viewpoint
            // One rate for every tool (U5, K1 0.1): half a turn across the screen's long side, on any iPad.
            let degreesPerPoint = editor.orbitDegreesPerPoint
            viewpoint.yaw -= Double(translation.x) * degreesPerPoint
            viewpoint.pitch += Double(translation.y) * degreesPerPoint
            stage.setViewpoint(viewpoint)
        case let .moveObjects(planeY, last):
            guard let hit = groundHit(at: point, planeY: planeY, stage: stage) else { return }
            var delta = hit - last
            delta.y = 0
            // Rays near the horizon jump huge distances: ignore them.
            guard delta.length <= 20 else { return }
            delta.y = carryRise(movedBy: delta, editor: editor)
            editor.translateSelection(by: delta, gesture: gestureKey)
            drag = .moveObjects(planeY: planeY, last: hit)
        case let .gizmo(handle, pivot, lastPoint, accumulated):
            continueGizmo(handle, pivot: pivot, from: lastPoint, to: point, accumulated: accumulated, editor: editor, stage: stage)
        case var .turn(ring):
            ring.total = ringAngle(ring, at: point, stage: stage)
            let step = editor.snapping.rotation ? editor.snapping.rotationStep * .pi / 180 : 0
            let wanted = step > 0 ? (ring.total / step).rounded() * step : ring.total
            if abs(wanted - ring.applied) > 1e-9 {
                editor.rotateSelection(by: wanted - ring.applied, axis: ring.axis, around: ring.pivot, gesture: gestureKey)
                if step > 0 { HmmHaptics.play(.selection) }
                ring.applied = wanted
            }
            drag = .turn(ring)
        case .lasso:
            if let last = editor.lassoPoints.last, hypot(last.x - point.x, last.y - point.y) > 4 { editor.lassoPoints.append(point) }
        case let .scatter(center):
            continueScatter(center: center, at: point, editor: editor, stage: stage)
        case let .perform(planeY, last):
            guard let hit = groundHit(at: point, planeY: planeY, stage: stage) else { return }
            var delta = hit - last
            delta.y = 0
            guard delta.length <= 20 else { return }
            editor.performMove(by: delta)
            drag = .perform(planeY: planeY, last: hit)
        case .aimCamera:
            let rate = editor.orbitDegreesPerPoint
            editor.aimCamera(pan: -Double(translation.x) * rate, tilt: -Double(translation.y) * rate, gesture: gestureKey)
        case let .moveOverlay(id, last):
            editor.moveOverlay(id, by: CGSize(width: point.x - last.x, height: point.y - last.y), gesture: gestureKey)
            drag = .moveOverlay(id, last: point)
        case let .pathKey(time):
            editor.moveMotionPathKey(at: time, to: point, gesture: gestureKey)
        case let .ik(handle):
            editor.dragIK(handle, to: point, gesture: gestureKey)
        case let .pushPull(axis, grab):
            if let along = editor.pullDistance(at: point, axis: axis) { editor.updatePull(along - grab, axis: axis) }
        case .modelLasso:
            if let last = editor.lassoPoints.last, hypot(last.x - point.x, last.y - point.y) > 4 { editor.lassoPoints.append(point) }
        case .sketch:
            editor.sketchDragMoved(to: point)
            loupe?.move(to: point, withCaretRect: .zero, trackingCaret: false)
        case .part, .sculpt, .knife:
            continueShapeDrag(to: point, editor: editor)
        case .none:
            break
        }
    }

    /// With the Model tool: a drag on the picked face or region pulls it; while sketching the Pencil (or a finger, where
    /// fingers make) draws the shape's next point; a Pencil loops in a pick mode; else orbit.
    private func beginModelDrag(at point: CGPoint, editor: EditorModel) -> DragKind {
        let shapes = InputJob.shape.allows(pencil: panTouchIsPencil, fingerMakes: pencilOrHand.fingerMakes)
        if let kind = beginShapeDrag(at: point, editor: editor, shapes: shapes) { return kind }
        if shapes, editor.canPull(at: point), editor.prepareFacePull(), let axis = editor.pullAxis {
            return .pushPull(axis, grab: editor.pullDistance(at: point, axis: axis) ?? 0)
        }
        if editor.isSketching, editor.modeling.mode.sketchKind != .offset, panTouchIsPencil || pencilOrHand.fingerMakes {
            editor.sketchDragBegan(at: point)
            if !panTouchIsPencil, let stage { startLoupe(at: point, in: stage) }
            return .sketch
        }
        if shapes, panTouchIsPencil, editor.modeling.mode.pickMode != nil {
            editor.lassoPoints = [point]
            return .modelLasso
        }
        return .orbit
    }

    private func continueGizmo(_ handle: GizmoHandle, pivot: Vec3, from lastPoint: CGPoint, to point: CGPoint, accumulated: Double,
                               editor: EditorModel, stage: StageView) {
        let result = gizmoDelta(handle: handle, pivot: pivot, from: lastPoint, to: point, stage: stage)
        switch handle.kind {
        case .move:
            // With grid snapping, the object jumps cell by cell while the finger moves freely.
            let total = accumulated + result
            var step = result
            if editor.snapping.grid {
                step = Snapping.snapToGrid(total, size: editor.snapping.gridSize) - Snapping.snapToGrid(accumulated, size: editor.snapping.gridSize)
            }
            if step != 0 { editor.translateSelection(by: handle.axis.unit * step, gesture: gestureKey) }
            drag = .gizmo(handle, pivot: pivot + handle.axis.unit * step, lastPoint: point, accumulated: total)
        case .scale:
            var vector = Vec3.one
            vector[handle.axis] = max(0.2, 1 + result)
            editor.scaleSelection(by: vector, gesture: gestureKey)
            drag = .gizmo(handle, pivot: pivot, lastPoint: point, accumulated: accumulated)
        case .uniformScale:
            let factor = max(0.2, exp(-Double(point.y - lastPoint.y) * 0.006 + Double(point.x - lastPoint.x) * 0.006))
            editor.scaleSelection(by: Vec3(factor, factor, factor), gesture: gestureKey)
            drag = .gizmo(handle, pivot: pivot, lastPoint: point, accumulated: accumulated)
        case .rotate:
            break
        }
    }

    private func continueScatter(center: Vec3, at point: CGPoint, editor: EditorModel, stage: StageView) {
        guard let ground = stage.groundPoint(at: point, height: center.y), let centerScreen = stage.screenPoint(of: center) else { return }
        let radius = Vec3(ground.x - center.x, 0, ground.z - center.z).length
        let right = stage.viewpoint.rotation.act(.unitX)
        let edgeScreen = stage.screenPoint(of: center + Vec3(right.x, 0, right.z).normalized * radius) ?? point
        editor.scatterPreview = (centerScreen, hypot(edgeScreen.x - centerScreen.x, edgeScreen.y - centerScreen.y))
        scatterRadius = radius
    }

    private func endDrag(editor: EditorModel, stage: StageView, cancelled: Bool) {
        switch drag {
        case .moveObjects:
            // It sits down where it was carried (the lift goes), then snaps.
            if let lift = carry?.lift, lift > 0 { editor.translateSelection(by: Vec3(0, -lift, 0), gesture: gestureKey) }
            carry = nil
            editor.finishTransform(gesture: gestureKey)
        case .gizmo:
            editor.finishTransform(gesture: gestureKey)
        case .lasso:
            if !cancelled { selectInLasso(editor: editor, stage: stage) }
            editor.lassoPoints = []
            // One loop, then back to what was in the hand (U5: the lasso is a quick action, not a mode).
            editor.tool = editor.lastTool == .lasso ? .select : editor.lastTool
        case let .scatter(center):
            editor.scatterPreview = nil
            if !cancelled, scatterRadius > 0.2 { editor.scatterSelection(center: center, radius: scatterRadius) }
            scatterRadius = 0
        case .perform:
            editor.performTouchEnded()
        case .ik:
            if editor.performPhase == .recording {
                editor.performTouchEnded()
            } else {
                editor.finishIKDrag(commit: !cancelled)
            }
        case .pushPull:
            editor.endPull(commit: !cancelled)
        case .modelLasso:
            if !cancelled { editor.pickElements(inLoop: editor.lassoPoints) }
            editor.lassoPoints = []
        case .part, .sculpt, .knife:
            endShapeDrag(editor: editor, cancelled: cancelled)
        case .sketch:
            editor.sketchDragEnded(commit: !cancelled)
            loupe?.invalidate()
            loupe = nil
        case .turn, .orbit, .aimCamera, .moveOverlay, .pathKey, .none:
            break
        }
        editor.endGesture()
    }
}
