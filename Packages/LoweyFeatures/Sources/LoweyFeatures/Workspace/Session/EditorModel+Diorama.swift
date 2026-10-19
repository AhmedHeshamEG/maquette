import Foundation
import HmmDesign
import LoweyCore
import LoweyEngine
import UniformTypeIdentifiers

/// Bring your drawing (L2, D-487): a layered Photoshop or Procreate file stands up as a diorama where you look, a thin
/// painted sheet a layer, the bottom one at the back. One undo step. The work happens off the main thread and the sheets
/// land when they're ready; nothing says "getting ready".
extension EditorModel {
    /// What Model ▸ Add ▸ Drawing, Home's import and a drop take as a layered drawing.
    static let drawingTypes: [UTType] = [UTType("com.adobe.photoshop-image"), UTType(filenameExtension: "psb"),
                                         UTType(filenameExtension: ProcreateReader.fileExtension)].compactMap(\.self)

    /// Stands the drawing at `source` up as a diorama; returns its group (nil when it couldn't be read).
    @discardableResult
    func importDrawing(_ source: URL) async -> ObjectID? {
        let scoped = source.startAccessingSecurityScopedResource()
        let data = try? Data(contentsOf: source)
        if scoped { source.stopAccessingSecurityScopedResource() }
        guard let data else {
            app.show("Couldn't read \(source.lastPathComponent)", kind: .error)
            return nil
        }
        let name = ObjectFactory.uniqueName((source.lastPathComponent as NSString).deletingPathExtension, in: scene)
        let made = await Task.detached(priority: .userInitiated) { () -> Result<DioramaImport.Result, Error> in
            Result { try DioramaImport.make(LayeredImage.read(data), name: name, makeID: { .make() }, encode: PaintPixels.png) }
        }.value
        guard case var .success(result) = made else {
            if case let .failure(error) = made {
                let reason = (error as? LayeredReadFailure)?.description ?? error.localizedDescription
                app.show(String.LocalizationValue(reason), kind: .error)
            }
            return nil
        }
        do {
            try await Self.write(result.files, to: assetsFolder)
        } catch {
            app.show("Couldn't save the drawing's paint: \(error.localizedDescription)", kind: .error)
            return nil
        }
        if let index = result.objects.firstIndex(where: { $0.id == result.root }) {
            result.objects[index] = operations.nudgedToFreeSpot(operations.placeOnGround(result.objects[index], at: dropPoint()), in: scene)
        }
        guard perform(.insert(SceneFragment(objects: result.objects, roots: [result.root]), parent: nil, index: nil)) else { return nil }
        select(result.root)
        HmmHaptics.play(.commit)
        app.show(String.LocalizationValue(Self.drawingLine(result)))
        return result.root
    }

    /// What came in, and what didn't, in one line.
    static func drawingLine(_ result: DioramaImport.Result) -> String {
        let sheets = result.objects.filter { $0.kind != .group }.count
        var notes: [String] = []
        let skipped = result.skipped.values.reduce(0, +)
        if skipped > 0 { notes.append(String(localized: "\(skipped) layers with nothing to show left out")) }
        if result.mixesLost > 0 { notes.append(String(localized: "\(result.mixesLost) mixing layers show as they are")) }
        let made = String(localized: "\(sheets) layers, each a painted sheet. Pin and rig them in Rig")
        return notes.isEmpty ? made : made + " · " + notes.joined(separator: " · ")
    }
}
