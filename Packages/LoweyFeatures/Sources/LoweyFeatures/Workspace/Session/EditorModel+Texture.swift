import CoreGraphics
import Foundation
import HmmDesign
import LoweyCore
import LoweyEngine

/// What U7's tools keep between touches: the surfaces the Pencil is found on (by unwrap), the smudge in progress, and
/// each shape's wear bake (slow to make, so made once per shape).
final class TextureWork {
    var picks: [String: PaintSurfacePick] = [:]
    var smudge: SmudgeSession?
    /// A decal picture waiting for its tap (`ColourPaintSettings.decalWaiting`).
    var decal: RGBAImage?
    var wearBakes: [String: WearBake] = [:]

    /// A smudge under the Pencil: the layer's map as a picture, the dabs so far and the tiles they changed.
    struct SmudgeSession {
        var object: ObjectID
        var layer: String
        var map: PaintMap
        var image: RGBAImage
        var last: PaintSmudge.Dab?
        var changed: Set<PaintTileIndex> = []
    }
}

/// U7 Texture on the stage (CONTEXT §10.11): the surface under the Pencil in the texture's terms, smudge on painted
/// surfaces, the faces brush and hand-marked seams.
extension EditorModel {
    /// A painted object's paint mesh in the space its paint is laid in, and the picker over it (cached by unwrap).
    func paintSurface(of object: SceneObject) -> (paint: ObjectPaint, mesh: MeshData, pick: PaintSurfacePick)? {
        guard let paint = object.paint, paintFitsShape(object), let source = paintSource(of: object) else { return nil }
        let key = "\(paint.surface.unwrap) \(paint.surface.mesh)"
        if let known = texture.picks[key] { return (paint, known.mesh, known) }
        guard let unwrap = paintFiles(paint.surface.unwrap).flatMap({ try? PaintUnwrap(data: $0) }), let mesh = unwrap.mesh(over: source) else { return nil }
        let pick = PaintSurfacePick(paintMesh: mesh)
        if texture.picks.count > 8 { texture.picks.removeAll() }
        texture.picks[key] = pick
        return (paint, mesh, pick)
    }

    /// A world point in the paint mesh's space (a bevelled shape's mesh is built at its size).
    func paintSpace(_ point: Vec3, of object: SceneObject) -> SIMD3<Float> {
        var local = displayed.scene.worldTransform(of: object.id).inverseApply(to: point).float3
        if PaintSource.toObjectSpace(of: object) != nil {
            let scale = object.transform.scale
            local *= SIMD3<Float>(Float(scale.x), Float(scale.y), Float(scale.z))
        }
        return local
    }

    /// The painted surface under a stage point.
    struct SurfaceHit {
        var object: SceneObject
        var paint: ObjectPaint
        var mesh: MeshData
        var pick: PaintSurfacePick
        var hit: PaintSurfacePick.Hit
        /// How many texels a stage point covers there.
        var texelsPerPoint: Float
    }

    /// The painted surface under a stage point: the object, its paint, where in the texture, and how many texels a
    /// stage point covers there.
    func surfaceHit(at point: CGPoint) -> SurfaceHit? {
        guard let stage, let picked = stage.pickObject(at: point), let object = displayed.scene.objects[picked.0],
              let surface = paintSurface(of: object), let ray = stage.worldRay(at: point),
              let across = stage.worldRay(at: CGPoint(x: point.x + 1, y: point.y)) else { return nil }
        let origin = paintSpace(ray.origin, of: object)
        let target = paintSpace(picked.1.point, of: object)
        guard let hit = surface.pick.hit(origin: origin, direction: target - origin, size: surface.paint.surface.size) else { return nil }
        // A stage point's width at the hit: where the next pixel's ray is at the same distance.
        let distance = picked.1.point.distance(to: ray.origin)
        let worldPerPoint = Float(across.point(at: distance).distance(to: picked.1.point))
        return SurfaceHit(object: object, paint: surface.paint, mesh: surface.mesh, pick: surface.pick, hit: hit, texelsPerPoint: worldPerPoint * hit.density)
    }

    // MARK: Smudge

    /// A smudge starts on the layer's map under the Pencil (its picture read once).
    func beginPaintSmudge(at point: CGPoint) {
        texture.smudge = nil
        guard let found = surfaceHit(at: point), let layer = paintLayer(of: found.object) else { return }
        let map = paintedMap(of: layer)
        guard !layer.tiles(of: map).isEmpty else {
            app.show("Nothing painted on \(layer.name) to smudge")
            return
        }
        let file = paintFiles
        let image = PaintComposer.layerImage(layer, map: map, surface: found.paint.surface) { name in file(name).flatMap(PaintPixels.decode) }
        colourPaint.target = found.object.id
        texture.smudge = TextureWork.SmudgeSession(object: found.object.id, layer: layer.id, map: map, image: image)
    }

    /// The smudge follows the Pencil: each point becomes a dab in the texture, the changed tiles shown at once.
    func continuePaintSmudge(_ points: [CGPoint]) {
        guard var session = texture.smudge, let stage else { return }
        var dabs: [PaintSmudge.Dab] = session.last.map { [$0] } ?? []
        for point in points {
            guard let found = surfaceHit(at: point), found.object.id == session.object else { continue }
            let size = Float(found.paint.surface.size)
            dabs.append(PaintSmudge.Dab(center: found.hit.uv * size, radius: max(Float(colourPaint.size / 2) * found.texelsPerPoint, 1.5),
                                        strength: Float(colourPaint.opacity) * 0.8))
        }
        guard dabs.count > 1 else {
            session.last = dabs.last
            texture.smudge = session
            return
        }
        let changed = PaintSmudge.apply(dabs, to: &session.image)
        session.changed.formUnion(changed)
        session.last = dabs.last
        texture.smudge = session
        let tiles = Dictionary(uniqueKeysWithValues: changed.map { ($0, session.image.tile($0, size: PaintSurface.tileSize)) })
        stage.renderer.showLivePaint(object: session.object, layer: PaintPictures.key(session.layer, session.map), tiles: tiles)
        stage.redraw()
    }

    /// The smudge kept as one step (its tiles written first), or put back.
    func finishPaintSmudge(keep: Bool) {
        guard let session = texture.smudge else { return }
        texture.smudge = nil
        guard keep, !session.changed.isEmpty, let layer = baseScene.objects[session.object]?.paint?.layer(session.layer) else {
            revertPaint()
            return
        }
        let folder = assetsFolder
        Task {
            let made = await Task.detached(priority: .userInitiated) {
                PaintOperations.tileChanges(session.image, tiles: session.changed, map: session.map, layer: layer, encode: PaintPixels.png)
            }.value
            do {
                try await Self.write(made.files, to: folder)
            } catch {
                app.show("Couldn't save the smudge: \(error.localizedDescription)", kind: .error)
                return
            }
            perform(made.changes.isEmpty ? nil : .paintTiles(session.object, made.changes))
        }
    }

    // MARK: Faces and seams

    /// The faces brush: the flat face under the Pencil, filled edge to edge in the layer's map (one step).
    func fillFace(at point: CGPoint) {
        guard let found = surfaceHit(at: point), let layer = paintLayer(of: found.object) else {
            if let stage, let picked = stage.pickObject(at: point), let object = displayed.scene.objects[picked.0], object.isPaintable,
               object.paint == nil { preparePaint(object.id) }
            return
        }
        let map = paintedMap(of: layer)
        let face = found.pick.face(of: found.hit.triangle)
        let file = paintFiles
        let image = PaintComposer.layerImage(layer, map: map, surface: found.paint.surface) { name in file(name).flatMap(PaintPixels.decode) }
        let made = PaintOperations.fillFaces(face, color: strokeColor, map: map, layer: layer, surface: found.paint.surface, paintMesh: found.mesh,
                                             image: image, encode: PaintPixels.png)
        let folder = assetsFolder
        let id = found.object.id
        HmmPencilHaptics.buzz(at: point)
        Task {
            do {
                try await Self.write(made.files, to: folder)
            } catch {
                app.show("Couldn't save the face: \(error.localizedDescription)", kind: .error)
                return
            }
            perform(made.changes.isEmpty ? nil : .paintTiles(id, made.changes))
        }
    }

    /// Seams: the edge of the flat face nearest the Pencil is marked (or unmarked); Cut lays the surface out again.
    func markSeam(at point: CGPoint) {
        guard let found = surfaceHit(at: point) else { return }
        let face = found.pick.face(of: found.hit.triangle)
        guard let edge = Self.nearestBoundary(of: face, in: found.mesh, to: found.hit.position) else { return }
        let seam = PaintSeam(Vec3(Double(edge.0.x), Double(edge.0.y), Double(edge.0.z)), Vec3(Double(edge.1.x), Double(edge.1.y), Double(edge.1.z)))
        colourPaint.target = found.object.id
        if let index = colourPaint.pendingSeams.firstIndex(of: seam) {
            colourPaint.pendingSeams.remove(at: index)
        } else {
            colourPaint.pendingSeams.append(seam)
        }
        HmmPencilHaptics.buzz(at: point)
        refreshSeamOverlay()
    }

    /// The outline edge of a flat face (triangle edges used once) nearest a point.
    static func nearestBoundary(of face: [Int], in mesh: MeshData, to point: SIMD3<Float>) -> (SIMD3<Float>, SIMD3<Float>)? {
        func key(_ p: SIMD3<Float>) -> SIMD3<Int32> {
            SIMD3<Int32>(Int32(clamping: Int((p.x * 1e4).rounded())), Int32(clamping: Int((p.y * 1e4).rounded())), Int32(clamping: Int((p.z * 1e4).rounded())))
        }
        var uses: [[SIMD3<Int32>]: (count: Int, ends: (SIMD3<Float>, SIMD3<Float>))] = [:]
        for triangle in face {
            for (a, b) in [(0, 1), (1, 2), (2, 0)] {
                let pa = mesh.positions[Int(mesh.indices[triangle * 3 + a])], pb = mesh.positions[Int(mesh.indices[triangle * 3 + b])]
                let edge = [key(pa), key(pb)].sorted { ($0.x, $0.y, $0.z) < ($1.x, $1.y, $1.z) }
                uses[edge, default: (0, (pa, pb))].count += 1
            }
        }
        return uses.values.filter { $0.count == 1 }.map(\.ends).min { first, second in
            Self.distance(point, first) < Self.distance(point, second)
        }
    }

    private static func distance(_ p: SIMD3<Float>, _ edge: (SIMD3<Float>, SIMD3<Float>)) -> Float {
        let ab = edge.1 - edge.0
        let t = min(max(((p - edge.0) * ab).sum() / max((ab * ab).sum(), 1e-12), 0), 1)
        let d = p - (edge.0 + ab * t)
        return (d * d).sum().squareRoot()
    }

    /// The marked and pending seams drawn over the thing (accent for pending, white for kept).
    func refreshSeamOverlay() {
        guard let stage else { return }
        guard colourPaint.mode == .seams, let id = colourPaint.target, let object = displayed.scene.objects[id] else {
            stage.showModelOverlay([])
            return
        }
        let world = displayed.scene.worldTransform(of: id)
        let unscale = PaintSource.toObjectSpace(of: object)
        func toWorld(_ point: Vec3) -> Vec3 {
            let local = unscale.map { Vec3(point.x * Double($0.x), point.y * Double($0.y), point.z * Double($0.z)) } ?? point
            return world.apply(to: local)
        }
        var kept = MeshData(), pending = MeshData()
        for seam in object.paint?.surface.seams ?? [] {
            ModelOverlay.line(toWorld(seam.a), toWorld(seam.b), width: 0.006, into: &kept)
        }
        for seam in colourPaint.pendingSeams {
            ModelOverlay.line(toWorld(seam.a), toWorld(seam.b), width: 0.008, into: &pending)
        }
        stage.showModelOverlay([EditorOverlay(mesh: kept, color: .white, opacity: 0.9, onTop: true),
                                EditorOverlay(mesh: pending, color: RGBA.hex("#FFB847"), onTop: true)])
    }

    /// Lays the surface out again cutting along the kept and pending seams (or the unwrapper's own when there are
    /// none), the paint carried over by position (one step).
    func applySeams(clear: Bool = false) {
        guard let id = colourPaint.target ?? paintTarget?.id, let object = baseScene.objects[id], let paint = object.paint,
              let source = paintSource(of: object) else { return }
        let seams: [PaintSeam]? = clear ? nil : (paint.surface.seams ?? []) + colourPaint.pendingSeams
        let file = paintFiles
        let folder = assetsFolder
        Task {
            let made = await Task.detached(priority: .userInitiated) {
                PaintOperations.rebased(paint, source: source, file: file, seams: .some(seams.flatMap { $0.isEmpty ? nil : $0 }), encode: PaintPixels.png)
            }.value
            guard let made else {
                app.show("These seams couldn't be laid flat", kind: .error)
                return
            }
            do {
                try await Self.write(made.files, to: folder)
            } catch {
                app.show("Couldn't save the new surface: \(error.localizedDescription)", kind: .error)
                return
            }
            guard baseScene.objects[id]?.paint == paint else { return }
            perform(.batch(clear ? "Automatic seams" : "Cut seams", [.setPaint(id, made.paint)]))
            colourPaint.pendingSeams = []
            refreshSeamOverlay()
        }
    }
}
