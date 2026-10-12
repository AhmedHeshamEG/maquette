import Foundation

/// Bringing a sculpt in (CONTEXT §10.8, "Bring your sculpt"): a model heavier than this iPad keeps smooth is lightened
/// as it comes in, its paint carried across, with no question asked; the Detail slider asks for more or less
/// afterwards, always from the original, which the library keeps.
public enum SculptImport {
    /// Triangles one model may keep on an iPad of this tier (`DeviceTier`'s A, B, C): what a scene with a few of them
    /// still draws inside the frame budget.
    public static func budget(tier: String) -> Int {
        switch tier.uppercased() {
        case "A": 500_000
        case "B": 200_000
        default: 80000
        }
    }

    /// The Detail slider's range, as a share of the budget.
    public static let detailRange: ClosedRange<Double> = 0.25 ... 2

    /// The triangles to keep for a detail (1 is the budget).
    public static func target(budget: Int, detail: Double) -> Int {
        Int(Double(budget) * min(max(detail, detailRange.lowerBound), detailRange.upperBound))
    }

    /// The model lightened to `target` triangles in all (each part its share; parts that move with a skeleton are kept
    /// whole), or nil when it's light enough already.
    public static func lightened(_ model: ImportedModel, target: Int) -> ImportedModel? {
        let total = model.triangleCount
        let unskinned = model.parts.filter { !$0.isSkinned }.reduce(0) { $0 + $1.mesh.triangleCount }
        // A picture wrapped on the surface would lose its place; sculpts carry their paint on their corners.
        let textured = model.materials.contains { $0.baseColorTexture != nil }
        guard total > target, unskinned > 0, !textured else { return nil }
        let room = max(target - (total - unskinned), target / 10)
        var result = model
        for index in result.parts.indices where !result.parts[index].isSkinned {
            let part = result.parts[index]
            let share = max(Int(Double(room) * Double(part.mesh.triangleCount) / Double(unskinned)), 4)
            let (mesh, colors) = MeshSimplify.simplified(part.mesh, colors: part.hasColors ? part.colors : [], target: share)
            result.parts[index].mesh = mesh
            result.parts[index].colors = colors
        }
        return result
    }

    /// Whether a model is heavier than the budget and can be lightened (a sculpt: no picture wrapped on it).
    public static func needsLightening(_ model: ImportedModel, budget: Int) -> Bool {
        model.triangleCount > budget && !model.materials.contains { $0.baseColorTexture != nil }
    }

    /// The lightened model as the file the library keeps: one GLB, its parts with their materials and colours.
    public static func glb(_ model: ImportedModel, name: String) -> Data {
        var scene = Scene(id: "sculpt", name: name)
        let object = SceneObject(id: "sculpt", name: name, kind: .asset("sculpt"))
        scene.objects[object.id] = object
        scene.roots = [object.id]
        let parts = model.parts.map { part in
            let material = model.materials.indices.contains(part.material) ? model.materials[part.material] : ImportedMaterial()
            return GLTFScene.LocalPart(name: part.name, mesh: part.mesh,
                                       material: ExportMaterial(color: material.baseColor, roughness: material.roughness, metallic: material.metallic),
                                       colors: part.hasColors ? part.colors : [])
        }
        return GLTFScene.glb(nil, in: scene, look: Look(), parts: { _ in parts })
    }
}

public extension LibraryStore {
    /// Keeps a lighter copy of an asset beside its original (which stays, for the Detail slider) and points the asset
    /// at it; a lighter copy made before is replaced.
    func storeLightened(_ model: ImportedModel, for asset: LibraryAsset, detail: Double) throws -> LibraryAsset {
        let folder = assetFolder(asset.id)
        let name = "light-\(Int((detail * 100).rounded())).glb"
        try SculptImport.glb(model, name: asset.name).write(to: folder.appendingPathComponent(name), options: .atomic)
        var result = asset
        if let original = asset.original {
            if asset.file != original, asset.file != name { try? FileManager.default.removeItem(at: folder.appendingPathComponent(asset.file)) }
        } else {
            result.original = asset.file
        }
        result.file = name
        result.format = .glb
        result.detail = detail
        result.triangleCount = model.triangleCount
        return result
    }

    /// The file a lightened asset came from.
    func originalURL(of asset: LibraryAsset) -> URL? {
        asset.original.map { assetFolder(asset.id).appendingPathComponent($0) }
    }
}
