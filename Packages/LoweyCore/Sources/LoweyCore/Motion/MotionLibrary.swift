import Foundation

/// A pose, a clip or a loop kept in the Library, to drop on anything with joints (CONTEXT §10.10: motion is library
/// material). It remembers the joints it moved by name, so on a rig of another kind it plays where the names match
/// and says which it skipped.
public struct MotionItem: Codable, Hashable, Sendable, Identifiable {
    public enum Kind: String, Codable, Sendable, CaseIterable {
        case pose, clip, loop

        public var title: String {
            switch self {
            case .pose: "Pose"
            case .clip: "Clip"
            case .loop: "Loop"
            }
        }
    }

    public var id: String
    public var name: String
    public var kind: Kind
    /// The standard its joint names follow (humanoid motion plays on any humanoid).
    public var standard: SkeletonStandard
    /// Each moved joint's keys (a pose: one key at 0), times from 0.
    public var joints: [String: [Keyframe]]
    /// The thing's own move and turn, relative to where it started (a walk that travels).
    public var travel: [PropertyKey: [Keyframe]]
    public var duration: Double
    public var favorite: Bool
    public var added: Date
    public var lastUsed: Date?

    public init(id: String, name: String, kind: Kind, standard: SkeletonStandard = .custom, joints: [String: [Keyframe]],
                travel: [PropertyKey: [Keyframe]] = [:], duration: Double = 0, favorite: Bool = false, added: Date = Date()) {
        self.id = id
        self.name = name
        self.kind = kind
        self.standard = standard
        self.joints = joints
        self.travel = travel
        self.duration = duration
        self.favorite = favorite
        self.added = added
    }

    private enum CodingKeys: String, CodingKey { case id, name, kind, standard, joints, travel, duration, favorite, added, lastUsed }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        kind = try c.decodeIfPresent(Kind.self, forKey: .kind) ?? .clip
        standard = try c.decodeIfPresent(SkeletonStandard.self, forKey: .standard) ?? .custom
        joints = try c.decodeIfPresent([String: [Keyframe]].self, forKey: .joints) ?? [:]
        let rawTravel = try c.decodeIfPresent([String: [Keyframe]].self, forKey: .travel) ?? [:]
        travel = Dictionary(uniqueKeysWithValues: rawTravel.map { (PropertyKey($0.key), $0.value) })
        duration = try c.decodeIfPresent(Double.self, forKey: .duration) ?? 0
        favorite = try c.decodeIfPresent(Bool.self, forKey: .favorite) ?? false
        added = try c.decodeIfPresent(Date.self, forKey: .added) ?? Date(timeIntervalSince1970: 0)
        lastUsed = try c.decodeIfPresent(Date.self, forKey: .lastUsed)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(kind, forKey: .kind)
        try c.encode(standard, forKey: .standard)
        try c.encode(joints, forKey: .joints)
        try c.encode(Dictionary(uniqueKeysWithValues: travel.map { ($0.key.rawValue, $0.value) }), forKey: .travel)
        try c.encode(duration, forKey: .duration)
        try c.encode(favorite, forKey: .favorite)
        try c.encode(added, forKey: .added)
        try c.encodeIfPresent(lastUsed, forKey: .lastUsed)
    }
}

/// Saving motion from a thing and dropping it on another.
public enum MotionLibrary {
    /// The properties of a thing a clip carries as travel (relative to where it starts).
    static let travelKeys: [PropertyKey] = [.position, .rotation]

    /// A thing's pose as library material: every joint's turn as it stands in `scene`.
    public static func pose(of character: ObjectID, in scene: Scene, skeletonPose: [Transform]? = nil, rigs: [AssetID: RigAsset] = [:],
                            id: String, name: String) -> MotionItem? {
        guard let rig = CharacterRig.of(character, in: scene, rigs: rigs), rig.body != .blob else { return nil }
        let local = rig.localPose(in: scene, pose: skeletonPose)
        var joints: [String: [Keyframe]] = [:]
        for (index, joint) in rig.skeleton.joints.enumerated() where index < local.count && !RigMarks.isBetween(joint.name) {
            joints[standardName(joint.name, rig: rig)] = [Keyframe(time: 0, value: .quat(local[index].rotation))]
        }
        return MotionItem(id: id, name: name, kind: .pose, standard: rig.standard, joints: joints)
    }

    /// A thing's keyed motion between `start` and `end` (its whole animation when nil): its joints' keys and its own
    /// move and turn, from 0. A loop knows it loops.
    public static func clip(of character: ObjectID, in scene: Scene, timeline: Timeline, from start: Double? = nil, to end: Double? = nil,
                            loops: Bool, rigs: [AssetID: RigAsset] = [:], id: String, name: String) -> MotionItem? {
        let rig = CharacterRig.of(character, in: scene, rigs: rigs)
        let tracks = timeline.tracks.filter { $0.target == character && ($0.property.boneJoint != nil || travelKeys.contains($0.property)) }
        let times = tracks.flatMap { $0.keyframes.map(\.time) }
        guard let first = start ?? times.min(), let last = end ?? times.max(), last > first else { return nil }
        var joints: [String: [Keyframe]] = [:]
        var travel: [PropertyKey: [Keyframe]] = [:]
        for track in tracks {
            let keys = slice(track, from: first, to: last)
            guard keys.count >= 2 else { continue }
            if let joint = track.property.boneJoint {
                joints[rig.map { standardName(joint, rig: $0) } ?? joint] = keys
            } else {
                travel[track.property] = relative(keys)
            }
        }
        guard !joints.isEmpty || !travel.isEmpty else { return nil }
        return MotionItem(id: id, name: name, kind: loops ? .loop : .clip, standard: rig?.standard ?? .custom, joints: joints, travel: travel,
                          duration: last - first)
    }

    /// The track's keys between two moments, moved to start at 0 (a key added at each edge when none sits there).
    static func slice(_ track: Track, from start: Double, to end: Double) -> [Keyframe] {
        var keys = track.keyframes.filter { $0.time > start + 1e-6 && $0.time < end - 1e-6 }
        for edge in [start, end] {
            let easing = track.keyframes.last { $0.time <= edge + 1e-6 }?.easing ?? .easeInOut
            if let value = track.value(at: edge) { keys.append(Keyframe(time: edge, value: value, easing: easing)) }
        }
        return keys.sorted { $0.time < $1.time }.map { Keyframe(time: $0.time - start, value: $0.value, easing: $0.easing) }
    }

    /// Move and turn keys as changes from the first.
    static func relative(_ keys: [Keyframe]) -> [Keyframe] {
        guard let base = keys.first?.value else { return keys }
        return keys.map { key in
            let value: PropertyValue = switch (key.value, base) {
            case let (.vec3(now), .vec3(start)): .vec3(now - start)
            case let (.quat(now), .quat(start)): .quat((now * start.inverse).normalized)
            default: key.value
            }
            return Keyframe(time: key.time, value: value, easing: key.easing)
        }
    }

    /// A humanoid's joint as the standard names it (so it plays on other humanoids).
    static func standardName(_ joint: String, rig: CharacterRig) -> String {
        rig.boneMap.first { $0.value == joint }?.key ?? joint
    }

    /// What dropping `item` on `character` at `time` does: the tracks to set (its keys at their places, a loop
    /// cycling forever) and the joints it moved that this thing doesn't have.
    public static func applying(_ item: MotionItem, to character: ObjectID, at time: Double, in scene: Scene, timeline: Timeline,
                                rigs: [AssetID: RigAsset] = [:], newID: () -> TrackID) -> (tracks: [TrackEdit], skipped: [String]) {
        guard let rig = CharacterRig.of(character, in: scene, rigs: rigs) else { return ([], item.joints.keys.sorted()) }
        var edits: [TrackEdit] = []
        var skipped: [String] = []
        let cycle = item.kind == .loop && item.duration > 0 ? TrackCycle(start: time, end: time + item.duration) : nil
        for (joint, keys) in item.joints.sorted(by: { $0.key < $1.key }) {
            guard let index = rig.joint(joint), let change = rig.changes(turning: [index: .identity]).first else {
                skipped.append(joint)
                continue
            }
            edits.append(edit(change.object, change.key, keys: keys, at: time, cycle: cycle, timeline: timeline, newID: newID))
        }
        if let object = scene.objects[character] {
            for (key, keys) in item.travel.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
                let placed = keys.map { Keyframe(time: $0.time, value: absolute($0.value, from: object, key: key), easing: $0.easing) }
                edits.append(edit(character, key, keys: placed, at: time, cycle: cycle, timeline: timeline, newID: newID))
            }
        }
        return (edits, skipped)
    }

    /// What dropping a pose on `character` changes (its joints turned as the pose has them), and the joints it skipped.
    public static func poseChanges(_ item: MotionItem, to character: ObjectID, in scene: Scene,
                                   rigs: [AssetID: RigAsset] = [:]) -> (changes: [PropertyChange], skipped: [String]) {
        guard let rig = CharacterRig.of(character, in: scene, rigs: rigs) else { return ([], item.joints.keys.sorted()) }
        var turns: [Int: Quat] = [:]
        var skipped: [String] = []
        for (joint, keys) in item.joints.sorted(by: { $0.key < $1.key }) {
            guard let index = rig.joint(joint), let turn = keys.first?.value.quatValue else {
                skipped.append(joint)
                continue
            }
            turns[index] = turn
        }
        return (rig.changes(turning: turns), skipped)
    }

    /// A travel key placed from where the thing stands now.
    static func absolute(_ value: PropertyValue, from object: SceneObject, key: PropertyKey) -> PropertyValue {
        switch (value, key) {
        case let (.vec3(offset), .position): .vec3(object.transform.position + offset)
        case let (.quat(turn), .rotation): .quat((turn * object.transform.rotation).normalized)
        default: value
        }
    }

    /// The thing's track for a property with these keys laid in from `time` (keys already there in that stretch go).
    static func edit(_ object: ObjectID, _ key: PropertyKey, keys: [Keyframe], at time: Double, cycle: TrackCycle?, timeline: Timeline,
                     newID: () -> TrackID) -> TrackEdit {
        let end = time + (keys.last?.time ?? 0)
        let existing = timeline.tracks.first { $0.target == object && $0.property == key }
        var kept = (existing?.keyframes ?? []).filter { $0.time < time - 1e-6 || $0.time > end + 1e-6 }
        kept += keys.map { Keyframe(time: $0.time + time, value: $0.value, easing: $0.easing) }
        let track = Track(id: existing?.id ?? newID(), target: object, property: key, keyframes: kept, cycle: cycle ?? existing?.cycle)
        return TrackEdit(id: track.id, track: track)
    }
}
