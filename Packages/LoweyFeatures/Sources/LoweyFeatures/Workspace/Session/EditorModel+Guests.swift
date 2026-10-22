import CoreGraphics
import Foundation
import HmmDesign
import LoweyCore
import LoweyEngine
import PDFKit
import UIKit

/// G1, Room: the tap tools (columns, beams, people, names, terrain; holes and words for Print), the walk at eye height,
/// underlays to trace and setting them to scale.
extension EditorModel {
    /// One-tap and two-tap tools (corners take `buildCornerTap`).
    func guestTap(at point: CGPoint, tool: BuildTool) {
        switch tool {
        case .hole, .engrave:
            surfaceTap(at: point, tool: tool)
            return
        default:
            break
        }
        guard let result = snapPoint(at: point, plane: Self.groundPlane) else { return }
        let spot = result.point
        let id = ObjectID.make()
        let yaw = stage.map { atan2($0.viewpoint.eye.x - spot.x, $0.viewpoint.eye.z - spot.z) * 180 / .pi } ?? 0
        let command: EditCommand?
        switch tool {
        case .column: command = ModelingOperations.addColumn(at: spot, id: id)
        case .person: command = ModelingOperations.addPerson(at: spot, yaw: yaw, id: id)
        case .label: command = ModelingOperations.addLabel(String(localized: "Room"), at: spot, id: id)
        case .terrain: command = ModelingOperations.addTerrain(width: 30, depth: 30, hills: 1, at: Vec3(spot.x, -0.01, spot.z), seed: 1, id: id)
        case .beam:
            guard let first = modeling.build.first else {
                modeling.build = [Vec3(spot.x, max(spot.y, Architecture.wallHeight), spot.z)]
                viewRevision &+= 1
                return
            }
            modeling.build = []
            let end = Vec3(spot.x, first.y, spot.z)
            command = nil
            if runModeling({ try ModelingOperations.addBeam(from: first, to: end, id: id) }) { setSelection([id]) }
        default: command = nil
        }
        if let command, perform(command) {
            HmmHaptics.play(.commit)
            setSelection([id])
            if tool == .label { app.show("Rename it to name the room; plans write its area under it") }
        }
    }

    /// A screw hole or words where a modelled surface was tapped.
    private func surfaceTap(at point: CGPoint, tool: BuildTool) {
        guard let stage, let (id, hit) = stage.pickObject(at: point), let object = scene.objects[id], ModelingOperations.canModel(object) else {
            app.show(String.LocalizationValue(tool.hint))
            return
        }
        let current = baseScene
        let done = runModeling { [guest] in
            if tool == .hole {
                return try ModelingOperations.screwHole(guest.hole, guest.screw, in: id, at: hit.point, normal: hit.normal, tolerance: guest.tolerance,
                                                        in: current)
            }
            return try ModelingOperations.engrave(guest.text, into: id, at: hit.point, normal: hit.normal, size: guest.textSize, raised: false,
                                                  in: current)
        }
        if done { setSelection([id]) }
    }

    // MARK: Walking through

    /// The shot camera at eye height on the floor in the middle of the view, flown with the sticks but kept level with
    /// the eyes (Room's walk-through).
    func startWalking() {
        guard let stage else { return }
        if editedCamera == nil { addCamera() }
        let floor = dropPoint().y
        let target = stage.viewpoint.target
        var heading = target - stage.viewpoint.eye
        heading.y = 0
        let look = heading.length > 1e-6 ? heading.normalized : Vec3(0, 0, -1)
        let eye = Vec3(target.x, floor + 1.6, target.z) - look * 2
        guest.walkHeight = floor + 1.6
        setCameraWorld(CoreTransform(position: eye, rotation: Quat.rotation(from: Vec3(0, 0, -1), to: look)), gesture: "walk")
        endGesture()
        startFlying()
        app.show("Walking at eye height: the left stick walks, the right one looks round")
    }

    func stopWalking() {
        guest.walkHeight = nil
        stopFlying()
    }

    // MARK: Underlays

    static let underlayTypes = ["pdf", "dxf", "png", "jpg", "jpeg", "heic"]

    /// A plan to trace: a DXF at full size as a sketch on the ground, a PDF page at its drawing scale or a picture a
    /// tenth of a metre a hundred pixels, flat and faint; then set it to scale with two taps.
    func importUnderlay(_ source: URL) {
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }
        let id = ObjectID.make()
        let spot = dropPoint()
        do {
            let object: SceneObject
            switch source.pathExtension.lowercased() {
            case "dxf":
                let drawing = try DXF.read(Data(contentsOf: source))
                object = Underlay.sketch(drawing, at: spot, id: id)
                if drawing.skipped > 0 { app.show("\(drawing.skipped) things in the drawing weren't lines, circles or arcs and were left out") }
            case "pdf":
                guard let (file, aspect, points) = try renderPDFPage(source) else { throw DXF.Failure.notADrawing }
                object = Underlay.card(image: file, aspect: aspect, width: Underlay.width(pagePoints: points, scale: guest.underlayScale), at: spot, id: id)
            default:
                let file = uniqueMediaName(source.lastPathComponent)
                try FileManager.default.createDirectory(at: assetsFolder, withIntermediateDirectories: true)
                try FileManager.default.copyItem(at: source, to: assetsFolder.appendingPathComponent(file))
                let size = UIImage(contentsOfFile: assetsFolder.appendingPathComponent(file).path)?.size ?? CGSize(width: 1000, height: 1000)
                object = Underlay.card(image: file, aspect: size.width / max(size.height, 1), width: size.width / 1000, at: spot, id: id)
            }
            guard perform(.batch("Underlay", [.insert(SceneFragment(object: object), parent: nil, index: nil)])) else { return }
            guest.scaling = UnderlayScaling(object: id)
            startModeling(.measure)
            app.show("Tap two points of a length you know on it, then type that length")
        } catch {
            app.show(String.LocalizationValue((error as? DXF.Failure)?.description ?? error.localizedDescription), kind: .error)
        }
    }

    /// The PDF's first page as a picture in the project (4096 pixels across), its shape and its width in points.
    private func renderPDFPage(_ source: URL) throws -> (String, Double, Double)? {
        guard let document = PDFDocument(url: source), let page = document.page(at: 0) else { return nil }
        let box = page.bounds(for: .mediaBox)
        let side = 4096 / max(box.width, 1)
        let image = page.thumbnail(of: CGSize(width: box.width * side, height: box.height * side), for: .mediaBox)
        guard let png = image.pngData() else { return nil }
        let file = uniqueMediaName((source.deletingPathExtension().lastPathComponent) + ".png")
        try FileManager.default.createDirectory(at: assetsFolder, withIntermediateDirectories: true)
        try png.write(to: assetsFolder.appendingPathComponent(file), options: .atomic)
        return (file, box.width / max(box.height, 1), box.width)
    }

    /// The measure just taken on an underlay being set to scale: the underlay grows so it's `metres` long.
    func setUnderlayLength(_ metres: Double) {
        guard let scaling = guest.scaling, modeling.measure.count == 2, let object = baseScene.objects[scaling.object],
              let factor = Underlay.factor(from: modeling.measure[0], to: modeling.measure[1], real: metres) else { return }
        let scaled = Underlay.rescale(object, about: modeling.measure[0], by: factor)
        let changes: [EditCommand] = if case .sketch = scaled.kind {
            [.setKind(object.id, scaled.kind)]
        } else {
            [.setProperties([PropertyChange(object: object.id, key: .position, value: .vec3(scaled.transform.position)),
                             PropertyChange(object: object.id, key: .scale, value: .vec3(scaled.transform.scale))])]
        }
        if perform(.batch("Set to scale", changes)) {
            guest.scaling = nil
            modeling.measure = []
            app.show("The underlay is to scale: trace it with Walls")
        }
    }

    /// Procreate's palette (`.swatches`), kept with the picker's saved palettes.
    func importSwatches(_ source: URL) {
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: source), let json = try? ProcreateSwatchesFile.json(data),
              let palette = HmmPalette.procreate(swatchesJSON: json) else {
            app.show("This isn't a Procreate palette (.swatches)", kind: .error)
            return
        }
        var memory = HmmColourMemory.load()
        memory.palettes.append(palette)
        memory.save()
        app.show("“\(palette.name)” is in Colour ▸ Palettes")
    }
}
