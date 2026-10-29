import LoweyCore
import LoweyEngine
import UIKit

/// The Pencil on Rig: a tap places a pin or a dot (or picks the mark new ones hang from); a stroke along a part lays a
/// chain of them, shown inside the object as it's drawn; with the weight brush, it paints the chosen bone's weight.
/// Naming its parts (Q2), a tap names a piece and a circle names an area. Each becomes one undo step when the Pencil
/// lifts. Marks themselves are dragged and held over the stage (`RigMarksOverlay`).
extension StageGestures {
    func rigStroke(_ recognizer: StrokeGestureRecognizer, editor: EditorModel, stage: StageView) {
        let samples = recognizer.samples
        switch recognizer.state {
        case .began:
            consumedSamples = 0
            flipSamples = []
            if editor.rigging.person != nil {
                // A person's dots: the Pencil moves the nearest one where it touches.
                if let first = samples.first { editor.personTap(at: first.location) }
                return
            }
            // Who places pins and dots is Settings' to say (the Pencil, unless changed).
            ignoringRigStroke = editor.rigging.mode == .marks
                && !InputJob.marks.allows(pencil: recognizer.isPencil, fingerMakes: pencilOrHand.fingerMakes)
            guard !ignoringRigStroke else { return }
            rigContinue(Array(samples), editor: editor, stage: stage)
        case .changed:
            guard editor.rigging.person == nil, !ignoringRigStroke else { return }
            rigContinue(Array(samples.suffix(from: min(consumedSamples, samples.count))), editor: editor, stage: stage)
        case .ended:
            guard editor.rigging.person == nil, !ignoringRigStroke else { return }
            rigContinue(Array(samples.suffix(from: min(consumedSamples, samples.count))), editor: editor, stage: stage)
            rigFinish(editor: editor, stage: stage, keep: true)
        default:
            rigFinish(editor: editor, stage: stage, keep: false)
        }
    }

    /// How far the Pencil has travelled since it touched (points): under a tap's reach it's a tap.
    private var rigTravel: Double {
        guard let first = flipSamples.first else { return 0 }
        return flipSamples.map { hypot($0.point.x - first.point.x, $0.point.y - first.point.y) }.max() ?? 0
    }

    private static let tapReach = 10.0

    /// The stroke so far, under the tip: a thin line for a chain once it's more than a tap, the weight brush's dabs.
    private func rigContinue(_ samples: [StrokeGestureRecognizer.Sample], editor: EditorModel, stage: StageView) {
        consumedSamples += samples.count
        flipSamples += samples.map { BrushInput(point: Vec2(Double($0.location.x), Double($0.location.y)), pressure: $0.pressure,
                                                altitude: $0.altitude, time: $0.time) }
        let marking = editor.rigging.mode == .marks
        let lines = editor.rigging.mode != .weights
        guard !lines || rigTravel > Self.tapReach else { return }
        let path = rigPath(editor)
        let brush = rigBrush(editor)
        var color = RGBA(1, 0.722, 0.278)
        if editor.rigging.mode == .parts { color = RGBA(0.3, 0.8, 1) }
        if editor.rigging.mode == .weights { color = editor.rigging.erase ? RGBA(0.35, 0.45, 1) : RGBA(1, 0.3, 0.2) }
        stage.showLiveStroke(LiveBrushStroke(stamps: .screen(BrushStroker.dabs(path, brush: brush, seed: 1)), brush: brush, color: color))
        // The chain as it'll land, every few samples (each time, every sample looks through the object again).
        if marking, flipSamples.count >= 4, flipSamples.count % 3 == 0 || samples.count > 2 {
            editor.previewBone(along: flipSamples.map { CGPoint(x: $0.point.x, y: $0.point.y) })
        }
    }

    private func rigBrush(_ editor: EditorModel) -> Brush {
        editor.rigging.mode == .weights ? BuiltInBrushes.airbrush : BuiltInBrushes.technicalPen
    }

    private func rigPath(_ editor: EditorModel) -> BrushPath<Vec2> {
        let weights = editor.rigging.mode == .weights
        return BrushStroker.path(flipSamples, brush: rigBrush(editor), size: weights ? editor.rigging.size / 2 : 2.5,
                                 opacity: weights ? max(editor.rigging.strength, 0.3) : 1, minimumSpacing: 1.5)
    }

    private func rigFinish(editor: EditorModel, stage: StageView, keep: Bool) {
        let travel = rigTravel
        defer {
            stage.showLiveStroke(nil)
            flipSamples = []
            consumedSamples = 0
            editor.endBonePreview()
            editor.strokeEnded()
        }
        guard keep, let first = flipSamples.first else { return }
        switch editor.rigging.mode {
        case .marks where travel <= Self.tapReach:
            editor.tapMark(at: CGPoint(x: first.point.x, y: first.point.y))
        case .marks:
            editor.drawChain(along: flipSamples.map { CGPoint(x: $0.point.x, y: $0.point.y) })
        case .parts where travel <= Self.tapReach:
            editor.partsTap(at: CGPoint(x: first.point.x, y: first.point.y))
        case .parts:
            editor.circlePart(along: flipSamples.map { CGPoint(x: $0.point.x, y: $0.point.y) })
        case .weights:
            // The brush engine spaces the dabs; each carries its pressure as its opacity.
            let dabs = BrushStroker.dabs(rigPath(editor), brush: rigBrush(editor), seed: 1)
            let spaced = dabs.isEmpty ? flipSamples.map { (CGPoint(x: $0.point.x, y: $0.point.y), $0.pressure) }
                : dabs.map { (CGPoint(x: $0.center.x, y: $0.center.y), min($0.opacity / max(editor.rigging.strength, 0.3), 1)) }
            editor.paintWeights(spaced.map { (point: $0.0, pressure: $0.1) })
        }
    }
}
