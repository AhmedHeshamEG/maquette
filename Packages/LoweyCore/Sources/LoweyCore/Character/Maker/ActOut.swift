import Foundation

/// Act it out (K1 step 5): a person filmed (the camera, or a video) moves, and a character copies the body's motion.
/// The body's joints come from Apple's on-device body pose (Vision, in the app); here each frame becomes the character's
/// joint turns: every bone of the humanoid points where the person's matching bone points, the hips take the person's
/// facing and lean, and the whole character travels as the person's hips do, scaled to its own size. Nothing is
/// generated: the motion is the person's, frame by frame.
public enum ActOut {
    /// The body joints the pose reader gives (Vision's 3D body pose names, in the person's own space: y up, x to the
    /// person's left, z forward).
    public enum BodyJoint: String, CaseIterable, Sendable {
        case root, spine, centerShoulder, centerHead, topHead
        case leftShoulder, leftElbow, leftWrist, leftHip, leftKnee, leftAnkle
        case rightShoulder, rightElbow, rightWrist, rightHip, rightKnee, rightAnkle

        /// The same joint on the other side (for acting as in a mirror).
        public var mirror: BodyJoint {
            let name = rawValue
            if name.hasPrefix("left") { return BodyJoint(rawValue: "right" + name.dropFirst(4)) ?? self }
            if name.hasPrefix("right") { return BodyJoint(rawValue: "left" + name.dropFirst(5)) ?? self }
            return self
        }
    }

    public struct Frame: Sendable {
        public var time: Double
        public var joints: [BodyJoint: Vec3]

        public init(time: Double, joints: [BodyJoint: Vec3]) {
            self.time = time
            self.joints = joints
        }

        /// As seen in a mirror: left and right swap and x flips (raise your right hand, the character raises the hand on
        /// that side of the screen).
        public var mirrored: Frame {
            var flipped: [BodyJoint: Vec3] = [:]
            for (joint, point) in joints {
                flipped[joint.mirror] = Vec3(-point.x, point.y, point.z)
            }
            return Frame(time: time, joints: flipped)
        }
    }

    /// Each aimed bone of the humanoid: the character's joint, and the body joints its bone runs between.
    static let aims: [(joint: String, from: BodyJoint, to: BodyJoint)] = [
        ("spine", .spine, .centerShoulder), ("chest", .spine, .centerShoulder), ("neck", .centerShoulder, .centerHead),
        ("head", .centerHead, .topHead),
        ("leftUpperArm", .leftShoulder, .leftElbow), ("leftLowerArm", .leftElbow, .leftWrist),
        ("rightUpperArm", .rightShoulder, .rightElbow), ("rightLowerArm", .rightElbow, .rightWrist),
        ("leftUpperLeg", .leftHip, .leftKnee), ("leftLowerLeg", .leftKnee, .leftAnkle),
        ("rightUpperLeg", .rightHip, .rightKnee), ("rightLowerLeg", .rightKnee, .rightAnkle)
    ]

    /// The joint each aimed joint's bone runs to, on the character.
    static let childJoint: [String: String] = [
        "spine": "chest", "chest": "neck", "neck": "head", "leftUpperArm": "leftLowerArm", "leftLowerArm": "leftHand",
        "rightUpperArm": "rightLowerArm", "rightLowerArm": "rightHand", "leftUpperLeg": "leftLowerLeg", "leftLowerLeg": "leftFoot",
        "rightUpperLeg": "rightLowerLeg", "rightLowerLeg": "rightFoot"
    ]

    /// The local turn of each joint of a humanoid rig for one frame (joints the frame says nothing about keep their rest).
    public static func pose(_ frame: Frame, rig: ObjectRig) -> [String: Quat] {
        let skeleton = rig.skeleton
        let rest = rig.restPositions
        var global: [Int: Quat] = [:]
        var result: [String: Quat] = [:]
        for (index, joint) in skeleton.joints.enumerated() {
            let parentTurn = joint.parent.flatMap { global[$0] } ?? .identity
            var turn = parentTurn
            if joint.name == "hips", let facing = hipsTurn(frame, rig: rig) {
                turn = facing
            } else if let aim = aims.first(where: { $0.joint == joint.name }), let child = childJoint[joint.name].flatMap(skeleton.index(of:)),
                      let from = frame.joints[aim.from], let to = frame.joints[aim.to], (to - from).length > 1e-6 {
                let restDirection = rest[child] - rest[index]
                if restDirection.length > 1e-6 {
                    // Point the bone, starting from where its parent already turned it (the least twist).
                    let carried = parentTurn.act(restDirection)
                    turn = (Quat.rotation(from: carried, to: to - from) * parentTurn).normalized
                }
            }
            global[index] = turn
            let local = (parentTurn.inverse * turn).normalized
            if !local.isApproximately(.identity, tolerance: 1e-9) || joint.name == "hips" { result[joint.name] = local }
        }
        return result
    }

    /// The hips' turn: up along the spine, across from the right hip to the left.
    static func hipsTurn(_ frame: Frame, rig: ObjectRig) -> Quat? {
        guard let left = frame.joints[.leftHip], let right = frame.joints[.rightHip],
              let up = frame.joints[.spine] ?? frame.joints[.centerShoulder] else { return nil }
        let root = frame.joints[.root] ?? left.lerp(to: right, 0.5)
        let skeleton = rig.skeleton
        let rest = rig.restPositions
        guard let l = skeleton.index(of: "leftUpperLeg"), let r = skeleton.index(of: "rightUpperLeg"), let hips = skeleton.index(of: "hips"),
              let spine = skeleton.index(of: "spine") else { return nil }
        let restAcross = rest[l] - rest[r], restUp = rest[spine] - rest[hips]
        let across = left - right, rising = up - root
        guard restAcross.length > 1e-6, restUp.length > 1e-6, across.length > 1e-6, rising.length > 1e-6 else { return nil }
        let first = Quat.rotation(from: restUp, to: rising)
        // Then about the spine, so the hips face the way the person's hips face.
        let turnedAcross = first.act(restAcross)
        let axis = rising.normalized
        let a = (turnedAcross - axis * turnedAcross.dot(axis)), b = (across - axis * across.dot(axis))
        guard a.length > 1e-6, b.length > 1e-6 else { return first }
        return (Quat.rotation(from: a, to: b) * first).normalized
    }

    /// The keys that make `character` act out `frames` from `start` on the timeline: a turn key per joint and frame, and
    /// position keys that carry the character as the person's hips travel (scaled from the person's leg length to its
    /// own). One undo step.
    public static func keys(_ frames: [Frame], rig: ObjectRig, character: SceneObject, from start: Double, mirrored: Bool, timeline: Timeline,
                            ids: inout IDFactory) -> EditCommand? {
        let frames = (mirrored ? frames.map(\.mirrored) : frames).filter { $0.joints[.leftHip] != nil && $0.joints[.rightHip] != nil }
        guard let first = frames.first, rig.standard == .humanoid else { return nil }
        var tracks: [String: [Keyframe]] = [:]
        var positions: [Keyframe] = []
        let scale = travelScale(frames, rig: rig)
        let origin = first.joints[.root] ?? first.joints[.leftHip].map { $0.lerp(to: first.joints[.rightHip] ?? $0, 0.5) } ?? .zero
        let base = character.transform.position
        for frame in frames {
            let time = start + frame.time - first.time
            for (joint, turn) in pose(frame, rig: rig) {
                tracks[joint, default: []].append(Keyframe(time: time, value: .quat(turn), easing: .linear))
            }
            if let root = frame.joints[.root] {
                let moved = (root - origin) * scale
                positions.append(Keyframe(time: time, value: .vec3(base + character.transform.rotation.act(Vec3(moved.x, max(moved.y, -0.5), moved.z))),
                                          easing: .linear))
            }
        }
        let range = TimeRange(start: start, end: start + (frames.last?.time ?? first.time) - first.time)
        func replaced(_ key: PropertyKey, with keys: [Keyframe]) -> TrackEdit {
            // What was keyed outside the acted stretch stays.
            var track = timeline.track(for: character.id, key) ?? Track(id: ids.next(), target: character.id, property: key)
            track.removeKeys(in: range)
            track.setKeys(track.keyframes + keys)
            return TrackEdit(track)
        }
        var edits: [TrackEdit] = tracks.keys.sorted().map { replaced(.boneTurn($0), with: tracks[$0] ?? []) }
        if positions.count > 1 { edits.append(replaced(.position, with: positions)) }
        return edits.isEmpty ? nil : .batch("Act it out", [.setTracks(edits)])
    }

    /// The character's leg length over the person's.
    static func travelScale(_ frames: [Frame], rig: ObjectRig) -> Double {
        let rest = rig.restPositions
        let skeleton = rig.skeleton
        guard let hip = skeleton.index(of: "leftUpperLeg"), let foot = skeleton.index(of: "leftFoot") else { return 1 }
        let own = rest[hip].distance(to: rest[foot])
        let theirs = frames.compactMap { frame -> Double? in
            guard let hip = frame.joints[.leftHip], let knee = frame.joints[.leftKnee], let ankle = frame.joints[.leftAnkle] else { return nil }
            return hip.distance(to: knee) + knee.distance(to: ankle)
        }.sorted()
        guard !theirs.isEmpty, theirs[theirs.count / 2] > 1e-3 else { return 1 }
        return own / theirs[theirs.count / 2]
    }
}
