import CoreGraphics
import Foundation
import HmmDesign
import LoweyCore
import LoweyEngine

/// The sheet under the Pencil (CONTEXT §10.10, `DrawingSheet`): ink, solid shapes, flipbooks and precise sketches land
/// on it. Hands place it: a finger-tap on a surface lays it there, a finger-tap in empty space stands it there facing
/// you, and its grip pushes it nearer or farther. The control on its edge gives it one of four shapes. The first
/// stroke on a sheet keeps it (named, in the scene, in the stroke's undo step); flipbooks drawn on it stay on it.
extension EditorModel {
    /// The sheet strokes land on now: a kept one as the scene has it (so undo moves it too), else the working one.
    var currentSheet: DrawingSheet? {
        guard let sheet = drawingSheet else { return nil }
        return baseScene.sheet(sheet.id) ?? sheet
    }

    /// The current sheet is in the scene (something was drawn on it).
    var sheetIsKept: Bool {
        drawingSheet.map { baseScene.sheet($0.id) != nil } ?? false
    }

    /// A tool that draws on the sheet is in the hand (flipbooks stuck to the camera draw on the frame instead).
    var drawsOnSheet: Bool {
        switch tool {
        case .ink: ink.mode == .draw
        case .draw: true
        case .flipbook: !flipbook.onCamera
        case .model: modeling.mode.sketchKind != nil && modeling.mode.sketchKind != .offset
        default: false
        }
    }

    /// The sheet is there before the first stroke: standing where the view looks, facing it; for precise sketches,
    /// lying on the ground there (where a model starts, as in Shapr3D).
    func ensureSheet() {
        guard drawsOnSheet, let stage else { return }
        if let sheet = currentSheet, sheet.worldFrame(in: displayed.scene) != nil { return }
        let viewpoint = stage.viewpoint
        let target = selectionBounds?.center ?? viewpoint.target
        if isSketching {
            let ground = Vec3(target.x, 0, target.z)
            drawingSheet = .lying(on: SurfaceHit(point: ground, normal: .unitY, distance: 0), object: nil, eye: viewpoint.eye, in: displayed.scene,
                                  id: Self.newID(), name: baseScene.nextSheetName(), size: sheetSize(at: ground))
            return
        }
        drawingSheet = .facing(eye: viewpoint.eye, at: target, id: Self.newID(), name: baseScene.nextSheetName(),
                               size: sheetSize(at: target))
    }

    /// The sheet a stroke in the air lands on (U5, zero setup): the one in use, unless nobody placed it and nothing is
    /// drawn on it (it turns to face you where you look), or it is a flat one seen edge-on (a new one faces you). A
    /// flipbook keeps its sheet whatever the view: its frames live there.
    func prepareSheetForStroke() {
        guard drawsOnSheet, let stage else { return }
        if isSketching || tool == .flipbook {
            ensureSheet()
            return
        }
        if let sheet = currentSheet, let frame = sheet.worldFrame(in: displayed.scene) {
            let toEye = (stage.viewpoint.eye - frame.origin).normalized
            let edgeOn = sheet.shape == .flat && abs(toEye.dot(frame.rotation.act(.unitZ))) < 0.26
            if sheetIsKept || sheetPlaced, !edgeOn { return }
            if sheet.shape == .onObject { return }
        }
        drawingSheet = nil
        sheetPlaced = false
        ensureSheet()
    }

    /// The sheet comes to lie on a surface the Pencil started a sketch on (unless it lies there already).
    func laySheet(on hit: SurfaceHit, object: ObjectID?) {
        if let sheet = currentSheet, sheet.object == object, let plane = sheetPlane(sheet), plane.normal.dot(hit.normal) > 1 - 1e-6,
           abs((hit.point - plane.origin).dot(plane.normal)) < 1e-6 { return }
        guard let stage else { return }
        drawingSheet = .lying(on: hit, object: object, eye: Vec3(stage.camera.position), in: displayed.scene, id: Self.newID(),
                              name: baseScene.nextSheetName(), size: sheetSize(at: hit.point))
    }

    /// About two thirds of what the view shows at that distance.
    func sheetSize(at point: Vec3) -> Double {
        guard let stage else { return 2 }
        return max(stage.worldPerPoint(at: point) * Double(stage.bounds.height) * 0.65, 0.2)
    }

    /// A finger tapped the stage with a drawing tool: the sheet goes there. On a surface it lies on it (and rides with
    /// its object); in empty space it stands facing you, as far away as the sheet was. An ink drawing is picked instead,
    /// so the next strokes join it.
    func placeSheet(at point: CGPoint) {
        guard let stage, let ray = stage.worldRay(at: point) else { return }
        let eye = Vec3(stage.camera.position)
        let shape = currentSheet?.shape ?? .flat
        if let (id, _) = stage.pickObject(at: point), let object = baseScene.objects[id] {
            if object.isInk {
                select(id)
                return
            }
            if let mesh = stage.worldMesh(of: id), let hit = MeshRaycast.intersect(ray, mesh: mesh) {
                let sheet = DrawingSheet.lying(on: hit, object: id, eye: eye, in: displayed.scene, id: Self.newID(), name: baseScene.nextSheetName(),
                                               size: sheetSize(at: hit.point))
                moveSheet(to: sheet.with(shape: shape == .flat ? .flat : shape))
                return
            }
        }
        let depth = currentSheet.flatMap { $0.worldFrame(in: displayed.scene) }.map { ($0.origin - eye).length } ?? stage.viewpoint.distance
        let spot = ray.point(at: max(depth, 0.2))
        if tool == .ink, !selection.isEmpty { select(nil) }
        let sheet = DrawingSheet.facing(eye: eye, at: spot, id: Self.newID(), name: baseScene.nextSheetName(), size: sheetSize(at: spot))
        moveSheet(to: sheet.with(shape: shape == .onObject ? .flat : shape))
    }

    /// The sheet goes somewhere new: a working sheet is simply replaced, a kept one stays in the scene with its
    /// drawings and the new place is a new working sheet.
    private func moveSheet(to sheet: DrawingSheet) {
        drawingSheet = sheet
        sheetPlaced = true
        wakeSheet()
        HmmHaptics.play(.selection)
    }

    /// The grip: pushes the sheet nearer (positive) or farther, in metres. A kept sheet moves as one undo step per drag.
    func pushSheet(by distance: Double, gesture: String) {
        guard let sheet = currentSheet, abs(distance) > 1e-9 else { return }
        updateSheet(sheet.pushed(by: distance), gesture: gesture)
    }

    /// The grip, dragged on screen: down brings the sheet nearer, up pushes it away (about two of its widths a screen).
    func pushSheet(byPoints points: Double, gesture: String) {
        guard let stage, let origin = currentSheet?.worldFrame(in: displayed.scene)?.origin else { return }
        pushSheet(by: points * stage.worldPerPoint(at: origin) * 2, gesture: gesture)
    }

    /// The sheet's menu: a step nearer or farther (a seventh of the way to the eye).
    func nudgeSheet(nearer: Bool) {
        guard let stage, let origin = currentSheet?.worldFrame(in: displayed.scene)?.origin else { return }
        let step = (stage.viewpoint.eye - origin).length / 7
        pushSheet(by: nearer ? step : -step, gesture: UUID().uuidString)
        endGesture()
        HmmHaptics.play(.selection)
    }

    /// The sheet's menu: it turns to face you where it stands (what's drawn on it turns with it).
    func faceSheet() {
        guard let stage, let sheet = currentSheet, sheet.object == nil, let origin = sheet.worldFrame(in: displayed.scene)?.origin else { return }
        var facing = DrawingSheet.facing(eye: stage.viewpoint.eye, at: origin, id: sheet.id, name: sheet.name, size: max(sheet.width, sheet.height))
        facing.width = sheet.width
        facing.height = sheet.height
        updateSheet(facing.with(shape: sheet.shape), gesture: nil)
        HmmHaptics.play(.selection)
    }

    /// One of the four shapes (from the sheet's menu).
    func setSheetShape(_ shape: DrawingSheet.Shape) {
        ensureSheet()
        guard let sheet = currentSheet, sheet.shape != shape else { return }
        HmmHaptics.play(.selection)
        updateSheet(sheet.with(shape: shape), gesture: nil)
    }

    /// How tightly an "around" or "dome" sheet curves (the edge control's slider).
    func setSheetRadius(_ radius: Double, gesture: String) {
        guard var sheet = currentSheet else { return }
        sheet.radius = max(radius, 0.05)
        updateSheet(sheet, gesture: gesture)
    }

    /// A kept sheet moves with what is drawn on it, in one step (U5).
    private func updateSheet(_ sheet: DrawingSheet, gesture: String?) {
        if sheetIsKept, let old = baseScene.sheet(sheet.id) {
            let carried = SheetCarry.carrying(from: old, to: sheet, in: baseScene)
            let move: EditCommand = carried.isEmpty ? .setSheets([SheetEdit(sheet)])
                : .batch("Move sheet", [.setSheets([SheetEdit(sheet)]), .setProperties(carried)])
            perform(move, coalesceKey: gesture)
        }
        drawingSheet = sheet
        wakeSheet()
    }

    // MARK: Kept sheets

    /// Draw on a kept sheet again; the flipbook drawn on it (the newest) becomes the one the Pencil draws into.
    func chooseSheet(_ id: String) {
        guard let sheet = baseScene.sheet(id) else { return }
        drawingSheet = sheet
        if let track = timeline.flipbooks.last(where: { $0.anchor.sheet == id }) { flipbook.track = track.id }
        HmmHaptics.play(.selection)
    }

    /// A fresh sheet where the view looks (the next stroke keeps it).
    func newSheet() {
        drawingSheet = nil
        flipbook.track = nil
        ensureSheet()
        HmmHaptics.play(.selection)
    }

    func renameSheet(_ id: String, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, var sheet = baseScene.sheet(id) ?? (drawingSheet?.id == id ? drawingSheet : nil) else { return }
        sheet.name = trimmed
        if baseScene.sheet(id) != nil { perform(.batch("Rename sheet", [.setSheets([SheetEdit(sheet)])])) }
        if drawingSheet?.id == id { drawingSheet = sheet }
    }

    /// Deletes a kept sheet and the flipbooks drawn on it, as one undo step.
    func deleteSheet(_ id: String) {
        let tracks = timeline.flipbooks.filter { $0.anchor.sheet == id }.map { FlipbookEdit(id: $0.id, track: nil) }
        var commands: [EditCommand] = [.setSheets([SheetEdit(id: id, sheet: nil)])]
        if !tracks.isEmpty { commands.append(.setFlipbooks(tracks)) }
        guard perform(.batch("Delete sheet", commands)) else { return }
        if drawingSheet?.id == id { drawingSheet = nil }
        if let track = flipbook.track, timeline.flipbook(track) == nil { flipbook.track = nil }
        ensureSheet()
    }

    /// `command` with the current sheet kept in front of it when this is its first stroke (one undo step).
    func keepingSheet(_ command: EditCommand?) -> EditCommand? {
        guard let command, let sheet = currentSheet, !sheetIsKept else { return command }
        return .batch(command.label, [.setSheets([SheetEdit(sheet)]), command])
    }

    // MARK: Where a stroke lands

    /// Where a ray lands on the sheet: its shape, or the surface of the object it lies on.
    func land(_ ray: Ray, on sheet: DrawingSheet, objectMesh: MeshData?) -> SurfaceHit? {
        if sheet.shape == .onObject {
            guard let objectMesh else { return nil }
            return MeshRaycast.intersect(ray, mesh: objectMesh)
        }
        return sheet.land(ray, in: displayed.scene)
    }

    /// The world mesh a stroke on an "on the object" sheet lands on (read once when the stroke starts).
    func sheetObjectMesh(_ sheet: DrawingSheet?) -> MeshData? {
        guard let sheet, sheet.shape == .onObject, let object = sheet.object else { return nil }
        return stage?.worldMesh(of: object)
    }

    /// The flat plane through the sheet (its own plane; a curved sheet's tangent plane where it was placed), for the
    /// plane's drawing guide and precise sketches.
    func sheetPlane(_ sheet: DrawingSheet?) -> (origin: Vec3, u: Vec3, v: Vec3, normal: Vec3)? {
        guard let sheet, let frame = sheet.worldFrame(in: displayed.scene) else { return nil }
        return (frame.origin, frame.rotation.act(.unitX), frame.rotation.act(.unitY), frame.rotation.act(.unitZ))
    }

    // MARK: On the stage

    /// Draws the sheet while a tool that draws on it is in the hand (U5): paper, with a soft edge and faint dots, while
    /// the Pencil works; a trace between strokes. Hidden with the guides (the quick menu).
    func refreshSheet() {
        guard let stage else { return }
        guard drawsOnSheet, !chromeHidden, !sheetHidden, let sheet = currentSheet, let origin = sheet.worldFrame(in: displayed.scene)?.origin else {
            stage.showSheet([])
            return
        }
        let scene = displayed.scene
        let paper = StageColors.sheet
        let point = stage.worldPerPoint(at: origin)
        let strength = sheetAwake ? 1.0 : StageColors.sheetRestingAlpha / StageColors.sheetFillAlpha
        let fillAlpha = sheet.shape == .onObject ? 0.7 : StageColors.sheetFillAlpha * strength
        var overlays = [EditorOverlay(mesh: SheetMesh.fill(sheet, in: scene), color: paper, opacity: Float(fillAlpha))]
        let border = SheetMesh.border(sheet, in: scene, thickness: point * 1.2)
        if !border.isEmpty { overlays.append(EditorOverlay(mesh: border, color: paper, opacity: Float(StageColors.sheetBorderAlpha * strength))) }
        guard sheetAwake else {
            stage.showSheet(overlays)
            return
        }
        let edges = SheetMesh.softEdge(sheet, in: scene, width: point * 18, steps: StageColors.sheetEdgeAlphas.count)
        for (mesh, alpha) in zip(edges, StageColors.sheetEdgeAlphas) {
            overlays.append(EditorOverlay(mesh: mesh, color: paper, opacity: Float(alpha * StageColors.sheetFillAlpha * 2)))
        }
        let dots = SheetMesh.dots(sheet, in: scene, spacing: point * 28, size: point * 2.2)
        if !dots.isEmpty { overlays.append(EditorOverlay(mesh: dots, color: paper, opacity: Float(StageColors.sheetDotAlpha))) }
        stage.showSheet(overlays)
    }

    /// The sheet shows as paper now (a stroke starts, it was placed, the Pencil hovers) and fades a moment after.
    func wakeSheet(for seconds: Double = 1.6) {
        guard drawsOnSheet else { return }
        sheetFadeTask?.cancel()
        if !sheetAwake {
            sheetAwake = true
            refreshSheet()
        }
        sheetFadeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard let self, !Task.isCancelled, !strokeInProgress else { return }
            sheetAwake = false
            refreshSheet()
        }
    }
}
