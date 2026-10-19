import Foundation
import LoweyCore
import UIKit

/// The Keeper's Tower (L2): a sample made fresh when asked, and the Samples stack on Home showing it turning. Its
/// picture is drawn once a version and kept in the caches, so Home never waits for it.
extension AppModel {
    func createTowerSample(open shouldOpen: Bool) {
        do {
            let (info, scenes) = try KeepersTowerSample.build(ids: .random)
            var fresh = info
            fresh.id = .make()
            fresh.created = Date()
            fresh.modified = Date()
            let url = try projectStore.writeProject(info: fresh, scenes: scenes)
            refreshProjects()
            if shouldOpen { open(url: url) }
        } catch {
            show("Couldn't add the Keeper's Tower: \(error.localizedDescription)", kind: .error)
        }
    }

    static var samplesCardFolder: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("Samples card", isDirectory: true)
    }

    /// The turning Tower the Samples stack plays (this version's).
    var samplesLoopURL: URL {
        Self.samplesCardFolder.appendingPathComponent("tower-\(AppIdentity.shortVersion).gif")
    }

    /// Draws the Samples stack's picture once a version: a still first, then the turntable.
    func drawSamplesCard() async {
        guard !AppIdentity.isUITesting || AppIdentity.isTakingScreenshots else { return }
        let folder = Self.samplesCardFolder
        let stillURL = folder.appendingPathComponent("tower-\(AppIdentity.shortVersion).png")
        if let still = UIImage(contentsOfFile: stillURL.path), FileManager.default.fileExists(atPath: samplesLoopURL.path) {
            samplesStill = still
            return
        }
        guard let (info, scenes) = try? KeepersTowerSample.build(), let scene = scenes.first else { return }
        let document = Document(project: info, scene: scene)
        guard let still = try? await thumbnailer.still(document, viewpoint: scene.viewpoint, width: 640, height: 360, catalog: library.catalog,
                                                       models: library.models) else { return }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let image = UIImage(cgImage: still)
        try? image.pngData()?.write(to: stillURL, options: .atomic)
        samplesStill = image
        let turntable = await (try? thumbnailer.turntable(document, pitch: scene.viewpoint.pitch, catalog: library.catalog,
                                                          models: library.models)) ?? []
        if turntable.count > 1 { try? Thumbnailer.writeLoop(turntable, to: samplesLoopURL) }
        samplesRevision += 1
    }
}
