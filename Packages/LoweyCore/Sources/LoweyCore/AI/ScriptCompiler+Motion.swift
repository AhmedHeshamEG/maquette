import Foundation

// MARK: - Motion (A1)

/// `{"do": "motion", "op": …}`: a drawn path the thing follows at the drawing's speed, following a line, looking at
/// something, picking up, handing off and putting down, and changing a drawn motion's timing or front. Each one undo
/// step. Points are in the scene's metres, times in seconds (or the usual words and markers).
extension ScriptState {
    static let motionOps: [String: @Sendable (inout ScriptState, JSONValue) throws -> Void] = [
        "path": { try $0.motionPath($1) },
        "follow": { try $0.motionFollow($1) },
        "lookAt": { try $0.motionLookAt($1) },
        "pickUp": { try $0.motionPickUp($1) },
        "putDown": { try $0.motionPutDown($1) },
        "letGo": { try $0.motionLetGo($1) },
        "evenSpeed": { try $0.motionEvenSpeed($1) },
        "timing": { try $0.motionTiming($1) },
        "front": { try $0.motionFront($1) }
    ]

    mutating func motion(_ action: JSONValue) throws {
        guard let op = string(action, "op"), let handler = Self.motionOps[op] else {
            throw fail("motion needs “op”: \(Self.motionOps.keys.sorted().joined(separator: ", "))")
        }
        try handler(&self, action)
    }

    /// The path as points with their moments: `times` (seconds from the first point), else a steady `speed` (m/s, 1.5
    /// by default) or a `duration` for the whole line.
    func pathSamples(_ action: JSONValue) throws -> [DrawnMotion.Sample] {
        let points = action["points"]?.arrayValue?.compactMap { vec3($0) } ?? []
        guard points.count >= 2 else { throw fail("path needs “points”: at least two [x, y, z]") }
        if let times = action["times"]?.arrayValue?.compactMap(\.numberValue) {
            guard times.count == points.count else { throw fail("“times” needs one number per point") }
            return zip(points, times).map { DrawnMotion.Sample(point: $0, time: $1) }
        }
        let lengths = zip(points, points.dropFirst()).map { $0.distance(to: $1) }
        let total = lengths.reduce(0, +)
        guard total > 0 else { throw fail("the path's points are all in one place") }
        let duration = number(action, "duration") ?? total / max(number(action, "speed") ?? 1.5, 0.01)
        var travelled = 0.0
        var samples = [DrawnMotion.Sample(point: points[0], time: 0)]
        for (index, length) in lengths.enumerated() {
            travelled += length
            samples.append(DrawnMotion.Sample(point: points[index + 1], time: travelled / total * duration))
        }
        return samples
    }

    /// Characters stay upright on a drawn path.
    func isCharacter(_ id: ObjectID) -> Bool {
        scene.objects[id]?[.characterStart] != nil || CharacterRig.of(id, in: scene) != nil
    }

    mutating func motionPath(_ action: JSONValue) throws {
        let id = try target(action["target"])
        let start = try time(action["at"])
        let options = DrawnMotion.Options(facesTheWay: bool(action, "facesTheWay") ?? true, banks: bool(action, "banks") ?? true,
                                          upright: bool(action, "upright") ?? isCharacter(id))
        let command = DrawnMotion.keys(try pathSamples(action), object: id, in: document, from: start, options: options, ids: &context.ids)
        guard let command else { throw fail("the path is too short to move along") }
        try run(command, label: "\(scene.objects[id]?.name ?? "It") follows a path from \(format(start))")
    }

    mutating func motionFollow(_ action: JSONValue) throws {
        let id = try target(action["target"])
        let line = try target(action["path"] ?? action["line"])
        guard case .drawing = scene.objects[line]?.kind else { throw fail("follow needs “path”: a drawn line to follow") }
        let start = try time(action["at"])
        let kind = BehaviorKind.followPath(.object(line), duration: max(number(action, "duration") ?? 4, 0.1), loop: bool(action, "loop") ?? false,
                                           orient: bool(action, "facesTheWay") ?? true)
        var copy = timeline
        copy.behaviors.append(Behavior(id: (context.ids.next() as TrackID).raw, target: id, kind: kind, start: start))
        try run(.batch("Follow a path", [.setTimeline(copy)]), label: "\(scene.objects[id]?.name ?? "It") follows \(scene.objects[line]?.name ?? "the line")")
    }

    mutating func motionLookAt(_ action: JSONValue) throws {
        let id = try target(action["target"])
        let watched = try string(action, "at") == "nothing" ? nil : target(action["at"])
        let command = if let from = action["from"] {
            try LookAtOperations.switchLook(id, to: watched, at: time(from), in: scene, ids: &context.ids)
        } else {
            LookAtOperations.look(id, at: watched, at: context.now, in: scene, ids: &context.ids)
        }
        guard let command else { throw fail("a thing can't look at itself") }
        try run(command, label: command.label)
    }

    mutating func motionPickUp(_ action: JSONValue) throws {
        let id = try target(action["target"])
        let holder = try target(action["by"])
        let at = try time(action["at"])
        let shown = Animator.evaluate(document, at: at)
        let joint = string(action, "joint")
        guard let command = HoldOperations.pickUp(id, by: holder, joint: joint, at: at, shown: shown, timeline: timeline, ids: &context.ids) else {
            throw fail("\(scene.objects[holder]?.name ?? "it") can't hold \(scene.objects[id]?.name ?? "that") (it would hold itself)")
        }
        try run(command, label: "\(command.label) at \(format(at))")
    }

    mutating func motionPutDown(_ action: JSONValue) throws {
        let id = try target(action["target"])
        let at = try time(action["at"])
        guard let command = HoldOperations.putDown(id, at: at, timeline: timeline, ids: &context.ids) else {
            throw fail("nothing holds \(scene.objects[id]?.name ?? "it") at \(format(at))")
        }
        try run(command, label: "Put down at \(format(at))")
    }

    mutating func motionLetGo(_ action: JSONValue) throws {
        let id = try target(action["target"])
        try run(HoldOperations.letGo(id, in: timeline), label: "Never held")
    }

    mutating func motionEvenSpeed(_ action: JSONValue) throws {
        let id = try target(action["target"])
        guard let command = DrawnMotion.evenSpeed(id, in: timeline) else { throw fail("evenSpeed needs a thing with a motion") }
        try run(command, label: "Even speed")
    }

    mutating func motionTiming(_ action: JSONValue) throws {
        let id = try target(action["target"])
        guard let duration = number(action, "duration") else { throw fail("timing needs “duration” (seconds)") }
        try run(DrawnMotion.retiming(id, to: duration, in: timeline), label: "Its motion lasts \(format(duration))")
    }

    mutating func motionFront(_ action: JSONValue) throws {
        let id = try target(action["target"])
        let turns = Int(number(action, "quarterTurns") ?? 1)
        try run(DrawnMotion.turningFront(id, quarterTurns: turns, in: timeline), label: "Turn its front")
    }
}
