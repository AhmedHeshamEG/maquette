import Foundation
import LoweyCore
import LoweyEngine
import Observation

/// The stage's physics run (P1): made in the background whenever the scene changes, played as far as it has gone,
/// kept for the last few versions of the scene so undo and redo don't wait. Preview = export: an export reuses a
/// finished run for the same scene, or makes the same one.
@MainActor
@Observable
final class PhysicsRun {
    /// The run, as far as it has gone (nil: nothing in the scene is real).
    private(set) var frames: PhysicsFrames?
    /// How much of the run is made (nil when there's nothing to run).
    private(set) var progress: Double?
    /// Speed and force arrows on the stage (Real ▸ Show the forces).
    var showsArrows = false
    /// The last "does it stand?" and what it was asked about.
    var stability: PhysicsTools.Stability?
    var stabilityOf: [ObjectID] = []

    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var recent: [PhysicsFrames] = []
    @ObservationIgnored private var generation = 0

    var isMaking: Bool { (progress ?? 1) < 1 }

    /// Starts again for this scene (or keeps the run when nothing that matters changed). `shown` is called on the
    /// main actor each time more of the run is ready.
    func update(_ document: Document, sources: PhysicsSources, shown: @escaping @MainActor @Sendable () -> Void) {
        task?.cancel()
        generation &+= 1
        let current = generation
        guard PhysicsInput.hasPhysics(document.scene) else {
            frames = nil
            progress = nil
            shown()
            return
        }
        let kept = recent
        task = Task.detached(priority: .userInitiated) { [weak self] in
            guard let input = sources.input(document) else { return }
            if let ready = kept.first(where: { $0.key == input.key && $0.isComplete }) {
                await self?.publish(ready, generation: current, shown: shown)
                return
            }
            guard let simulator = PhysicsSimulator(input) else { return }
            await self?.publish(simulator.frames, generation: current, shown: shown)
            var last = Date()
            while !Task.isCancelled, simulator.step() {
                // A few times a second, or every eight frames, whichever comes first.
                if simulator.frames.frames.count % 8 == 0 || Date().timeIntervalSince(last) > 0.12 {
                    last = Date()
                    await self?.publish(simulator.frames, generation: current, shown: shown)
                }
            }
            guard !Task.isCancelled else { return }
            await self?.publish(simulator.frames, generation: current, shown: shown)
        }
    }

    private func publish(_ run: PhysicsFrames, generation made: Int, shown: @MainActor @Sendable () -> Void) {
        guard made == generation else { return }
        frames = run
        progress = Double(run.frames.count) / Double(max(run.total, 1))
        if run.isComplete {
            recent.removeAll { $0.key == run.key }
            recent = Array(([run] + recent).prefix(3))
        }
        shown()
    }

    func stop() {
        task?.cancel()
        task = nil
    }
}
