import Foundation

/// Closing a loop (Export ▸ Loops seamlessly ▸ Close the loop): keys that end somewhere else get a last key back where
/// they began; motions that repeat (spin, float, bounce, swing, orbit, sway, a path followed round, a ripple, a wave of
/// letters) are retimed by the least that fits a whole number of repeats into the stretch. What can't repeat (a wiggle,
/// letters flying in once, real things falling) is left as it is and stays on the check's list.
public enum LoopClose {
    /// One undo step that closes the loop over `range`, or nil when nothing could change.
    public static func command(_ document: Document, range: TimeRange) -> EditCommand? {
        let length = range.duration
        guard length > 1e-3 else { return nil }
        var timeline = document.scene.timeline
        var changed = false
        for (index, track) in timeline.tracks.enumerated() {
            guard let closed = closed(track, range: range, palette: document.palette) else { continue }
            timeline.tracks[index] = closed
            changed = true
        }
        for (index, behavior) in timeline.behaviors.enumerated() where covers(behavior, range) {
            let kind = retimed(behavior.kind, length: length)
            guard kind != behavior.kind else { continue }
            timeline.behaviors[index].kind = kind
            changed = true
        }
        var commands: [EditCommand] = changed ? [.setTimeline(timeline)] : []
        for (id, object) in document.scene.objects.sorted(by: { $0.key.raw < $1.key.raw }) {
            guard let design = object.motionDesign else { continue }
            let fitted = fitted(design, length: length)
            if fitted != design { commands.append(.setMotionDesign(id, fitted.orNil)) }
        }
        return commands.isEmpty ? nil : .batch("Close the loop", commands)
    }

    /// The track with a key at the end matching its value at the start (nil when they already meet).
    static func closed(_ track: Track, range: TimeRange, palette: Palette) -> Track? {
        guard track.cycle == nil, let start = track.value(at: range.start, palette: palette),
              let end = track.value(at: range.end, palette: palette), !meets(start, end) else { return nil }
        var closed = track
        closed.setKey(Keyframe(time: range.end, value: start, easing: track.keyframes.last?.easing ?? .easeInOut))
        return closed
    }

    static func meets(_ a: PropertyValue, _ b: PropertyValue) -> Bool {
        switch (a, b) {
        case let (.float(x), .float(y)): abs(x - y) < 1e-6
        case let (.vec3(x), .vec3(y)): x.distance(to: y) < 1e-6
        case let (.quat(x), .quat(y)): abs(x.normalized.dot(y.normalized)) > 1 - 1e-9
        default: a == b
        }
    }

    /// Whether a behaviour runs through the whole stretch.
    static func covers(_ behavior: Behavior, _ range: TimeRange) -> Bool {
        behavior.enabled && behavior.start <= range.start + 1e-9 && (behavior.end.map { $0 >= range.end - 1e-9 } ?? true)
    }

    /// A whole number of repeats (at least one) in `length` seconds, nearest the `period` given.
    static func fit(_ period: Double, _ length: Double) -> Double {
        guard period > 0 else { return period }
        return length / max((length / period).rounded(), 1)
    }

    static func retimed(_ kind: BehaviorKind, length: Double) -> BehaviorKind {
        switch kind {
        case let .spin(degreesPerSecond, axis):
            let turns = max((abs(degreesPerSecond) * length / 360).rounded(), 1) * (degreesPerSecond < 0 ? -1 : 1)
            return .spin(degreesPerSecond: turns * 360 / length, axis: axis)
        case let .bob(height, period, tilt): return .bob(height: height, period: fit(period, length), tilt: tilt)
        case let .bounce(height, period): return .bounce(height: height, period: fit(period, length))
        case let .swing(angle, period): return .swing(angle: angle, period: fit(period, length))
        case let .orbit(centre, around, period, face): return .orbit(center: centre, around: around, period: fit(period, length), faceCenter: face)
        case let .windSway(angle, frequency, direction):
            return .windSway(angle: angle, frequency: frequency > 0 ? 1 / fit(1 / frequency, length) : frequency, direction: direction)
        case let .followPath(source, duration, true, orient):
            return .followPath(source, duration: fit(duration, length), loop: true, orient: orient)
        default:
            return kind
        }
    }

    /// Ripples that repeat every so often, and waves of letters, fitted to the stretch.
    static func fitted(_ design: MotionDesign, length: Double) -> MotionDesign {
        var fitted = design
        if var clones = design.clones {
            clones.effects = clones.effects.map { effect in
                guard case let .wave(speed, width, every) = effect.field, every > 0 else { return effect }
                var changed = effect
                changed.field = .wave(speed: speed, width: width, every: fit(every, length))
                return changed
            }
            fitted.clones = clones
        }
        if var letters = design.letters, letters.preset == .wave {
            letters.length = fit(letters.length, length)
            fitted.letters = letters
        }
        return fitted
    }
}
