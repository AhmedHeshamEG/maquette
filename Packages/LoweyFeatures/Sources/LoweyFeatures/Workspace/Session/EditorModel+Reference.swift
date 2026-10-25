import CoreGraphics
import Foundation
import HmmDesign
import LoweyCore
import LoweyEngine
import UIKit

/// The Reference window (Q1, made like Procreate's Actions ▸ Canvas ▸ Reference): one floating window over the stage
/// with a grab bar, a close button and three modes: the whole scene from its own camera (Canvas), a picture (Image)
/// or the front camera (Face). It glides where it's let go, keeps off the clusters and the edges, resizes from its
/// corner or a pinch on its bar, and comes back where and as big as it was. Pick takes a colour from it. Its state is
/// the project's `workspace.json`: how you see the work, not the work, so it's never undone.
extension EditorModel {
    /// The window as it is now (the defaults until it's first opened).
    var referenceState: ReferenceWindow { placing.window ?? ReferenceWindow() }

    var referenceOpen: Bool { placing.window?.open ?? false }

    /// Actions ▸ Reference and ⌘⌥R: open it as it was, or close it.
    func toggleReferenceWindow() {
        if referenceOpen { closeReferenceWindow() } else { openReferenceWindow() }
    }

    func openReferenceWindow(mode: ReferenceWindow.Mode? = nil) {
        var window = referenceState
        if let mode { window.mode = mode }
        window.open = true
        if window.mode == .canvas, window.view == nil { window.view = canvasView(for: window, from: stage?.viewpoint) }
        setReferenceWindow(window)
        placing.hidden = false
        HmmHaptics.play(.selection)
        if AppIdentity.isUITesting { trail("reference=open \(window.mode.rawValue)") }
    }

    func closeReferenceWindow() {
        guard var window = placing.window, window.open else { return }
        window.open = false
        setReferenceWindow(window)
        HmmHaptics.play(.selection)
        if AppIdentity.isUITesting { trail("reference=closed") }
    }

    func setReferenceMode(_ mode: ReferenceWindow.Mode) {
        var window = referenceState
        guard window.mode != mode || !window.open else { return }
        window.mode = mode
        window.open = true
        if mode == .canvas, window.view == nil { window.view = canvasView(for: window, from: stage?.viewpoint) }
        setReferenceWindow(window)
        HmmHaptics.play(.selection)
        if AppIdentity.isUITesting { trail("reference=mode \(mode.rawValue)") }
    }

    /// The window let go at `center` (stage points) in a stage of `size`: it settles off the edges and the clusters.
    func moveReferenceWindow(to center: CGPoint, in size: CGSize, stageOrigin: CGPoint) {
        let window = referenceState.settled(at: center, in: size, avoiding: clusterRects(stageOrigin: stageOrigin))
        setReferenceWindow(window)
        if AppIdentity.isUITesting { trail("reference=at \(Int(window.frame(in: size).minX)),\(Int(window.frame(in: size).minY))") }
    }

    /// The window made as big as asked (its corner, or a pinch on its bar).
    func resizeReferenceWindow(width: Double, height: Double, in size: CGSize, stageOrigin: CGPoint) {
        var window = referenceState.sized(width: width, height: height, in: size, avoiding: clusterRects(stageOrigin: stageOrigin))
        if window.mode == .canvas, let view = window.view { window.view = canvasView(for: window, from: view) }
        setReferenceWindow(window)
        if AppIdentity.isUITesting { trail("reference=size \(Int(window.width))x\(Int(window.height))") }
    }

    /// The clusters' frames in the stage's own points.
    private func clusterRects(stageOrigin: CGPoint) -> [CGRect] {
        placing.clusterFrames.values.map { $0.offsetBy(dx: -stageOrigin.x, dy: -stageOrigin.y) }
    }

    private func setReferenceWindow(_ window: ReferenceWindow) {
        guard window != placing.window else { return }
        placing.window = window
        workspaceChanged()
    }

    /// A two-finger tap on the window: it steps out of the way for a moment.
    func hideReferenceForAMoment() {
        placing.hidden = true
        HmmHaptics.play(.selection)
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.5))
            self?.placing.hidden = false
        }
    }

    // MARK: Image

    /// A picture from Photos, Files, the clipboard or a drop: kept in the project and shown in the window, fitted whole.
    func addReference(imageData data: Data, title _: String = "") {
        guard let image = UIImage(data: data), let png = image.pngData() else {
            app.show("That isn't a picture", kind: .error)
            return
        }
        guard let file = keepReferencePicture(png) else { return }
        setReferenceWindow(referenceState.showing(image: file, aspect: image.size.height / max(image.size.width, 1)))
        placing.hidden = false
        HmmHaptics.play(.commit)
        if AppIdentity.isUITesting { trail("reference=image") }
    }

    /// Writes a picture under the project's assets (named by its content, so the same picture is kept once).
    func keepReferencePicture(_ png: Data) -> String? {
        let file = "\(ProjectLayout.referencesFolder)/\(BrushKey.hex(BrushKey.fnv(png))).png"
        let url = assetsFolder.appendingPathComponent(file)
        do {
            if !FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try png.write(to: url, options: .atomic)
            }
            return file
        } catch {
            app.show("Couldn't keep that picture: \(error.localizedDescription)", kind: .error)
            return nil
        }
    }

    /// The window's Paste: the picture on the clipboard.
    func pasteReference() {
        guard let data = UIPasteboard.general.image?.pngData() else {
            app.show("There's no picture on the clipboard")
            return
        }
        addReference(imageData: data)
    }

    /// The window's Clear: the picture goes (its file stays in the project, like any media).
    func clearReferenceImage() {
        guard referenceState.image != nil else { return }
        setReferenceWindow(referenceState.cleared)
        HmmHaptics.play(.selection)
    }

    /// One finger moved the picture inside the window.
    func panReferenceImage(by drag: CGSize) {
        setReferenceWindow(referenceState.panned(by: drag))
    }

    /// Two fingers zoomed the picture about `focus` (the window's content points).
    func zoomReferenceImage(by scale: Double, about focus: CGPoint) {
        setReferenceWindow(referenceState.zoomed(by: scale, about: focus))
        if AppIdentity.isUITesting { trail("reference=zoom \(String(format: "%.1f", referenceState.zoom))") }
    }

    func referenceImageURL(_ file: String) -> URL {
        assetsFolder.appendingPathComponent(file)
    }

    /// The window's picture as a card, for Trace it and Stand it (the same as a pinned picture's).
    var referenceImageCard: ReferenceCard? {
        guard let file = referenceState.image else { return nil }
        return ReferenceCard(id: "reference-window", image: file, aspect: referenceState.imageAspect ?? 1)
    }

    // MARK: Canvas

    /// The whole scene from `angle`'s side, framed for the window's shape.
    func canvasView(for window: ReferenceWindow, from angle: Viewpoint?) -> Viewpoint {
        ReferenceWindow.canvasView(framing: allBounds, from: angle ?? Viewpoint(), aspect: window.width / max(window.height, 1))
    }

    /// The window's ⌖: Canvas shows the whole scene again, from where the stage looks now.
    func reframeReferenceCanvas() {
        var window = referenceState
        window.view = canvasView(for: window, from: stage?.viewpoint)
        setReferenceWindow(window)
        HmmHaptics.play(.selection)
    }

    /// What the Canvas window draws: the scene as the stage has it (so it's live), through its own camera, no helpers.
    func referenceCanvasFrame(for view: StageView) -> StageFrame? {
        let scale = view.contentScaleFactor
        guard view.bounds.width > 1, view.bounds.height > 1, scale > 0 else { return nil }
        let viewpoint = referenceState.view ?? canvasView(for: referenceState, from: nil)
        var input = RenderInput(document: displayDocument, time: time, poses: displayed.poses, showsHelpers: false,
                                mediaImage: { [weak self] key in self?.mediaImage(key) }, catalog: library.catalog, lightBudget: 8)
        input.paintFile = paintFiles
        let camera = RenderCamera(viewpoint: viewpoint)
        return StageFrame(request: FrameRequest(input: input, camera: camera, frameIndex: timeline.frame(for: time)), shotCamera: camera)
    }

    // MARK: Pick

    /// Pick on the window takes the colour there: a picture's pixel, what the Canvas shows (its thing's paint or
    /// colour), or the front camera's pixel.
    func pickReferenceColour(_ colour: RGBA?) {
        guard let colour else {
            app.show("Nothing to take a colour from there")
            return
        }
        currentColor = .rgba(colour)
        pickActive = false
        eyedropping = false
        HmmHaptics.play(.commit)
    }

    /// The colour of what the Canvas window shows at a point of it.
    func referenceCanvasColour(at point: CGPoint) -> RGBA? {
        guard let canvas = placing.canvas else { return nil }
        return colour(at: point, in: canvas)
    }

    /// Pick (the sidebar's eyedropper) on a pinned picture: its colour at `unit` (0…1 across and down).
    func pickColour(from image: UIImage, at unit: CGPoint) {
        pickReferenceColour(Self.colour(of: image, at: unit))
    }

    /// One pixel of a picture, in sRGB.
    static func colour(of image: UIImage, at unit: CGPoint) -> RGBA? {
        guard let cgImage = image.cgImage else { return nil }
        return colour(of: cgImage, at: unit)
    }

    static func colour(of cgImage: CGImage, at unit: CGPoint) -> RGBA? {
        guard cgImage.width > 0, cgImage.height > 0 else { return nil }
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

    // MARK: The bridge

    /// What a script asked of the window (`{"do": "reference", …}`), in order, after its command.
    func applyReference(_ asks: [ReferenceAsk]) {
        for ask in asks {
            switch ask {
            case let .open(mode): openReferenceWindow(mode: mode)
            case let .mode(mode): setReferenceMode(mode)
            case let .image(file):
                guard FileManager.default.fileExists(atPath: referenceImageURL(file).path),
                      let image = UIImage(contentsOfFile: referenceImageURL(file).path) else { continue }
                setReferenceWindow(referenceState.showing(image: file, aspect: image.size.height / max(image.size.width, 1)))
            case .frame:
                if !referenceOpen { openReferenceWindow(mode: .canvas) }
                reframeReferenceCanvas()
            case .close: closeReferenceWindow()
            }
        }
    }

    // MARK: Pictures pinned from the Board

    /// Folds a pinned picture to a small chip, or opens it again.
    func foldReference(_ id: String, folded: Bool) {
        guard let index = references.firstIndex(where: { $0.id == id }) else { return }
        references[index].folded = folded ? true : nil
        workspaceChanged()
        HmmHaptics.play(.selection)
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
