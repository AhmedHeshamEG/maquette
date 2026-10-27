import Foundation
import HmmDesign
import LoweyCore
import LoweyEngine

/// Bringing work in from other tools (X1): it comes in first and says afterwards, in a line, what changed on the way.
extension EditorModel {
    /// Whether a file is a three.js scene (`scene.toJSON()`), which comes into the scene rather than the library.
    static func isThreeJSON(_ url: URL) -> Bool {
        url.pathExtension.lowercased() == "json"
    }

    /// Whether a JSON file is three.js's own (`"metadata": {"type": "Object"}`), not a Scene Script or a Lottie file.
    static func isThreeSceneFile(_ url: URL) -> Bool {
        guard isThreeJSON(url) else { return false }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url), let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
        return (json["metadata"] as? [String: Any])?["type"] as? String == "Object"
    }

    /// A three.js scene file into the scene as editable things and keys, as one step.
    @discardableResult
    func bringInThreeJSON(_ url: URL) -> Bool {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        var ids = operations.ids
        defer { operations.ids = ids }
        do {
            let result = try ThreeObjectReader.read(Data(contentsOf: url), ids: &ids)
            guard result.scene.pictures.isEmpty, result.scene.files.isEmpty else {
                bringInPainted(result)
                return true
            }
            guard perform(ModelingOperations.importScene(result.scene, in: baseScene)) else { return false }
            broughtIn(result)
            return true
        } catch {
            app.show(String.LocalizationValue(String(describing: error)), kind: .error)
            return false
        }
    }

    /// One line: what came, then what changed on the way.
    func broughtIn(_ result: ThreeObjectReader.Result) {
        let count = result.scene.fragment.objects.count
        let notes = result.notes.joined(separator: " ")
        if notes.isEmpty {
            app.show("Brought in \(count) things from three.js")
        } else {
            app.show("Brought in \(count) things from three.js. \(notes)")
        }
        HmmHaptics.play(.commit)
    }

    /// A scene whose surfaces carry pictures or skins: the pictures are laid on as paint in the background, the skins'
    /// files written, then everything arrives as one step.
    func bringInPainted(_ result: ThreeObjectReader.Result) {
        let folder = assetsFolder
        Task {
            let scene = result.scene
            let made = await Task.detached(priority: .userInitiated) {
                scene.paints(in: scene.fragment, decode: { AssetPaint.decode($0.data) }, encode: PaintPixels.png)
            }.value
            do {
                try await Self.write(made.files.merging(scene.files) { first, _ in first }, to: folder)
            } catch {
                app.show("Couldn't save the painting's files: \(error.localizedDescription)", kind: .error)
                return
            }
            guard case let .batch(name, commands) = ModelingOperations.importScene(scene, in: baseScene),
                  perform(.batch(name, commands + made.commands)) else { return }
            broughtIn(result)
        }
    }
}
