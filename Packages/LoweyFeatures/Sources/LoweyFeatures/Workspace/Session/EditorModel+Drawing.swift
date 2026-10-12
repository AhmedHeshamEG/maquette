import Foundation
import HmmDesign
import LoweyCore

/// Solid shapes drawn in 3D on the sheet (tube, ribbon, extrude, lathe), and the Shadow Brush.
extension EditorModel {
    /// A finished stroke becomes a drawn object (one undo step).
    func commitStroke(points rawPoints: [Vec3], pressures: [Double], normals: [Vec3], sheet: DrawingSheet?) {
        guard rawPoints.count >= 2 || draw.style == .tube else { return }
        let widths = pressures.map { draw.width * (0.35 + 0.65 * min(max($0, 0), 1)) }
        let filtered = StrokeFilter.process(points: rawPoints, widths: widths, smoothing: draw.smoothing)
        guard !filtered.points.isEmpty else { return }
        let normal = strokeNormal(normals: normals, sheet: sheet)
        let origin = strokeOrigin(filtered.points)
        let points = filtered.points.map { $0 - origin }
        var strokes = [DrawingRecipe.Stroke(points: points, widths: filtered.widths)]
        if draw.mirror, draw.style != .lathe {
            let mirrorX = (sheetPlane(sheet)?.origin.x ?? selectionBounds?.center.x ?? origin.x) - origin.x
            strokes.append(DrawingRecipe.Stroke(points: points.map { Vec3(2 * mirrorX - $0.x, $0.y, $0.z) }, widths: filtered.widths))
        }
        let recipe = DrawingRecipe(style: draw.style, strokes: strokes, normal: normal, depth: draw.extrudeDepth,
                                   segments: draw.style == .lathe ? max(draw.segments, 6) : draw.segments)
        guard !DrawingMesher.mesh(for: recipe).isEmpty else {
            app.show(draw.style == .extrude ? "Draw a closed outline to extrude" : "That stroke was too small")
            return
        }
        var object = factory.drawing(recipe, transform: CoreTransform(position: origin), color: currentColor)
        object.name = ObjectFactory.uniqueName(object.name, in: scene)
        perform(keepingSheet(operations.add(object)))
    }

    /// Ribbons and extrusions face a flat sheet's normal, else the average surface normal.
    private func strokeNormal(normals: [Vec3], sheet: DrawingSheet?) -> Vec3 {
        if sheet?.shape == .flat, let plane = sheetPlane(sheet) { return plane.normal }
        guard !normals.isEmpty else { return .unitY }
        let averaged = normals.reduce(Vec3.zero, +).normalized
        return averaged.length > 0.5 ? averaged : .unitY
    }

    /// The object's origin: the lathe axis base, else the first point.
    private func strokeOrigin(_ points: [Vec3]) -> Vec3 {
        guard draw.style == .lathe else { return points[0] }
        let target = stage?.viewpoint.target ?? .zero
        let center = selectionBounds.map { Vec3($0.center.x, $0.min.y, $0.center.z) } ?? Vec3(target.x, 0, target.z)
        return Vec3(center.x, points.map(\.y).min() ?? center.y, center.z)
    }

    // MARK: Shadow Brush

    /// One dab of the Shadow Brush at a world point on an object: pushes its toon shadow in (or pulls it out) there.
    /// Dabs of one stroke coalesce into one undo step.
    func paintShadow(on id: ObjectID, at world: Vec3, pressure: Double, gesture: String) {
        guard let object = baseScene.objects[id], object.kind.hasSurface, !baseScene.isEffectivelyLocked(id) else { return }
        let transform = displayed.scene.worldTransform(of: id)
        let local = transform.inverseApply(to: world)
        let scale = max(abs(transform.scale.x), abs(transform.scale.y), abs(transform.scale.z), 1e-3)
        let amount = shadowBrush.strength * min(max(pressure, 0.1), 1) * (shadowBrush.pushesShadow ? -1 : 1)
        let dab = ShadowDab(position: local, radius: shadowBrush.radius / scale, amount: amount)
        let dabs = ShadowPaint.adding(dab, to: object.shadowDabs)
        perform(.setShadowPaint(id, dabs), coalesceKey: gesture)
    }

    /// Paints a designed shadow shape on the selection (a character's preset goes on its head), one undo step.
    func applyShadowPreset(_ preset: ShadowPreset) {
        let targets = Array(Set(selection.compactMap { shadowTarget(for: $0) }))
        let commands = targets.compactMap { id -> EditCommand? in
            guard let object = baseScene.objects[id], let bounds = localBounds(of: object) else { return nil }
            return .setShadowPaint(id, preset.dabs(in: bounds))
        }
        guard !commands.isEmpty else {
            app.show("Select something to paint (a character, a head, a shape)")
            return
        }
        perform(.batch("Shadows: \(preset.title)", commands))
        HmmHaptics.play(.commit)
    }

    /// What a preset paints for a selected object: a character's head surface, else the object itself.
    func shadowTarget(for id: ObjectID) -> ObjectID? {
        let scene = baseScene
        if scene.objects[id]?[.rigStandard] != nil {
            let subtree = scene.subtree(of: id)
            let head = subtree.first { scene.objects[$0]?[.faceRole]?.stringValue == "head" || scene.objects[$0]?[.bone]?.stringValue == "head" }
            if let head, let surface = scene.subtree(of: head).first(where: { scene.objects[$0]?.kind.hasSurface == true && $0 != head }) {
                return surface
            }
        }
        return scene.objects[id]?.kind.hasSurface == true ? id : nil
    }

    /// An object's own (unscaled) bounds, for placing preset shadows.
    func localBounds(of object: SceneObject) -> Bounds? {
        let unit = Bounds(min: Vec3(-0.5, 0, -0.5), max: Vec3(0.5, 1, 0.5))
        switch object.kind {
        case let .primitive(shape): return PrimitiveMesh.bounds(shape)
        case let .drawing(recipe): return DrawingMesher.mesh(for: recipe).bounds
        case let .mesh(mesh): return mesh.bounds ?? unit
        case let .asset(id): return library.manifest.asset(id)?.bounds ?? unit
        default: return unit
        }
    }

    func clearShadowPaint() {
        let painted = selection.filter { !(baseScene.objects[$0]?.shadowDabs.isEmpty ?? true) }
        guard !painted.isEmpty else { return }
        perform(.batch("Clear shadows", painted.map { EditCommand.setShadowPaint($0, []) }))
        HmmHaptics.play(.commit)
    }

    var selectionHasShadowPaint: Bool {
        selection.contains { !(baseScene.objects[$0]?.shadowDabs.isEmpty ?? true) }
    }
}
