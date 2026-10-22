import Foundation
import HmmDesign
import LoweyCore
import LoweyEngine

/// G1, Print, Study and Game on the selection: the printed pieces, the best way up, split, hollow, scale to size,
/// overhangs in red, the slicer; explode; greybox pieces and freezing transforms.
extension EditorModel {
    /// The one modelled thing chosen (the tools work on one part).
    var guestPart: ObjectID? {
        guard selection.count == 1, let id = selection.first, let object = baseScene.objects[id], ModelingOperations.canModel(object) else {
            return nil
        }
        return id
    }

    /// The selected group a Study explodes (the selection's top group).
    var explodableGroup: ObjectID? {
        guard let id = selection.first else { return nil }
        let top = baseScene.ancestors(of: id).last ?? id
        guard let object = baseScene.objects[top], !object.children.isEmpty else { return nil }
        return top
    }

    func addPrintPiece(_ piece: ModelingOperations.PrintPiece) {
        var ids = operations.ids
        let spot = dropPoint()
        let made = runModeling { [guest] in
            try ModelingOperations.addPrintPiece(piece, screw: guest.screw, tolerance: guest.tolerance, at: spot, ids: &ids)
        }
        operations.ids = ids
        if made { app.show(piece == .jar ? "The lid stands beside the jar, upside down: both print as they are" : "Ready to print") }
    }

    func orientForPrinting() {
        guard let id = guestPart else { return }
        let current = baseScene
        if runModeling({ try ModelingOperations.orientForPrinting(id, in: current) }) { app.show("Turned to need the least support") }
    }

    func splitForPrinting() {
        guard let id = guestPart, let box = SceneBounds(library: library.manifest).worldBounds(of: id, in: baseScene) else { return }
        var at = box.center
        at[guest.splitAxis] = box.min[guest.splitAxis] + box.size[guest.splitAxis] * guest.splitAt
        let newID = ObjectID.make()
        let current = baseScene
        let split = runModeling { [guest] in
            try ModelingOperations.splitForPrinting(id, point: at, normal: guest.splitAxis.unit, pegs: true, tolerance: guest.tolerance,
                                                    newID: newID, in: current)
        }
        if split {
            setSelection([id, newID])
            app.show("Two parts: pegs on one, holes in the other, a centimetre apart")
        }
    }

    func hollowForPrinting() {
        guard let id = guestPart else { return }
        let current = baseScene
        _ = runModeling { [guest] in try ModelingOperations.hollowForPrinting(id, wall: guest.wall, drain: 0.003, in: current) }
    }

    func scaleToSize(_ metres: Double, axis: CoreAxis?) {
        guard let id = guestPart else { return }
        let current = baseScene
        _ = runModeling { try ModelingOperations.scaleToSize(id, target: metres, axis: axis, in: current) }
    }

    /// The selection (or the scene) as a 3MF, handed to the share sheet so the slicer app opens it.
    func slicerFile() -> URL? {
        guard let file = modelFiles(.threeMF, preset: .apps, selectionOnly: !selection.isEmpty, colors: .texture).first else { return nil }
        let url = rendersFolder.appendingPathComponent(file.name)
        do {
            try FileManager.default.createDirectory(at: rendersFolder, withIntermediateDirectories: true)
            try file.data.write(to: url, options: .atomic)
            return url
        } catch {
            app.show("Couldn't write the file: \(error.localizedDescription)", kind: .error)
            return nil
        }
    }

    /// Faces that need support, in red over the chosen part.
    func overhangOverlays(_ stage: StageView) -> [EditorOverlay] {
        guard guest.overhangs, let id = guestPart, let (mesh, world) = modelMesh(of: id) else { return [] }
        let placed = mesh.transformed(by: world)
        let faces = PrintOrientation.overhangs(placed).faces
        guard !faces.isEmpty else { return [] }
        let picked = MeshSelection(mode: .face, faces: Set(faces))
        let width = stage.worldPerPoint(at: world.position)
        return [EditorOverlay(mesh: ModelOverlay.selection(picked, of: mesh, world: world, width: width), color: RGBA(1, 0.27, 0.23), opacity: 0.55)]
    }

    // MARK: Study

    func toggleExplode() {
        guard let group = explodableGroup else {
            app.show("Choose a group of parts to explode")
            return
        }
        let bounds = SceneBounds(library: library.manifest)
        let current = baseScene
        guard let command = Explode.toggle(group, in: current, bounds: { bounds.worldBounds(of: $0, in: current) }) else { return }
        if perform(command) { HmmHaptics.play(.commit) }
    }

    // MARK: Game

    func addGreybox(_ piece: GreyboxPiece) {
        let id = ObjectID.make()
        if perform(ModelingOperations.addGreybox(piece, at: dropPoint(), id: id)) {
            HmmHaptics.play(.commit)
            setSelection([id])
        }
    }

    func freezeTransforms() {
        guard let command = ModelingOperations.freezeTransforms(selection, in: baseScene) else {
            app.show("Nothing turned or sized to freeze")
            return
        }
        if perform(command) { app.show("Turns and sizes baked into the shapes") }
    }
}
