import Foundation
import LoweyCore

/// What a physics run needs from the app, gathered as values so the run itself can go to the background: every
/// thing's local mesh (placed models' parts merged), and the skeletons of rigged things (drawn rigs and rigged models).
public struct PhysicsSources: Sendable {
    public var meshes: [ObjectID: MeshData]
    public var skeletons: [ObjectID: Skeleton]

    /// The meshes of everything real (and, when there's a fluid, of every surface it may meet).
    @MainActor
    public static func gather(_ document: Document, catalog: AssetCatalog, models: ModelLibrary = .shared) -> PhysicsSources {
        let scene = document.scene
        guard PhysicsInput.hasPhysics(scene) else { return PhysicsSources(meshes: [:], skeletons: [:]) }
        let look = document.effectiveLook
        let fluids = scene.objects.values.contains {
            if case .fluid = $0.kind {
                true
            } else {
                false
            }
        }
        let wanted: [ObjectID] = fluids ? Array(scene.objects.keys) : PhysicsInput.realThings(in: scene).flatMap { scene.subtree(of: $0) }
        var meshes: [ObjectID: MeshData] = [:]
        var skeletons: [ObjectID: Skeleton] = [:]
        for id in wanted {
            guard let object = scene.objects[id] else { continue }
            if let mesh = local(object, look: look, catalog: catalog, models: models) { meshes[id] = mesh }
            if let rig = object.rig {
                skeletons[id] = rig.skeleton
            } else if let asset = object.kind.assetID, let rig = models.rig(asset) {
                skeletons[id] = rig.skeleton
            }
        }
        return PhysicsSources(meshes: meshes, skeletons: skeletons)
    }

    /// A thing's own triangles in its own space: Core's shapes, else a placed model's parts as one mesh.
    @MainActor
    public static func local(_ object: SceneObject, look: Look, catalog: AssetCatalog, models: ModelLibrary = .shared) -> MeshData? {
        if let mesh = SceneExport.localMesh(of: object, look: look), !mesh.isEmpty { return mesh }
        let parts = ModelExport.localParts(object, look: look, catalog: catalog, models: models)
        guard !parts.isEmpty else { return nil }
        var merged = MeshData()
        for part in parts {
            merged.append(part.mesh)
        }
        return merged
    }

    /// The run's input (built off the main thread: it evaluates the timeline once per frame for things that follow keys).
    public func input(_ document: Document) -> PhysicsInput? {
        let meshes = meshes
        let skeletons = skeletons
        return PhysicsInput.make(document, mesh: { meshes[$0.id] }, skeleton: { skeletons[$0.id] })
    }
}

public extension ExportSession {
    /// The whole physics run before the first frame (an export never shows a run still being made). A complete run the
    /// stage already made for the same scene is used as it is.
    func preparePhysics(reusing known: PhysicsFrames? = nil) async {
        let document = builder.document
        guard PhysicsInput.hasPhysics(document.scene) else {
            builder.physics = nil
            return
        }
        let sources = PhysicsSources.gather(document, catalog: builder.catalog, models: builder.models)
        let frames = await Task.detached(priority: .userInitiated) { () -> PhysicsFrames? in
            guard let input = sources.input(document) else { return nil }
            if let known, known.isComplete, known.key == input.key { return known }
            return PhysicsSimulator.run(input)
        }.value
        builder.physics = frames
    }
}
