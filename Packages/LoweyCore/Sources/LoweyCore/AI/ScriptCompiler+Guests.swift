import Foundation

// MARK: - The guests' kits (G1): Room, Print, Study, Game, and the mannequin

extension ScriptState {
    static let guestOps: [String: @Sendable (inout ScriptState, JSONValue) throws -> Void] = [
        "roof": { try $0.guestRoof($1) },
        "column": { try $0.guestColumn($1) },
        "beam": { try $0.guestBeam($1) },
        "railing": { try $0.guestRailing($1) },
        "person": { try $0.guestPerson($1) },
        "terrain": { try $0.guestTerrain($1) },
        "label": { try $0.guestLabel($1) },
        "explode": { try $0.guestExplode($1) },
        "orient": { try $0.guestOrient($1) },
        "split": { try $0.guestSplit($1) },
        "hollow": { try $0.guestHollow($1) },
        "engrave": { try $0.guestEngrave($1, raised: false) },
        "emboss": { try $0.guestEngrave($1, raised: true) },
        "hole": { try $0.guestHole($1) },
        "print": { try $0.guestPrintPiece($1) },
        "scale": { try $0.guestScale($1) },
        "greybox": { try $0.guestGreybox($1) },
        "freeze": { try $0.guestFreeze($1) }
    ]

    /// `{"do": "guest", "op": "roof" | "column" | … , …}`: the set-ups' tools (Room, Print, Study, Game).
    mutating func guest(_ action: JSONValue) throws {
        guard let op = string(action, "op"), let handler = Self.guestOps[op] else {
            throw fail("guest needs “op”: \(Self.guestOps.keys.sorted().joined(separator: ", "))")
        }
        try handler(&self, action)
    }

    private func points(_ value: JSONValue?) -> [Vec3] {
        value?.arrayValue?.compactMap { vec3($0) } ?? []
    }

    private mutating func added(_ command: EditCommand, action: JSONValue, name: String) throws {
        guard case let .batch(_, steps) = command, case let .insert(fragment, _, _)? = steps.first, let id = fragment.roots.first else {
            try run(command, label: name)
            return
        }
        try run(command, label: name)
        remember(action, id, name: name)
    }

    private func modelling(_ body: () throws(ModelingOperations.Failure) -> EditCommand) throws -> EditCommand {
        do { return try body() } catch { throw fail(error.description) }
    }

    // MARK: Room

    /// `{"op": "roof", "kind": "gable|hip|shed|flat", "outline": [[x, y, z]…]}` or `"over": "Walls"` (the walls' top).
    private mutating func guestRoof(_ action: JSONValue) throws {
        let kind = string(action, "kind").flatMap(RoomParts.RoofKind.init(rawValue:)) ?? .gable
        var outline = points(action["outline"])
        if outline.isEmpty, let over = action["over"] {
            guard let box = SceneBounds(library: context.library).worldBounds(of: try target(over), in: scene) else { throw fail("no walls") }
            outline = [Vec3(box.min.x, box.max.y, box.min.z), Vec3(box.max.x, box.max.y, box.min.z), Vec3(box.max.x, box.max.y, box.max.z),
                       Vec3(box.min.x, box.max.y, box.max.z)]
        }
        guard outline.count >= 3 else { throw fail("roof needs “outline” (three corners or more) or “over”: the walls it covers") }
        let id: ObjectID = context.ids.next()
        let pitch = number(action, "pitch") ?? 30
        try added(modelling { () throws(ModelingOperations.Failure) in try ModelingOperations.addRoof(kind, outline: outline, pitch: pitch, id: id) },
                  action: action, name: kind.title)
    }

    private mutating func guestColumn(_ action: JSONValue) throws {
        let id: ObjectID = context.ids.next()
        try added(ModelingOperations.addColumn(at: try point(action["at"]) ?? context.focus, height: number(action, "height") ?? Architecture.wallHeight,
                                               round: (string(action, "shape") ?? "round") == "round", id: id), action: action, name: "Column")
    }

    private mutating func guestBeam(_ action: JSONValue) throws {
        guard let from = try point(action["from"]), let to = try point(action["to"]) else { throw fail("beam needs “from” and “to”") }
        let id: ObjectID = context.ids.next()
        try added(modelling { () throws(ModelingOperations.Failure) in try ModelingOperations.addBeam(from: from, to: to, id: id) }, action: action,
                  name: "Beam")
    }

    private mutating func guestRailing(_ action: JSONValue) throws {
        let path = points(action["path"])
        let id: ObjectID = context.ids.next()
        try added(modelling { () throws(ModelingOperations.Failure) in try ModelingOperations.addRailing(along: path, id: id) }, action: action,
                  name: "Railing")
    }

    private mutating func guestPerson(_ action: JSONValue) throws {
        let id: ObjectID = context.ids.next()
        try added(ModelingOperations.addPerson(at: try point(action["at"]) ?? context.focus, yaw: number(action, "yaw") ?? 0, id: id),
                  action: action, name: "Person")
    }

    private mutating func guestTerrain(_ action: JSONValue) throws {
        let id: ObjectID = context.ids.next()
        let width = min(max(number(action, "width") ?? 20, 1), 500), depth = min(max(number(action, "depth") ?? width, 1), 500)
        try added(ModelingOperations.addTerrain(width: width, depth: depth, hills: number(action, "hills") ?? 1, at: try point(action["at"]) ?? .zero,
                                                seed: UInt64(max(number(action, "seed") ?? 1, 0)), id: id), action: action, name: "Terrain")
    }

    private mutating func guestLabel(_ action: JSONValue) throws {
        guard let text = string(action, "text"), !text.isEmpty else { throw fail("label needs “text”") }
        let id: ObjectID = context.ids.next()
        try added(ModelingOperations.addLabel(text, at: try point(action["at"]) ?? context.focus, id: id), action: action, name: text)
    }

    // MARK: Study

    /// `{"op": "explode", "target": "Gearbox"}`: pulls a group apart, or puts it back together.
    private mutating func guestExplode(_ action: JSONValue) throws {
        let id = try target(action["target"])
        let bounds = SceneBounds(library: context.library)
        let current = scene
        guard let command = Explode.toggle(id, in: current, bounds: { bounds.worldBounds(of: $0, in: current) }) else {
            throw fail("explode needs a group of parts")
        }
        try run(command, label: current.objects[id]?.explodeAmount ?? 0 > 0 ? "Put together" : "Explode")
    }

    // MARK: Print

    /// A face of a thing by the way it faces (top, bottom, front, back, left, right): its middle and its normal.
    private func face(_ action: JSONValue, of id: ObjectID) throws -> (point: Vec3, normal: Vec3) {
        guard let object = scene.objects[id], let mesh = ModelingOperations.editableMesh(of: object) else {
            throw fail("“\(scene.objects[id]?.name ?? id.raw)” isn't a shape made here")
        }
        let world = mesh.transformed(by: scene.worldTransform(of: id))
        let facing = string(action, "face").flatMap(Self.direction) ?? .unitY
        guard let index = world.faces.indices.max(by: { world.normal(of: $0).dot(facing) < world.normal(of: $1).dot(facing) }) else {
            throw fail("no face")
        }
        return (try point(action["at"]) ?? world.centroid(of: index), world.normal(of: index))
    }

    private mutating func guestOrient(_ action: JSONValue) throws {
        let id = try target(action["target"])
        let current = scene
        try run(modelling { () throws(ModelingOperations.Failure) in try ModelingOperations.orientForPrinting(id, in: current) },
                label: "Orient for printing")
    }

    /// `{"op": "split", "target": "Helmet", "axis": "y", "at": 0.12, "pegs": true}`: cut across `axis` at that height.
    private mutating func guestSplit(_ action: JSONValue) throws {
        let id = try target(action["target"])
        let axis = string(action, "axis").flatMap(Axis.init(rawValue:)) ?? .y
        guard let box = SceneBounds(library: context.library).worldBounds(of: id, in: scene) else { throw fail("nothing to split") }
        var at = box.center
        if let along = number(action, "at") { at[axis] = along }
        let newID: ObjectID = context.ids.next()
        let current = scene
        let pegs = bool(action, "pegs") ?? true, tolerance = number(action, "tolerance") ?? 0.0002
        try run(modelling { () throws(ModelingOperations.Failure) in
            try ModelingOperations.splitForPrinting(id, point: at, normal: axis.unit, pegs: pegs, tolerance: tolerance, newID: newID, in: current)
        }, label: "Split")
    }

    private mutating func guestHollow(_ action: JSONValue) throws {
        let id = try target(action["target"])
        let current = scene
        let wall = number(action, "wall") ?? 0.002, drain = number(action, "drain") ?? 0.003
        try run(modelling { () throws(ModelingOperations.Failure) in
            try ModelingOperations.hollowForPrinting(id, wall: wall, drain: drain, in: current)
        }, label: "Hollow")
    }

    private mutating func guestEngrave(_ action: JSONValue, raised: Bool) throws {
        let id = try target(action["target"])
        guard let text = string(action, "text"), !text.isEmpty else { throw fail("\(raised ? "emboss" : "engrave") needs “text”") }
        let (at, normal) = try face(action, of: id)
        let current = scene
        let size = number(action, "size") ?? 0.006
        try run(modelling { () throws(ModelingOperations.Failure) in
            try ModelingOperations.engrave(text, into: id, at: at, normal: normal, size: size, raised: raised, in: current)
        }, label: raised ? "Emboss" : "Engrave")
    }

    /// `{"op": "hole", "target": "Box", "screw": "M3", "kind": "clearance|counterbore|tapped|threaded|insert", "face": "top"}`.
    private mutating func guestHole(_ action: JSONValue) throws {
        let id = try target(action["target"])
        let screw = string(action, "screw").flatMap { MetricScrew(rawValue: $0.uppercased()) } ?? .m3
        let kind = string(action, "kind").flatMap(ScrewHole.init(rawValue:)) ?? .clearance
        let (at, normal) = try face(action, of: id)
        let current = scene
        let tolerance = number(action, "tolerance") ?? 0.0002
        try run(modelling { () throws(ModelingOperations.Failure) in
            try ModelingOperations.screwHole(kind, screw, in: id, at: at, normal: normal, tolerance: tolerance, in: current)
        }, label: "\(screw.rawValue) \(kind.title.lowercased()) hole")
    }

    /// `{"op": "print", "piece": "jar|bolt|nut", "screw": "M6", "at": [0, 0, 0]}`.
    private mutating func guestPrintPiece(_ action: JSONValue) throws {
        guard let name = string(action, "piece"), let piece = ModelingOperations.PrintPiece(rawValue: name) else {
            throw fail("print needs “piece”: \(ModelingOperations.PrintPiece.allCases.map(\.rawValue).joined(separator: ", "))")
        }
        let screw = string(action, "screw").flatMap { MetricScrew(rawValue: $0.uppercased()) } ?? .m6
        let at = try point(action["at"]) ?? context.focus
        let tolerance = number(action, "tolerance") ?? 0.0002
        var ids = context.ids
        let command = try modelling { () throws(ModelingOperations.Failure) in
            try ModelingOperations.addPrintPiece(piece, screw: screw, tolerance: tolerance, at: at, ids: &ids)
        }
        context.ids = ids
        try run(command, label: piece.title)
    }

    private mutating func guestScale(_ action: JSONValue) throws {
        let id = try target(action["target"])
        guard let size = number(action, "size"), size > 0 else { throw fail("scale needs “size” in metres") }
        let axis = string(action, "axis").flatMap(Axis.init(rawValue:))
        let current = scene
        try run(modelling { () throws(ModelingOperations.Failure) in
            try ModelingOperations.scaleToSize(id, target: size, axis: axis, in: current)
        }, label: "Scale to size")
    }

    // MARK: Game

    private mutating func guestGreybox(_ action: JSONValue) throws {
        guard let name = string(action, "piece"), let piece = GreyboxPiece(rawValue: name) else {
            throw fail("greybox needs “piece”: \(GreyboxPiece.allCases.map(\.rawValue).joined(separator: ", "))")
        }
        let id: ObjectID = context.ids.next()
        try added(ModelingOperations.addGreybox(piece, at: try point(action["at"]) ?? context.focus, id: id), action: action, name: piece.title)
    }

    private mutating func guestFreeze(_ action: JSONValue) throws {
        let ids = try targets(action["targets"] ?? action["target"])
        guard let command = ModelingOperations.freezeTransforms(ids, in: scene) else { throw fail("nothing turned or sized to freeze") }
        try run(command, label: "Freeze transforms")
    }
}
