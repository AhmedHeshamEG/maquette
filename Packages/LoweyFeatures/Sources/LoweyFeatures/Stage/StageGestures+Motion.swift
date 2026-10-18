import LoweyCore
import LoweyEngine
import UIKit

/// Animate ▸ Path (A1): the Pencil draws the way the selected thing goes, every sample with the moment it was drawn, so
/// the thing follows at the drawing's own speed.
extension StageGestures {
    func motionStroke(_ recognizer: StrokeGestureRecognizer, editor: EditorModel) {
        let samples = recognizer.samples
        switch recognizer.state {
        case .began:
            consumedSamples = 0
            guard editor.beginDrawnMotion() else { return }
            takeMotionSamples(samples, editor: editor)
        case .changed:
            takeMotionSamples(samples, editor: editor)
        case .ended:
            takeMotionSamples(samples, editor: editor)
            editor.finishDrawnMotion()
            consumedSamples = 0
        default:
            editor.cancelDrawnMotion()
            consumedSamples = 0
        }
    }

    /// The samples not taken yet (coalesced ones included: the Pencil's own clock times each).
    private func takeMotionSamples(_ samples: [StrokeGestureRecognizer.Sample], editor: EditorModel) {
        guard editor.motionDrawing != nil, consumedSamples < samples.count else { return }
        editor.addMotionSamples(samples[consumedSamples...].map { (point: $0.location, time: $0.time) })
        consumedSamples = samples.count
    }
}
