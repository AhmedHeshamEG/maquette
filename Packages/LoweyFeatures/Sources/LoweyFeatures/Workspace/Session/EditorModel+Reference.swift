import CoreGraphics
import Foundation
import HmmDesign
import LoweyCore
import UIKit

/// The Reference window (CONTEXT §10.10, as in Procreate): any picture floats over the stage, moves, resizes and folds
/// to a chip; with Pick in the hand a tap on it takes its colour; one tap stands it on the sheet to trace against. The
/// Board's pins are the same cards and keep working.
extension EditorModel {
    /// A picture from Photos, the clipboard or a drop, kept in the project and floated over the stage.
    func addReference(imageData data: Data, title: String = "") {
        guard let image = UIImage(data: data), let png = image.pngData() else {
            app.show("That isn't a picture", kind: .error)
            return
        }
        let file = "\(ProjectLayout.referencesFolder)/\(BrushKey.hex(BrushKey.fnv(png))).png"
        let url = assetsFolder.appendingPathComponent(file)
        do {
            if !FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try png.write(to: url, options: .atomic)
            }
        } catch {
            app.show("Couldn't keep that picture: \(error.localizedDescription)", kind: .error)
            return
        }
        let place = ReferenceCard.place(after: references)
        var card = ReferenceCard(id: UUID().uuidString, image: file, title: title, x: place.x, y: place.y, width: 300,
                                 aspect: image.size.height / max(image.size.width, 1))
        card.window = true
        references.append(card)
        workspaceChanged()
        HmmHaptics.play(.commit)
    }

    /// Actions ▸ Reference ▸ Paste: the picture on the clipboard.
    func pasteReference() {
        guard let data = UIPasteboard.general.image?.pngData() else {
            app.show("There's no picture on the clipboard")
            return
        }
        addReference(imageData: data)
    }

    /// Folds a reference to a small chip, or opens it again.
    func foldReference(_ id: String, folded: Bool) {
        guard let index = references.firstIndex(where: { $0.id == id }) else { return }
        references[index].folded = folded ? true : nil
        workspaceChanged()
        HmmHaptics.play(.selection)
    }

    /// Pick (the sidebar's eyedropper) on a reference: its colour at `unit` (0…1 across and down) is the colour in the
    /// hand.
    func pickColour(from image: UIImage, at unit: CGPoint) {
        guard let color = Self.colour(of: image, at: unit) else { return }
        currentColor = .rgba(color)
        pickActive = false
        HmmHaptics.play(.commit)
    }

    /// One pixel of a picture, in sRGB.
    static func colour(of image: UIImage, at unit: CGPoint) -> RGBA? {
        guard let cgImage = image.cgImage, cgImage.width > 0, cgImage.height > 0 else { return nil }
        let x = min(max(Int(unit.x * CGFloat(cgImage.width)), 0), cgImage.width - 1)
        let y = min(max(Int(unit.y * CGFloat(cgImage.height)), 0), cgImage.height - 1)
        var pixel = [UInt8](repeating: 0, count: 4)
        let drawn: Bool = pixel.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                          space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            // The picture placed so that pixel (x, y) lands on the context's one pixel (Core Graphics counts from the bottom).
            context.draw(cgImage, in: CGRect(x: -x, y: y - cgImage.height + 1, width: cgImage.width, height: cgImage.height))
            return true
        }
        guard drawn else { return nil }
        let alpha = max(Double(pixel[3]) / 255, 1e-6)
        return RGBA(min(Double(pixel[0]) / 255 / alpha, 1), min(Double(pixel[1]) / 255 / alpha, 1), min(Double(pixel[2]) / 255 / alpha, 1))
    }

    /// Stands the picture on the sheet (where it is, the size of it, half see-through) to draw over it. One undo step,
    /// the sheet kept with it.
    func traceReference(_ card: ReferenceCard) {
        guard let stage else { return }
        let viewpoint = stage.viewpoint
        let sheet = currentSheet ?? .facing(eye: viewpoint.eye, at: viewpoint.target, id: Self.newID(), name: baseScene.nextSheetName(),
                                            size: sheetSize(at: viewpoint.target))
        if drawingSheet == nil { drawingSheet = sheet }
        guard let frame = sheet.worldFrame(in: displayed.scene) else { return }
        let height = max(sheet.height * 0.8, 0.1)
        let up = frame.rotation.act(.unitY), normal = frame.rotation.act(.unitZ)
        let name = card.title.isEmpty ? String(localized: "Reference") : card.title
        var object = SceneObject(id: .make(), name: ObjectFactory.uniqueName(String(localized: "Trace: \(name)"), in: scene),
                                 kind: .card(CardRecipe(image: card.image, aspect: 1 / max(card.aspect, 0.01))))
        // A card stands on its bottom edge: half its height under the sheet's middle, a hair in front of it.
        object.transform = CoreTransform(position: frame.origin - up * (height / 2) + normal * 0.004, rotation: frame.rotation,
                                         scale: Vec3(height, height, height))
        object[.color] = .color(.rgba(RGBA(0.96, 0.95, 0.92)))
        object[.opacity] = .float(0.5)
        guard perform(keepingSheet(operations.add(object))) else { return }
        HmmHaptics.play(.commit)
        app.show("On the sheet, half see-through: draw over it")
    }
}
