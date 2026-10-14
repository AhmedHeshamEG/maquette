import CoreGraphics
import Foundation
import HmmDesign
import LoweyCore
import LoweyEngine

/// What's done to a whole thing's shape (U6): the Smooth switch, smoothing for real, the smooth angle, clean topology,
/// linked copies, the pivot, typed sizes. Each is one labelled step; linked copies follow through
/// `perform` (`LinkedCopies.propagate`).
extension EditorModel {
    /// The selected thing, when its shape can be changed here (shapes, modelled meshes, drawings, placed models).
    var shapedSelection: SceneObject? {
        guard let object = singleSelection, object.kind.hasSurface, !scene.isEffectivelyLocked(object.id) else { return nil }
        return object
    }

    // MARK: Smooth

    func smoothLevels(of object: SceneObject) -> Int { ShapeStack.subdivision(of: object) }

    /// The Smooth switch: 0 (off) to 3 levels, shown smoothed without changing the shape underneath.
    func setSmooth(_ levels: Int) {
        guard let object = shapedSelection, ModelingOperations.canModel(object) else { return }
        let clamped = min(max(levels, 0), Subdivision.maximumLevels)
        perform(.setProperties([PropertyChange(object: object.id, key: .subdivision, value: clamped == 0 ? nil : .int(clamped))]))
        HmmHaptics.play(.selection)
    }

    /// Makes the smoothing real: the shape takes the smoothed corners (to keep modelling them).
    func applySmooth() {
        guard let object = shapedSelection else { return }
        let levels = max(smoothLevels(of: object), 1)
        runModeling { try ModelingOperations.subdivide(object.id, levels: levels, in: baseScene) }
    }

    /// Edges sharper than this stay crisp (nil = every edge crisp).
    func setSmoothAngle(_ degrees: Double?, gesture: String? = nil) {
        guard let object = shapedSelection else { return }
        perform(.setProperties([PropertyChange(object: object.id, key: .smoothAngle, value: degrees.map { .float(min(max($0, 0), 180)) })]),
                coalesceKey: gesture)
    }

    func setFlatShading(_ flat: Bool) {
        guard let object = shapedSelection else { return }
        perform(.setProperties([PropertyChange(object: object.id, key: .shading, value: flat ? .enumeration(ShadingMode.flat.rawValue) : nil)]))
    }

    /// How many triangles the thing draws (what a game counts).
    func triangleCount(of object: SceneObject) -> Int? {
        if let mesh = SceneExport.localMesh(of: object, look: look) { return mesh.triangleCount }
        return stage?.worldMesh(of: object.id)?.triangleCount
    }

    // MARK: Clean topology

    /// The thing as shown, in its own space before its scale (a placed model's parts as one).
    func shownSurface(of object: SceneObject) -> MeshData? {
        if let mesh = SceneExport.localMesh(of: object, look: look) { return mesh }
        guard let id = object.kind.assetID, let asset = library.catalog.manifest.asset(id), let model = library.models.model(asset, catalog: library.catalog),
              let merged = AssetPaint.mergedMesh(model) else { return nil }
        return ShapeStack.moved(merged, for: object)
    }

    /// Clean topology: the thing becomes an even mesh of quads, about `faces` of them, off the main thread.
    func cleanUpShape(faces: Int, pureQuads: Bool = false) {
        guard let object = shapedSelection, let source = shownSurface(of: object), modeling.cleaning == nil else { return }
        modeling.cleaning = object.id
        let id = object.id
        let options = QuadRemesh.Options(faces: faces, pureQuads: pureQuads)
        Task { [weak self] in
            let result = await Task.detached(priority: .userInitiated) { () -> Result<EditableMesh, QuadRemesh.Failure> in
                do throws(QuadRemesh.Failure) {
                    return try .success(QuadRemesh.remesh(source, options: options))
                } catch {
                    return .failure(error)
                }
            }.value
            guard let self else { return }
            modeling.cleaning = nil
            switch result {
            case .success:
                // The command remeshes again from the same surface (deterministic): one path for the bridge and the app.
                runModeling { try ModelingOperations.cleanTopology(id, source: source, options: options, in: self.baseScene) }
            case let .failure(failure):
                app.show(String.LocalizationValue(failure.description), kind: .error)
            }
        }
    }

    // MARK: Holes, merging

    func fillHolesOfSelection() {
        guard let object = shapedSelection, prepareShapeObject(object.id) else { return }
        let near = modeling.target == object.id && modeling.elements?.mode == .vertex ? modeling.elements?.vertices : nil
        runModeling { try ModelingOperations.fillHoles(object.id, near: near, in: baseScene) }
    }

    func mergePickedCorners() {
        guard let id = modeling.target, let corners = modeling.elements?.vertices, modeling.elements?.mode == .vertex else { return }
        if runModeling({ try ModelingOperations.merge(id, corners: corners, in: baseScene) }) { modeling.elements = nil }
    }

    /// Corners closer than a tenth of a millimetre (or of the project's unit step) become one.
    func mergeByDistance() {
        guard let object = shapedSelection, prepareShapeObject(object.id) else { return }
        runModeling { try ModelingOperations.mergeByDistance(object.id, distance: pullStep * 0.1, in: baseScene) }
    }

    func bridgePickedFaces() {
        guard let id = modeling.target, let faces = modeling.elements?.faces.sorted(), faces.count == 2 else {
            app.show("Pick two faces to bridge (touch and hold to add the second)")
            return
        }
        if runModeling({ try ModelingOperations.bridge(id, faces: faces[0], faces[1], in: baseScene) }) { modeling.elements = nil }
    }

    func loopCutPickedEdge(cuts: Int = 1) {
        guard let id = modeling.target, let edge = modeling.elements?.edges.first, modeling.elements?.mode == .edge,
              prepareShapeObject(id) else { return }
        if runModeling({ try ModelingOperations.loopCut(id, across: edge, cuts: cuts, in: baseScene) }) { modeling.elements = nil }
    }

    // MARK: Linked copies

    func makeLinkedCopy() {
        guard let object = shapedSelection else { return }
        let size = operations.bounds.worldBounds(of: object.id, in: scene)?.size.x ?? 1
        var ids = operations.ids
        guard let command = LinkedCopies.makeCopy(of: object.id, in: baseScene, offset: Vec3(size * 1.2, 0, 0), ids: &ids) else { return }
        operations.ids = ids
        let before = Set(baseScene.objects.keys)
        if perform(command), let copy = Set(baseScene.objects.keys).subtracting(before).first { setSelection([copy]) }
    }

    func isLinked(_ object: SceneObject) -> Bool { !LinkedCopies.partners(of: object.id, in: baseScene).isEmpty }

    func unlinkSelection() {
        guard let object = shapedSelection else { return }
        perform(LinkedCopies.unlink(object.id))
    }

    // MARK: Pivot and sizes

    func movePivot(to preset: Arrange.PivotPreset) {
        guard let object = singleSelection, let point = Arrange.pivotPoint(preset, of: object.id, in: baseScene, bounds: operations.bounds) else { return }
        runModeling { try Arrange.movePivot(object.id, to: point, in: baseScene) }
    }

    /// The pivot to the picked corner, edge middle or face middle.
    func movePivotToPick() {
        guard let id = modeling.target, let elements = modeling.elements, let (mesh, world) = modelMesh(of: id) else { return }
        let corners = elements.touchedVertices(in: mesh).filter(mesh.vertices.indices.contains)
        guard !corners.isEmpty else { return }
        let point = world.apply(to: corners.reduce(Vec3.zero) { $0 + mesh.vertices[$1] } / Double(corners.count))
        runModeling { try Arrange.movePivot(id, to: point, in: baseScene) }
    }

    /// The selection's size along an axis (world metres).
    func selectionLength(_ axis: CoreAxis) -> Double? {
        operations.bounds.worldBounds(of: selection, in: scene)?.size[axis]
    }

    /// Types a side's length (world metres): it stretches along that axis.
    func setSelectionLength(_ axis: CoreAxis, to metres: Double, gesture: String? = nil) {
        guard let object = singleSelection else { return }
        do {
            try perform(Arrange.setLength(object.id, axis: axis, to: metres, in: baseScene), coalesceKey: gesture)
        } catch {
            app.show(String.LocalizationValue(String(describing: error)), kind: .error)
        }
    }
}
