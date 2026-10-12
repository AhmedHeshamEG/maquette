import CoreGraphics
import Foundation
import HmmDesign
import LoweyCore
import LoweyEngine

/// Rig (CONTEXT §10.5, U4): pins and dots make the skeleton (`EditorModel+RigMarks`), the weights are worked out by
/// bone heat in the background, and the brush paints them by hand one step deeper. Every change is one `setRig` (its
/// weights' file written first). While the Rig tool is on, the object stands as it was made (its rest pose), so marks
/// land where they're placed; leaving it returns the pose.
extension EditorModel {
    // MARK: What can be rigged

    /// Why an object can't take pins and dots (nil when it can).
    func rigBlocker(_ object: SceneObject) -> String? {
        // Something with a drawn rig is in the cast too, and is exactly what goes on being rigged.
        if let type = castType(of: object.id, object: object), type != .drawn {
            return type == .rigged ? "This model has its own skeleton: drag its joints to pose it"
                : "A \(type.title) has its skeleton built in: drag its hands and feet to pose it"
        }
        switch object.kind {
        case .primitive(.plane):
            return "A flat plane has nothing to bend: draw on it, then rig the drawing"
        case .primitive, .mesh, .drawing:
            return nil
        case .group:
            return object.children.isEmpty ? "This group is empty" : nil
        case let .asset(id):
            guard let model = loadedModel(id) else { return "This model hasn't loaded yet" }
            return model.parts.contains(where: \.isSkinned) ? "This model has its own skeleton: drag its joints to pose it" : nil
        default:
            return "Rig a shape, a modelled part, a drawing, a group of parts or a placed model"
        }
    }

    func loadedModel(_ id: AssetID) -> ImportedModel? {
        guard let asset = library.catalog.manifest.asset(id) else { return nil }
        return library.models.model(asset, catalog: library.catalog)
    }

    /// The object Rig works on: the one being rigged while it's there, else the selection when it can be rigged.
    var rigTarget: SceneObject? {
        if let id = rigging.target, let object = baseScene.objects[id], rigBlocker(object) == nil { return object }
        return rigSubject.flatMap { rigBlocker($0) == nil ? $0 : nil }
    }

    /// What the Rig panel speaks of: the selection, or (a part of a rigged group chosen) its group.
    var rigSubject: SceneObject? {
        guard let object = singleSelection else { return nil }
        guard object.rig == nil else { return object }
        let group = baseScene.ancestors(of: object.id).compactMap { baseScene.objects[$0] }.first { $0.kind == .group && $0.rig != nil }
        return group ?? object
    }

    /// Several parts chosen: they're grouped, and the group is rigged with pins and dots (ToonSquid's "bind a whole
    /// group": each part rides the bone nearest it).
    func rigTogether() {
        guard selection.count > 1 else { return }
        groupSelection()
        guard let group = singleSelection, group.kind == .group else { return }
        startMarking(group.id, kind: .dot)
    }

    /// Where the object's rig lives in the world, as it was made (the edited scene, unposed).
    func rigFrame(_ id: ObjectID) -> CoreTransform {
        RigSpace.frame(of: id, in: baseScene)
    }

    /// A ray on the stage, in the rig's space.
    func rigRay(at point: CGPoint, frame: CoreTransform) -> Ray? {
        guard let ray = stage?.worldRay(at: point) else { return nil }
        let origin = frame.inverseApply(to: ray.origin)
        let ahead = frame.inverseApply(to: ray.origin + ray.direction)
        return Ray(origin: origin, direction: (ahead - origin).normalized)
    }

    /// Whether the rig's weights still fit the object (its shape may have been modelled since). A group's parts ride
    /// their bones whole, so its rig always fits.
    func rigFits(_ object: SceneObject) -> Bool {
        guard let rig = object.rig else { return true }
        switch object.kind {
        case .group: return true
        case .drawing: return RigOperations.fits(rig, object: object, mesh: nil)
        default: return RigOperations.fits(rig, object: object, mesh: paintSource(of: object))
        }
    }

    // MARK: Storing a rig

    /// Stores the rig a change made: a group binds its parts to the bones at once; anything with a surface has its
    /// weights worked out in the background (the shape cut finer first when it has too few corners to bend), then
    /// lands as one step. `done` is said when there's something to say.
    func weigh(_ rig: ObjectRig, on object: SceneObject, label: String, also commands: [EditCommand] = [],
               done: String.LocalizationValue? = nil) {
        let id = object.id
        if case .group = object.kind {
            let binding = RigidParts.binding(id, rig: rig, in: baseScene)
            perform(.batch(label, [.setRig(id, rig)] + (binding.isEmpty ? [] : [.setProperties(binding)]) + commands))
            if let done { app.show(done) }
            return
        }
        var shaped = object
        var detail: [EditCommand] = []
        let mesh: MeshData? = if case .drawing = object.kind {
            nil
        } else {
            denser(&shaped, for: rig, commands: &detail)
        }
        rigging.weighing[id] = rig
        let folder = assetsFolder
        let target = shaped
        Task {
            let result = await Task.detached(priority: .userInitiated) { RigOperations.weighted(rig, object: target, mesh: mesh) }.value
            // A newer change is being weighed: it holds this one's marks too, and lands as one step.
            guard rigging.weighing[id] == rig else { return }
            rigging.weighing[id] = nil
            if boneSurface == nil { endBonePreview() }
            guard let result else {
                app.show("This can't be rigged", kind: .error)
                return
            }
            do {
                try await Self.write(result.files, to: folder)
            } catch {
                app.show("Couldn't save the rig's weights: \(error.localizedDescription)", kind: .error)
                return
            }
            guard baseScene.objects[id] != nil else { return }
            perform(.batch(label, detail + [.setRig(id, result.rig)] + commands))
            if let done { app.show(done) }
            if rigging.joint == nil || rigging.joint ?? 0 >= result.rig.skeleton.joints.count { rigging.joint = result.rig.skeleton.joints.count - 1 }
            HmmHaptics.play(.commit)
        }
    }

    /// The mesh a rig is weighed on: the object's own, or (a shape with too few corners to bend at its joints) cut
    /// finer, with the change that keeps it cut (CONTEXT §10.10: rigging adds the geometry a shape lacks).
    private func denser(_ object: inout SceneObject, for rig: ObjectRig, commands: inout [EditCommand]) -> MeshData? {
        guard let mesh = paintSource(of: object) else { return nil }
        switch object.kind {
        case .primitive, .mesh:
            break
        default:
            return mesh
        }
        let bones = rig.segments.map { (head: $0.head, tail: $0.tail) }
        guard object[.bendDetail] == nil, let cuts = MeshDensify.cuts(for: mesh, bones: bones) else { return mesh }
        object[.bendDetail] = .float(Double(cuts))
        commands.append(.setProperties([PropertyChange(object: object.id, key: .bendDetail, value: .float(Double(cuts)))]))
        return MeshDensify.densified(mesh, cuts: cuts)
    }

    /// The weights worked out again for the object's shape as it is now.
    func refitRig(_ id: ObjectID) {
        guard let object = baseScene.objects[id], let rig = object.rig else { return }
        var fresh = rig
        fresh.skin = nil
        fresh.points = nil
        weigh(fresh, on: object, label: "Fit the weights")
    }

    /// Removes the skeleton, its pose and its keys, and lets a group's parts go (one undo step).
    func removeRig(_ id: ObjectID) {
        guard let object = baseScene.objects[id], object.rig != nil else { return }
        var commands: [EditCommand] = [.setRig(id, nil)]
        var changes = object.properties.keys.filter { $0.boneJoint != nil }.sorted().map { PropertyChange(object: id, key: $0, value: nil) }
        if case .group = object.kind { changes += RigidParts.binding(id, rig: nil, in: baseScene) }
        if !changes.isEmpty { commands.append(.setProperties(changes)) }
        let tracks = timeline.tracks.filter { $0.target == id && $0.property.boneJoint != nil }.map { TrackEdit(id: $0.id, track: nil) }
        if !tracks.isEmpty { commands.append(.setTracks(tracks)) }
        perform(.batch("Remove the rig", commands))
        rigging.joint = nil
        rigging.current = nil
        if tool == .rig { tool = .select }
    }

    /// Puts every joint back as it was made (one undo step).
    func resetPose(_ id: ObjectID) {
        guard let rig = CharacterRig.of(id, in: baseScene, rigs: libraryRigs()) else { return }
        let changes = rig.resetting(in: baseScene)
        guard !changes.isEmpty else { return }
        perform(.batch("Reset the pose", [.setProperties(changes)]))
    }

    // MARK: Weights

    /// The rig's current weights (from its file, or inline for a drawing).
    func rigWeights(_ object: SceneObject) -> SkinWeights? {
        guard let rig = object.rig else { return nil }
        if let points = rig.points { return points }
        guard let file = rig.skin, let data = paintFiles(file) else { return nil }
        return try? SkinWeights(data: data)
    }

    /// Paint weights (one step deeper than the marks): the Rig tool with the weight brush.
    func startPaintingWeights(_ id: ObjectID) {
        guard let object = baseScene.objects[id], let rig = object.rig, rigFits(object), object.kind != .group else { return }
        rigging.target = id
        rigging.mode = .weights
        rigging.person = nil
        if rigging.joint.map({ $0 >= rig.skeleton.joints.count }) ?? true { rigging.joint = rig.skeleton.joints.count - 1 }
        tool = .rig
        openPanel = nil
    }

    /// A weight brush stroke (stage points, pressure): the chosen joint's weight added (or taken away) under it.
    func paintWeights(_ samples: [(point: CGPoint, pressure: Double)]) {
        guard let object = rigTarget, let rig = object.rig, let joint = rigging.joint, let weights = rigWeights(object), let stage else { return }
        let frame = rigFrame(object.id)
        let mesh: MeshData?
        let positions: [Vec3]
        if case let .drawing(recipe) = object.kind {
            mesh = nil
            positions = recipe.strokes.flatMap(\.points)
        } else {
            mesh = paintSource(of: object)
            positions = mesh?.positions.map { Vec3(Double($0.x), Double($0.y), Double($0.z)) } ?? []
        }
        let bvh = mesh.map(TriangleBVH.init)
        let plane = if case let .drawing(recipe) = object.kind {
            RigOperations.drawingPlane(recipe)
        } else { (origin: Vec3.zero, normal: Vec3.unitZ) }
        let scale = max((abs(frame.scale.x) + abs(frame.scale.y) + abs(frame.scale.z)) / 3, 1e-6)
        let dabs: [WeightPaint.Dab] = samples.compactMap { sample in
            guard let ray = rigRay(at: sample.point, frame: frame) else { return nil }
            let centre: Vec3? = if let bvh {
                bvh.hits(origin: ray.origin, direction: ray.direction).first.map { ray.origin + ray.direction * $0 }
            } else {
                GuideSurface.plane(origin: plane.origin, normal: plane.normal).intersect(ray)?.point
            }
            guard let centre else { return nil }
            let radius = stage.worldPerPoint(at: frame.apply(to: centre)) * rigging.size / 2 / scale
            return WeightPaint.Dab(centre: centre, radius: radius, amount: rigging.strength * max(sample.pressure, 0.2))
        }
        guard !dabs.isEmpty else { return }
        let painted = WeightPaint.apply(dabs, joint: joint, erase: rigging.erase, to: weights, positions: positions)
        let stored = RigOperations.stored(painted, in: rig, object: object, mesh: mesh)
        let id = object.id
        let folder = assetsFolder
        Task {
            do {
                try await Self.write(stored.files, to: folder)
            } catch {
                app.show("Couldn't save the rig's weights: \(error.localizedDescription)", kind: .error)
                return
            }
            perform(.batch("Paint weights", [.setRig(id, stored.rig)]))
        }
    }

    // MARK: On the stage

    /// The weight view while painting weights: the object in the colours of the chosen bone's weight.
    var weightView: WeightView? {
        guard tool == .rig, rigging.mode == .weights, rigging.person == nil, let object = rigTarget, object.rig != nil,
              let joint = rigging.joint else { return nil }
        return WeightView(object: object.id, joint: joint)
    }

    /// The bones of the object being rigged, as it was made: a line between each mark and the one it hangs from (the
    /// marks themselves are drawn over the stage, where they can be touched), and while painting weights the bone
    /// being painted in the accent colour. Drawn over everything, so bones inside the body show.
    func rigOverlays(_ stage: StageView) -> [EditorOverlay] {
        guard rigging.person == nil, let object = rigTarget else { return [] }
        let drawing = bonePreviewOverlays(stage)
        let frame = rigFrame(object.id)
        var lines = MeshData()
        var picked = MeshData()
        if rigging.mode == .weights, let rig = object.rig {
            for segment in rig.segments {
                let head = frame.apply(to: segment.head), tail = frame.apply(to: segment.tail)
                let width = stage.worldPerPoint(at: head) * 2
                if segment.joint == rigging.joint {
                    ModelOverlay.line(head, tail, width: width * 1.6, into: &picked)
                } else {
                    ModelOverlay.line(head, tail, width: width, into: &lines)
                }
            }
        } else {
            for (head, tail) in RigMarks.segments(shownMarks(of: object)) {
                let start = frame.apply(to: head), end = frame.apply(to: tail)
                ModelOverlay.line(start, end, width: stage.worldPerPoint(at: start) * 2, into: &lines)
            }
        }
        var overlays = [EditorOverlay(mesh: lines, color: RGBA(1, 1, 1), opacity: 0.9, onTop: true)]
        if !picked.isEmpty { overlays.append(EditorOverlay(mesh: picked, color: Self.modelAccent, onTop: true)) }
        return overlays + drawing
    }

    /// The library's rigged models in the scene (imported characters pose by their joints even without clips).
    func libraryRigs() -> [AssetID: RigAsset] {
        var result = rigs()
        for object in baseScene.objects.values {
            // Only models the library knows are rigged: most placed models aren't, and this runs on every redraw.
            guard let id = object.kind.assetID, result[id] == nil, library.manifest.asset(id)?.rig.isRigged == true,
                  let rig = library.models.rig(id) else { continue }
            result[id] = rig
        }
        return result
    }
}
