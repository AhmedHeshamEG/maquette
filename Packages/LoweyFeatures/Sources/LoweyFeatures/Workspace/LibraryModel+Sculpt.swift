import Foundation
import HmmDiagnostics
import LoweyCore
import LoweyEngine

/// Bringing a sculpt in (CONTEXT §10.8): a model heavier than this iPad keeps smooth is lightened as it comes in, its
/// paint carried across, with no question and no message; the Detail slider lightens it again from the original,
/// more or less.
extension LibraryModel {
    /// Triangles one model may keep on this iPad (its tier, or the one forced with `-device-tier`).
    nonisolated static var budget: Int { SculptImport.budget(tier: DeviceTier.current().rawValue) }

    /// The asset as it should stay: lightened when it's heavier than the budget, else as it came.
    func lightenIfHeavy(_ asset: LibraryAsset) async -> LibraryAsset {
        guard let model = models.model(asset, catalog: catalog), SculptImport.needsLightening(model, budget: Self.budget) else { return asset }
        return await lighten(asset, from: model, detail: 1) ?? asset
    }

    /// The asset pointed at a lighter copy of `model` (off the main thread), its old copy let go so it loads again.
    func lighten(_ asset: LibraryAsset, from model: ImportedModel, detail: Double) async -> LibraryAsset? {
        let target = SculptImport.target(budget: Self.budget, detail: detail)
        let store = store
        let result: LibraryAsset? = await Task.detached(priority: .userInitiated) {
            guard let light = SculptImport.lightened(model, target: target) else { return nil }
            return try? store.storeLightened(light, for: asset, detail: detail)
        }.value
        guard let result, let index = manifest.assets.firstIndex(where: { $0.id == asset.id }) else { return nil }
        models.evict(asset.id)
        manifest.assets[index] = result
        save()
        return result
    }

    /// The Detail slider: the model lightened again from its original (or the original itself, when asked for more
    /// than it has).
    func setDetail(_ detail: Double, of id: AssetID) async {
        guard let asset = manifest.assets.first(where: { $0.id == id }), let url = store.originalURL(of: asset),
              let format = AssetFormat(fileExtension: url.pathExtension) else { return }
        let original: ImportedModel? = await Task.detached(priority: .userInitiated) { try? ModelLibrary.read(url: url, format: format).0 }.value
        guard let original, let index = manifest.assets.firstIndex(where: { $0.id == id }) else { return }
        if SculptImport.target(budget: Self.budget, detail: detail) >= original.triangleCount, let file = asset.original {
            manifest.assets[index].file = file
            manifest.assets[index].format = format
            manifest.assets[index].detail = detail
            manifest.assets[index].triangleCount = original.triangleCount
            models.evict(id)
            save()
            return
        }
        _ = await lighten(asset, from: original, detail: detail)
    }
}
