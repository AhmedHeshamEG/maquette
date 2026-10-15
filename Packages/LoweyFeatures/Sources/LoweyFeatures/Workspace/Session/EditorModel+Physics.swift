import Foundation
import HmmDesign
import LoweyCore
import LoweyEngine

/// P1: making things real, the scene's gravity and wind, joints, forces and fluids, Keep it, Settle, does it stand.
extension EditorModel {
    // MARK: The run

    /// The scene changed: the run starts again in the background (or a finished one for this scene comes back).
    func schedulePhysics() {
        let document = session.document
        guard PhysicsInput.hasPhysics(document.scene) || physicsRun.frames != nil else { return }
        let sources = PhysicsSources.gather(document, catalog: library.catalog, models: library.models)
        physicsRun.update(document, sources: sources) { [weak self] in
            guard let self else { return }
            refreshDisplay()
            refreshPhysicsOverlay()
        }
    }

    /// While the run is still being made, playback waits for it rather than showing things that haven't moved yet.
    func physicsHold(_ next: Double) -> Double {
        guard let frames = physicsRun.frames, !frames.isComplete, next > frames.reach, !audioPlayback.isPlaying else { return next }
        return max(min(next, frames.reach), time)
    }

    // MARK: Real

    /// The real things among the selection (the top-most of each).
    var realSelection: [ObjectID] { selection.filter { baseScene.objects[$0]?.physics != nil } }

    func makeReal(_ material: PhysicsMaterial? = nil) {
        let targets = operations.topLevel(selection, in: baseScene)
        guard !targets.isEmpty else { return }
        let commands = targets.map { id -> EditCommand in
            var physics = baseScene.objects[id]?.physics ?? ObjectPhysics()
            if let material { physics.material = material }
            return .setPhysics(id, physics)
        }
        if perform(.batch(material.map { "Real: \($0.title)" } ?? "Real", commands)), physicsRun.frames == nil {
            app.show("Real things move when you play")
        }
    }

    func makeUnreal() {
        let targets = selection.filter { baseScene.objects[$0]?.physics != nil }
        perform(.batch("Not real", targets.map { .setPhysics($0, nil) }))
    }

    /// One change to every selected real thing (a material, a number, how it moves).
    func changePhysics(_ label: String, coalesce: String? = nil, _ change: (inout ObjectPhysics) -> Void) {
        let commands = realSelection.compactMap { id -> EditCommand? in
            guard var physics = baseScene.objects[id]?.physics else { return nil }
            change(&physics)
            return physics == baseScene.objects[id]?.physics ? nil : .setPhysics(id, physics)
        }
        guard !commands.isEmpty else { return }
        perform(.batch(label, commands), coalesceKey: coalesce)
    }

    // MARK: The scene

    var scenePhysics: ScenePhysics { baseScene.physics ?? ScenePhysics() }

    func changeScenePhysics(_ label: String, coalesce: String? = nil, _ change: (inout ScenePhysics) -> Void) {
        var settings = scenePhysics
        change(&settings)
        guard settings != baseScene.physics else { return }
        perform(.setScenePhysics(settings), coalesceKey: coalesce)
    }

    // MARK: Joints

    /// The joints that hold the selected thing.
    var selectedJoints: [PhysicsJoint] {
        guard let id = singleSelection?.id else { return [] }
        return scenePhysics.joints.filter { $0.first == id || $0.second == id }
    }

    /// Joins two selected things (or one to the world, where it hangs from its top) with a joint of this kind, placed
    /// where they meet; a hinge turns about the vertical, a slider slides from one toward the other.
    func join(_ kind: PhysicsJoint.Kind) {
        let targets = operations.topLevel(selection, in: baseScene)
        guard let first = targets.first, let firstBox = operations.bounds.worldBounds(of: first, in: baseScene) else { return }
        let second = targets.count > 1 ? targets[1] : nil
        let secondBox = second.flatMap { operations.bounds.worldBounds(of: $0, in: baseScene) }
        let world = baseScene.worldTransform(of: first)
        let anchor: Vec3 = if let secondBox {
            Self.meeting(firstBox, secondBox)
        } else {
            Vec3(firstBox.center.x, firstBox.max.y, firstBox.center.z)
        }
        let direction = secondBox.map { ($0.center - firstBox.center).normalized } ?? .unitY
        var joint = PhysicsJoint(id: "joint-\(UUID().uuidString.prefix(8).lowercased())", kind: kind, first: first, second: second,
                                 anchor: world.inverseApply(to: anchor), axis: world.inverseApplyDirection(kind == .slider ? direction : .unitY).normalized)
        if kind == .spring || kind == .rope {
            joint.anchor = world.inverseApply(to: secondBox == nil ? anchor : firstBox.center)
            let other = secondBox?.center ?? Vec3(anchor.x, anchor.y + 1, anchor.z)
            joint.otherAnchor = second.map { baseScene.worldTransform(of: $0).inverseApply(to: other) } ?? other
        }
        if kind == .gear {
            let hinges = scenePhysics.joints.filter { $0.kind == .hinge && ($0.first == first || $0.first == second) }
            guard hinges.count >= 2 else {
                app.show("A gear joins two hinges: give each wheel a hinge first")
                return
            }
            joint.gears = [hinges[0].id, hinges[1].id]
            joint.ratio = 1
        }
        var making = [EditCommand]()
        for id in [first] + (second.map { [$0] } ?? []) where baseScene.objects[id]?.physics == nil {
            making.append(.setPhysics(id, ObjectPhysics()))
        }
        var settings = scenePhysics
        settings.joints.append(joint)
        perform(.batch(kind.title, making + [.setScenePhysics(settings)]))
    }

    /// The middle of where two boxes overlap, or the point halfway between their nearest faces.
    static func meeting(_ a: Bounds, _ b: Bounds) -> Vec3 {
        let low = Vec3(max(a.min.x, b.min.x), max(a.min.y, b.min.y), max(a.min.z, b.min.z))
        let high = Vec3(min(a.max.x, b.max.x), min(a.max.y, b.max.y), min(a.max.z, b.max.z))
        return (low + high) * 0.5
    }

    func changeJoint(_ id: String, coalesce: String? = nil, _ change: (inout PhysicsJoint) -> Void) {
        changeScenePhysics("Joint", coalesce: coalesce) { settings in
            guard let index = settings.joints.firstIndex(where: { $0.id == id }) else { return }
            change(&settings.joints[index])
        }
    }

    func removeJoint(_ id: String) {
        changeScenePhysics("Remove joint") { settings in
            settings.joints.removeAll { $0.id == id || ($0.gears?.contains(id) ?? false) }
        }
    }

    // MARK: Forces and fluids

    func addForce(_ kind: ForceRecipe.Kind) {
        refreshOperationsLibrary()
        var object = SceneObject(id: .make(), name: ObjectFactory.uniqueName(kind.title, in: scene), kind: .force(ForceRecipe(kind: kind)))
        let anchor = selectionPivot ?? dropPoint()
        object.transform.position = kind == .fan ? anchor + Vec3(0, 0.6, 1.5) : anchor + Vec3(0, 1, 0)
        if perform(operations.add(object)) { select(object.id) }
    }

    func addFluid(_ kind: FluidRecipe.Kind) {
        refreshOperationsLibrary()
        var object = SceneObject(id: .make(), name: ObjectFactory.uniqueName(kind.title, in: scene), kind: .fluid(FluidRecipe(kind: kind)))
        // A tap goes above what's selected (a glass), smoke and fire sit on it, a splash is let go a little above it.
        let top = selectionBounds.map { Vec3($0.center.x, $0.max.y, $0.center.z) } ?? dropPoint()
        object.transform.position = switch kind {
        case .pour: top + Vec3(0, 0.25, 0)
        case .splash: top + Vec3(0, 0.4, 0)
        case .smoke, .fire: top
        }
        if perform(operations.add(object)) {
            select(object.id)
            app.show("Play to see it; it's worked out in the background")
        }
    }

    func updateForce(_ id: ObjectID, _ change: (inout ForceRecipe) -> Void) {
        guard case var .force(recipe) = baseScene.objects[id]?.kind else { return }
        change(&recipe)
        perform(.setKind(id, .force(recipe)), coalesceKey: "force-\(id.raw)")
    }

    func updateFluid(_ id: ObjectID, _ change: (inout FluidRecipe) -> Void) {
        guard case var .fluid(recipe) = baseScene.objects[id]?.kind else { return }
        change(&recipe)
        perform(.setKind(id, .fluid(recipe)), coalesceKey: "fluid-\(id.raw)")
    }

    // MARK: Keep it, Settle, does it stand

    /// The run as ordinary keys (one undo step): what fell now follows its keys.
    func keepRun() {
        guard let frames = physicsRun.frames else { return }
        guard frames.isComplete else {
            app.show("The run is still being worked out")
            return
        }
        var ids = IDFactory.random
        guard perform(PhysicsKeep.keep(frames, in: session.document, ids: &ids)) else {
            app.show("Nothing moved")
            return
        }
        app.show("Kept: the run is keys now")
    }

    /// The selected thing drops onto its natural resting face, on the ground or what's under it.
    func settleSelection() {
        guard let id = operations.topLevel(selection, in: baseScene).first, let object = baseScene.objects[id] else { return }
        let shown = baseScene
        var meshes: [ObjectID: MeshData] = [:]
        for (other, thing) in shown.objects where thing.kind.hasSurface && shown.isEffectivelyVisible(other) {
            if let mesh = PhysicsSources.local(thing, look: look, catalog: library.catalog, models: library.models) { meshes[other] = mesh }
        }
        guard let settled = PhysicsTools.settle(id, in: shown, meshes: meshes, ground: scenePhysics.ground) else {
            app.show("There's nothing to settle it on")
            return
        }
        let parent = object.parent.map { shown.worldTransform(of: $0) } ?? .identity
        let local = CoreTransform.relative(world: settled, toParent: parent)
        perform(.batch("Settle", [.setProperties([PropertyChange(object: id, key: .position, value: .vec3(local.position)),
                                                  PropertyChange(object: id, key: .rotation, value: .quat(local.rotation))])]))
    }

    /// Does it stand? The answer in one line, and its centre of mass and footprint on the stage.
    func checkStands() {
        let targets = operations.topLevel(selection, in: baseScene)
        guard !targets.isEmpty else { return }
        var meshes: [ObjectID: MeshData] = [:]
        for id in targets.flatMap({ baseScene.subtree(of: $0) }) {
            guard let object = baseScene.objects[id],
                  let mesh = PhysicsSources.local(object, look: look, catalog: library.catalog, models: library.models) else { continue }
            meshes[id] = mesh
        }
        guard let result = PhysicsTools.stability(of: targets, in: baseScene, meshes: meshes) else { return }
        physicsRun.stability = result
        physicsRun.stabilityOf = targets
        let centimetres = String(Int((abs(result.margin) * 100).rounded()))
        if result.stands {
            app.show("It stands: its weight is \(centimetres) cm inside its footprint", kind: .success)
        } else {
            app.show("It tips over: its weight is \(centimetres) cm past its footprint", kind: .error)
        }
        refreshPhysicsOverlay()
    }
}
