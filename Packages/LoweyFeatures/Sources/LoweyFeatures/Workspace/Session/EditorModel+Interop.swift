import Foundation
import HmmDesign
import LoweyCore

/// Bringing work in from other tools (X1): it comes in first and says afterwards, in a line, what changed on the way.
extension EditorModel {
    /// Whether a file is a three.js scene (`scene.toJSON()`), which comes into the scene rather than the library.
    static func isThreeJSON(_ url: URL) -> Bool {
        url.pathExtension.lowercased() == "json"
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
            guard perform(ModelingOperations.importScene(result.scene, in: baseScene)) else { return false }
            let count = result.scene.fragment.objects.count
            // One line: what came, then what changed on the way.
            let notes = result.notes.joined(separator: " ")
            if notes.isEmpty {
                app.show("Brought in \(count) things from three.js")
            } else {
                app.show("Brought in \(count) things from three.js. \(notes)")
            }
            HmmHaptics.play(.commit)
            return true
        } catch {
            app.show(String.LocalizationValue(String(describing: error)), kind: .error)
            return false
        }
    }
}
