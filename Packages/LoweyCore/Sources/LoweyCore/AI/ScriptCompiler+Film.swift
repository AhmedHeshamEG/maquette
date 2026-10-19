import Foundation

// MARK: - Film (F1): the lens, the frame, focus, rigs, the air and the HDRI

extension ScriptState {
    static let filmOps: [String: @Sendable (inout ScriptState, JSONValue) throws -> Void] = [
        "lens": { try $0.filmLens($1) },
        "frame": { try $0.filmFrame($1) },
        "focus": { try $0.filmFocus($1) },
        "rig": { try $0.filmRig($1) },
        "air": { try $0.filmAir($1) },
        "environment": { try $0.filmEnvironment($1) },
        "shots": { $0.filmShots($1) }
    ]

    /// `{"do": "film", "op": "lens" | "frame" | "focus" | "rig" | "air" | "environment" | "shots", …}`.
    mutating func film(_ action: JSONValue) throws {
        guard let op = string(action, "op"), let handler = Self.filmOps[op] else {
            throw fail("film needs “op”: \(Self.filmOps.keys.sorted().joined(separator: ", "))")
        }
        try handler(&self, action)
    }

    /// The camera an op is about: "camera", else the shot camera at the playhead.
    private func filmCamera(_ action: JSONValue) throws -> ObjectID {
        if let named = action["camera"] {
            let id = try target(named)
            guard scene.objects[id]?.kind == .camera else { throw fail("“\(scene.objects[id]?.name ?? id.raw)” isn't a camera") }
            return id
        }
        guard let id = timeline.cutCamera(at: context.now) ?? scene.activeCamera else { throw fail("there's no camera yet (add one with “camera”)") }
        return id
    }

    /// `{"op": "lens", "camera": "Shot", "mm": 50, "sensor": "super35", "aperture": 2.8}`: millimetres on the body.
    private mutating func filmLens(_ action: JSONValue) throws {
        let id = try filmCamera(action)
        guard let camera = scene.objects[id] else { return }
        var changes: [PropertyChange] = []
        var sensor = CameraSensor.of(camera)
        if let name = string(action, "sensor") {
            guard let body = CameraSensor(rawValue: name) else {
                throw fail("sensor is one of \(CameraSensor.allCases.map(\.rawValue).joined(separator: ", "))")
            }
            sensor = body
            changes.append(PropertyChange(object: id, key: .sensor, value: body == .fullFrame ? nil : .enumeration(body.rawValue)))
        }
        if let mm = number(action, "mm") {
            guard mm >= 4, mm <= 1200 else { throw fail("mm is 4–1200") }
            changes.append(PropertyChange(object: id, key: .fieldOfView, value: .float(CameraLens.fieldOfView(focalLength: mm, on: sensor))))
        }
        if let aperture = number(action, "aperture") {
            changes.append(PropertyChange(object: id, key: .aperture, value: .float(aperture < 0.9 ? 0 : min(aperture, 32))))
        }
        guard !changes.isEmpty else { throw fail("lens needs “mm”, “sensor” or “aperture”") }
        try run(.setProperties(changes), label: "Lens on “\(camera.name)”")
    }

    /// `{"op": "frame", "shape": "2.39:1"}`: the picture's shape for the Director view, Frame shot and every export.
    private mutating func filmFrame(_ action: JSONValue) throws {
        guard let name = string(action, "shape"), let shape = FrameShape(rawValue: name) else {
            throw fail("frame needs “shape”: \(FrameShape.allCases.map(\.rawValue).joined(separator: ", "))")
        }
        var edited = timeline
        edited.frame = shape == .landscape ? nil : shape
        try run(.setTimeline(edited), label: "Frame \(shape.rawValue)")
    }

    /// `{"op": "focus", "camera": "Shot", "on": "Hero", "at": 2}`: the lens keeps the thing sharp from that moment, pulling
    /// from what it held before; `"on": null` goes back to a set distance.
    private mutating func filmFocus(_ action: JSONValue) throws {
        let id = try filmCamera(action)
        let subject: ObjectID? = if case .null? = action["on"] {
            nil
        } else {
            try target(action["on"])
        }
        let time = try action["at"].map { try self.time($0) } ?? context.now
        var ids = context.ids
        defer { context.ids = ids }
        guard let command = FocusOperations.focus(id, on: subject, at: time, in: scene, ids: &ids) else { throw fail("can't focus on that") }
        try run(command, label: subject.flatMap { scene.objects[$0]?.name }.map { "Focus on “\($0)”" } ?? "Focus by distance")
        if let camera = scene.objects[id], (camera[.aperture]?.floatValue ?? 0) < 0.9 {
            report.append("The aperture is off, so everything is sharp: set one (lens “aperture”: 2.8) to see the focus")
        }
    }

    /// `{"op": "rig", "camera": "Shot", "kind": "crane", "lift": 2, "swing": 20, "keys": {"lift": [[0, 0], [3, 2.5]]}}`.
    private mutating func filmRig(_ action: JSONValue) throws {
        let id = try filmCamera(action)
        guard let name = string(action, "kind"), let rig = CameraRig(rawValue: name) else {
            throw fail("rig needs “kind”: \(CameraRig.allCases.map(\.rawValue).joined(separator: ", "))")
        }
        let names: [String: PropertyKey] = ["travel": .rigTravel, "lift": .rigLift, "swing": .rigSwing, "arm": .rigArm, "shake": .rigShake]
        var changes = [PropertyChange(object: id, key: .rig, value: rig == .none ? nil : .enumeration(rig.rawValue))]
        for (word, key) in names.sorted(by: { $0.key < $1.key }) {
            if let value = number(action, word) { changes.append(PropertyChange(object: id, key: key, value: .float(value))) }
        }
        try run(.setProperties(changes), label: "\(rig.title) on “\(scene.objects[id]?.name ?? "camera")”")
        guard case let .object(keyed)? = action["keys"] else { return }
        var edits: [TrackEdit] = []
        for (word, value) in keyed.sorted(by: { $0.key < $1.key }) {
            guard let key = names[word], key.spec?.animatable == true else { throw fail("keys are for travel, lift, swing or shake") }
            var track = timeline.track(for: id, key) ?? Track(id: context.ids.next(), target: id, property: key)
            for pair in value.arrayValue ?? [] {
                guard let numbers = pair.arrayValue?.compactMap(\.numberValue), numbers.count == 2 else { throw fail("a key is [seconds, value]") }
                track.setKey(Keyframe(time: max(numbers[0], 0), value: .float(numbers[1]), easing: .easeInOut))
            }
            edits.append(TrackEdit(track))
        }
        if !edits.isEmpty { try run(.setTracks(edits), label: "Keys on the \(rig.title.lowercased())") }
    }

    /// `{"op": "air", "haze": 0.4, "godRays": 0.6, "color": "#FFD9A0"}` (0 clears).
    private mutating func filmAir(_ action: JSONValue) throws {
        var look = document.effectiveLook
        var air = look.atmosphere ?? Atmosphere()
        if let haze = number(action, "haze") { air.haze = min(max(haze, 0), 1) }
        if let rays = number(action, "godRays") { air.godRays = min(max(rays, 0), 1) }
        if action["color"] != nil { air.color = try color(action["color"])?.resolved(in: document.palette) }
        look.atmosphere = air.isClear ? nil : air
        try run(.setLook(look, scope: scene.look != nil ? .scene : .project), label: air.isClear ? "Clear air" : "Haze and god rays")
    }

    /// `{"op": "environment", "turn": 40}` turns the HDRI (and its sun with it); `"off": true` goes back to the mood's sky.
    /// The picture itself comes over `add_media` as an environment.
    private mutating func filmEnvironment(_ action: JSONValue) throws {
        var look = document.effectiveLook
        guard look.sky.environment != nil else { throw fail("there's no HDRI: send one with add_media as an environment first") }
        if bool(action, "off") == true {
            look = look.applying(look.lightingPreset ?? .day)
            look.sky.environment = nil
        } else {
            let turn = number(action, "turn") ?? look.sky.environmentTurn ?? 0
            look.lighting.sunAzimuth += turn - (look.sky.environmentTurn ?? 0)
            look.sky.environmentTurn = turn
            if let exposure = number(action, "exposure") { look.sky.environmentExposure = exposure }
        }
        try run(.setLook(look, scope: scene.look != nil ? .scene : .project), label: look.sky.environment == nil ? "No HDRI" : "HDRI turned")
    }

    /// Lists the shots (read-only): what a storyboard would show.
    private mutating func filmShots(_ action: JSONValue) {
        for panel in Storyboard.panels(document) {
            report.append("\(panel.heading) (\(format(panel.shot.start))–\(format(panel.shot.end))): \(panel.detail)"
                + (panel.words.isEmpty ? "" : " — “\(panel.words)”"))
        }
    }
}
