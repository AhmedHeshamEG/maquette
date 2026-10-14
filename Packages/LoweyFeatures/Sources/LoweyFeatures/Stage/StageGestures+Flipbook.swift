import HmmDesign
import LoweyCore
import LoweyEngine
import UIKit

/// The Pencil on a flipbook: draws a stroke into the drawing at the playhead (on the sheet, or on the camera's frame),
/// or erases from it. Draw, then hold: the stroke becomes a clean line, arc or circle. While the frame strip loops the
/// drawings, the one under the playhead holds still for the stroke.
extension StageGestures {
    func flipbookStroke(_ recognizer: StrokeGestureRecognizer, editor: EditorModel) {
        let samples = recognizer.samples
        switch recognizer.state {
        case .began:
            gestureKey = UUID().uuidString
            strokeSeed = EditorModel.strokeSeed()
            consumedSamples = 0
            snapped = nil
            inkPath = []
            flipSamples = []
            editor.holdFlipbookLoop()
            editor.ensureSheet()
            flipbookContinue(Array(samples), recognizer: recognizer, editor: editor)
        case .changed:
            if snapped != nil {
                adjustFlipbookShape(editor: editor)
            } else {
                flipbookContinue(Array(samples.suffix(from: min(consumedSamples, samples.count))), recognizer: recognizer, editor: editor)
            }
        case .ended:
            if !recognizer.isPencil, snapped == nil, let flick = Self.flick(in: samples) {
                // A finger's flick turns the frame (U5); it draws nothing.
                flipbookFinish(editor: editor)
                editor.flickFlipbook(flick)
                return
            }
            if snapped == nil {
                flipbookContinue(Array(samples.suffix(from: min(consumedSamples, samples.count))), recognizer: recognizer, editor: editor)
            }
            if editor.flipbook.mode == .draw { editor.commitFlipbookStrokes(flipbookCopies(flipSamples, editor: editor), seed: strokeSeed) }
            flipbookFinish(editor: editor)
        default:
            flipbookFinish(editor: editor)
        }
    }

    /// The flick a stroke's samples make, if they make one.
    static func flick(in samples: [StrokeGestureRecognizer.Sample]) -> Flick? {
        guard let first = samples.first, let last = samples.last else { return nil }
        return Flick.read(dx: Double(last.location.x - first.location.x), dy: Double(last.location.y - first.location.y),
                          duration: last.time - first.time)
    }

    private func flipbookContinue(_ samples: [StrokeGestureRecognizer.Sample], recognizer: StrokeGestureRecognizer, editor: EditorModel) {
        consumedSamples += samples.count
        let points = samples.map(\.location)
        inkPath += points
        flipSamples += samples.map { BrushInput(point: Vec2(Double($0.location.x), Double($0.location.y)), pressure: $0.pressure,
                                                altitude: $0.altitude, time: $0.time) }
        if editor.flipbook.mode == .erase {
            editor.eraseFlipbook(at: points, gesture: gestureKey)
        } else if let stage {
            showFlipbookPreview(recognizer, editor: editor, stage: stage)
        }
    }

    /// Held after drawing: the flipbook stroke becomes its clean shape (in stage points, like the stroke).
    func snapFlipbookToQuickShape(editor: EditorModel) {
        guard editor.flipbook.mode == .draw, let anchor = stroke.samples.last?.location else { return }
        let points = flipSamples.map(\.point)
        guard let shape = QuickShape.fit(points) else { return }
        let pressure = flipSamples.map(\.pressure).reduce(0, +) / Double(max(flipSamples.count, 1))
        snapped = (shape, anchor, pressure)
        redrawFlipbookShape(shape.points, pressure: pressure, editor: editor)
        HmmHaptics.play(.selection)
        if let stage { HmmPencilHaptics.completed(at: anchor, in: stage) }
        editor.app.show("\(shape.kind.title). Keep holding and drag to adjust")
    }

    private func adjustFlipbookShape(editor: EditorModel) {
        guard let snapped, let tip = stroke.samples.last?.location else { return }
        let shape = QuickShape.adjusted(snapped.shape, anchor: Vec2(Double(snapped.anchor.x), Double(snapped.anchor.y)),
                                        current: Vec2(Double(tip.x), Double(tip.y)))
        redrawFlipbookShape(shape.points, pressure: snapped.pressure, editor: editor)
    }

    private func redrawFlipbookShape(_ points: [Vec2], pressure: Double, editor: EditorModel) {
        let start = flipSamples.first?.time ?? 0
        flipSamples = points.enumerated().map { index, point in BrushInput(point: point, pressure: pressure, time: start + Double(index) / 240) }
        if let stage { showFlipbookPreview(stroke, editor: editor, stage: stage) }
    }

    private func flipbookFinish(editor: EditorModel) {
        stage?.showLiveStroke(nil)
        editor.strokeEnded()
        editor.endGesture()
        editor.resumeFlipbookLoop()
        inkPath = []
        flipSamples = []
        consumedSamples = 0
        snapped = nil
    }
}
