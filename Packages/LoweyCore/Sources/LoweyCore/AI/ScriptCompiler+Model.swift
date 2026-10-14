import Foundation

// MARK: - Modelling (U6)

/// `{"do": "model", "target": "Box", "op": …}`: the modelling set for the bridge, everything a hand can do without
/// pointing at a part. Faces are named by the way they face ("top", "front", "+x"…), edges by the axis they run along.
extension ScriptState {
    static let modelOps: [String: @Sendable (inout ScriptState, ObjectID, JSONValue) throws -> Void] = [
        "smooth": { state, id, action in
            let levels = min(max(Int(state.number(action, "levels") ?? 1), 0), Subdivision.maximumLevels)
            try state.run(.setProperties([PropertyChange(object: id, key: .subdivision, value: levels == 0 ? nil : .int(levels))]),
                          label: "Smooth \(levels)")
        },
        "subdivide": { state, id, action in
            try state.run(ModelingOperations.subdivide(id, levels: Int(state.number(action, "levels") ?? 1), in: state.scene), label: "Subdivide")
        },
        "smoothAngle": { state, id, action in
            let degrees = state.number(action, "degrees")
            try state.run(.setProperties([PropertyChange(object: id, key: .smoothAngle, value: degrees.map { .float($0) })]), label: "Smooth angle")
        },
        "flat": { state, id, action in
            let flat = state.bool(action, "on") ?? true
            try state.run(.setProperties([PropertyChange(object: id, key: .shading, value: flat ? .enumeration("flat") : nil)]), label: "Flat shading")
        },
        "bend": { try $0.modelBend($1, $2) },
        "cage": { try $0.modelCage($1, $2) },
        "brush": { try $0.modelBrush($1, $2) },
        "pull": { try $0.modelPull($1, $2) },
        "loopCut": { try $0.modelLoopCut($1, $2) },
        "knife": { state, id, action in
            guard let point = state.vec3(action["point"]),
                  let normal = state.vec3(action["normal"]) else { throw state.fail("knife needs “point” and “normal”") }
            let space = ModelingOperations.modellingSpace(of: id, in: state.scene)
            try state.run(ModelingOperations.knife(id, planePoint: space.inverseApply(to: point), planeNormal: space.inverseApplyDirection(normal),
                                                   within: { _ in true }, in: state.scene), label: "Knife")
        },
        "fillHoles": { state, id, _ in try state.run(ModelingOperations.fillHoles(id, near: nil, in: state.scene), label: "Fill holes") },
        "mergeByDistance": { state, id, action in
            try state.run(ModelingOperations.mergeByDistance(id, distance: state.number(action, "distance") ?? 0.0001, in: state.scene),
                          label: "Merge by distance")
        },
        "cleanUp": { try $0.modelCleanUp($1, $2) },
        "linkedCopy": { state, id, action in
            var ids = state.context.ids
            let command = LinkedCopies.makeCopy(of: id, in: state.scene, offset: state.vec3(action["offset"]) ?? Vec3(1.5, 0, 0), ids: &ids)
            state.context.ids = ids
            try state.run(command, label: "Linked copy")
        },
        "unlink": { state, id, _ in try state.run(LinkedCopies.unlink(id), label: "Unlink") },
        "pivot": { try $0.modelPivot($1, $2) },
        "size": { state, id, action in
            guard let axis = state.string(action, "axis").flatMap(Axis.init(rawValue:)), let length = state.number(action, "length") else {
                throw state.fail("size needs “axis” (x, y or z) and “length” (metres)")
            }
            try state.run(Arrange.setLength(id, axis: axis, to: length, in: state.scene), label: "Size \(axis.rawValue) \(Self.short(length)) m")
        }
    ]

    mutating func model(_ action: JSONValue) throws {
        let id = try target(action["target"])
        guard let op = string(action, "op"), let handler = Self.modelOps[op] else {
            throw fail("model needs “op”: \(Self.modelOps.keys.sorted().joined(separator: ", ")), or profile ops on a sketch")
        }
        try handler(&self, id, action)
    }

    private mutating func modelBend(_ id: ObjectID, _ action: JSONValue) throws {
        guard let name = string(action, "kind") else {
            try run(.setProperties([.deform, .deformAmount, .deformAxis].map { PropertyChange(object: id, key: $0, value: nil) }), label: "No bend")
            return
        }
        guard let kind = Deform(rawValue: name) else { throw fail("bend “kind” is one of \(Deform.allCases.map(\.rawValue).joined(separator: ", "))") }
        let amount = min(max(number(action, "amount") ?? kind.starting, kind.range.lowerBound), kind.range.upperBound)
        var changes = [PropertyChange(object: id, key: .deform, value: .enumeration(kind.rawValue)),
                       PropertyChange(object: id, key: .deformAmount, value: .float(amount))]
        if let axis = string(action, "axis").flatMap(Axis.init(rawValue:)) {
            changes.append(PropertyChange(object: id, key: .deformAxis, value: axis == .y ? nil : .enumeration(axis.rawValue)))
        }
        try run(.setProperties(changes), label: "\(kind.title) \(Self.short(amount))")
    }

    /// `{"op": "cage", "counts": [3, 3, 3]}` puts one on; `"point": [i, j, k], "offset": [x, y, z]` pulls a point (its own
    /// space); `"remove": true` takes it off.
    private mutating func modelCage(_ id: ObjectID, _ action: JSONValue) throws {
        guard let object = scene.objects[id] else { throw fail("no such object") }
        var shaping = object.shaping ?? ObjectShaping()
        if bool(action, "remove") == true {
            shaping.cage = nil
        } else if let point = action["point"]?.arrayValue?.compactMap(\.numberValue), point.count == 3, var cage = shaping.cage {
            let index = cage.index(Int(point[0]), Int(point[1]), Int(point[2]))
            guard cage.offsets.indices.contains(index) else { throw fail("no such cage point") }
            cage.offsets[index] = vec3(action["offset"]) ?? .zero
            shaping.cage = cage
        } else {
            let counts = action["counts"]?.arrayValue?.compactMap { $0.numberValue.map(Int.init) } ?? [3, 3, 3]
            guard let bounds = PaintSource.unshaped(of: object)?.bounds ?? SceneBounds(library: context.library).localBounds(of: object) else {
                throw fail("this has no shape to put a cage around")
            }
            shaping.cage = DeformCage.around(bounds, counts: counts)
        }
        try run(.setShaping(id, shaping.isEmpty ? nil : shaping), label: "Cage")
    }

    /// One dab of a surface brush at a world point.
    private mutating func modelBrush(_ id: ObjectID, _ action: JSONValue) throws {
        // A shape too coarse to brush is cut finer first, as the app does.
        if let coarse = scene.objects[id], ModelingOperations.canModel(coarse), coarse[.bendDetail] == nil,
           let surface = PaintSource.unshaped(of: coarse), surface.triangleCount < 3000 {
            try run(.setProperties([PropertyChange(object: id, key: .bendDetail, value: .float(Double(MeshDensify.maximumCuts)))]), label: nil)
        }
        guard let object = scene.objects[id], let surface = PaintSource.unshaped(of: object) else { throw fail("this can't be brushed") }
        guard let brush = string(action, "brush").flatMap(SculptBrush.init(rawValue:)), let at = try point(action["at"]) else {
            throw fail("brush needs “brush” (grab, smooth, inflate) and “at”")
        }
        let world = scene.worldTransform(of: id)
        let local = world.inverseApply(to: at)
        let offsets = object.shaping?.sculpt.flatMap { $0.vertexCount == surface.positions.count ? $0.offsets : nil }
        var stroke = SculptStroke(brush: brush, mesh: surface, cornerOffsets: offsets, symmetry: bool(action, "mirror") == true ? .x : nil)
        let radius = Float((number(action, "radius") ?? 0.2) / max(world.scale.maxComponent, 1e-9))
        let moved = vec3(action["by"]).map { world.inverseApplyDirection($0) } ?? .zero
        stroke.dab(at: local.float3, radius: radius, strength: Float(number(action, "strength") ?? 0.5), moved: moved.float3)
        var shaping = object.shaping ?? ObjectShaping()
        shaping.sculpt = SculptLayer(offsets: stroke.cornerOffsets)
        try run(.setShaping(id, shaping), label: brush.title)
    }

    /// The face facing a way, pulled out (or pushed in, negative) by a distance.
    private mutating func modelPull(_ id: ObjectID, _ action: JSONValue) throws {
        guard let object = scene.objects[id], let mesh = ModelingOperations.editableMesh(of: object) else { throw fail("this can't be modelled") }
        guard let direction = string(action, "face").flatMap(Self.direction), let distance = number(action, "distance") else {
            throw fail("pull needs “face” (top, bottom, front, back, left, right) and “distance”")
        }
        guard let face = mesh.faces.indices.max(by: { mesh.normal(of: $0).dot(direction) < mesh.normal(of: $1).dot(direction) }) else {
            throw fail("no face")
        }
        try run(ModelingOperations.pushPull(id, face: face, distance: distance, in: scene), label: "Pull \(Self.short(distance)) m")
    }

    /// Cuts a ring around the shape across the edges that run along an axis.
    private mutating func modelLoopCut(_ id: ObjectID, _ action: JSONValue) throws {
        guard let object = scene.objects[id], let mesh = ModelingOperations.editableMesh(of: object)?.withoutHoles() else {
            throw fail("this can't be modelled")
        }
        let axis = string(action, "along").flatMap(Axis.init(rawValue:)) ?? .x
        guard let edge = mesh.edges.max(by: { lhs, rhs in
            abs((mesh.vertices[lhs.b] - mesh.vertices[lhs.a]).normalized.dot(axis.unit)) <
                abs((mesh.vertices[rhs.b] - mesh.vertices[rhs.a]).normalized.dot(axis.unit))
        }) else { throw fail("no edge") }
        try run(ModelingOperations.loopCut(id, across: edge, cuts: Int(number(action, "cuts") ?? 1), in: scene), label: "Loop cut")
    }

    private mutating func modelCleanUp(_ id: ObjectID, _ action: JSONValue) throws {
        guard let object = scene.objects[id], let source = SceneExport.localMesh(of: object, look: document.effectiveLook) else {
            throw fail("this can't be cleaned up here (placed models: in the app)")
        }
        let faces = Int(number(action, "faces") ?? Double(QuadRemesh.suggestedFaces(for: source)))
        let options = QuadRemesh.Options(faces: faces, pureQuads: bool(action, "quadsOnly") ?? false)
        try run(ModelingOperations.cleanTopology(id, source: source, options: options, in: scene), label: "Clean up to about \(faces) faces")
    }

    private mutating func modelPivot(_ id: ObjectID, _ action: JSONValue) throws {
        let point: Vec3? = if let at = try point(action["at"]) {
            at
        } else {
            Arrange.pivotPoint(string(action, "to") == "base" ? .base : .middle, of: id, in: scene, bounds: SceneBounds(library: context.library))
        }
        guard let point else { throw fail("pivot needs “to” (middle, base) or “at”") }
        try run(Arrange.movePivot(id, to: point, in: scene), label: "Move pivot")
    }

    static func short(_ value: Double) -> String { String(format: "%.3g", value) }

    static func direction(_ name: String) -> Vec3? {
        switch name {
        case "top", "+y": .unitY
        case "bottom", "-y": -Vec3.unitY
        case "front", "+z": .unitZ
        case "back", "-z": -Vec3.unitZ
        case "right", "+x": .unitX
        case "left", "-x": -Vec3.unitX
        default: nil
        }
    }

    // MARK: Profiles

    /// `{"do": "profile", "target": "Sketch", "region": 0, "op": "sweep" | "revolve" | "loft", …}`.
    mutating func profile(_ action: JSONValue) throws {
        let sketch = try target(action["target"])
        let region = Int(number(action, "region") ?? 0)
        var ids = context.ids
        defer { context.ids = ids }
        switch string(action, "op") {
        case "sweep":
            guard let path = action["path"]?.arrayValue?.compactMap({ vec3($0) }), path.count >= 2 else { throw fail("sweep needs “path”: points") }
            try run(ModelingOperations.sweep(sketch: sketch, region: region, along: path, closed: bool(action, "closed") ?? false, in: scene, ids: &ids),
                    label: "Sweep")
        case "revolve":
            guard let axis = action["axis"], let origin = vec3(axis["point"]), let direction = vec3(axis["direction"]) else {
                throw fail("revolve needs “axis”: {point, direction}")
            }
            try run(ModelingOperations.revolve(sketch: sketch, region: region, axisPoint: origin, axisDirection: direction,
                                               degrees: number(action, "degrees") ?? 360, in: scene, ids: &ids), label: "Revolve")
        case "loft":
            let others = try targets(action["through"])
            let profiles = [(sketch, region)] + others.map { ($0, 0) }
            try run(ModelingOperations.loft(profiles, in: scene, ids: &ids), label: "Loft")
        default:
            throw fail("profile needs “op”: sweep, revolve or loft")
        }
    }
}
