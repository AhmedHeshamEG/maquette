import Foundation

/// A motion drawn with the Pencil (A1): the thing follows the line at the speed it was drawn, facing the way it goes
/// and leaning into its turns. What it makes is ordinary keys (position, and rotation while it faces the way), so the
/// path's dots, the dope sheet and the graph change it like any other motion.
public enum DrawnMotion {
    /// A point of the drawing: where the thing's pivot goes, and when.
    public struct Sample: Hashable, Sendable {
        /// In the world, metres.
        public var point: Vec3
        /// Seconds since the stroke began (the Pencil's own clock).
        public var time: Double

        public init(point: Vec3, time: Double) {
            self.point = point
            self.time = time
        }
    }

    public struct Options: Hashable, Sendable {
        /// Turns to face where it's going (on by default).
        public var facesTheWay: Bool
        /// Leans into its turns, the way a bike or a plane does.
        public var banks: Bool
        /// Characters stay upright: no nose-up on slopes, and only a runner's lean in turns.
        public var upright: Bool

        public init(facesTheWay: Bool = true, banks: Bool = true, upright: Bool = false) {
            self.facesTheWay = facesTheWay
            self.banks = banks
            self.upright = upright
        }
    }

    static let gravity = 9.81
    /// The most a thing banks (degrees); a character leans a third as much.
    static let maxBank = 35.0
    static let uprightLean = 0.3
    /// Below this speed (m/s) a thing keeps the heading it had.
    static let still = 0.05

    /// The drawing a frame apart by its own clock: the first sample at 0, the last at the moment the stroke ended (so
    /// the motion lasts exactly as long as the drawing did). Nil when it's shorter than two frames or barely moves.
    public static func frames(_ samples: [Sample], fps: Int) -> [Sample]? {
        var clean: [Sample] = []
        for sample in samples.sorted(by: { $0.time < $1.time }) where sample.time > (clean.last?.time ?? -.infinity) {
            clean.append(sample)
        }
        guard let first = clean.first, let last = clean.last, fps > 0 else { return nil }
        let duration = last.time - first.time
        let travel = zip(clean, clean.dropFirst()).reduce(0) { $0 + $1.0.point.distance(to: $1.1.point) }
        guard duration >= 2 / Double(fps), travel > 0.001 else { return nil }
        var frames: [Sample] = []
        var cursor = 0
        let count = Int((duration * Double(fps)).rounded(.down))
        for index in 0 ... count {
            let time = Double(index) / Double(fps)
            frames.append(Sample(point: point(in: clean, at: first.time + time, cursor: &cursor), time: time))
        }
        if duration - (frames.last?.time ?? 0) > 1e-6 { frames.append(Sample(point: last.point, time: duration)) }
        return frames
    }

    /// The drawing's point at `time`, between the samples around it.
    private static func point(in samples: [Sample], at time: Double, cursor: inout Int) -> Vec3 {
        while cursor + 1 < samples.count, samples[cursor + 1].time < time {
            cursor += 1
        }
        guard cursor + 1 < samples.count else { return samples[samples.count - 1].point }
        let a = samples[cursor]
        let b = samples[cursor + 1]
        let span = b.time - a.time
        return span > 0 ? a.point.lerp(to: b.point, min(max((time - a.time) / span, 0), 1)) : b.point
    }

    // MARK: Keys

    /// The keys that make `id` follow the drawing from `start`: a position key wherever the line needs one to stay within
    /// half a centimetre (or 0.2 % of its size) at every frame, and rotation keys facing the way when asked. Keys of
    /// those properties already in that stretch go. The timeline grows to hold the motion.
    public static func keys(_ samples: [Sample], object id: ObjectID, in document: Document, from start: Double,
                            options: Options = Options(), ids: inout IDFactory) -> EditCommand? {
        let timeline = document.scene.timeline
        guard document.scene.objects[id] != nil, let frames = frames(samples, fps: timeline.fps), let end = frames.last.map({ start + $0.time })
        else { return nil }
        let parents = parentWorlds(of: id, in: document, at: frames.map { start + $0.time })
        let positions = frames.indices.map { parents[$0].inverseApply(to: frames[$0].point) }
        let extent = bounds(frames.map(\.point))
        let times = frames.map(\.time)
        let kept = simplified(positions, times: times, tolerance: max(0.005, extent * 0.002))
        let positionKeys = kept.map { Keyframe(time: start + frames[$0].time, value: .vec3(positions[$0]), easing: .linear) }
        var tracks = [replacing(.position, of: id, with: positionKeys, over: TimeRange(start: start, end: end), in: timeline, ids: &ids)]
        if options.facesTheWay {
            let world = orientations(frames, options: options)
            let local = world.indices.map { (parents[$0].rotation.inverse * world[$0]).normalized }
            let turns = continuous(local)
            let keptTurns = simplifiedTurns(turns, times: times, toleranceDegrees: 1.5)
            let rotationKeys = keptTurns.map { Keyframe(time: start + frames[$0].time, value: .quat(turns[$0]), easing: .linear) }
            tracks.append(replacing(.rotation, of: id, with: rotationKeys, over: TimeRange(start: start, end: end), in: timeline, ids: &ids))
        }
        guard end + 0.2 > timeline.duration else { return .batch("Draw a motion", [.setTracks(tracks)]) }
        var longer = timeline
        longer.duration = (end + 0.5).rounded(.up)
        for edit in tracks {
            longer.tracks.removeAll { $0.id == edit.id }
            if let track = edit.track { longer.tracks.append(track) }
        }
        return .batch("Draw a motion", [.setTimeline(longer)])
    }

    /// The property's track with `keys` laid over `range` (keys already in it go; a new track if there was none).
    static func replacing(_ property: PropertyKey, of id: ObjectID, with keys: [Keyframe], over range: TimeRange, in timeline: Timeline,
                          ids: inout IDFactory) -> TrackEdit {
        var track = timeline.track(for: id, property) ?? Track(id: ids.next(), target: id, property: property)
        track.removeKeys(in: TimeRange(start: range.start - 1e-6, end: range.end + 1e-6))
        for key in keys {
            track.setKey(key)
        }
        return TrackEdit(track)
    }

    /// Where the thing's parent is at each moment (identity for a thing at the top), so keys land in its parent's space.
    static func parentWorlds(of id: ObjectID, in document: Document, at times: [Double]) -> [Transform] {
        guard let parent = document.scene.objects[id]?.parent else { return times.map { _ in .identity } }
        let rates = FrameRates(document)
        return times.map { MotionPath.worldTransform(of: parent, in: document, at: $0, rates: rates) }
    }

    static func bounds(_ points: [Vec3]) -> Double {
        guard let first = points.first else { return 0 }
        let low = points.reduce(first) { Vec3.min($0, $1) }
        let high = points.reduce(first) { Vec3.max($0, $1) }
        return (high - low).length
    }
}

// MARK: Keeping only the keys a line needs

extension DrawnMotion {
    /// The indices worth a key: a point is dropped while the straight line between the keys around it passes within
    /// `tolerance` of where the thing was drawn *at that moment* (a time-synchronous Douglas–Peucker), so the timing
    /// stays the drawing's.
    static func simplified(_ points: [Vec3], times: [Double], tolerance: Double) -> [Int] {
        simplifiedIndices(points.count) { a, b, index in
            let u = (times[index] - times[a]) / (times[b] - times[a])
            return points[index].distance(to: points[a].lerp(to: points[b], u))
        } tolerance: { $0 > tolerance }
    }

    /// The same for turns: a key is kept where turning straight between its neighbours misses by more than `toleranceDegrees`.
    static func simplifiedTurns(_ turns: [Quat], times: [Double], toleranceDegrees: Double) -> [Int] {
        simplifiedIndices(turns.count) { a, b, index in
            let u = (times[index] - times[a]) / (times[b] - times[a])
            return angle(between: turns[index], and: turns[a].slerp(to: turns[b], u))
        } tolerance: { $0 > toleranceDegrees * .pi / 180 }
    }

    /// Splits at the worst miss until nothing misses by more than the tolerance.
    private static func simplifiedIndices(_ count: Int, error: (Int, Int, Int) -> Double, tolerance exceeds: (Double) -> Bool) -> [Int] {
        guard count > 2 else { return Array(0 ..< count) }
        var keep = Set([0, count - 1])
        var stack = [(0, count - 1)]
        while let (a, b) = stack.popLast() {
            guard b - a > 1 else { continue }
            var worst = 0.0
            var worstIndex = -1
            for index in a + 1 ..< b {
                let miss = error(a, b, index)
                if miss > worst {
                    worst = miss
                    worstIndex = index
                }
            }
            guard worstIndex >= 0, exceeds(worst) else { continue }
            keep.insert(worstIndex)
            stack.append((a, worstIndex))
            stack.append((worstIndex, b))
        }
        return keep.sorted()
    }

    static func angle(between a: Quat, and b: Quat) -> Double {
        2 * acos(min(abs(a.normalized.dot(b.normalized)), 1))
    }

    /// Each turn on the same side as the one before (q and −q are the same turn), so slerp never takes the long way.
    static func continuous(_ turns: [Quat]) -> [Quat] {
        var result: [Quat] = []
        for turn in turns {
            if let previous = result.last, previous.dot(turn) < 0 {
                result.append(Quat(x: -turn.x, y: -turn.y, z: -turn.z, w: -turn.w))
            } else {
                result.append(turn)
            }
        }
        return result
    }
}
