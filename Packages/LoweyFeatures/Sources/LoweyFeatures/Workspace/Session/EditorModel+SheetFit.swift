import CoreGraphics
import Foundation
import HmmDesign
import LoweyCore
import LoweyEngine

/// Placing the sheet on a face, precise (Q1, `SheetFit`): it lies on the face's own plane, sized to the face with a
/// small margin and lined up with its longest edge; on a curve, the tangent plane under the tip. While the Pencil
/// hovers a face lights and the sheet's ghost sits on it; a finger's tap lays it there; sliding snaps it to the face's
/// middle and edges with a light tick. Its chip makes it exact: offset, turn and size, each a slider with the number pad
/// behind it.
extension EditorModel {
    /// The face under a point of the stage: the thing, where the ray landed, the face, the world mesh.
    func sheetFace(at point: CGPoint) -> (object: ObjectID, hit: SurfaceHit, face: SheetFit.Face, mesh: MeshData)? {
        guard let stage, let ray = stage.worldRay(at: point), let (id, _) = stage.pickObject(at: point),
              let object = baseScene.objects[id], !object.isInk, let mesh = stage.worldMesh(of: id),
              let landed = MeshRaycast.intersectTriangle(ray, mesh: mesh) else { return nil }
        let eye = Vec3(stage.camera.position)
        if let cache = placing.faceCache, cache.object == id, cache.revision == session.revision, !cache.face.curved,
           cache.face.triangles.contains(landed.triangle) {
            return (id, landed.hit, cache.face, mesh)
        }
        let face: SheetFit.Face
        if mesh.triangleCount > SheetFit.denseTriangles {
            face = SheetFit.tangentFace(at: landed.hit, triangle: landed.triangle, bounds: mesh.bounds, eye: eye)
        } else {
            guard let found = SheetFit.face(around: landed.triangle, in: mesh, eye: eye) else { return nil }
            face = found
        }
        placing.faceCache = SheetFaceCache(object: id, revision: session.revision, face: face)
        return (id, landed.hit, face, mesh)
    }

    /// Where the sheet goes for a touch at `point` on a face: about two thirds of the view at most, never bigger than
    /// the face, snapping within 16 points of the face's middle and edges.
    func fittedSheet(at point: CGPoint) -> FittedSheet? {
        guard let stage, let found = sheetFace(at: point) else { return nil }
        let size = sheetSize(at: found.hit.point)
        let snap = stage.worldPerPoint(at: found.hit.point) * 16
        let placement = SheetFit.placement(on: found.face, tip: found.hit.point, maximum: (size, size * 0.75), snap: snap)
        let sheet = DrawingSheet.fitted(placement, object: found.object, in: displayed.scene, id: Self.newID(), name: baseScene.nextSheetName())
        return FittedSheet(sheet: sheet, placement: placement, object: found.object, face: found.face, mesh: found.mesh)
    }

    /// A finger's tap on a thing with a drawing tool: the sheet lies on that face, fitted. False when it isn't on one.
    func laySheetFitted(at point: CGPoint, shape: DrawingSheet.Shape) -> Bool {
        guard let fitted = fittedSheet(at: point) else { return false }
        let sheet = fitted.sheet.with(shape: shape == .flat ? .flat : shape)
        placing.fit = SheetFitState(sheetID: sheet.id, base: sheet)
        flashFace(fitted.face, mesh: fitted.mesh, object: fitted.object, sheet: sheet)
        drawingSheet = sheet
        sheetPlaced = true
        wakeSheet()
        HmmHaptics.play(.selection)
        if !fitted.placement.snaps.isEmpty, let stage { HmmPencilHaptics.snapped(at: point, in: stage) }
        if AppIdentity.isUITesting { trail("sheet=fitted \(fitted.face.curved ? "curve" : "face") \(fitted.placement.snaps.map(\.rawValue).sorted())") }
        return true
    }

    // MARK: The ghost

    /// The Pencil hovers (nil: it left): after it rests a moment on a face the sheet isn't on, the face lights and the
    /// sheet's ghost sits on it; sliding moves it from face to face, snapping with a tick.
    func hoverSheetGhost(at point: CGPoint?) {
        placing.ghostTask?.cancel()
        guard let point, drawsOnSheet, !strokeInProgress else {
            clearSheetGhost()
            return
        }
        if placing.ghost != nil {
            showSheetGhost(at: point)
            return
        }
        placing.ghostTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(0.3))
            guard let self, !Task.isCancelled else { return }
            showSheetGhost(at: point)
        }
    }

    private func showSheetGhost(at point: CGPoint) {
        guard let fitted = fittedSheet(at: point) else {
            clearSheetGhost()
            return
        }
        // Already lying on this face: nothing to show.
        if let current = currentSheet, current.object == fitted.object, let frame = current.worldFrame(in: displayed.scene),
           frame.rotation.act(.unitZ).dot(fitted.face.normal) > 1 - 1e-6,
           abs((frame.origin - fitted.placement.center).dot(fitted.face.normal)) < 0.01 {
            clearSheetGhost()
            return
        }
        let snapped = !fitted.placement.snaps.isEmpty
        let wasSnapped = placing.ghostSnapped
        placing.ghostSnapped = snapped
        if snapped, !wasSnapped || placing.ghost?.object != fitted.object, let stage {
            HmmHaptics.play(.selection)
            HmmPencilHaptics.snapped(at: point, in: stage)
        }
        let lift = SheetFit.lift(for: max(fitted.placement.width, fitted.placement.height))
        var world = fitted.sheet
        world.object = nil
        world.origin = fitted.placement.center + fitted.face.normal * lift
        world.rotation = fitted.placement.rotation
        placing.ghost = SheetGhost(object: fitted.object, sheet: world, lit: SheetFit.mesh(of: fitted.face, in: fitted.mesh, lift: lift / 2))
        refreshSheet()
    }

    func clearSheetGhost() {
        placing.ghostTask?.cancel()
        guard placing.ghost != nil else { return }
        placing.ghost = nil
        placing.ghostSnapped = false
        refreshSheet()
    }

    /// The face that was tapped lights for a moment as the sheet lands on it.
    private func flashFace(_ face: SheetFit.Face, mesh: MeshData, object: ObjectID, sheet: DrawingSheet) {
        var world = sheet
        if let frame = sheet.worldFrame(in: displayed.scene) {
            world.object = nil
            world.origin = frame.origin
            world.rotation = frame.rotation
        }
        placing.ghost = SheetGhost(object: object, sheet: world, lit: SheetFit.mesh(of: face, in: mesh, lift: SheetFit.lift(for: sheet.width) / 2))
        placing.ghostTask?.cancel()
        placing.ghostTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(0.6))
            guard let self, !Task.isCancelled else { return }
            clearSheetGhost()
        }
    }

    /// The ghost on the stage: the lit face and a faint sheet with its edge.
    func sheetGhostOverlays() -> [EditorOverlay] {
        guard let ghost = placing.ghost, let stage else { return [] }
        let scene = displayed.scene
        let point = stage.worldPerPoint(at: ghost.sheet.origin)
        var overlays = [EditorOverlay(mesh: ghost.lit, color: StageColors.selection, opacity: 0.22),
                        EditorOverlay(mesh: SheetMesh.fill(ghost.sheet, in: scene), color: StageColors.sheet, opacity: 0.18)]
        let border = SheetMesh.border(ghost.sheet, in: scene, thickness: point * 1.6)
        if !border.isEmpty { overlays.append(EditorOverlay(mesh: border, color: StageColors.sheet, opacity: 0.7)) }
        return overlays
    }

    // MARK: Exact, from its chip

    /// The chip's numbers: how far above where it was laid, turned about its normal, and how wide (its shape kept).
    func adjustFittedSheet(offset: Double? = nil, turn: Double? = nil, width: Double? = nil, gesture: String?) {
        guard var state = placing.fit, let sheet = currentSheet, sheet.id == state.sheetID else { return }
        if let offset, offset.isFinite { state.offset = min(max(offset, -10), 10) }
        if let turn, turn.isFinite { state.turn = turn.truncatingRemainder(dividingBy: 360) }
        let base = state.base
        let normal = base.rotation.act(.unitZ)
        var next = sheet
        next.origin = base.origin + normal * state.offset
        next.rotation = (Quat(angle: state.turn * .pi / 180, axis: normal) * base.rotation).normalized
        if let width, width.isFinite, width > 0.001 {
            next.width = width
            next.height = width * base.height / max(base.width, 1e-9)
        }
        placing.fit = state
        updateSheet(next, gesture: gesture)
    }

    /// The turn being dragged: it snaps to 15° steps with a tick.
    func scrubFittedSheetTurn(_ degrees: Double, gesture: String) {
        let snapped = SheetFit.snappedTurn(degrees)
        if snapped.snapped, snapped.degrees != placing.fit?.turn { HmmHaptics.play(.selection) }
        adjustFittedSheet(turn: snapped.degrees, gesture: gesture)
    }
}
