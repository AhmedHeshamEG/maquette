import Foundation

// MARK: - Characters (K1)

/// `{"do": "character", "op": …}`: make a character from a start, add, restyle and remove parts (on a character or any
/// thing), make a thing a part or the drawing of a face state, change a face state, change a proportion, make it say a
/// typed line, rig it again. Every change to the parts rigs the character again in the same undo step.
extension ScriptState {
    static let characterOps: [String: @Sendable (inout ScriptState, JSONValue) throws -> Void] = [
        "new": { try $0.characterNew($1) },
        "add": { try $0.characterAdd($1) },
        "style": { try $0.characterStyle($1) },
        "remove": { try $0.characterRemove($1) },
        "assign": { try $0.characterAssign($1) },
        "state": { try $0.characterState($1) },
        "proportion": { try $0.characterProportion($1) },
        "say": { try $0.characterSay($1) },
        "rig": { try $0.characterRig($1) }
    ]

    mutating func characterMaker(_ action: JSONValue) throws {
        guard let op = string(action, "op"), let handler = Self.characterOps[op] else {
            throw fail("character needs “op”: \(Self.characterOps.keys.sorted().joined(separator: ", "))")
        }
        try handler(&self, action)
    }

    mutating func characterNew(_ action: JSONValue) throws {
        let start = string(action, "start").flatMap { CharacterStart(rawValue: $0) } ?? .person
        let name = ObjectFactory.uniqueName(string(action, "name") ?? start.title, in: scene)
        let fragment = try CharacterMaker.start(start, name: name, at: point(action["at"]) ?? context.focus, ids: &context.ids)
        let root = fragment.roots[0]
        let insert = EditCommand.insert(fragment, parent: nil, index: nil)
        try run(CharacterAutoRig.rigging(after: insert, root: root, in: document, label: "New \(start.title.lowercased())"),
                label: "New character “\(name)” (\(start.title))")
        remember(action, root, name: name)
    }

    /// A part job by name ("eye", "eyes", "legs"…).
    func partJob(_ action: JSONValue, _ key: String = "part") throws -> CharacterPart.Job {
        guard let word = string(action, key)?.lowercased()
        else { throw fail("needs “\(key)”: \(CharacterPart.Job.allCases.map(\.rawValue).joined(separator: ", "))") }
        let singular = word.hasSuffix("s") && CharacterPart.Job(rawValue: String(word.dropLast())) != nil ? String(word.dropLast()) : word
        guard let job = CharacterPart.Job(rawValue: singular) ?? (singular == "extras" ? .extra : nil) else {
            throw fail("unknown part “\(word)” (\(CharacterPart.Job.allCases.map(\.rawValue).joined(separator: ", ")))")
        }
        return job
    }

    mutating func characterAdd(_ action: JSONValue) throws {
        let target = try target(action["target"] ?? action["character"])
        let job = try partJob(action)
        let style = string(action, "style")
        if let style, !PartSet.styles(for: job).contains(where: { $0.name == style }) {
            throw fail("\(job.rawValue) has the styles \(PartSet.styles(for: job).map(\.name).joined(separator: ", "))")
        }
        guard let change = CharacterMaker.add(job, style: style, to: target, symmetric: bool(action, "symmetric") ?? true, in: scene,
                                              ids: &context.ids, shapeBounds: characterBounds) else { throw fail("couldn't add \(job.rawValue)") }
        try run(CharacterAutoRig.rigging(after: change.command, root: change.root, in: document, label: "Add \(job.title.lowercased())"),
                label: "Added \(job.title.lowercased()) to “\(scene.objects[change.root]?.name ?? "")”")
    }

    /// A thing's shape bounds: Core's, else the app's mesh (placed models).
    func characterBounds(_ object: SceneObject) -> Bounds? {
        CharacterAnatomy.coreBounds(object) ?? context.mesh(object)?.bounds
    }

    /// The piece named by `target`, and the character it belongs to.
    func characterPart(_ action: JSONValue) throws -> (piece: ObjectID, root: ObjectID) {
        let piece = try target(action["target"])
        guard scene.objects[piece]?.part != nil, let root = CharacterMaker.character(of: piece, in: scene) else {
            throw fail("“target” must be a part of a made character")
        }
        return (piece, root)
    }

    mutating func characterStyle(_ action: JSONValue) throws {
        let (piece, root) = try characterPart(action)
        guard let style = string(action, "style"), let job = scene.objects[piece]?.part?.job,
              PartSet.styles(for: job).contains(where: { $0.name == style }) else { throw fail("style needs a “style” of the part's set") }
        guard let change = CharacterMaker.restyle(piece, to: style, mirrored: bool(action, "symmetric") ?? true, in: scene, ids: &context.ids) else {
            throw fail("that part was drawn or modelled; it has no styles")
        }
        try run(CharacterAutoRig.rigging(after: change, root: root, in: document, label: change.label), label: "Restyled to \(style)")
    }

    mutating func characterRemove(_ action: JSONValue) throws {
        let (piece, root) = try characterPart(action)
        let change = CharacterMaker.remove(piece, mirrored: bool(action, "symmetric") ?? true, in: scene)
        try run(CharacterAutoRig.rigging(after: change, root: root, in: document, label: "Remove part"), label: "Removed a part")
    }

    mutating func characterAssign(_ action: JSONValue) throws {
        let thing = try target(action["target"])
        let root = try target(action["character"])
        let job = try partJob(action)
        let side = string(action, "side").flatMap(CharacterPart.Side.init(rawValue:)) ?? .middle
        let shows = string(action, "state")
        if let shows, !FaceStates.names(for: job).contains(shows) {
            throw fail("\(job.rawValue) has the states \(FaceStates.names(for: job).joined(separator: ", "))")
        }
        guard let change = CharacterMaker.assign(thing, as: job, side: side, shows: shows, character: root, in: scene) else {
            throw fail("couldn't make that a part")
        }
        try run(CharacterAutoRig.rigging(after: change, root: root, in: document, label: change.label), label: change.label)
    }

    mutating func characterState(_ action: JSONValue) throws {
        let (piece, _) = try characterPart(action)
        guard let part = scene.objects[piece]?.part, let state = string(action, "state"), FaceStates.names(for: part.job).contains(state) else {
            throw fail("state needs a “state” of the part (mouths: \(MouthShape.allCases.map(\.rawValue).joined(separator: ", ")))")
        }
        var bend: FaceBend? = FaceStates.bend(of: part, state)
        if bool(action, "reset") == true {
            bend = nil
        } else if let given = action["bend"] {
            var changed = bend ?? .none
            for (key, path) in [("open", \FaceBend.open), ("wide", \.wide), ("round", \.round), ("smile", \.smile), ("lift", \.lift),
                                ("tilt", \.tilt), ("close", \.squash)] {
                if let value = given[key]?.numberValue { changed[keyPath: path] = value }
            }
            bend = changed
        }
        try run(CharacterMaker.setState(state, of: piece, to: bend, mirrored: bool(action, "symmetric") ?? true, in: scene),
                label: "\(FaceStates.title(state)) changed")
    }

    mutating func characterProportion(_ action: JSONValue) throws {
        let root = try target(action["target"])
        guard let name = string(action, "measure"), let measure = CharacterProportions.Measure(rawValue: name) else {
            throw fail("proportion needs “measure”: \(CharacterProportions.Measure.allCases.map(\.rawValue).joined(separator: ", "))")
        }
        guard let anatomy = CharacterAnatomy(root, in: scene, shapeBounds: characterBounds) else { throw fail("“target” must be a made character") }
        var factor = number(action, "by") ?? 1
        if let metres = number(action, "to"), let now = CharacterProportions.measure(anatomy)[measure], now > 1e-6 { factor = metres / now }
        let side = string(action, "side").flatMap(CharacterPart.Side.init(rawValue:))
        guard let change = CharacterProportions.change(measure, by: factor, anatomy: anatomy, scene: scene, side: side) else { return }
        try run(CharacterAutoRig.rigging(after: change, root: root, in: document, label: change.label), label: change.label)
    }

    mutating func characterSay(_ action: JSONValue) throws {
        let root = try target(action["target"] ?? action["character"])
        guard let text = string(action, "line"), !text.isEmpty else { throw fail("say needs a “line”") }
        let language = string(action, "language") ?? "en-US"
        try run(LipSync.line(text, character: root, from: time(action["at"], default: 0), language: language, timeline: timeline, ids: &context.ids),
                label: "Says “\(text)”")
    }

    mutating func characterRig(_ action: JSONValue) throws {
        let root = try target(action["target"])
        guard let rig = CharacterAutoRig.command(root, in: scene, shapeBounds: characterBounds) else { throw fail("“target” must be a made character") }
        try run(rig, label: "Rigged “\(scene.objects[root]?.name ?? "")”")
    }
}
