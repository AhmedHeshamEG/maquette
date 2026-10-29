import Foundation
import LoweyCore

/// Named regions of models made characters (Q2): their face states move the model's own corners, then its rig and its
/// paint go on exactly as for any surface, so a skinned, painted model blinks and talks with its own geometry.
extension SceneCompiler {
    /// The surface with its regions bent: the same unmoved base (paint is found there), the bent corners shown. Nil
    /// when nothing on it is away from rest.
    func regionSurface(_ surface: SurfaceMeshes, object: SceneObject, input: RenderInput) -> SurfaceMeshes? {
        regionMesh(surface.shown, object: object, input: input).map { SurfaceMeshes(base: surface.base, shown: $0.mesh) }
    }

    /// Corners in the object's own space (a surface, or a placed model's part) with its regions bent, and what that
    /// depends on (for the caches built from it). Nil when nothing on it is away from rest.
    func regionMesh(_ source: GPUMesh, object: SceneObject, input: RenderInput) -> (mesh: GPUMesh, key: Int)? {
        guard let bends = input.simulated.regions[object.id], !bends.isEmpty else { return nil }
        let key = Self.regionKey(bends, over: source)
        if let known = regionMeshes[key] { return (known, key) }
        guard let bent = GPUMesh(device: device, mesh: FaceRegions.bend(source.data, bends), label: "\(object.name) face") else { return nil }
        // A face only shows a handful of states; a blink passes through a few more. Start again past a small set.
        if regionMeshes.count > 64 { regionMeshes.removeAll() }
        regionMeshes[key] = bent
        return (bent, key)
    }

    /// What a bent surface depends on: the corners it starts from and each region's bend, to a fiftieth.
    static func regionKey(_ bends: [FaceRegionBend], over mesh: GPUMesh) -> Int {
        var hasher = Hasher()
        hasher.combine(ObjectIdentifier(mesh))
        for item in bends {
            hasher.combine(item.region)
            let bend = item.bend
            for value in [bend.open, bend.wide, bend.round, bend.smile, bend.lift, bend.tilt, bend.squash] {
                hasher.combine(Int((value * 50).rounded()))
            }
        }
        return hasher.finalize()
    }
}
