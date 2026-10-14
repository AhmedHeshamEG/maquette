import Foundation

/// Recording modelling steps into a shape's editable history, and changing them (H1).
public extension ModelingOperations {
    enum HistoryFailure: Error, Equatable, CustomStringConvertible {
        /// The shape was changed some other way after these steps.
        case fixed
        case painted
        case rigged
        case replay(ModelHistory.ReplayFailure)

        public var description: String {
            switch self {
            case .fixed: "The shape was changed by hand after these steps, so they stay as they are."
            case .painted: "It was painted after these steps, so they stay as they are."
            case .rigged: "It was rigged after these steps, so they stay as they are."
            case let .replay(failure): failure.description
            }
        }
    }

    /// Why an object's steps can't be changed right now, or nil when they can.
    static func historyLock(of object: SceneObject) -> HistoryFailure? {
        guard let history = object.modelHistory else { return .fixed }
        if object.paint != nil { return .painted }
        if object.rig != nil { return .rigged }
        guard let mesh = editableMesh(of: object), history.describes(mesh) else { return .fixed }
        return nil
    }

    /// Step `index` of the object's steps (counting only the ones that can change) with number `number` set to
    /// `value` (metres), and every step after it replayed, as one command.
    static func changeStep(_ id: ObjectID, step index: Int, number: Int, to value: Double, in scene: Scene,
                           format: (Double) -> String = { "\($0)" }) throws(HistoryFailure) -> EditCommand {
        guard let object = scene.objects[id], let history = object.modelHistory, history.steps.indices.contains(index) else {
            throw .fixed
        }
        if let lock = historyLock(of: object) { throw lock }
        let step = history.steps[index].setting(number, to: value)
        do {
            let replayed = try history.replaying(index, as: step, format: format)
            return .batch("Change \(step.name)", [.setKind(id, .mesh(replayed.shape)), .setModelHistory(id, replayed.history)])
        } catch {
            throw .replay(error)
        }
    }

    // MARK: Recording

    /// The history a new step on the object continues: its own while it still makes the shape, else a fresh one from
    /// the shape as it is, the old steps kept as fixed. Nil once the object is painted or rigged (the history stays
    /// as it was, fixed at that point).
    internal static func continuing(_ object: SceneObject, mesh: EditableMesh) -> ModelHistory? {
        if object.paint != nil || object.rig != nil { return nil }
        guard let history = object.modelHistory else { return ModelHistory(starting: mesh) }
        if history.describes(mesh) { return history }
        return ModelHistory(starting: mesh, earlier: history.earlier + history.steps)
    }

    /// Runs one step on the object's baked shape (picked parts as picked) and records it, as one labelled command.
    internal static func record(_ id: ObjectID, label: String, in scene: Scene, picks: ModelStep.Picks?, keepsSymmetry: Bool = true,
                                near: (EditableMesh) -> Vec3?,
                                action: (_ mesh: EditableMesh, _ tags: [PartTags.Tag]) -> ModelStep.Action) throws(Failure) -> EditCommand {
        guard let object = scene.objects[id], let (mesh, bakes) = bakedMesh(of: object) else { throw .notEditable }
        let history = continuing(object, mesh: mesh)
        let shape = ModelStep.Shape(mesh: mesh, tags: history?.tags ?? [])
        let symmetry = keepsSymmetry ? symmetry(of: object) : nil
        let keepsPositive = near(mesh).map { (symmetry?.plane.height(of: $0) ?? 0) >= -1e-12 } ?? true
        let step = ModelStep(tag: history?.nextTag ?? 0, action: action(mesh, shape.tags), symmetry: symmetry, keepsPositive: keepsPositive)
        let result = try step.apply(to: shape, picks: picks)
        var commands = setMesh(id, result.mesh, bakesScale: bakes)
        if var history {
            history.append(step, making: result)
            commands.append(.setModelHistory(id, history))
        }
        return .batch(label, commands)
    }

    internal static func faceRefs(_ faces: [Int], in mesh: EditableMesh, tags: [PartTags.Tag]) -> [FaceRef] {
        faces.compactMap { PartTags.faceRef($0, in: mesh, tags: tags) }
    }

    internal static func edgeRefs(_ edges: Set<MeshEdge>, in mesh: EditableMesh, tags: [PartTags.Tag]) -> [EdgeRef] {
        let topology = MeshTopology(mesh)
        return edges.sorted { ($0.a, $0.b) < ($1.a, $1.b) }.compactMap { PartTags.edgeRef($0, in: mesh, topology: topology, tags: tags) }
    }

    // MARK: Sketches and other solids

    /// A sketch's area pulled into or cut out of the object it was drawn on, recorded as a step. Nil when the target's
    /// own scale isn't one (the step would have to live in a stretched space; the shape changes unrecorded).
    internal static func recordedSketch(_ sketch: Sketch, region: SketchRegion, distance: Double, into target: ObjectID,
                                        in scene: Scene) throws(Failure) -> EditCommand? {
        guard let object = scene.objects[target], object.transform.scale.isApproximately(.one, tolerance: 1e-12),
              let mesh = editableMesh(of: object) else { return nil }
        let world = scene.worldTransform(of: target)
        let plane = PlaneFrame(origin: world.inverseApply(to: sketch.plane.origin), normal: world.inverseApplyDirection(sketch.plane.normal),
                               u: world.inverseApplyDirection(sketch.plane.u), v: world.inverseApplyDirection(sketch.plane.v))
        let used = sketch.curves(making: region).sorted().map { sketch.curves[$0] }
        let own = Sketch(plane: plane, curves: used)
        guard let index = own.regions
            .firstIndex(where: { abs($0.area - region.area) <= max(region.area, 1e-12) * 1e-6 && $0.holes.count == region.holes.count })
        else { return nil }
        let tolerance = max(mesh.bounds?.size.maxComponent ?? 1, 1e-3) * 1e-6
        let through = distance < 0 && distance <= ModelStep.deepest(mesh, below: plane) + tolerance
        let tags = object.modelHistory.flatMap { $0.describes(mesh) ? $0.tags : nil } ?? PartTags.base(count: mesh.faces.count)
        let onFace = mesh.faces.indices.first { face in
            let flat = PartTags.FlatFace(mesh, face: face)
            return flat.normal.dot(plane.normal) > 1 - 1e-6 && abs(flat.normal.dot(plane.origin) - flat.offset) < tolerance
                && flat.contains(plane.lift(region.outline.first ?? Vec2(0, 0)), tolerance: tolerance)
        }.flatMap { PartTags.faceRef($0, in: mesh, tags: tags) }
        let cut = ModelStep.SketchCut(plane: plane, curves: used, region: index, distance: distance, through: through, onFace: onFace)
        return try record(target, label: distance > 0 ? "Pull" : "Cut", in: scene, picks: .faces([]), keepsSymmetry: false,
                          near: { _ in nil }) { _, _ in .sketch(cut) }
    }

    /// Other solids combined into one, each recorded as a step of the one that stays. Nil when its scale isn't one.
    internal static func recordedBoolean(_ keeper: ObjectID, others: [EditableMesh], _ operation: MeshBoolean.Operation,
                                         in scene: Scene) throws(Failure) -> [EditCommand]? {
        guard let object = scene.objects[keeper], object.transform.scale.isApproximately(.one, tolerance: 1e-12),
              let mesh = editableMesh(of: object) else { return nil }
        let world = scene.worldTransform(of: keeper)
        var history = continuing(object, mesh: mesh)
        var shape = ModelStep.Shape(mesh: mesh, tags: history?.tags ?? [])
        for solid in others {
            let step = ModelStep(tag: history?.nextTag ?? 0, action: .combine(tool: solid.untransformed(by: world), operation: operation))
            shape = try step.apply(to: shape)
            history?.append(step, making: shape)
        }
        var commands: [EditCommand] = [.setKind(keeper, .mesh(shape.mesh))]
        if let history { commands.append(.setModelHistory(keeper, history)) }
        return commands
    }
}
