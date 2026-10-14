import CoreGraphics
import Foundation
import HmmDesign
import LoweyCore
import LoweyEngine

/// Flipbook tracks: frame-by-frame drawing on the sheet in the space (CONTEXT §10.10), or stuck to the camera as
/// screen effects; drawn effects ride on an object. The Pencil draws into the drawing at the playhead; drawing past
/// the last one keeps the flipbook going. Every change is one `setFlipbooks` command.
extension EditorModel {
    var flipbookTracks: [FlipbookTrack] { timeline.flipbooks }

    /// The track the Pencil draws into.
    var activeFlipbook: FlipbookTrack? { flipbook.track.flatMap(timeline.flipbook) }

    /// The drawing of the active track at the playhead.
    var activeFlipbookFrame: Int? {
        activeFlipbook?.frameIndex(at: time, fps: timeline.fps, sceneDuration: timeline.duration)
    }

    // MARK: Layout on the stage

    /// Flipbooks laid out in stage points (inside `frameRect`), through the camera the stage shows.
    func stageFlipbookLayout() -> (layout: FlipbookLayout, rect: CGRect)? {
        guard let stage else { return nil }
        let rect = frameRect
        guard rect.width > 1, rect.height > 1 else { return nil }
        let camera = directorShot(in: stage.bounds.size)?.camera ?? stage.camera
        let pose = CoreTransform(position: Vec3(camera.position), rotation: Quat(camera.orientation))
        let layout = FlipbookLayout(width: Double(rect.width), height: Double(rect.height), camera: pose, fieldOfView: Double(camera.fieldOfView))
        return (layout, rect)
    }

    /// The anchor frame of a camera or object track on the stage, and the stage rect it's drawn in.
    private func stageAnchor(_ track: FlipbookTrack) -> (frame: FlipbookAnchorFrame, rect: CGRect)? {
        guard let (layout, rect) = stageFlipbookLayout(), let frame = layout.anchorFrame(track, in: displayed.scene) else { return nil }
        return (frame, rect)
    }

    /// A stroke of a track in stage points (a stroke on a sheet can come back in pieces).
    func stagePixels(of stroke: FlipStroke, in track: FlipbookTrack) -> [FlipbookPixelStroke] {
        guard let (layout, rect) = stageFlipbookLayout() else { return [] }
        let offset = Vec2(Double(rect.minX), Double(rect.minY))
        return layout.pixels(of: stroke, in: track, scene: displayed.scene).map { pixels in
            var moved = pixels
            moved.points = pixels.points.map { $0 + offset }
            return moved
        }
    }

    // MARK: Drawing

    /// The path the current flipbook brush makes of samples, `pointsPerUnit` stage points to one of their units (1 for
    /// the live stroke in points, a drawing's scale when it's kept): the same function draws both.
    func flipbookPath(_ samples: [BrushInput<Vec2>], pointsPerUnit scale: Double = 1) -> BrushPath<Vec2> {
        BrushStroker.path(samples, brush: currentBrush(for: .flipbook), size: flipbook.width / scale, opacity: flipbook.opacity,
                          streamline: pencilFeel.stabilisation * 0.6, minimumSpacing: 1.5 / scale)
    }

    /// A finished stroke from points and pressures alone (tests; the Pencil gives full samples).
    func commitFlipbookStroke(points: [CGPoint], pressures: [Double]) {
        let samples = points.enumerated().map { index, point in
            BrushInput(point: Vec2(Double(point.x), Double(point.y)), pressure: pressures.indices.contains(index) ? pressures[index] : 1,
                       time: Double(index) / 240)
        }
        commitFlipbookStrokes([samples], seed: Self.strokeSeed())
    }

    /// A stroke and its copies, in stage points, as one undo step: on the sheet (a first stroke makes a track there and
    /// keeps the sheet), or on the camera when the flipbook is stuck to it.
    func commitFlipbookStrokes(_ copies: [[BrushInput<Vec2>]], seed: UInt64) {
        guard copies.contains(where: { !$0.isEmpty }) else { return }
        if let track = activeFlipbook, track.anchor.object != nil {
            // A drawn effect riding on an object keeps its place.
            commitAnchoredStrokes(copies, seed: seed, into: track)
        } else if flipbook.onCamera {
            let track = activeFlipbook.flatMap { $0.anchor == .camera ? $0 : nil } ?? newFlipbookTrack(named: nil, anchor: .camera)
            commitAnchoredStrokes(copies, seed: seed, into: track)
        } else {
            commitSheetStrokes(copies, seed: seed)
        }
    }

    /// Strokes on a camera or object track: frame or object units through its one frame.
    private func commitAnchoredStrokes(_ copies: [[BrushInput<Vec2>]], seed: UInt64, into track: FlipbookTrack) {
        guard let (frame, rect) = stageAnchor(track) else {
            app.show("Its object is out of view: draw where you can see it")
            return
        }
        let brush = projectBrush(currentBrush(for: .flipbook)).key
        let strokes = copies.enumerated().compactMap { index, samples -> FlipStroke? in
            let units = samples.map { sample in
                var moved = sample
                moved.point = frame.point(Vec2(sample.point.x - Double(rect.minX), sample.point.y - Double(rect.minY)))
                return moved
            }
            return flipStroke(units, pointsPerUnit: frame.pixelsPerUnit, seed: seed &+ UInt64(index), brush: brush)
        }
        addFlipStrokes(strokes, to: track, keepingSheet: false)
    }

    /// Strokes on the sheet: each point where it lands, in the sheet's own metres. A sheet on an object takes them on
    /// its plane there (a drawing laid on the object, riding with it).
    private func commitSheetStrokes(_ copies: [[BrushInput<Vec2>]], seed: UInt64) {
        ensureSheet()
        guard let stage, let sheet = currentSheet, let origin = sheet.worldFrame(in: displayed.scene)?.origin else { return }
        let surface = sheet.shape == .onObject ? sheet.with(shape: .flat) : sheet
        let scene = displayed.scene
        let track = activeFlipbook.flatMap { $0.anchor.sheet == sheet.id ? $0 : nil }
            ?? timeline.flipbooks.last { $0.anchor.sheet == sheet.id } ?? newFlipbookTrack(named: sheet.name, anchor: .sheet(sheet.id))
        let pointsPerMetre = 1 / max(stage.worldPerPoint(at: origin), 1e-9)
        let brush = projectBrush(currentBrush(for: .flipbook)).key
        let strokes = copies.enumerated().compactMap { index, samples -> FlipStroke? in
            let units = samples.compactMap { sample -> BrushInput<Vec2>? in
                guard let ray = stage.worldRay(at: CGPoint(x: sample.point.x, y: sample.point.y)), let hit = surface.land(ray, in: scene),
                      let coordinates = surface.surfaceCoordinates(of: hit.point, in: scene) else { return nil }
                var moved = sample
                moved.point = coordinates
                return moved
            }
            return flipStroke(units, pointsPerUnit: pointsPerMetre, seed: seed &+ UInt64(index), brush: brush)
        }
        addFlipStrokes(strokes, to: track, keepingSheet: true)
    }

    private func flipStroke(_ units: [BrushInput<Vec2>], pointsPerUnit: Double, seed: UInt64, brush: String) -> FlipStroke? {
        let path = flipbookPath(units, pointsPerUnit: pointsPerUnit)
        guard !path.points.isEmpty else { return nil }
        let color = currentColor.resolved(in: look.palette)
        return FlipStroke(points: path.points, widths: path.widths, color: .rgba(color), alphas: path.alphas, brush: brush, seed: seed)
    }

    private func addFlipStrokes(_ strokes: [FlipStroke], to track: FlipbookTrack, keepingSheet keeps: Bool) {
        guard !strokes.isEmpty else { return }
        let brushCommand = projectBrush(currentBrush(for: .flipbook)).command
        var drawn = track
        for stroke in strokes {
            drawn = FlipbookEditing.adding(stroke, at: time, fps: timeline.fps, hold: flipbook.hold, to: drawn, newID: Self.newID()).track
        }
        let command = EditCommand.setFlipbooks([FlipbookEdit(drawn)])
        if performStroke(keeps ? keepingSheet(command) : command, brush: brushCommand) { flipbook.track = track.id }
    }

    /// Erases the active track's drawing at the playhead under the eraser (one undo step per gesture).
    func eraseFlipbook(at points: [CGPoint], gesture: String) {
        guard let track = activeFlipbook, let index = activeFlipbookFrame else { return }
        let radius = flipbook.eraserRadius
        let erased = FlipbookEditing.erasing(frame: index, in: track) { point in
            guard let pixel = stagePoint(of: point, in: track) else { return false }
            return points.contains { hypot(Double($0.x) - pixel.x, Double($0.y) - pixel.y) <= radius }
        }
        guard erased != track else { return }
        perform(.setFlipbooks([FlipbookEdit(erased)]), coalesceKey: gesture)
    }

    /// A point of a track's drawing, in stage points.
    private func stagePoint(of point: Vec2, in track: FlipbookTrack) -> Vec2? {
        guard let (layout, rect) = stageFlipbookLayout() else { return nil }
        let offset = Vec2(Double(rect.minX), Double(rect.minY))
        if let id = track.anchor.sheet {
            let scene = displayed.scene
            guard let sheet = scene.sheet(id), let world = sheet.worldPoint(at: point, in: scene), let pixel = layout.pixel(of: world) else { return nil }
            return pixel.point + offset
        }
        return layout.anchorFrame(track, in: displayed.scene).map { $0.pixel(point) + offset }
    }

    static func newID() -> String { UUID().uuidString.lowercased() }

    /// Drawn effects go on the selected object (not a camera) when one is selected, else the camera.
    var defaultFlipbookAnchor: FlipbookAnchor {
        if let object = singleSelection, object.kind != .camera, !object.kind.isOverlay { return .object(object.id) }
        return .camera
    }

    // MARK: Tracks

    /// A new empty track (not yet in the timeline: the first stroke or effect adds it).
    func newFlipbookTrack(named name: String?, anchor: FlipbookAnchor) -> FlipbookTrack {
        let number = timeline.flipbooks.count + 1
        let objectName = anchor.object.flatMap { scene.objects[$0]?.name }
        return FlipbookTrack(id: Self.newID(), name: name ?? objectName.map { "\($0) FX" } ?? "Flipbook \(number)", anchor: anchor,
                             start: time)
    }

    /// Starts a new track: the next stroke goes into it.
    func startNewFlipbook() {
        flipbook.track = nil
        tool = .flipbook
        app.show(flipbook.onCamera ? "Draw: a new flipbook on the camera" : "Draw: a new flipbook on the sheet")
    }

    func updateFlipbook(_ label: String, coalesceKey: String? = nil, _ change: (inout FlipbookTrack) -> Void) {
        guard var track = activeFlipbook else { return }
        change(&track)
        perform(.batch(label, [.setFlipbooks([FlipbookEdit(track)])]), coalesceKey: coalesceKey)
    }

    func deleteFlipbook() {
        guard let track = activeFlipbook else { return }
        perform(.setFlipbooks([FlipbookEdit(id: track.id, track: nil)]))
        flipbook.track = timeline.flipbooks.last?.id
    }

    // MARK: Drawings

    func addFlipbookDrawing() {
        guard let track = activeFlipbook else { return }
        let index = activeFlipbookFrame ?? track.frames.count - 1
        let updated = FlipbookEditing.insertingFrame(after: index, hold: flipbook.hold, in: track, newID: Self.newID())
        perform(.setFlipbooks([FlipbookEdit(updated)]))
        setTime(updated.startTime(ofFrame: index + 1, fps: timeline.fps))
    }

    func duplicateFlipbookDrawing() {
        guard let track = activeFlipbook, let index = activeFlipbookFrame else { return }
        perform(.setFlipbooks([FlipbookEdit(FlipbookEditing.duplicatingFrame(index, in: track, newID: Self.newID()))]))
        setTime(track.startTime(ofFrame: index + 1, fps: timeline.fps) + (Double(track.frames[index].hold) / Double(timeline.fps)))
    }

    func deleteFlipbookDrawing() {
        guard let track = activeFlipbook, let index = activeFlipbookFrame else { return }
        perform(.setFlipbooks([FlipbookEdit(FlipbookEditing.removingFrame(index, from: track))]))
    }

    /// Lengthens or shortens the hold of the drawing at the playhead.
    func changeFlipbookHold(by delta: Int) {
        guard let track = activeFlipbook, let index = activeFlipbookFrame else { return }
        let updated = FlipbookEditing.settingHold(track.frames[index].hold + delta, ofFrame: index, in: track)
        perform(.setFlipbooks([FlipbookEdit(updated)]), coalesceKey: "flipbook-hold")
    }

    /// The frame strip: a drawing's hold set by dragging its edge (one undo step per drag).
    func setFlipbookHold(_ hold: Int, ofDrawing index: Int, gesture: String) {
        guard let track = activeFlipbook, track.frames.indices.contains(index), track.frames[index].hold != hold else { return }
        perform(.setFlipbooks([FlipbookEdit(FlipbookEditing.settingHold(hold, ofFrame: index, in: track))]), coalesceKey: gesture)
    }

    /// The frame strip: a drawing dragged to another place; the playhead follows it.
    func moveFlipbookDrawing(_ index: Int, to destination: Int) {
        guard let track = activeFlipbook, index != destination else { return }
        let moved = FlipbookEditing.movingFrame(index, to: destination, in: track)
        guard moved != track, perform(.batch("Move drawing", [.setFlipbooks([FlipbookEdit(moved)])])) else { return }
        setTime(moved.startTime(ofFrame: min(max(destination, 0), moved.frames.count - 1), fps: timeline.fps))
        HmmHaptics.play(.commit)
    }

    /// Jumps to a drawing of a track and makes the track active.
    func showFlipbookDrawing(_ index: Int, of trackID: String) {
        guard let track = timeline.flipbook(trackID), track.frames.indices.contains(index) else { return }
        flipbook.track = trackID
        setTime(track.startTime(ofFrame: index, fps: timeline.fps))
    }

    /// A finger's flick while frames are drawn (U5): right, a new drawing after this one (the first stroke makes the
    /// first); left, the drawing before. The Pencil Pro clicks on each frame.
    func flickFlipbook(_ flick: Flick) {
        switch flick {
        case .right:
            guard activeFlipbook?.frames.isEmpty == false else { return }
            addFlipbookDrawing()
        case .left:
            stepFlipbookDrawing(by: -1)
        }
        HmmHaptics.play(.selection)
        HmmPencilHaptics.buzz()
    }

    /// The frame strip's previous and next.
    func stepFlipbookDrawing(by step: Int) {
        guard let track = activeFlipbook, !track.frames.isEmpty else { return }
        let current = activeFlipbookFrame ?? (time < track.start ? -1 : track.frames.count)
        showFlipbookDrawing(min(max(current + step, 0), track.frames.count - 1), of: track.id)
    }

    // MARK: Loop while drawing

    /// The range the frame strip's loop plays: the active track's drawings.
    var flipbookLoopRange: TimeRange? {
        guard tool == .flipbook, flipbook.looping, let track = activeFlipbook, !track.frames.isEmpty else { return nil }
        let end = track.start + track.duration(fps: timeline.fps)
        return end > track.start ? TimeRange(start: track.start, end: end) : nil
    }

    func toggleFlipbookLoop() {
        flipbook.looping.toggle()
        if flipbook.looping { play(withAudio: false) } else { pause() }
    }

    /// The Pencil touched while the drawings loop: the drawing under the playhead holds still for the stroke.
    func holdFlipbookLoop() {
        guard flipbookLoopRange != nil, isPlaying else { return }
        pause()
    }

    /// The Pencil lifted: the loop goes on a moment later.
    func resumeFlipbookLoop() {
        guard flipbookLoopRange != nil, !isPlaying else { return }
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(450))
            guard let self, flipbookLoopRange != nil, !isPlaying else { return }
            play(withAudio: false)
        }
    }

    // MARK: Drawn effects

    /// A ready-made drawn effect (impact burst, sparkle…) as a new track at the playhead, on the selection or the camera.
    func addFlipbookEffect(_ fx: FlipbookFX) {
        let anchor = defaultFlipbookAnchor
        var track = newFlipbookTrack(named: fx.title, anchor: anchor)
        var ids = IDFactory.random
        let size: Double = switch anchor {
        case let .object(id): max((operations.bounds.worldBounds(of: [id], in: scene).map { $0.size.maxComponent } ?? 1) * 1.4, 0.3)
        default: 0.45
        }
        let white: ColorValue = .rgba(.white)
        let color: ColorValue = fx == .sweatDrop ? .rgba(RGBA.hex("#8FD3FF")) : (currentColor == .palette(0) ? white : currentColor)
        track.frames = fx.frames(size: size, color: color, seed: UInt64(truncatingIfNeeded: track.id.hashValue), ids: &ids)
        track.loops = fx.loops
        if fx.loops { track.end = min(time + 2, timeline.duration) }
        if case .object = anchor, fx == .sweatDrop { track.offset = Vec2(size * 0.3, size * 0.6) }
        if perform(.setFlipbooks([FlipbookEdit(track)])) {
            flipbook.track = track.id
            HmmHaptics.play(.commit)
        }
    }

    // MARK: Onion skin

    /// The drawings before (tinted red) and after (green) the one at the playhead, faded, in stage points.
    func flipbookOnionSkin() -> [(outlines: [[CGPoint]], before: Bool, fade: Double)] {
        guard tool == .flipbook, flipbook.onionSkin, let track = activeFlipbook else { return [] }
        let current = activeFlipbookFrame ?? (time >= track.start ? track.frames.count : -1)
        var result: [(outlines: [[CGPoint]], before: Bool, fade: Double)] = []
        let offsets = (1 ... max(flipbook.onionBefore, 1)).map { -$0 } + (1 ... max(flipbook.onionAfter, 1)).map { $0 }
        for offset in offsets where track.frames.indices.contains(current + offset) {
            if offset < 0, -offset > flipbook.onionBefore { continue }
            if offset > 0, offset > flipbook.onionAfter { continue }
            let outlines = track.frames[current + offset].strokes.flatMap { stroke -> [[CGPoint]] in
                stagePixels(of: stroke, in: track).map { pixels in
                    let shape = stroke.filled ? pixels.points : FlipbookLayout.outline(pixels)
                    return shape.map { CGPoint(x: CGFloat($0.x), y: CGFloat($0.y)) }
                }
            }
            result.append((outlines, offset < 0, 1 / Double(abs(offset) + 1)))
        }
        return result
    }
}
