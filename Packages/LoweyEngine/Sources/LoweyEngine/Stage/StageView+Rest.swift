import Foundation
import HmmDiagnostics
import QuartzCore

/// Sharp at rest, smooth always (U1): while the view moves, dynamic scale holds the frame rate; once nothing has moved
/// for a moment the stage draws one frame at full resolution, and a single change after a rest (a tap, a slider
/// step) is drawn at full resolution too while that is known to fit the frame budget.
extension StageView {
    /// How long nothing must move before the sharp frame.
    static let restDelay: CFTimeInterval = 0.15

    /// The render scale for a frame starting at `time`.
    func frameScale(at time: CFTimeInterval) -> Float {
        let rest = restPending
        restPending = false
        guard dynamicScale.enabled else { return dynamicScale.scale }
        if rest { return 1 }
        let isolated = isPaused && time - lastDrawn >= Self.restDelay
        if isolated, let gpu = fullResolutionGPU, gpu <= dynamicScale.budget * 0.9 { return 1 }
        return dynamicScale.scale
    }

    /// After each frame: if it was drawn below full resolution, a sharp one follows once nothing moves.
    func frameDrawn(at time: CFTimeInterval, scale: Float) {
        lastDrawn = time
        cancelRestFrame()
        // A hot iPad keeps its lighter preview (CONTEXT §6): the sharp frame waits until it cools.
        guard sharpensAtRest, dynamicScale.enabled, isPaused, scale < 1, ThermalLevel.current < .serious else { return }
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.isPaused else { return }
                self.restWork = nil
                self.restPending = true
                self.setNeedsDisplay()
            }
        }
        restWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.restDelay, execute: work)
    }

    func cancelRestFrame() {
        restWork?.cancel()
        restWork = nil
    }
}
