import Foundation

// MARK: - Sketches and booleans from a script

extension ScriptState {
    /// `{"do": "sketch", "name": "Profile", "plane": "xy", "at": [0, 0, 0], "curves": [{"rectangle": [[0, 0], [1, 2]]}]}`
    /// draws construction curves on a plane ("xy", "xz", "yz", or `{"origin", "normal"}`) or on the face of a thing
    /// (`"on": "Box", "face": "top"`); `profile` then pulls, sweeps, revolves or lofts its closed areas.
    mutating func sketch(_ action: JSONValue) throws {
        let (plane, target) = try sketchPlane(action)
        guard let list = action["curves"]?.arrayValue, !list.isEmpty else {
            throw fail("sketch needs “curves”: [{\"rectangle\": [[x, y], [x, y]]}, {\"circle\": {\"center\": [x, y], \"radius\": r}}, …]")
        }
        let curves = try list.enumerated().map { index, entry in try sketchCurve(entry, index: index) }
        let sketch = Sketch(plane: plane, curves: curves, target: target)
        let object = SceneObject(id: context.ids.next(), name: name(action, fallback: "Sketch"), kind: .sketch(sketch))
        try insert(object, action: action, verb: "Sketch")
        report.append("\(sketch.regions.count) closed area(s) to pull, sweep, revolve or loft")
    }

    /// `{"do": "boolean", "op": "subtract", "target": "Body", "with": ["Arch front", "Arch back"]}`: the target keeps its
    /// name, look and place; the others are used up (as in the app).
    mutating func boolean(_ action: JSONValue) throws {
        guard let name = string(action, "op"), let operation = MeshBoolean.Operation(rawValue: name) else {
            throw fail("boolean needs “op”: \(MeshBoolean.Operation.allCases.map(\.rawValue).joined(separator: ", "))")
        }
        let keeper = try target(action["target"])
        let others = try targets(action["with"]).filter { $0 != keeper }
        guard !others.isEmpty else { throw fail("boolean needs “with”: the things to \(name)") }
        for id in [keeper] + others where !(scene.objects[id].map(ModelingOperations.canModel) ?? false) {
            throw fail(
                "“\(scene.objects[id]?.name ?? id.raw)” can't be combined: only shapes and models made here can (make a placed model editable in the app)"
            )
        }
        try run(ModelingOperations.boolean([keeper] + others, operation, in: scene), label: operation.label)
    }

    private func sketchPlane(_ action: JSONValue) throws -> (PlaneFrame, ObjectID?) {
        if let on = action["on"] {
            let id = try target(on)
            guard let object = scene.objects[id], let mesh = ModelingOperations.editableMesh(of: object) else {
                throw fail("a sketch goes on a shape or a model made here")
            }
            let world = mesh.transformed(by: scene.worldTransform(of: id))
            let facing = string(action, "face").flatMap(Self.direction) ?? .unitY
            guard let face = world.faces.indices.max(by: { world.normal(of: $0).dot(facing) < world.normal(of: $1).dot(facing) }) else {
                throw fail("no face")
            }
            return (PlaneFrame(normal: world.normal(of: face), origin: world.centroid(of: face)), id)
        }
        let origin = try point(action["at"]) ?? .zero
        if let normal = vec3(action["plane"]?["normal"]) {
            return (PlaneFrame(normal: normal, origin: vec3(action["plane"]?["origin"]) ?? origin), nil)
        }
        switch string(action, "plane") ?? "xy" {
        case "xy": return (PlaneFrame(origin: origin, normal: .unitZ, u: .unitX, v: .unitY), nil)
        case "xz": return (PlaneFrame(origin: origin, normal: .unitY, u: .unitX, v: -Vec3.unitZ), nil)
        case "yz": return (PlaneFrame(origin: origin, normal: .unitX, u: -Vec3.unitZ, v: .unitY), nil)
        case let other: throw fail("plane “\(other)” is one of xy (facing front), xz (the ground), yz (facing the side), or {origin, normal}")
        }
    }

    private func sketchCurve(_ entry: JSONValue, index: Int) throws -> SketchCurve {
        func points(_ key: String) -> [Vec2]? {
            entry[key]?.arrayValue?.compactMap { point in
                point.arrayValue.flatMap { $0.count == 2 ? $0.compactMap(\.numberValue) : nil }.flatMap { $0.count == 2 ? Vec2($0[0], $0[1]) : nil }
            }
        }
        let closed = bool(entry, "closed") ?? false
        if let ends = points("line"), ends.count == 2 { return .line(ends[0], ends[1]) }
        if let corners = points("rectangle"), corners.count == 2 { return .rectangle(corners[0], corners[1]) }
        if let three = points("arc"), three.count == 3 { return .arc(three[0], three[1], three[2]) }
        if let through = points("spline"), through.count >= 2 { return .spline(through, closed: closed) }
        if let through = points("polyline"), through.count >= 2 { return .polyline(through, closed: closed) }
        if let circle = entry["circle"], let center = vec3(circle["center"]), let radius = number(circle, "radius"), radius > 0 {
            return .circle(center: Vec2(center.x, center.y), radius: radius)
        }
        throw fail("curve \(index + 1) is one of {\"line\": [a, b]}, {\"rectangle\": [corner, corner]}, {\"circle\": {\"center\": [x, y], "
            + "\"radius\": r}}, {\"arc\": [start, through, end]}, {\"polyline\" or \"spline\": [points], \"closed\": true}, in metres on the plane")
    }
}
