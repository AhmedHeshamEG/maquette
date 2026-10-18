import Foundation

/// What a 3D file keeps of motion that keys don't hold (A1): behaviours, holds and looks are played frame by frame
/// and written as keys, so a glTF, a Blender package or an FBX moves the way the stage does. The things they move
/// then follow those keys only (behaviours, holds and looks leave the exported copy).
public enum MotionBake {
    /// The document with its behaviours, holds and looks baked into keys (unchanged when it has none).
    public static func baked(_ document: Document, rigs: [AssetID: RigAsset] = [:]) -> Document {
        let timeline = document.scene.timeline
        let plan = drives(document, rigs: rigs)
        guard !plan.isEmpty else { return document }
        let step = 1 / Double(max(timeline.fps, 1))
        let count = max(Int((timeline.duration / step).rounded()), 1)
        var samples: [ObjectID: [PropertyKey: [Keyframe]]] = [:]
        for frame in 0 ... count {
            let time = min(Double(frame) * step, timeline.duration)
            let shown = Animator.evaluate(document, at: time, rigs: rigs)
            for (id, keys) in plan {
                for key in keys {
                    guard let value = value(of: key, for: id, in: shown, rigs: rigs) else { continue }
                    samples[id, default: [:]][key, default: []].append(Keyframe(time: time, value: value, easing: .linear))
                }
            }
        }
        var result = document
        var ids = IDFactory.sequential("motion-bake")
        for id in samples.keys.sorted() {
            for (key, keys) in (samples[id] ?? [:]).sorted(by: { $0.key < $1.key }) {
                let track = Simulation.bake(id, key, PerformBaker.simplify(keys, tolerance: key == .position ? 0.0005 : 0.001),
                                            timeline: result.scene.timeline, ids: &ids)
                result.scene.timeline.tracks.removeAll { $0.id == track.id }
                result.scene.timeline.tracks.append(track)
            }
        }
        let moved = Set(plan.keys)
        result.scene.timeline.behaviors.removeAll { moved.contains($0.target) }
        result.scene.timeline.holds = []
        result.scene.timeline.tracks.removeAll { $0.property == .lookAt }
        for id in moved {
            result.scene.objects[id]?.properties[.lookAt] = nil
        }
        return result
    }

    /// What each thing needs keyed: its place and turn (a behaviour, a hold, a whole-body look) or its head joint (a
    /// character's look).
    static func drives(_ document: Document, rigs: [AssetID: RigAsset]) -> [ObjectID: [PropertyKey]] {
        let scene = document.scene
        var plan: [ObjectID: Set<PropertyKey>] = [:]
        for behavior in scene.timeline.behaviors where behavior.enabled && scene.objects[behavior.target] != nil {
            plan[behavior.target, default: []].formUnion(behavior.kind.drives)
        }
        for hold in scene.timeline.holds where scene.objects[hold.target] != nil {
            plan[hold.target, default: []].formUnion([.position, .rotation])
        }
        let lookers = scene.objects.values.filter { $0[.lookAt] != nil }.map(\.id)
            + scene.timeline.tracks.filter { $0.property == .lookAt }.map(\.target)
        for id in Set(lookers) where scene.objects[id] != nil {
            if let rig = CharacterRig.of(id, in: scene, rigs: rigs), rig.body == .bones, let head = rig.joint("head") {
                plan[id, default: []].insert(.boneTurn(rig.skeleton.joints[head].name))
            } else {
                plan[id, default: []].insert(.rotation)
            }
        }
        return plan.mapValues { $0.sorted() }
    }

    /// A property as the shown scene has it; a head joint's turn from its pose.
    static func value(of key: PropertyKey, for id: ObjectID, in shown: AnimatedScene, rigs: [AssetID: RigAsset]) -> PropertyValue? {
        if let joint = key.boneJoint {
            guard let rig = CharacterRig.of(id, in: shown.scene, rigs: rigs), let index = rig.skeleton.index(of: joint),
                  let pose = shown.poses[id], index < pose.count else { return nil }
            return .quat(pose[index].rotation)
        }
        return shown.scene.objects[id].flatMap { $0.properties[key] ?? PropertyDefaults.value(for: key) }
    }
}
