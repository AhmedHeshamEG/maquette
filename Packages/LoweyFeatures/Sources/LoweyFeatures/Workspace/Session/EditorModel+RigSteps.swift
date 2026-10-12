import CoreGraphics
import Foundation
import LoweyCore
import LoweyEngine

/// The surface marks are placed on: built once when a touch starts, asked for every sample after.
struct BoneSurface {
    var object: ObjectID
    /// nil for a drawing: its marks lie on its plane.
    var tree: TriangleBVH?
    /// Every vertex in the rig's space (for the body's root, and for guesses).
    var points: [Vec3]
}

/// Where marks land in a thing (the middle of the part under the Pencil), and the chain a stroke would make, shown as
/// it's drawn.
extension EditorModel {
    /// The surface the object's marks are placed on (kept until the touch ends). A group's surface is all its parts,
    /// in the group's space.
    func boneSurface(of object: SceneObject) -> BoneSurface? {
        if let boneSurface, boneSurface.object == object.id { return boneSurface }
        let surface: BoneSurface
        if case let .drawing(recipe) = object.kind {
            surface = BoneSurface(object: object.id, tree: nil, points: recipe.strokes.flatMap(\.points))
        } else {
            guard let mesh = rigSurfaceMesh(of: object), !mesh.isEmpty else { return nil }
            surface = BoneSurface(object: object.id, tree: TriangleBVH(mesh),
                                  points: mesh.positions.map { Vec3(Double($0.x), Double($0.y), Double($0.z)) })
        }
        boneSurface = surface
        return surface
    }

    /// The mesh marks are placed on, in the rig's space: the object's own, or a group's parts together.
    func rigSurfaceMesh(of object: SceneObject) -> MeshData? {
        guard case .group = object.kind else { return paintSource(of: object) }
        let frame = rigFrame(object.id)
        var merged = MeshData()
        for id in baseScene.subtree(of: object.id) where id != object.id {
            guard let part = baseScene.objects[id], let mesh = paintSource(of: part) else { continue }
            let partFrame = RigSpace.frame(of: id, in: baseScene)
            var placed = mesh
            placed.positions = mesh.positions.map { position in
                let world = partFrame.apply(to: Vec3(Double(position.x), Double(position.y), Double(position.z)))
                let local = frame.inverseApply(to: world)
                return SIMD3<Float>(Float(local.x), Float(local.y), Float(local.z))
            }
            merged.append(placed)
        }
        return merged.isEmpty ? nil : merged
    }

    /// A stroke's rays (in the world) as the centreline it draws through the object, in the rig's space.
    func boneSamples(_ worldRays: [Ray], through surface: BoneSurface, of object: SceneObject) -> [BoneStroke.Sample] {
        let frame = rigFrame(object.id)
        let rays = worldRays.map { ray in
            let origin = frame.inverseApply(to: ray.origin)
            return Ray(origin: origin, direction: (frame.inverseApply(to: ray.origin + ray.direction) - origin).normalized)
        }
        if let tree = surface.tree { return BoneStroke.centreline(rays: rays, surface: tree) }
        guard case let .drawing(recipe) = object.kind else { return [] }
        let plane = RigOperations.drawingPlane(recipe)
        return BoneStroke.onPlane(rays: rays, origin: plane.origin, normal: plane.normal)
    }

    /// While the Pencil is still down: the marks the stroke so far would make, shown inside the object.
    func previewBone(along points: [CGPoint]) {
        guard let stage, let object = rigTarget, let surface = boneSurface(of: object) else { return }
        let samples = boneSamples(points.compactMap { stage.worldRay(at: $0) }, through: surface, of: object)
        rigging.preview = BoneStroke.preview(samples)
    }

    /// The touch is over (kept or not): the preview goes and the surface is let go.
    func endBonePreview() {
        boneSurface = nil
        if !rigging.preview.isEmpty { rigging.preview = [] }
    }

    /// The joints of `old` a new rig no longer has. Joints keep their marks' names when marks move, so a joint is gone
    /// only when its name is.
    func jointsGone(from old: ObjectRig, in rig: ObjectRig) -> Set<String> {
        Set(old.skeleton.names).subtracting(rig.skeleton.names)
    }

    /// Taking away what joints that are gone held: their turns and their keys.
    func forgetting(_ gone: Set<String>, of object: SceneObject) -> [EditCommand] {
        guard !gone.isEmpty else { return [] }
        func isGone(_ key: PropertyKey) -> Bool { key.boneJoint.map(gone.contains) ?? false }
        var commands: [EditCommand] = []
        let turns = object.properties.keys.filter(isGone).sorted().map { PropertyChange(object: object.id, key: $0, value: nil) }
        if !turns.isEmpty { commands.append(.setProperties(turns)) }
        let tracks = timeline.tracks.filter { $0.target == object.id && isGone($0.property) }.map { TrackEdit(id: $0.id, track: nil) }
        if !tracks.isEmpty { commands.append(.setTracks(tracks)) }
        return commands
    }

    /// The chain being drawn, on the stage: its marks and the bones between them, in the accent colour.
    func bonePreviewOverlays(_ stage: StageView) -> [EditorOverlay] {
        guard rigging.preview.count >= 2, let object = rigTarget else { return [] }
        let frame = rigFrame(object.id)
        let joints = rigging.preview.map { frame.apply(to: $0) }
        let width = stage.worldPerPoint(at: joints[0]) * 2.4
        var lines = MeshData()
        var dots = MeshData()
        for (head, tail) in zip(joints, joints.dropFirst()) {
            ModelOverlay.line(head, tail, width: width, into: &lines)
        }
        for joint in joints {
            ModelOverlay.dot(joint, radius: width * 2, into: &dots)
        }
        return [EditorOverlay(mesh: lines, color: Self.modelAccent, onTop: true), EditorOverlay(mesh: dots, color: RGBA(1, 1, 1), onTop: true)]
    }
}
