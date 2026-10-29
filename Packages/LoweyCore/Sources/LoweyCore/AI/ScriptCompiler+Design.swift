import Foundation
import HmmVector

// MARK: - Motion design (D1): logos, clones and effects, links, morphs, letters, loops

extension ScriptState {
    static let designOps: [String: @Sendable (inout ScriptState, JSONValue) throws -> Void] = [
        "logo": { try $0.designLogo($1) },
        "clone": { try $0.designClone($1) },
        "effect": { try $0.designEffect($1) },
        "link": { try $0.designLink($1) },
        "morph": { try $0.designMorph($1) },
        "letters": { try $0.designLetters($1) },
        "loop": { try $0.designLoop($1) }
    ]

    /// `{"do": "design", "op": "logo" | "clone" | "effect" | "link" | "morph" | "letters" | "loop", …}`.
    mutating func design(_ action: JSONValue) throws {
        guard let op = string(action, "op"), let handler = Self.designOps[op] else {
            throw fail("design needs “op”: \(Self.designOps.keys.sorted().joined(separator: ", "))")
        }
        try handler(&self, action)
    }

    /// `{"op": "logo", "svg": "<svg…>" | "file": "media/logo.svg", "name": "Brand", "width": 1.2, "depth": 0.08, "at": [0, 0, 0]}`.
    private mutating func designLogo(_ action: JSONValue) throws {
        let data: Data
        if let svg = string(action, "svg") {
            data = Data(svg.utf8)
        } else if let path = string(action, "file"), let file = context.file(path) {
            data = file
        } else {
            throw fail("logo needs “svg” (the file's text) or “file” (an SVG added to the project)")
        }
        let drawing: VectorDrawing
        do { drawing = try SVG.read(data) } catch { throw fail(error.description) }
        let width = min(max(number(action, "width") ?? 1, 0.01), 100)
        let depth = min(max(number(action, "depth") ?? width * 0.08, 0.001), width)
        var ids = context.ids
        let name = name(action, fallback: "Logo")
        guard var made = LogoImport.objects(drawing, name: name, width: width, depth: depth, makeID: { ids.next() }) else {
            throw fail("the logo has no filled shapes")
        }
        context.ids = ids
        if let index = made.objects.firstIndex(where: { $0.id == made.root }) {
            made.objects[index].transform.position = try point(action["at"]) ?? context.focus
        }
        try run(.insert(SceneFragment(objects: made.objects, roots: [made.root]), parent: nil, index: nil), label: "Logo “\(name)”")
        remember(action, made.root, name: name)
        report.append("\(drawing.colors.count) colour(s), \(drawing.shapes.count) shape(s)" + Self.skippedNote(drawing.skipped))
    }

    static func skippedNote(_ skipped: VectorSkipped) -> String {
        var left: [String] = []
        if skipped.strokes > 0 { left.append("\(skipped.strokes) stroke(s)") }
        if skipped.texts > 0 { left.append("\(skipped.texts) text(s)") }
        if skipped.images > 0 { left.append("\(skipped.images) picture(s)") }
        return left.isEmpty ? "" : "; left out (convert them to shapes first): " + left.joined(separator: ", ")
    }

    /// `{"op": "clone", "target": "Logo", "layout": "grid", "columns": 5, "rows": 5, "spacing": [1.4, 1.4, 1.4]}`;
    /// circle: `count`, `radius`, `facesOut`; line: `count`, `step`; path: `count`, `path`, `along`; placed: `places`, a list
    /// of `{"at": [x, y, z], "turn": [degrees], "size": [x, y, z]}` against the thing's own (the first is the thing).
    /// `"off": true` removes.
    private mutating func designClone(_ action: JSONValue) throws {
        let id = try target(action["target"])
        var design = scene.objects[id]?.motionDesign ?? MotionDesign()
        if bool(action, "off") == true {
            design.clones = nil
        } else {
            var clones = design.clones ?? ObjectClones(layout: .grid(columns: 5, rows: 5, layers: 1, spacing: Vec3(1.4, 1.4, 1.4)))
            clones.layout = try cloneLayout(action, current: clones.layout)
            design.clones = clones
            report.append("\(clones.count) copies")
        }
        try run(.setMotionDesign(id, design.orNil), label: "Clone “\(scene.objects[id]?.name ?? id.raw)”")
    }

    private func cloneLayout(_ action: JSONValue, current: ObjectClones.Layout) throws -> ObjectClones.Layout {
        let count = Int(number(action, "count") ?? Double(current.count))
        switch string(action, "layout") ?? current.title.lowercased() {
        case "grid":
            let spacing = vec3(action["spacing"]) ?? number(action, "spacing").map { Vec3($0, $0, $0) } ?? Vec3(1.4, 1.4, 1.4)
            return .grid(columns: Int(number(action, "columns") ?? 5), rows: Int(number(action, "rows") ?? 5),
                         layers: Int(number(action, "layers") ?? 1), spacing: spacing)
        case "circle":
            return .circle(count: count, radius: number(action, "radius") ?? 2, facesOut: bool(action, "facesOut") ?? true)
        case "line":
            return .line(count: count, step: vec3(action["step"]) ?? Vec3(1.2, 0, 0))
        case "path", "along a path":
            return try .path(count: count, path: target(action["path"]), along: bool(action, "along") ?? true)
        case "placed", "as placed":
            if let list = action["places"]?.arrayValue, !list.isEmpty {
                return .placed(list.map { Transform(position: vec3($0["at"]) ?? .zero, rotation: Quat(eulerDegrees: vec3($0["turn"]) ?? .zero),
                                                    scale: vec3($0["size"]) ?? Vec3(1, 1, 1)) })
            }
            if case .placed = current { return current }
            throw fail("a placed layout needs “places”: a list of {at, turn, size}")
        case let other:
            throw fail("layout “\(other)” is one of grid, circle, line, path, placed")
        }
    }

    /// `{"op": "effect", "target": "Logo", "kind": "push", "move": [0, 0.5, 0], "grow": 0.2, "field": "ripple",
    /// "speed": 3, "width": 1.5, "every": 2}`; random: `move`, `turn`, `grow`; delay: `delay` seconds; field: everywhere,
    /// sphere (`centre`, `radius`) or ripple. `"clear": true` removes the effects.
    private mutating func designEffect(_ action: JSONValue) throws {
        let id = try target(action["target"])
        guard var design = scene.objects[id]?.motionDesign, var clones = design.clones else {
            throw fail("“\(scene.objects[id]?.name ?? id.raw)” has no clones yet (clone it first)")
        }
        if bool(action, "clear") == true {
            clones.effects = []
        } else {
            guard let kind = string(action, "kind").flatMap(CloneEffect.Kind.init(rawValue:)) else {
                throw fail("effect needs “kind”: random, delay, push")
            }
            var effect = CloneEffect(id: context.ids.next(ObjectID.self).raw, kind: kind, move: vec3(action["move"]) ?? .zero,
                                     turn: vec3(action["turn"]) ?? .zero, grow: number(action, "grow") ?? 0, delay: number(action, "delay") ?? 0)
            effect.field = try cloneField(action)
            clones.effects.append(effect)
        }
        design.clones = clones
        try run(.setMotionDesign(id, design), label: "Clone effect")
    }

    private func cloneField(_ action: JSONValue) throws -> CloneField {
        switch string(action, "field") ?? "everywhere" {
        case "everywhere": return .everywhere
        case "sphere", "near":
            return .sphere(centre: vec3(action["centre"]) ?? .zero, radius: number(action, "radius") ?? 1)
        case "ripple", "wave":
            return .wave(speed: number(action, "speed") ?? 3, width: number(action, "width") ?? 1.5, every: number(action, "every") ?? 2)
        case let other:
            throw fail("field “\(other)” is one of everywhere, sphere, ripple")
        }
    }

    /// `{"op": "link", "target": "Gear B", "channel": "turnY", "from": "Gear A", "fromChannel": "turnY", "amount": -0.5}` or
    /// `{"op": "link", "target": "Logo", "channel": "effect", "sound": "Music", "feature": "beat", "amount": 1}`;
    /// `"off": true` removes the target's links (on that channel, when one is named).
    private mutating func designLink(_ action: JSONValue) throws {
        let id = try target(action["target"])
        let channel = try string(action, "channel").map { name in
            guard let channel = MotionLink.Channel(rawValue: name) else {
                throw fail("channel is one of \(MotionLink.Channel.allCases.map(\.rawValue).joined(separator: ", "))")
            }
            return channel
        }
        var links = timeline.links
        if bool(action, "off") == true {
            links.removeAll { $0.target == id && (channel == nil || $0.channel == channel) }
            try run(.setLinks(links), label: "Unlink")
            return
        }
        guard let channel else { throw fail("link needs “channel”") }
        let driver = try linkDriver(action, channel: channel)
        let amount = number(action, "amount") ?? (driver.isSound ? channel.soundAmount : 1)
        if driver.isSound, channel == .effect { report.append("the effects start from nothing and rise with the sound") }
        links.append(MotionLink(id: context.ids.next(ObjectID.self).raw, target: id, channel: channel, driver: driver, amount: amount,
                                delay: number(action, "delay") ?? 0))
        var commands: [EditCommand] = [.setLinks(links)]
        if driver.isSound, channel == .effect {
            commands.append(.setProperties([PropertyChange(object: id, key: .effectStrength, value: .float(0))]))
        }
        try run(.batch("Link", commands), label: "Link “\(scene.objects[id]?.name ?? id.raw)”")
    }

    private func linkDriver(_ action: JSONValue, channel _: MotionLink.Channel) throws -> MotionLink.Driver {
        if let sound = string(action, "sound") {
            guard let clip = timeline.audio.first(where: { $0.id == sound || $0.name.caseInsensitiveCompare(sound) == .orderedSame }) else {
                throw fail("no sound “\(sound)” on the timeline (\(timeline.audio.map(\.name).joined(separator: ", ")))")
            }
            let feature = string(action, "feature").flatMap(MotionLink.SoundFeature.init(rawValue:)) ?? .beat
            return .sound(clip: clip.id, feature: feature)
        }
        let from = try target(action["from"])
        let fromChannel = string(action, "fromChannel").flatMap(MotionLink.Channel.init(rawValue:)) ?? .turnY
        guard MotionLink.Channel.motion.contains(fromChannel) else {
            throw fail("fromChannel is one of \(MotionLink.Channel.motion.map(\.rawValue).joined(separator: ", "))")
        }
        return .thing(id: from, channel: fromChannel)
    }

    /// `{"op": "morph", "target": "Cube", "into": "Ball", "at": 1, "duration": 1}`: the cube becomes the ball's shape over
    /// a second from that moment (the ball is hidden: it's the shape to reach). `"off": true` removes the morph.
    private mutating func designMorph(_ action: JSONValue) throws {
        let id = try target(action["target"])
        var design = scene.objects[id]?.motionDesign ?? MotionDesign()
        if bool(action, "off") == true {
            design.morph = nil
            try run(.setMotionDesign(id, design.orNil), label: "No morph")
            return
        }
        let into = try target(action["into"])
        guard into != id else { throw fail("a thing can't morph into itself") }
        let start = try time(action["at"], default: context.now)
        let duration = max(number(action, "duration") ?? 1, 0.05)
        design.morph = ObjectMorph(target: into)
        var ids = context.ids
        let command = MorphOperations.command(id, into: into, design: design, from: start, duration: duration, in: document, ids: &ids)
        context.ids = ids
        try run(command, label: "Morph “\(scene.objects[id]?.name ?? id.raw)”")
    }

    /// `{"op": "letters", "target": "Title", "preset": "flyIn", "order": "forward", "at": {"word": "Hello"}, "stagger": 0.06,
    /// "length": 0.6}`; `"preset": "none"` stops them.
    private mutating func designLetters(_ action: JSONValue) throws {
        let id = try target(action["target"])
        guard let object = scene.objects[id], case .text = object.kind else { throw fail("letters animate on 3D text") }
        var design = object.motionDesign ?? MotionDesign()
        let presetName = string(action, "preset") ?? "flyIn"
        if presetName == "none" {
            design.letters = nil
        } else {
            guard let preset = TextAnimator.Preset(rawValue: presetName) else {
                throw fail("preset is one of \(TextAnimator.Preset.allCases.map(\.rawValue).joined(separator: ", ")), none")
            }
            var letters = try TextAnimator.starting(preset, at: time(action["at"], default: context.now))
            if let order = string(action, "order").flatMap(TextAnimator.Order.init(rawValue:)) { letters.order = order }
            if let stagger = number(action, "stagger") { letters.stagger = max(stagger, 0) }
            if let length = number(action, "length") { letters.length = max(length, 0.01) }
            design.letters = letters
        }
        try run(.setMotionDesign(id, design.orNil), label: "Letters")
    }

    /// `{"op": "loop", "close": true}`: whether the timeline (or its loop region) loops seamlessly, what jumps, and with
    /// `close` the fix (keys back where they began, repeats retimed to fit).
    private mutating func designLoop(_ action: JSONValue) throws {
        let range = timeline.loop ?? TimeRange(start: 0, end: timeline.duration)
        if bool(action, "close") == true, let command = LoopClose.command(document, range: range) {
            try run(command, label: "Close the loop")
        }
        let seams = LoopCheck.seams(document, range: range)
        report.append(seams.isEmpty ? "loops seamlessly (\(format(range.start))–\(format(range.end)))"
            : "jumps at the loop: " + seams.map { "\($0.name) \($0.what.title)" }.joined(separator: "; "))
    }
}

private extension MotionLink.Driver {
    var isSound: Bool {
        if case .sound = self { return true }
        return false
    }
}
