import Foundation

/// Pick-up and hand-off (A1): from `start` on, `target` rides `holder` (a thing, or a joint of its skeleton: a hand)
/// the way it sat when it was picked up. A hold with no holder puts it down: it stays where the last holder left it.
/// Holds live on the timeline, one list for the scene; each thing's holds take turns by their moments.
public struct Hold: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    /// The thing held.
    public var target: ObjectID
    /// From this moment on (seconds).
    public var start: Double
    /// Who holds it from then (nil: put down).
    public var holder: ObjectID?
    /// A joint of the holder's skeleton (an imported or drawn rig's hand); nil holds by the thing itself.
    public var joint: String?
    /// The thing in the holder's (or the joint's) space, as it sat when picked up.
    public var grip: Transform

    public init(id: String, target: ObjectID, start: Double, holder: ObjectID?, joint: String? = nil, grip: Transform = .identity) {
        self.id = id
        self.target = target
        self.start = start
        self.holder = holder
        self.joint = joint
        self.grip = grip
    }
}

/// How holds place things while a scene plays (the Animator's step after parts ride their bones).
public enum HoldPlayback {
    /// Where the holder holds from: the thing itself, or one joint of its skeleton as posed now.
    static func frame(of holder: ObjectID, joint: String?, in scene: Scene, poses: [ObjectID: [Transform]], rigs: [AssetID: RigAsset]) -> Transform? {
        guard scene.objects[holder] != nil else { return nil }
        guard let joint else { return scene.worldTransform(of: holder) }
        guard let rig = CharacterRig.of(holder, in: scene, rigs: rigs), let index = rig.skeleton.index(of: joint) else {
            return scene.worldTransform(of: holder)
        }
        let model = rig.skeleton.modelSpace(rig.localPose(in: scene, pose: poses[holder]))
        return rig.frame(in: scene) * model[index]
    }

    /// Each thing's hold at `time` (the latest that has started), for things held at least once by then.
    static func current(_ holds: [Hold], at time: Double) -> [ObjectID: (hold: Hold, earlier: [Hold])] {
        var result: [ObjectID: (Hold, [Hold])] = [:]
        for (target, list) in Dictionary(grouping: holds, by: \.target) {
            let started = list.filter { $0.start <= time + 1e-9 }.sorted { $0.start < $1.start }
            guard let last = started.last else { continue }
            result[target] = (last, Array(started.dropLast()))
        }
        return result
    }

    /// Puts every held thing in its holder's hand (holders first, so a tray carries the cups on it), and every thing
    /// put down where its last holder left it.
    static func apply(to state: inout Animator.Posed, document: Document, time: Double, rigs: [AssetID: RigAsset], depth: Int = 0) {
        let holds = document.scene.timeline.holds
        guard !holds.isEmpty else { return }
        let now = current(holds, at: time)
        var past: [Double: Animator.Posed] = [:]
        for target in ordered(now) {
            guard let (hold, earlier) = now[target], state.scene.objects[target] != nil else { continue }
            let world: Transform?
            if let holder = hold.holder {
                world = frame(of: holder, joint: hold.joint, in: state.scene, poses: state.poses, rigs: rigs).map { $0 * hold.grip }
            } else if depth < 3, let last = earlier.last(where: { $0.holder != nil }), let holder = last.holder {
                // Put down: where the last holder had it at the moment it let go.
                let then = past[hold.start] ?? pastState(document, at: hold.start, rigs: rigs, depth: depth)
                past[hold.start] = then
                world = frame(of: holder, joint: last.joint, in: then.scene, poses: then.poses, rigs: rigs).map { $0 * last.grip }
            } else {
                world = nil
            }
            guard let world, var object = state.scene.objects[target] else { continue }
            let parent = object.parent.map { state.scene.worldTransform(of: $0) } ?? .identity
            object.transform = Transform.relative(world: world, toParent: parent)
            state.scene.objects[target] = object
            state.animated.insert(target)
        }
    }

    /// The scene posed at another moment, its parts on their bones and its own holds applied (for a put-down place).
    static func pastState(_ document: Document, at time: Double, rigs: [AssetID: RigAsset], depth: Int) -> Animator.Posed {
        var state = Animator.posed(document, at: time, rigs: rigs, overrides: [:])
        LiveRig.carryParts(in: &state, rigs: rigs)
        apply(to: &state, document: document, time: time, rigs: rigs, depth: depth + 1)
        return state
    }

    /// Held things after the things holding them (a cycle, which picking up refuses, is left in any order).
    static func ordered(_ now: [ObjectID: (hold: Hold, earlier: [Hold])]) -> [ObjectID] {
        var done: [ObjectID] = []
        var left = Set(now.keys)
        while !left.isEmpty {
            let ready = left.filter { target in
                guard let holder = now[target]?.hold.holder else { return true }
                return !left.contains(holder)
            }.sorted()
            let next = ready.isEmpty ? left.sorted() : ready
            done += next
            left.subtract(next)
        }
        return done
    }
}

/// Picking up, handing off and putting down, as commands (one undo step each).
public enum HoldOperations {
    /// The holds of one thing, in time order.
    public static func holds(of target: ObjectID, in timeline: Timeline) -> [Hold] {
        timeline.holds.filter { $0.target == target }.sorted { $0.start < $1.start }
    }

    /// Who holds `target` at `time` (nil when nobody does).
    public static func holder(of target: ObjectID, at time: Double, in timeline: Timeline) -> Hold? {
        guard let hold = holds(of: target, in: timeline).last(where: { $0.start <= time + 1e-9 }), hold.holder != nil else { return nil }
        return hold
    }

    /// `holder` (a joint of it, for a skeleton's hand) takes `target` at `time`, as it sits in the shown scene: a
    /// pick-up, or a hand-off when someone else holds it then. Refused when it would hold itself.
    public static func pickUp(_ target: ObjectID, by holder: ObjectID, joint: String? = nil, at time: Double, shown: AnimatedScene,
                              rigs: [AssetID: RigAsset] = [:], timeline: Timeline, ids: inout IDFactory) -> EditCommand? {
        let scene = shown.scene
        guard target != holder, scene.objects[target] != nil, scene.objects[holder] != nil,
              !scene.subtree(of: target).contains(holder), !Self.holds(holder, through: target, at: time, in: timeline),
              let frame = HoldPlayback.frame(of: holder, joint: joint, in: scene, poses: shown.poses, rigs: rigs) else { return nil }
        let grip = Transform.relative(world: scene.worldTransform(of: target), toParent: frame)
        let handOff = Self.holder(of: target, at: time, in: timeline) != nil
        let hold = Hold(id: (ids.next() as TrackID).raw, target: target, start: time, holder: holder, joint: joint, grip: grip)
        return .batch(handOff ? "Hand off" : "Pick up", [.setHolds(placing(hold, in: timeline.holds))])
    }

    /// `target` is let go at `time`: it stays where it is then.
    public static func putDown(_ target: ObjectID, at time: Double, timeline: Timeline, ids: inout IDFactory) -> EditCommand? {
        guard holder(of: target, at: time, in: timeline) != nil else { return nil }
        let hold = Hold(id: (ids.next() as TrackID).raw, target: target, start: time, holder: nil)
        return .batch("Put down", [.setHolds(placing(hold, in: timeline.holds))])
    }

    /// Takes one hold away (its thing goes back to the hold before it, or to its own keys).
    public static func removing(_ id: String, from timeline: Timeline) -> EditCommand? {
        guard timeline.holds.contains(where: { $0.id == id }) else { return nil }
        return .batch("Remove the hold", [.setHolds(timeline.holds.filter { $0.id != id })])
    }

    /// Every hold of `target` gone (it moves by its own keys again).
    public static func letGo(_ target: ObjectID, in timeline: Timeline) -> EditCommand? {
        guard timeline.holds.contains(where: { $0.target == target }) else { return nil }
        return .batch("Never held", [.setHolds(timeline.holds.filter { $0.target != target })])
    }

    /// The list with `hold` in it (one at the same moment for the same thing is replaced).
    static func placing(_ hold: Hold, in holds: [Hold]) -> [Hold] {
        var result = holds.filter { !($0.target == hold.target && abs($0.start - hold.start) < 0.0005) }
        result.append(hold)
        return result.sorted { ($0.start, $0.id) < ($1.start, $1.id) }
    }

    /// Whether `holder` is (through any chain of holds at `time`) held by `target`: picking up would close a loop.
    static func holds(_ holder: ObjectID, through target: ObjectID, at time: Double, in timeline: Timeline) -> Bool {
        var current: ObjectID? = holder
        var seen = Set<ObjectID>()
        while let thing = current, seen.insert(thing).inserted {
            if thing == target { return true }
            current = self.holder(of: thing, at: time, in: timeline)?.holder
        }
        return false
    }

    /// The joint of a skeleton nearest a world point (a hand when one is about as near): what a tap on a rigged
    /// character's surface picks to hold by.
    public static func nearestJoint(to point: Vec3, of holder: ObjectID, in shown: AnimatedScene, rigs: [AssetID: RigAsset] = [:]) -> String? {
        guard let rig = CharacterRig.of(holder, in: shown.scene, rigs: rigs), rig.body == .bones, !rig.skeleton.isEmpty else { return nil }
        let frame = rig.frame(in: shown.scene)
        let model = rig.skeleton.modelSpace(rig.localPose(in: shown.scene, pose: shown.poses[holder]))
        let distances = model.map { frame.apply(to: $0.position).distance(to: point) }
        guard let nearest = distances.indices.min(by: { distances[$0] < distances[$1] }) else { return nil }
        let names = rig.skeleton.names
        let hand = names.indices.filter { names[$0].lowercased().contains("hand") || names[$0].lowercased().contains("wrist") }
            .min { distances[$0] < distances[$1] }
        if let hand, distances[hand] < distances[nearest] + 0.12 { return names[hand] }
        return names[nearest]
    }
}
