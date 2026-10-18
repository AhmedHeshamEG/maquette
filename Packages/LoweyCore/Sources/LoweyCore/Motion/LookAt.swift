import Foundation

public extension PropertyKey {
    /// The id of the thing this one looks at (A1). A character turns its head, anything else turns whole. Keyed, it
    /// switches who it watches, turning over a quarter of a second.
    static let lookAt: PropertyKey = "lookAt"
}

/// Looking at something (A1): the Animator's step after things are held, so a head follows a cup in a moving hand.
public enum LookAt {
    /// How long a look takes to move to a new target (seconds).
    static let turn = 0.25

    static func anyone(in scene: Scene) -> Bool {
        scene.objects.values.contains { $0[.lookAt] != nil }
    }

    /// Turns every looker toward its target. Returns the characters whose heads turned (their parts ride again).
    static func apply(to state: inout Animator.Posed, timeline: Timeline, time: Double, rigs: [AssetID: RigAsset]) -> Set<ObjectID> {
        var turned = Set<ObjectID>()
        for id in state.scene.objects.keys.sorted() {
            guard let target = state.scene.objects[id]?[.lookAt]?.stringValue.map(ObjectID.init(raw:)), target != id,
                  var aim = aimPoint(of: target, in: state) else { continue }
            if let (previous, progress) = switching(id, timeline: timeline, at: time), let from = aimPoint(of: previous, in: state) {
                aim = from.lerp(to: aim, Easing.easeInOut.apply(progress))
            }
            if turnHead(id, toward: aim, in: &state, rigs: rigs) {
                turned.insert(id)
            } else {
                turnWhole(id, toward: aim, in: &state)
            }
        }
        return turned
    }

    /// Where to look on a thing: a character's head, else the thing's own place.
    static func aimPoint(of id: ObjectID, in state: Animator.Posed) -> Vec3? {
        guard state.scene.objects[id] != nil else { return nil }
        if let head = HoldPlayback.frame(of: id, joint: headJoint(of: id, in: state.scene), in: state.scene, poses: state.poses, rigs: [:]) {
            return head.position
        }
        return state.scene.worldTransform(of: id).position
    }

    static func headJoint(of id: ObjectID, in scene: Scene) -> String? {
        guard let rig = CharacterRig.of(id, in: scene), let head = rig.joint("head") else { return nil }
        return rig.skeleton.joints[head].name
    }

    /// The target before the latest change and how far the look has come since (nil once it has arrived).
    static func switching(_ id: ObjectID, timeline: Timeline, at time: Double) -> (ObjectID, Double)? {
        guard let keys = timeline.track(for: id, .lookAt)?.keyframes,
              let index = keys.lastIndex(where: { $0.time <= time + 1e-9 }), index > 0, time - keys[index].time < turn,
              let previous = keys[index - 1].value.stringValue, previous != keys[index].value.stringValue else { return nil }
        return (ObjectID(raw: previous), (time - keys[index].time) / turn)
    }

    /// A skeleton's head turns (up to 70°, the neck's reach). False when it has no head to turn.
    static func turnHead(_ id: ObjectID, toward aim: Vec3, in state: inout Animator.Posed, rigs: [AssetID: RigAsset]) -> Bool {
        guard let rig = CharacterRig.of(id, in: state.scene, rigs: rigs), let head = rig.joint("head") else { return false }
        var pose = rig.localPose(in: state.scene, pose: state.poses[id])
        let frame = rig.frame(in: state.scene)
        IKSolver.lookAt(&pose, skeleton: rig.skeleton, joint: head, target: frame.inverseApply(to: aim))
        switch rig.body {
        case .bones:
            state.poses[id] = pose
        case let .joints(ids):
            let model = rig.skeleton.modelSpace(pose)
            guard var object = state.scene.objects[ids[head]] else { return false }
            let world = (frame.rotation * model[head].rotation).normalized
            let parent = object.parent.map { state.scene.worldTransform(of: $0).rotation } ?? .identity
            object.transform.rotation = (parent.inverse * world).normalized
            state.scene.objects[ids[head]] = object
            state.animated.insert(ids[head])
        case .blob:
            return false
        }
        state.animated.insert(id)
        return true
    }

    /// A thing with no head faces the target whole (a camera points its lens at it).
    static func turnWhole(_ id: ObjectID, toward aim: Vec3, in state: inout Animator.Posed) {
        guard var object = state.scene.objects[id] else { return }
        let world = state.scene.worldTransform(of: id)
        let facing = BehaviorEvaluator.facing(aim - world.position, cameraStyle: object.kind == .camera)
        let parent = object.parent.map { state.scene.worldTransform(of: $0).rotation } ?? .identity
        object.transform.rotation = (parent.inverse * facing).normalized
        state.scene.objects[id] = object
        state.animated.insert(id)
    }
}

/// Setting who a thing looks at, as commands.
public enum LookAtOperations {
    /// `looker` looks at `target` (nil: at nothing). Keyed at `time` when it already changes over time, so a second
    /// target from a later moment turns the look; set for the whole shot otherwise.
    public static func look(_ looker: ObjectID, at target: ObjectID?, at time: Double, in scene: Scene, ids: inout IDFactory) -> EditCommand? {
        guard scene.objects[looker] != nil, target != looker else { return nil }
        let value = target.map { PropertyValue.string($0.raw) }
        let label = target.flatMap { scene.objects[$0]?.name }.map { "Look at \($0)" } ?? "Look at nothing"
        guard let track = scene.timeline.track(for: looker, .lookAt) else {
            return .batch(label, [.setProperties([PropertyChange(object: looker, key: .lookAt, value: value)])])
        }
        var keyed = track
        keyed.setKey(Keyframe(time: time, value: value ?? .string(""), easing: .step))
        return .batch(label, [.setTracks([TrackEdit(keyed)])])
    }

    /// From `time` on it looks at `target`, before that at whom it looked already: the look becomes keyed.
    public static func switchLook(_ looker: ObjectID, to target: ObjectID?, at time: Double, in scene: Scene,
                                  ids: inout IDFactory) -> EditCommand? {
        guard let object = scene.objects[looker], target != looker else { return nil }
        if scene.timeline.track(for: looker, .lookAt) != nil { return look(looker, at: target, at: time, in: scene, ids: &ids) }
        let before = object[.lookAt] ?? .string("")
        var track = Track(id: ids.next(), target: looker, property: .lookAt)
        if time > 1e-6 { track.setKey(Keyframe(time: 0, value: before, easing: .step)) }
        track.setKey(Keyframe(time: time, value: target.map { .string($0.raw) } ?? .string(""), easing: .step))
        let label = target.flatMap { scene.objects[$0]?.name }.map { "Look at \($0)" } ?? "Look at nothing"
        return .batch(label, [.setTracks([TrackEdit(track)])])
    }
}
