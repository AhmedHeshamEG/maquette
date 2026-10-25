import AVFoundation
import Foundation
import LoweyCore
import UIKit
import UniformTypeIdentifiers

/// Pictures and videos in the shot (screenshots, clips, Manim renders), copied into the project: a thin card standing
/// in the world (the default), or flat over the frame (transparent graphics).
extension EditorModel {
    var assetsFolder: URL { projectURL.appendingPathComponent(ProjectLayout.assetsFolder) }
    var rendersFolder: URL { projectURL.appendingPathComponent(ProjectLayout.rendersFolder) }

    /// A media file of the project (nil when it isn't there).
    func mediaURL(_ file: String) -> URL? {
        let url = assetsFolder.appendingPathComponent(file)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// Copies a picture or video into the project and puts it in the shot, playing from `start` (default: the playhead).
    @discardableResult
    func importMedia(_ source: URL, at start: Double? = nil, as placement: MediaPlacement = .card) async -> ObjectID? {
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }
        do {
            try FileManager.default.createDirectory(at: assetsFolder, withIntermediateDirectories: true)
            let file = uniqueMediaName(source.lastPathComponent)
            let destination = assetsFolder.appendingPathComponent(file)
            try FileManager.default.copyItem(at: source, to: destination)
            if let piece = Self.webPiece(file, at: destination, start: start ?? time) {
                return addWebPiece(piece, as: placement)
            }
            if UTType(filenameExtension: destination.pathExtension)?.conforms(to: .movie) ?? false {
                return try await addVideo(file, at: destination, start: start ?? time, placement: placement)
            }
            let aspect = UIImage(contentsOfFile: destination.path).map { $0.size.width / max($0.size.height, 1) } ?? 1
            if placement == .card { return addMediaCard(CardRecipe(image: file, aspect: aspect)) }
            return addMediaOverlay(OverlayRecipe(shape: .image, image: file))
        } catch {
            app.show("Couldn't add \(source.lastPathComponent): \(error.localizedDescription)", kind: .error)
            return nil
        }
    }

    private func addVideo(_ file: String, at url: URL, start: Double, placement: MediaPlacement) async throws -> ObjectID? {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration).seconds
        var aspect = 16.0 / 9
        if let track = try await asset.loadTracks(withMediaType: .video).first {
            let natural = try await track.load(.naturalSize)
            let size = try await natural.applying(track.load(.preferredTransform))
            aspect = abs(size.width) / max(abs(size.height), 1)
        }
        if placement == .card {
            return addMediaCard(CardRecipe(video: file, videoStart: start, videoDuration: duration, aspect: aspect))
        }
        return addMediaOverlay(OverlayRecipe(shape: .image, video: file, videoStart: start, videoDuration: duration))
    }

    /// A card where you're looking, turned to face you, about 1.2 m tall. `named` replaces the file's name (a pinned
    /// reference is called what its frame was).
    @discardableResult
    func addMediaCard(_ recipe: CardRecipe, named: String? = nil) -> ObjectID? {
        let name = named ?? recipe.video ?? recipe.image ?? "Picture"
        var object = SceneObject(id: .make(), name: ObjectFactory.uniqueName((name as NSString).deletingPathExtension, in: scene), kind: .card(recipe))
        let ground = dropPoint()
        let yaw = stage.map { atan2($0.viewpoint.eye.x - ground.x, $0.viewpoint.eye.z - ground.z) } ?? 0
        object.transform = CoreTransform(position: ground, rotation: Quat(angle: yaw, axis: .unitY), scale: Vec3(1.2, 1.2, 1.2))
        object[.color] = .color(.rgba(RGBA(0.96, 0.95, 0.92)))
        object = operations.nudgedToFreeSpot(object, in: scene)
        guard perform(operations.add(object)) else { return nil }
        select(object.id)
        let start = recipe.videoStart ?? recipe.web?.start ?? 0
        app.show(recipe.video != nil || recipe.web != nil ? "Plays from \(TimeFormat.clock(start)). Move, turn and size it like any object"
            : "Move, turn and size it like any object")
        return object.id
    }

    /// Media flat over the frame, filling most of its height, on top.
    private func addMediaOverlay(_ recipe: OverlayRecipe, named: String? = nil) -> ObjectID? {
        let layer = Double(baseScene.objects.values.filter(\.kind.isOverlay).count)
        let name = named ?? recipe.video ?? recipe.image ?? "Media"
        let object = SceneObject(id: .make(), name: ObjectFactory.uniqueName((name as NSString).deletingPathExtension, in: scene), kind: .overlay(recipe),
                                 transform: CoreTransform(position: Vec3(0, 0, layer), scale: Vec3(2.6, 2.6, 1)))
        guard perform(operations.add(object)) else { return nil }
        select(object.id)
        app.show("Drag it in the frame; pinch to size it")
        return object.id
    }

    /// Pages, folders with a page and Lottie files are web pieces: they play on a card or over the frame (M12).
    static let webTypes: [UTType] = [.html, .folder, .json, UTType(filenameExtension: "lottie") ?? .json]

    /// The web piece a copied file or folder is, if it is one: a `.html`, a folder with an `index.html` (or one page), a
    /// Lottie `.json` (its size and length read from it).
    static func webPiece(_ file: String, at url: URL, start: Double) -> WebPiece? {
        var isFolder: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isFolder)
        if isFolder.boolValue {
            let pages = (try? FileManager.default.contentsOfDirectory(atPath: url.path))?.filter { $0.lowercased().hasSuffix(".html") } ?? []
            guard let entry = pages.contains("index.html") ? "index.html" : pages.min() else { return nil }
            return WebPiece(kind: .html, file: file, entry: entry, start: start)
        }
        switch url.pathExtension.lowercased() {
        case "html", "htm": return WebPiece(kind: .html, file: file, start: start)
        case "json", "lottie":
            guard let data = try? Data(contentsOf: url), let lottie = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  lottie["layers"] != nil, let rate = lottie["fr"] as? Double, rate > 0 else { return nil }
            let frames = ((lottie["op"] as? Double) ?? 0) - ((lottie["ip"] as? Double) ?? 0)
            return WebPiece(kind: .lottie, file: file, width: (lottie["w"] as? Int) ?? 512, height: (lottie["h"] as? Int) ?? 512, start: start,
                            duration: frames > 0 ? frames / rate : nil)
        default: return nil
        }
    }

    /// A web piece on a card where you're looking, or over the frame.
    func addWebPiece(_ piece: WebPiece, as placement: MediaPlacement, named: String? = nil) -> ObjectID? {
        let name = named ?? ((piece.file ?? "Web piece") as NSString).lastPathComponent
        if placement == .card {
            return addMediaCard(CardRecipe(aspect: piece.aspect, border: 0.015, web: piece), named: name)
        }
        return addMediaOverlay(OverlayRecipe(shape: .image, aspect: piece.aspect, web: piece), named: name)
    }

    func uniqueMediaName(_ original: String) -> String {
        let base = (original as NSString).deletingPathExtension
        let ext = (original as NSString).pathExtension
        var candidate = original
        var index = 2
        while FileManager.default.fileExists(atPath: assetsFolder.appendingPathComponent(candidate).path) {
            candidate = ext.isEmpty ? "\(base) \(index)" : "\(base) \(index).\(ext)"
            index += 1
        }
        return candidate
    }
}
