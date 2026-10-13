import HmmDesign
import LoweyCore
import LoweyEngine
import UIKit

/// The Pencil's strokes on the stage: lines and solids landing on the surface under them or on the sheet (draw, then
/// hold to snap to a clean shape), and the tools that have strokes of their own.
extension StageGestures {
    @objc func handleStroke(_ recognizer: StrokeGestureRecognizer) {
        guard let editor, let stage else { return }
        noteStroke(recognizer, editor: editor)
        if routedStroke(recognizer, editor: editor, stage: stage) { return }
        lineStroke(recognizer, editor: editor, stage: stage)
    }

    /// The panel closes on the first stroke (CONTEXT §10.10), the sheet wakes as paper, the clusters rest (U5).
    private func noteStroke(_ recognizer: StrokeGestureRecognizer, editor: EditorModel) {
        switch recognizer.state {
        case .began:
            if editor.openPanel != nil, !(editor.openPanel?.isLeading ?? true) { editor.openPanel = nil }
            editor.pencilFeel = recognizer.feel
            editor.strokeInProgress = true
            editor.restClusters()
            editor.wakeSheet()
        case .ended, .cancelled, .failed:
            editor.strokeInProgress = false
            editor.wakeSheet()
        default:
            break
        }
    }

    /// Tools with strokes of their own; true when one took it. A paint brush that starts in the air draws a line
    /// instead (zero setup: it lands on the sheet).
    private func routedStroke(_ recognizer: StrokeGestureRecognizer, editor: EditorModel, stage: StageView) -> Bool {
        switch editor.tool {
        case .shadowBrush:
            brushStroke(recognizer, editor: editor, stage: stage)
        case .flipbook:
            flipbookStroke(recognizer, editor: editor)
        case .paint:
            if recognizer.state == .began {
                paintsThisStroke = editor.colourPaint.mode != .paint || recognizer.samples.first.map { editor.paintsSurface(at: $0.location) } ?? false
            }
            guard paintsThisStroke else { return false }
            colourStroke(recognizer, editor: editor, stage: stage)
        case .rig:
            rigStroke(recognizer, editor: editor, stage: stage)
        case .ink where editor.ink.mode != .draw:
            inkEditStroke(recognizer, editor: editor, stage: stage)
        case .ink where reshapesPickedStroke(recognizer, editor: editor):
            // The Pencil dragged along a picked stroke reshapes it (U5: strokes stay editable).
            reshapeStroke(recognizer, editor: editor)
        default:
            return false
        }
        return true
    }

    /// Whether this stroke reshapes the picked strokes: it started on one of them (decided as it begins).
    private func reshapesPickedStroke(_ recognizer: StrokeGestureRecognizer, editor: EditorModel) -> Bool {
        if recognizer.state == .began {
            reshapingPicked = !editor.inkStrokes.isEmpty && recognizer.samples.first.map { editor.isOnPickedStroke($0.location) } ?? false
        }
        return reshapingPicked
    }

    private func reshapeStroke(_ recognizer: StrokeGestureRecognizer, editor: EditorModel) {
        let samples = recognizer.samples
        switch recognizer.state {
        case .began:
            gestureKey = UUID().uuidString
            inkDragLast = samples.first?.location
            consumedSamples = samples.count
        case .changed:
            if let last = inkDragLast, let current = samples.last?.location {
                editor.smudgeInk(from: last, to: current, gesture: gestureKey)
                inkDragLast = current
            }
        default:
            editor.endGesture()
            inkDragLast = nil
            reshapingPicked = false
        }
    }

    /// Lines (ink) and solids.
    private func lineStroke(_ recognizer: StrokeGestureRecognizer, editor: EditorModel, stage: StageView) {
        switch recognizer.state {
        case .began:
            snapped = nil
            strokePoints = []
            strokePressures = []
            strokeNormals = []
            strokeAltitudes = []
            strokeTimes = []
            strokeSeed = EditorModel.strokeSeed()
            consumedSamples = 0
            beginLanding(at: recognizer.samples.first?.location, editor: editor, stage: stage)
            consume(Array(recognizer.samples), editor: editor, stage: stage)
        case .changed:
            continueStroke(recognizer, editor: editor, stage: stage)
        case .ended:
            continueStroke(recognizer, editor: editor, stage: stage)
            stage.showStrokePreview(nil, color: .white)
            stage.showLiveStroke(nil)
            finishLine(recognizer, editor: editor, stage: stage)
            consumedSamples = 0
            snapped = nil
        default:
            stage.showStrokePreview(nil, color: .white)
            stage.showLiveStroke(nil)
            consumedSamples = 0
            snapped = nil
        }
    }

    /// A tap on a line picks it (its chip opens: U5); anything else is kept.
    private func finishLine(_ recognizer: StrokeGestureRecognizer, editor: EditorModel, stage: StageView) {
        if Self.isTap(recognizer.samples), editor.drawsLines, let point = recognizer.samples.first?.location, editor.tapLine(at: point) { return }
        if editor.drawsLines {
            editor.commitInkStrokes(inkCopies(inkSamples(stage: stage), editor: editor), seed: strokeSeed, onSheet: !strokeOnSurface)
            editor.strokeEnded()
        } else {
            editor.commitStroke(points: strokePoints, pressures: strokePressures, normals: strokeNormals, sheet: strokeSheet, onSheet: !strokeOnSurface)
        }
    }

    /// A touch that barely moved and lifted quickly.
    static func isTap(_ samples: [StrokeGestureRecognizer.Sample]) -> Bool {
        guard let first = samples.first, let last = samples.last else { return false }
        let still = samples.allSatisfy { hypot($0.location.x - first.location.x, $0.location.y - first.location.y) < 6 }
        return still && last.time - first.time < 0.3
    }

    private func continueStroke(_ recognizer: StrokeGestureRecognizer, editor: EditorModel, stage: StageView) {
        if snapped != nil {
            adjustQuickShape(editor: editor, stage: stage)
        } else {
            consume(Array(recognizer.samples.suffix(from: min(consumedSamples, recognizer.samples.count))), editor: editor, stage: stage)
        }
    }

    // MARK: QuickShape

    /// Draw, then hold: the stroke becomes the clean shape it was meant to be.
    func snapToQuickShape() {
        guard HmmShortcut.cleanShape.isOn(), let editor, let stage, editor.tool.usesSheet, stroke.state == .began || stroke.state == .changed,
              let anchor = stroke.samples.last?.location else { return }
        if editor.tool == .flipbook {
            snapFlipbookToQuickShape(editor: editor)
            return
        }
        let points = stroke.samples.map { Vec2(Double($0.location.x), Double($0.location.y)) }
        guard let shape = QuickShape.fit(points) else { return }
        let pressure = stroke.samples.map(\.pressure).reduce(0, +) / Double(max(stroke.samples.count, 1))
        snapped = (shape, anchor, pressure)
        redrawStroke(shape.points, pressure: pressure, editor: editor, stage: stage)
        HmmHaptics.play(.selection)
        HmmPencilHaptics.completed(at: anchor, in: stage)
        // Its size shows (U5): the two longest sides of what it became, in the project's units.
        let extents = Bounds(points: strokePoints).map { [$0.size.x, $0.size.y, $0.size.z].sorted(by: >) } ?? []
        let size = extents.count >= 2 ? "\(editor.units.format(extents[0])) × \(editor.units.format(extents[1]))" : ""
        editor.app.show("\(shape.kind.title) \(size). Keep holding and drag to adjust")
    }

    /// Still holding after the snap: a line's end follows the tip; other shapes turn and scale.
    private func adjustQuickShape(editor: EditorModel, stage: StageView) {
        guard let snapped, let tip = stroke.samples.last?.location else { return }
        let shape = QuickShape.adjusted(snapped.shape, anchor: Vec2(Double(snapped.anchor.x), Double(snapped.anchor.y)),
                                        current: Vec2(Double(tip.x), Double(tip.y)))
        redrawStroke(shape.points, pressure: snapped.pressure, editor: editor, stage: stage)
    }

    private func redrawStroke(_ points: [Vec2], pressure: Double, editor: EditorModel, stage: StageView) {
        strokePoints = []
        strokePressures = []
        strokeNormals = []
        strokeAltitudes = []
        strokeTimes = []
        project(points.map { StrokeGestureRecognizer.Sample(location: CGPoint(x: $0.x, y: $0.y), pressure: pressure) }, editor: editor, stage: stage)
        updatePreview(editor: editor, stage: stage)
    }

    private func consume(_ samples: [StrokeGestureRecognizer.Sample], editor: EditorModel, stage: StageView) {
        consumedSamples += samples.count
        project(samples, editor: editor, stage: stage)
        updatePreview(editor: editor, stage: stage)
    }

    /// Where the stroke lands (U5, zero setup): begun over a surface, on that surface (the sheet is left alone); in the
    /// air, on the sheet, facing you unless a finger placed it.
    private func beginLanding(at point: CGPoint?, editor: EditorModel, stage: StageView) {
        if let point, let surface = surfaceUnder(point, editor: editor, stage: stage) {
            strokeSheet = DrawingSheet.lying(on: surface.hit, object: surface.id, eye: Vec3(stage.camera.position), in: editor.displayed.scene,
                                             id: "surface", name: "", size: 1).with(shape: .onObject)
            strokeTargetMesh = surface.mesh
            strokeOnSurface = true
            return
        }
        editor.prepareSheetForStroke()
        strokeSheet = editor.currentSheet
        strokeTargetMesh = editor.sheetObjectMesh(strokeSheet)
        strokeOnSurface = false
    }

    /// The surface under a point a line or a solid can land on: a thing's (not an ink drawing's: lines drawn over lines
    /// go on the sheet), while drawing lines or solids.
    private func surfaceUnder(_ point: CGPoint, editor: EditorModel, stage: StageView) -> (id: ObjectID, hit: SurfaceHit, mesh: MeshData)? {
        guard editor.tool == .ink || editor.tool == .draw || editor.tool == .paint, let ray = stage.worldRay(at: point),
              let (id, _) = stage.pickObject(at: point),
              let object = editor.displayed.scene.objects[id], !object.isInk, let mesh = stage.worldMesh(of: id),
              let hit = MeshRaycast.intersect(ray, mesh: mesh) else { return nil }
        return (id, hit, mesh)
    }

    /// Screen samples → points on the stroke's guide (or the object it started on). Off the edge of a surface the line
    /// carries on in the plane where it left it.
    private func project(_ samples: [StrokeGestureRecognizer.Sample], editor: EditorModel, stage: StageView) {
        for sample in samples {
            guard let ray = stage.worldRay(at: sample.location), let sheet = strokeSheet,
                  let hit = editor.land(ray, on: sheet, objectMesh: strokeTargetMesh) ?? carriedOn(ray) else { continue }
            // Tubes sit on the surface instead of half buried in it.
            let lift = editor.tool == .draw && editor.draw.style == .tube ? editor.draw.width * 0.5 : 0.002
            strokePoints.append(hit.point + hit.normal * lift)
            strokePressures.append(sample.pressure)
            strokeNormals.append(hit.normal)
            strokeAltitudes.append(sample.altitude)
            strokeTimes.append(sample.time)
        }
    }

    /// A ray that misses the surface the stroke is on: the plane where the stroke left it.
    func carriedOn(_ ray: Ray) -> SurfaceHit? {
        guard strokeTargetMesh != nil, let last = strokePoints.last, let normal = strokeNormals.last else { return nil }
        return GuideSurface.plane(origin: last, normal: normal).intersect(ray)
    }

    private func updatePreview(editor: EditorModel, stage: StageView) {
        guard strokePoints.count >= 2 else { return }
        if editor.drawsLines {
            showInkPreview(stroke, editor: editor, stage: stage)
            return
        }
        let widths = strokePressures.map { editor.draw.width * (0.35 + 0.65 * $0) }
        let thin = editor.draw.style == .extrude || editor.draw.style == .lathe
        let preview = DrawingRecipe.Stroke(points: strokePoints, widths: thin ? widths.map { _ in 0.012 } : widths)
        let mesh = editor.draw.style == .ribbon ? DrawingMesher.ribbon(preview, normal: strokeNormals.last ?? .unitY)
            : DrawingMesher.tube(preview, sides: 5)
        stage.showStrokePreview(mesh, color: editor.currentColor.resolved(in: editor.look.palette))
    }

    // MARK: Shadow Brush

    /// Paints where the Pencil touches the object the stroke started on (raycast on its world mesh, so every sample
    /// lands even between frames). One stroke is one undo step.
    private func brushStroke(_ recognizer: StrokeGestureRecognizer, editor: EditorModel, stage: StageView) {
        switch recognizer.state {
        case .began:
            gestureKey = UUID().uuidString
            consumedSamples = 0
            brushTarget = recognizer.samples.first.flatMap { sample in
                stage.pickObject(at: sample.location).flatMap { hit in stage.worldMesh(of: hit.0).map { (hit.0, $0) } }
            }
            if brushTarget == nil { editor.app.show("Start the stroke on an object") }
            paint(Array(recognizer.samples), editor: editor, stage: stage)
        case .changed:
            paint(Array(recognizer.samples.suffix(from: min(consumedSamples, recognizer.samples.count))), editor: editor, stage: stage)
        default:
            brushTarget = nil
            consumedSamples = 0
            editor.endGesture()
        }
    }

    private func paint(_ samples: [StrokeGestureRecognizer.Sample], editor: EditorModel, stage: StageView) {
        consumedSamples += samples.count
        guard let target = brushTarget else { return }
        // A dab every few points is plenty (the brush is soft); fewer dabs keep the undo step small.
        for (index, sample) in samples.enumerated() where index % 3 == 0 {
            guard let ray = stage.worldRay(at: sample.location), let hit = MeshRaycast.intersect(ray, mesh: target.mesh) else { continue }
            editor.paintShadow(on: target.id, at: hit.point, pressure: sample.pressure, gesture: gestureKey)
        }
    }
}
