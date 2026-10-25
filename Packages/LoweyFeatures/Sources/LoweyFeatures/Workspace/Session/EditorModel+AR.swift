import CoreGraphics
import Foundation
import HmmWeb
import LoweyCore
import LoweyEngine
import UIKit

/// The AR view's state on the editor (M12).
struct ARViewState {
    /// The AR view is showing.
    var open = false
    /// The USDZ being shared for AR Quick Look (Share for AR).
    var share: URL?
    /// The bridge asked for a Monitor window (the editor screen opens it: only a view can open a window).
    var monitorRequested = false
}

/// The scene in the room on the iPad (M12): the AR view draws it with our own renderer over the camera; Share for AR
/// hands over a USDZ that AR Quick Look opens on any iPhone or iPad, without the app.
extension EditorModel {
    /// Whether this iPad can place the scene in the room.
    var canShowAR: Bool {
        ARStageView.isSupported
    }

    func openAR() {
        openPanel = nil
        pause()
        ar.open = true
    }

    func closeAR() {
        ar.open = false
        pause()
    }

    /// The frame the AR view draws at the playhead (the shot's scene; the AR view brings its own camera).
    func arFrame(size: CGSize) -> FrameRequest? {
        guard size.width > 1, size.height > 1 else { return nil }
        let builder = ShotBuilder(document: displayDocument, catalog: library.catalog, models: library.models)
        builder.mediaImage = { [weak self] key in self?.mediaImage(key) }
        builder.paintFile = paintFiles
        let framing: Framing = size.width >= size.height ? .landscape : .portrait
        return builder.request(at: time, framing: framing, size: size, frameIndex: timeline.frame(for: time), transparent: true,
                               animated: displayed, captions: false)
    }

    /// Share for AR: the scene as a USDZ in the share sheet.
    func shareForAR() {
        openPanel = nil
        ar.share = arShareFile()
    }

    /// The whole scene's box, for the table size.
    var arSceneBounds: Bounds? {
        SceneBounds(library: library.manifest).worldBounds(of: baseScene.roots, in: baseScene)
    }

    /// The scene as a USDZ in a temporary folder, to share: AR Quick Look opens it on any iPhone or iPad.
    func arShareFile() -> URL? {
        guard let file = modelFiles(.usdz, preset: .apps, selectionOnly: false, colors: .texture).first else { return nil }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("ar", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(ProjectStore.sanitize(baseScene.name.isEmpty ? "Scene" : baseScene.name))
            .appendingPathExtension("usdz")
        do {
            try file.data.write(to: url, options: .atomic)
            return url
        } catch {
            app.show("Couldn't make the AR file: \(error.localizedDescription)", kind: .error)
            return nil
        }
    }
}

// MARK: Pictures that play (kept here: the editor's file is at its length limit)

extension EditorModel {
    func makeVideoPreview() -> VideoFrames {
        let frames = VideoFrames(exact: false)
        frames.onFrame = { [weak self] in self?.stage?.redraw() }
        return frames
    }

    /// The web pieces' frames on the stage (the same player steps as an export's; the stage never waits).
    func makeWebPreview() -> HmmWebFrames {
        HmmWebPlayer.windowScene = { UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first }
        let frames = HmmWebFrames()
        frames.onFrame = { [weak self] in
            self?.overlayCache = StageOverlayCache()
            self?.stage?.redraw()
        }
        return frames
    }
}
