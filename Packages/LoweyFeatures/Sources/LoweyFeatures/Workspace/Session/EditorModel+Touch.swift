import CoreGraphics
import Foundation
import HmmDesign
import LoweyCore
import LoweyEngine

/// Modelling by touch, no modes (U6, CONTEXT §10.10): over the selected shape the Pencil lights the face, edge or
/// corner under its tip; dragging a face pulls it, an edge rounds it, a corner moves it. A tap picks the part and
/// shows its chip with the rest. Every shape is editable: it becomes a modelled mesh quietly on the first touch.
extension EditorModel {
    /// The shape the Pencil models: the one selected thing, when it can be modelled.
    var touchModelTarget: ObjectID? {
        guard let object = singleSelection, ModelingOperations.canModel(object), !scene.isEffectivelyLocked(object.id) else { return nil }
        return object.id
    }

    /// The part of the selected shape under a screen point (corner, edge or face, by distance on screen).
    func modelPart(at point: CGPoint) -> (object: ObjectID, part: MeshSelection)? {
        guard let stage, let id = modeling.target ?? touchModelTarget, let (mesh, world) = modelMesh(of: id),
              let (hit, _) = stage.pickObject(at: point), hit == id, let ray = stage.worldRay(at: point) else { return nil }
        let local = Ray(origin: world.inverseApply(to: ray.origin), direction: world.inverseApplyDirection(ray.direction))
        let screen = Vec2(Double(point.x), Double(point.y))
        guard let part = MeshPicking.nearestPart(local, screenPoint: screen, in: mesh, project: { [weak stage] in
            stage?.screenPoint(of: world.apply(to: $0)).map { Vec2(Double($0.x), Double($0.y)) }
        }) else { return nil }
        return (id, part)
    }

    /// What will be picked lights up first: the part under the hovering Pencil (nil clears it).
    func lightModelPart(at point: CGPoint?) {
        let lit = point.flatMap { modelPart(at: $0) }.map { LitPart(object: $0.object, part: $0.part) }
        guard lit != modeling.lit else { return }
        modeling.lit = lit
        refreshModelOverlay()
    }

    /// A Pencil tap on the selected shape: picks the part under it (its chip shows). False when there was none.
    @discardableResult
    func pickModelPart(at point: CGPoint, additive: Bool = false) -> Bool {
        guard let (id, part) = modelPart(at: point) else { return false }
        var picked = part
        if additive, modeling.target == id, var current = modeling.elements, current.mode == part.mode {
            current.vertices.formSymmetricDifference(part.vertices)
            current.edges.formSymmetricDifference(part.edges)
            current.faces.formSymmetricDifference(part.faces)
            picked = current
        }
        modeling.region = nil
        modeling.pull = nil
        modeling.target = id
        modeling.elements = picked
        modeling.shapeOp = nil
        HmmHaptics.play(.selection)
        if let stage { HmmPencilHaptics.snapped(at: point, in: stage) }
        refreshModelOverlay()
        viewRevision &+= 1
        return true
    }

    // MARK: Dragging a part

    /// A drag starting on the selected shape: what it will do, nil when it's not on a part.
    func beginPartDrag(at point: CGPoint) -> PartDrag? {
        guard let (id, part) = modelPart(at: point) else { return nil }
        modeling.target = id
        modeling.elements = part
        modeling.region = nil
        modeling.lit = nil
        switch part.mode {
        case .face:
            guard prepareFacePull(), let axis = pullAxis else { return nil }
            return .face(axis, grab: pullDistance(at: point, axis: axis) ?? 0)
        case .edge:
            guard prepareShapeObject(id), let (mesh, world) = modelMesh(of: id), let edge = part.edges.first,
                  let middle = ModelingOperations.edgeMiddle(edge, in: mesh) else { return nil }
            return .edge(edge, anchor: world.apply(to: middle), start: point)
        case .vertex:
            guard prepareShapeObject(id), let corner = part.vertices.first, let (mesh, world) = modelMesh(of: id),
                  mesh.vertices.indices.contains(corner) else { return nil }
            return .corner(corner, start: world.apply(to: mesh.vertices[corner]), from: point)
        }
    }

    func continuePartDrag(_ drag: PartDrag, to point: CGPoint) {
        switch drag {
        case let .face(axis, grab):
            if let along = pullDistance(at: point, axis: axis) { updatePull(along - grab, axis: axis) }
        case let .edge(edge, anchor, start):
            let perPoint = stage?.worldPerPoint(at: anchor) ?? 0.001
            let raw = Double(hypot(point.x - start.x, point.y - start.y)) * perPoint * 0.5
            previewRound(edge, size: (raw / pullStep).rounded() * pullStep)
        case let .corner(corner, origin, from):
            previewCorner(corner, to: cornerTarget(origin, from: from, to: point))
        }
    }

    func endPartDrag(_ drag: PartDrag, commit: Bool) {
        switch drag {
        case .face:
            endPull(commit: commit)
        case let .edge(edge, anchor, _):
            let size = modeling.dragSize ?? 0
            clearPartPreview()
            guard commit, size > 1e-9, let id = modeling.target else { return }
            runShapeOp(ShapeOpRecord(kind: .round, object: id, edges: [edge], amount: size, anchor: anchor), fitting: true)
        case let .corner(corner, origin, _):
            let target = modeling.dragCorner
            clearPartPreview()
            guard commit, let target, let id = modeling.target else { return }
            let space = ModelingOperations.modellingSpace(of: id, in: baseScene)
            let delta = space.inverseApplyDirection(target - origin)
            if runModeling({ try ModelingOperations.moveCorners(id, corners: [corner], by: delta, in: baseScene) }) {
                modeling.elements = MeshSelection(mode: .vertex, vertices: [corner])
            }
        }
    }

    /// Where a dragged corner goes: across the plane facing you through where it started, its step the grid's.
    private func cornerTarget(_ origin: Vec3, from start: CGPoint, to point: CGPoint) -> Vec3 {
        guard let stage, let ray = stage.worldRay(at: point), let first = stage.worldRay(at: start) else { return origin }
        let facing = GuideSurface.plane(origin: origin, normal: -ray.direction)
        guard let hit = facing.intersect(ray)?.point, let begin = facing.intersect(first)?.point else { return origin }
        var delta = hit - begin
        if snapping.grid { delta = delta.map { ($0 / pullStep).rounded() * pullStep } }
        return origin + delta
    }

    private func previewRound(_ edge: MeshEdge, size: Double) {
        guard size != modeling.dragSize else { return }
        if let old = modeling.dragSize, (old / pullStep).rounded() != (size / pullStep).rounded() { HmmHaptics.play(.selection) }
        modeling.dragSize = size
        guard let id = modeling.target, let object = baseScene.objects[id], case let .mesh(mesh) = object.kind, size > 1e-9,
              let rounded = try? EdgeBevel.apply(mesh, edges: [edge], size: size, style: .round) else {
            kindOverride = [:]
            refreshDisplay()
            return
        }
        kindOverride = [id: .mesh(rounded)]
        refreshDisplay()
        viewRevision &+= 1
    }

    private func previewCorner(_ corner: Int, to target: Vec3) {
        guard let id = modeling.target, let object = baseScene.objects[id], case let .mesh(mesh) = object.kind,
              mesh.vertices.indices.contains(corner) else { return }
        modeling.dragCorner = target
        let local = scene.worldTransform(of: id).inverseApply(to: target)
        kindOverride = [id: .mesh(mesh.moving([corner: local]))]
        refreshDisplay()
        refreshModelOverlay()
    }

    private func clearPartPreview() {
        kindOverride = [:]
        modeling.dragSize = nil
        modeling.dragCorner = nil
        refreshDisplay()
    }

    // MARK: The knife

    /// A Pencil line across the shape with the knife armed: the faces under it are cut along it.
    func knifeCut(from start: CGPoint, to end: CGPoint) {
        modeling.knifeArmed = false
        guard let stage, let id = modeling.target ?? touchModelTarget, hypot(end.x - start.x, end.y - start.y) > 8,
              let first = stage.worldRay(at: start), let second = stage.worldRay(at: end), prepareShapeObject(id) else { return }
        // The plane the line sweeps away from the eye, in modelling space.
        let space = ModelingOperations.modellingSpace(of: id, in: baseScene)
        let eye = space.inverseApply(to: first.origin)
        let a = space.inverseApplyDirection(first.direction), b = space.inverseApplyDirection(second.direction)
        let normal = a.cross(b).normalized
        guard normal.lengthSquared > 0.5 else { return }
        let line = (Vec2(Double(start.x), Double(start.y)), Vec2(Double(end.x), Double(end.y)))
        let within: (Vec3) -> Bool = { [weak stage] point in
            guard let screen = stage?.screenPoint(of: space.apply(to: point)) else { return false }
            return Self.alongSegment(Vec2(Double(screen.x), Double(screen.y)), line)
        }
        if runModeling({ try ModelingOperations.knife(id, planePoint: eye, planeNormal: normal, within: within, in: baseScene) }) {
            modeling.elements = nil
        }
    }

    /// Whether a screen point lies between the ends of a drawn line (measured along it).
    static func alongSegment(_ point: Vec2, _ line: (Vec2, Vec2)) -> Bool {
        let along = line.1 - line.0
        let length = along.dot(along)
        guard length > 0 else { return false }
        let t = (point - line.0).dot(along) / length
        return t >= -0.02 && t <= 1.02
    }
}

/// The part lit under the hovering Pencil.
struct LitPart: Hashable, Sendable {
    var object: ObjectID
    var part: MeshSelection
}

/// A part being dragged with the Pencil: a face pulled along its normal, an edge rounded, a corner moved.
enum PartDrag: Sendable {
    case face(PullAxis, grab: Double)
    case edge(MeshEdge, anchor: Vec3, start: CGPoint)
    case corner(Int, start: Vec3, from: CGPoint)
}
