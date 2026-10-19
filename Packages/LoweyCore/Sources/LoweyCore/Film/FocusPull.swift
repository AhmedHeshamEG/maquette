import Foundation

/// Focus that follows a thing (F1): a camera with `focusOn` keeps that thing sharp wherever it goes; a new target keyed
/// later pulls focus over `duration`, the way a focus puller turns the ring. The Animator's step after looks.
public enum FocusPull {
    /// How long a pull takes (seconds).
    public static let duration = 0.8

    static func anyone(in scene: Scene) -> Bool {
        scene.objects.values.contains { $0.kind == .camera && $0[.focusOn] != nil }
    }

    static func apply(to state: inout Animator.Posed, timeline: Timeline, time: Double) {
        for id in state.scene.objects.keys.sorted() {
            guard var camera = state.scene.objects[id], camera.kind == .camera,
                  let target = camera[.focusOn]?.stringValue.map(ObjectID.init(raw:)), !target.raw.isEmpty,
                  var distance = distance(from: id, to: target, in: state) else { continue }
            if let (previous, progress) = switching(id, timeline: timeline, at: time), let from = self.distance(from: id, to: previous, in: state) {
                // A real pull eases in and out of the ring's turn, in focus distance (what the ring turns), not in place.
                distance = from + (distance - from) * Easing.easeInOut.apply(progress)
            }
            camera[.focusDistance] = .float(max(distance, 0.05))
            state.scene.objects[id] = camera
            state.animated.insert(id)
        }
    }

    static func distance(from camera: ObjectID, to target: ObjectID, in state: Animator.Posed) -> Double? {
        guard let aim = LookAt.aimPoint(of: target, in: state) else { return nil }
        return state.scene.worldTransform(of: camera).position.distance(to: aim)
    }

    /// The target before the latest change and how far the pull has come (nil once it has landed).
    static func switching(_ id: ObjectID, timeline: Timeline, at time: Double) -> (ObjectID, Double)? {
        guard let keys = timeline.track(for: id, .focusOn)?.keyframes,
              let index = keys.lastIndex(where: { $0.time <= time + 1e-9 }), index > 0, time - keys[index].time < duration,
              let previous = keys[index - 1].value.stringValue, !previous.isEmpty, previous != keys[index].value.stringValue else { return nil }
        return (ObjectID(raw: previous), (time - keys[index].time) / duration)
    }
}

/// Setting what the lens keeps sharp, as commands.
public enum FocusOperations {
    /// From `time` on, `camera` keeps `target` sharp. With nothing keyed yet and the playhead at the start, it's set for the
    /// whole shot; later, the focus becomes keyed (what it was before stays up to the pull).
    public static func focus(_ camera: ObjectID, on target: ObjectID?, at time: Double, in scene: Scene, ids: inout IDFactory) -> EditCommand? {
        guard let object = scene.objects[camera], object.kind == .camera, target != camera else { return nil }
        let value = target.map { PropertyValue.string($0.raw) } ?? .string("")
        let label = target.flatMap { scene.objects[$0]?.name }.map { "Focus on \($0)" } ?? "Focus by distance"
        if var track = scene.timeline.track(for: camera, .focusOn) {
            track.setKey(Keyframe(time: time, value: value, easing: .step))
            return .batch(label, [.setTracks([TrackEdit(track)])])
        }
        guard time > 1e-6, let before = object[.focusOn] else {
            return .batch(label, [.setProperties([PropertyChange(object: camera, key: .focusOn, value: target == nil ? nil : value)])])
        }
        var track = Track(id: ids.next(), target: camera, property: .focusOn)
        track.setKey(Keyframe(time: 0, value: before, easing: .step))
        track.setKey(Keyframe(time: time, value: value, easing: .step))
        return .batch(label, [.setTracks([TrackEdit(track)])])
    }
}

/// A stretch of the edit seen through one camera: between two cuts, or the whole timeline without cuts.
public struct Shot: Hashable, Sendable {
    public var index: Int
    public var camera: ObjectID?
    public var start: Double
    public var end: Double

    public var duration: Double { end - start }
    /// The moment that stands for the shot (a storyboard panel, an animatic's held frame): a third of the way in, after
    /// the cut has landed and before anything leaves.
    public var keyMoment: Double { start + duration / 3 }
}

public extension Timeline {
    /// The shots in `range` (the whole timeline by default), in order.
    func shots(in range: TimeRange? = nil) -> [Shot] {
        let whole = range ?? TimeRange(start: 0, end: duration)
        let starts = Array(Set(cuts.map(\.time).filter { $0 > whole.start + 1e-3 && $0 < whole.end - 1e-3 } + [whole.start])).sorted()
        return starts.enumerated().map { index, start in
            Shot(index: index, camera: cutCamera(at: start), start: start, end: index + 1 < starts.count ? starts[index + 1] : whole.end)
        }
    }
}
