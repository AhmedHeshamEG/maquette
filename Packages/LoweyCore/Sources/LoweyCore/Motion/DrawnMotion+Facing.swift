import Foundation

// MARK: Facing the way it goes

extension DrawnMotion {
    /// The thing's turn at each frame: its front (+Z, the way models face) along the way it travels, its top leaning into
    /// the turn by as much as the turn's pull against gravity (a bike's lean, at most 35°). An upright thing (a character)
    /// keeps its front level and leans a third as much. Where it stands still it keeps the heading it had.
    static func orientations(_ frames: [Sample], options: Options) -> [Quat] {
        let velocities = derivatives(frames.map(\.point), times: frames.map(\.time))
        let accelerations = smoothed(derivatives(velocities, times: frames.map(\.time)), radius: 3)
        var forwards: [Vec3?] = velocities.map { velocity in
            let way = options.upright ? Vec3(velocity.x, 0, velocity.z) : velocity
            return way.length > still ? way.normalized : nil
        }
        // Before it first moves it already faces the way it will go; after a stop it keeps the last heading.
        let firstMoving = forwards.firstIndex { $0 != nil }
        guard let firstMoving else { return frames.map { _ in .identity } }
        for index in forwards.indices {
            if forwards[index] == nil { forwards[index] = index < firstMoving ? forwards[firstMoving] : forwards[index - 1] }
        }
        let lean = options.banks ? (options.upright ? uprightLean : 1) : 0
        let limit = tan(maxBank * .pi / 180)
        return frames.indices.map { index in
            let forward = forwards[index] ?? .unitZ
            var pull = accelerations[index] - forward * accelerations[index].dot(forward)
            pull.y = 0
            var tilt = pull / gravity * lean
            if tilt.length > limit { tilt = tilt.normalized * limit }
            return facing(forward, up: (Vec3.unitY + tilt).normalized)
        }
    }

    /// The turn that puts the front (+Z) along `forward` and the top (+Y) as near `up` as the front allows.
    static func facing(_ forward: Vec3, up: Vec3) -> Quat {
        let z = forward.normalized
        var x = up.cross(z)
        if x.length < 1e-9 { x = Vec3.unitY.cross(z).length > 1e-9 ? Vec3.unitY.cross(z) : .unitX }
        x = x.normalized
        let y = z.cross(x)
        return fromBasis(x: x, y: y, z: z)
    }

    /// A rotation from the columns of its matrix.
    static func fromBasis(x: Vec3, y: Vec3, z: Vec3) -> Quat {
        let trace = x.x + y.y + z.z
        if trace > 0 {
            let s = (trace + 1).squareRoot() * 2
            return Quat(x: (y.z - z.y) / s, y: (z.x - x.z) / s, z: (x.y - y.x) / s, w: s / 4).normalized
        }
        if x.x > y.y, x.x > z.z {
            let s = (1 + x.x - y.y - z.z).squareRoot() * 2
            return Quat(x: s / 4, y: (y.x + x.y) / s, z: (z.x + x.z) / s, w: (y.z - z.y) / s).normalized
        }
        if y.y > z.z {
            let s = (1 + y.y - x.x - z.z).squareRoot() * 2
            return Quat(x: (y.x + x.y) / s, y: s / 4, z: (z.y + y.z) / s, w: (z.x - x.z) / s).normalized
        }
        let s = (1 + z.z - x.x - y.y).squareRoot() * 2
        return Quat(x: (z.x + x.z) / s, y: (z.y + y.z) / s, z: s / 4, w: (x.y - y.x) / s).normalized
    }

    /// Central differences (one-sided at the ends).
    static func derivatives(_ values: [Vec3], times: [Double]) -> [Vec3] {
        guard values.count > 1 else { return values.map { _ in .zero } }
        return values.indices.map { index in
            let a = max(index - 1, 0)
            let b = min(index + 1, values.count - 1)
            let span = times[b] - times[a]
            return span > 0 ? (values[b] - values[a]) / span : .zero
        }
    }

    /// A moving average over `radius` frames each side (the Pencil's small wobbles aren't turns).
    static func smoothed(_ values: [Vec3], radius: Int) -> [Vec3] {
        values.indices.map { index in
            let range = max(index - radius, 0) ... min(index + radius, values.count - 1)
            return range.reduce(Vec3.zero) { $0 + values[$1] } / Double(range.count)
        }
    }
}

// MARK: Changing a drawn motion

extension DrawnMotion {
    /// The stretch a thing's motion covers: its first position key to its last.
    public static func span(of id: ObjectID, in timeline: Timeline) -> TimeRange? {
        guard let keys = timeline.track(for: id, .position)?.keyframes, let first = keys.first, let last = keys.last,
              last.time > first.time else { return nil }
        return TimeRange(start: first.time, end: last.time)
    }

    /// The motion's keys (position and rotation inside its span), for retiming them together.
    static func spanKeys(of id: ObjectID, in timeline: Timeline) -> (TimeRange, [KeyRef])? {
        guard let span = span(of: id, in: timeline) else { return nil }
        let tracks = [PropertyKey.position, .rotation].compactMap { timeline.track(for: id, $0) }
        let keys = tracks.flatMap { track in
            track.keyframes.filter { $0.time >= span.start - 1e-6 && $0.time <= span.end + 1e-6 }.map { KeyRef(track: track.id, time: $0.time) }
        }
        return (span, keys)
    }

    /// The whole motion played in `duration` seconds (its first key stays where it is).
    public static func retiming(_ id: ObjectID, to duration: Double, in timeline: Timeline) -> EditCommand? {
        guard duration > 0.05, let (span, keys) = spanKeys(of: id, in: timeline), abs(span.duration - duration) > 1e-6 else { return nil }
        guard let command = KeyOperations().stretch(keys, to: TimeRange(start: span.start, end: span.start + duration), in: timeline)
        else { return nil }
        return .batch("Change its timing", [command])
    }

    /// The same path at one steady speed: each key's moment moved to where it lies along the way (a stop disappears).
    public static func evenSpeed(_ id: ObjectID, in timeline: Timeline) -> EditCommand? {
        guard let (span, keys) = spanKeys(of: id, in: timeline), let track = timeline.track(for: id, .position) else { return nil }
        let steps = max(Int(span.duration * 120), 2)
        var travelled = [0.0]
        var previous = track.value(at: span.start)?.vec3Value ?? .zero
        for step in 1 ... steps {
            let point = track.value(at: span.start + span.duration * Double(step) / Double(steps))?.vec3Value ?? previous
            travelled.append(travelled[step - 1] + point.distance(to: previous))
            previous = point
        }
        guard let total = travelled.last, total > 1e-6 else { return nil }
        let map: (Double) -> Double = { time in
            let place = (time - span.start) / span.duration * Double(steps)
            let low = min(max(Int(place.rounded(.down)), 0), steps)
            let high = min(low + 1, steps)
            let along = travelled[low] + (travelled[high] - travelled[low]) * (place - Double(low))
            return span.start + along / total * span.duration
        }
        guard let command = KeyOperations().retimed(keys, in: timeline, map) else { return nil }
        return .batch("Even speed", [command])
    }

    /// Turns the thing's front a quarter turn at a time through the whole motion (for a model whose front isn't +Z).
    public static func turningFront(_ id: ObjectID, quarterTurns: Int, in timeline: Timeline) -> EditCommand? {
        guard quarterTurns % 4 != 0, var track = timeline.track(for: id, .rotation), let span = span(of: id, in: timeline) else { return nil }
        let turn = Quat(angle: Double(quarterTurns) * .pi / 2, axis: .unitY)
        track.setKeys(track.keyframes.map { key in
            guard key.time >= span.start - 1e-6, key.time <= span.end + 1e-6, let value = key.value.quatValue else { return key }
            var turned = key
            turned.value = .quat((value * turn).normalized)
            return turned
        })
        return .batch("Turn its front", [.setTracks([TrackEdit(track)])])
    }
}
