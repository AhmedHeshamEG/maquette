import CoreGraphics
import Foundation
import HmmDesign
import LoweyCore
import LoweyEngine

/// Model ▸ Brush (U6): grab, smooth and inflate on the selected thing's surface, mirrored across its middle when
/// symmetry is on. The stroke shows live and lands as one step. A shape too coarse to brush is cut finer first (the
/// same cuts rigging uses); a placed model is brushed as one surface, the one painting uses, so it's made paintable first.
/// The brush stroke in progress and the shaping it shows instead of the document's.
struct Sculpting {
    var session: EditorModel.SculptSession?
    var shown: [ObjectID: ObjectShaping] = [:]
}

extension EditorModel {
    /// The stroke in progress.
    struct SculptSession {
        var object: ObjectID
        var stroke: SculptStroke
        /// Where the stroke began, in the thing's own space, and the plane facing the eye through it (grab drags across it).
        var start: Vec3
        var startScreen: CGPoint
        var shaping: ObjectShaping
    }

    /// Fewer triangles than this and the surface is cut finer before brushing.
    static let brushableTriangles = 3000

    /// The surface the brushes move: built and cut, before strokes, cage and bend (a placed model's parts as one).
    func brushSurface(of object: SceneObject) -> MeshData? {
        if let mesh = PaintSource.unshaped(of: object) { return mesh }
        guard object.paint != nil, let id = object.kind.assetID, let asset = library.catalog.manifest.asset(id),
              let model = library.models.model(asset, catalog: library.catalog) else { return nil }
        return AssetPaint.mergedMesh(model)
    }

    /// Gets the selected thing ready for brushing; false (with what's happening said) when it isn't yet.
    func prepareBrushing() -> SceneObject? {
        guard let object = shapedSelection else {
            app.show("Select the thing to brush")
            return nil
        }
        if object.kind.assetID != nil, object.paint == nil {
            preparePaint(object.id)
            return nil
        }
        if ModelingOperations.canModel(object), let surface = brushSurface(of: object), surface.triangleCount < Self.brushableTriangles,
           object[.bendDetail] == nil {
            perform(.setProperties([PropertyChange(object: object.id, key: .bendDetail, value: .float(Double(MeshDensify.maximumCuts)))]))
        }
        return baseScene.objects[object.id]
    }

    func sculptBegan(at point: CGPoint) {
        guard sculpting.session == nil, let object = prepareBrushing(), let surface = brushSurface(of: object),
              let local = surfacePoint(at: point, of: object.id) else { return }
        let offsets = object.shaping?.sculpt.flatMap { $0.vertexCount == surface.positions.count ? $0.offsets : nil }
        let stroke = SculptStroke(brush: modeling.sculpt.brush, mesh: surface, cornerOffsets: offsets,
                                  symmetry: modeling.sculpt.symmetry ? .x : nil)
        sculpting.session = SculptSession(object: object.id, stroke: stroke, start: local, startScreen: point, shaping: object.shaping ?? ObjectShaping())
        strokeInProgress = true
        sculptMoved(to: point, pressure: 1)
    }

    func sculptMoved(to point: CGPoint, pressure: Double) {
        guard var session = sculpting.session, let stage else { return }
        let world = scene.worldTransform(of: session.object)
        let radius = Float(modeling.sculpt.size * stage.worldPerPoint(at: world.apply(to: session.start)) / max(world.scale.maxComponent, 1e-9))
        let strength = Float(modeling.sculpt.strength * min(max(pressure, 0.2), 1))
        switch session.stroke.brush {
        case .grab:
            guard let now = grabPoint(at: point, session: session, world: world) else { return }
            session.stroke.dab(at: session.start.float3, radius: radius, strength: 1, moved: (now - session.start).float3)
        case .smooth, .inflate:
            guard let local = surfacePoint(at: point, of: session.object) else { return }
            session.stroke.dab(at: local.float3, radius: radius, strength: strength)
        }
        sculpting.session = session
        var shaping = session.shaping
        shaping.sculpt = SculptLayer(offsets: session.stroke.cornerOffsets)
        sculpting.shown = [session.object: shaping]
        refreshDisplay()
    }

    func sculptEnded(commit: Bool) {
        guard let session = sculpting.session else { return }
        sculpting.session = nil
        sculpting.shown = [:]
        strokeInProgress = false
        guard commit else {
            refreshDisplay()
            return
        }
        var shaping = session.shaping
        let layer = SculptLayer(offsets: session.stroke.cornerOffsets)
        shaping.sculpt = layer.moved.isEmpty ? nil : layer
        perform(.batch(session.stroke.brush.title, [.setShaping(session.object, shaping.isEmpty ? nil : shaping)]))
    }

    /// Takes every stroke off the thing.
    func clearStrokes() {
        guard let object = shapedSelection, var shaping = object.shaping, shaping.sculpt != nil else { return }
        shaping.sculpt = nil
        perform(.batch("Clear strokes", [.setShaping(object.id, shaping.isEmpty ? nil : shaping)]))
    }

    /// The point of the thing's surface under the screen point, in its own space.
    private func surfacePoint(at point: CGPoint, of id: ObjectID) -> Vec3? {
        guard let stage, let (hit, info) = stage.pickObject(at: point), hit == id else { return nil }
        return scene.worldTransform(of: id).inverseApply(to: info.point)
    }

    /// Grab follows the Pencil across the plane facing the eye through where the stroke began.
    private func grabPoint(at point: CGPoint, session: SculptSession, world: CoreTransform) -> Vec3? {
        guard let stage, let ray = stage.worldRay(at: point) else { return nil }
        let plane = GuideSurface.plane(origin: world.apply(to: session.start), normal: -ray.direction)
        return plane.intersect(ray).map { world.inverseApply(to: $0.point) }
    }
}
