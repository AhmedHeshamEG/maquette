import Foundation

/// Ragdolls from any rig: a capsule along each bone, joined to its parent's by a shoulder-like joint (a cone and a
/// twist), the parts of one ragdoll never colliding with each other. What comes back is each joint's turn, written as
/// the rig's own `bone.<joint>` values, so a ragdoll's run becomes ordinary keys.
extension PhysicsSimulator {
    func addRagdoll(_ id: ObjectID, skeleton: Skeleton, pose: [Transform], world: Transform, physics: ObjectPhysics) -> Bool {
        let model = skeleton.modelSpace(pose)
        guard model.count == skeleton.joints.count else { return false }
        let jointWorld = model.map { world * $0 }
        let scale = (abs(world.scale.x) + abs(world.scale.y) + abs(world.scale.z)) / 3
        var segments: [(joint: Int, head: Vec3, tail: Vec3)] = []
        for index in skeleton.joints.indices {
            let children = skeleton.children(of: index)
            if let child = children.first {
                segments.append((index, jointWorld[index].position, jointWorld[child].position))
            } else if let parent = skeleton.joints[index].parent {
                // A leaf bone carries on in its parent's direction for half its parent's length.
                let direction = jointWorld[index].position - jointWorld[parent].position
                segments.append((index, jointWorld[index].position, jointWorld[index].position + direction * 0.5))
            }
        }
        let lengths = segments.map { $0.head.distance(to: $0.tail) }
        let totalLength = lengths.reduce(0, +)
        guard totalLength > 1e-4 else { return false }
        let volume = input.meshes[id].map { SoftMesh.volume(MeshData(positions: $0.positions.map { $0 * SIMD3<Float>(world.scale.map(abs).floats) },
                                                                     indices: $0.indices)) } ?? 0
        let totalMass = physics.mass ?? max(volume * physics.material.density, totalLength * 8 * scale)
        let group = UInt32(ragdolls.count + 1)
        var parts: [RagdollPart] = []
        for (segment, length) in zip(segments, lengths) where length > 1e-4 {
            let radius = min(max(length * 0.2, 0.012 * scale), 0.25 * scale)
            let direction = (segment.tail - segment.head) / length
            let rotation = Quat.rotation(from: .unitY, to: direction).normalized
            let centre = (segment.head + segment.tail) * 0.5
            let mass = totalMass * length / totalLength
            let spec = PhysicsWorld.BodySpec(shape: BodyShape(kind: .hull(Self.capsulePoints(length: length, radius: radius))), position: centre,
                                             rotation: rotation, motion: .falls, density: 1000, mass: mass,
                                             friction: physics.effectiveFriction, bounce: min(physics.effectiveBounce, 0.2),
                                             linearVelocity: physics.startSpeed ?? .zero, angularVelocity: physics.startSpin ?? .zero,
                                             linearDamping: 0.05, angularDamping: 0.6, group: group)
            guard let body = self.world.add(spec) else { continue }
            let bodyWorld = Transform(position: centre, rotation: rotation)
            let joint = Transform(position: jointWorld[segment.joint].position, rotation: jointWorld[segment.joint].rotation.normalized)
            parts.append(RagdollPart(joint: segment.joint, body: body, jointFromBody: Transform.relative(world: joint, toParent: bodyWorld), mass: mass))
        }
        guard !parts.isEmpty else { return false }
        for part in parts {
            guard let parentJoint = skeleton.joints[part.joint].parent,
                  let parent = Self.part(holding: parentJoint, in: parts, skeleton: skeleton) else { continue }
            let at = jointWorld[part.joint].position
            let along = (segments.first { $0.joint == part.joint }.map { $0.tail - $0.head } ?? .unitY).normalized
            let spec = PhysicsWorld.JointSpec(kind: .swingTwist, a: parent.body, b: part.body, pointA: at, pointB: at, axis: along,
                                              normal: Self.perpendicular(to: along), limits: -0.45 ... 0.45, motorSpeed: nil,
                                              motorStrength: nil, swing: 0.9)
            _ = self.world.addJoint(spec)
        }
        ragdolls.append(RagdollState(id: id, skeleton: skeleton, parts: parts, model: model, world: world))
        return true
    }

    /// The part a joint rides: its own, else its nearest ancestor's.
    static func part(holding joint: Int, in parts: [RagdollPart], skeleton: Skeleton) -> RagdollPart? {
        var current: Int? = joint
        while let index = current {
            if let part = parts.first(where: { $0.joint == index }) { return part }
            current = skeleton.joints[index].parent
        }
        return nil
    }

    /// A capsule along Y as hull points (rings at both ends and the poles).
    static func capsulePoints(length: Double, radius: Double) -> [Vec3] {
        let half = max(length * 0.5 - radius, 0.001)
        var points: [Vec3] = [Vec3(0, half + radius, 0), Vec3(0, -half - radius, 0)]
        for ring in 0 ..< 3 {
            let lift = Double(ring) / 3 * .pi / 2
            for side in 0 ..< 8 {
                let angle = Double(side) / 8 * 2 * .pi
                let r = radius * cos(lift)
                let y = radius * sin(lift)
                points.append(Vec3(cos(angle) * r, half + y, sin(angle) * r))
                points.append(Vec3(cos(angle) * r, -half - y, sin(angle) * r))
            }
        }
        return points
    }

    /// This frame's joint turns (4 per joint, local to the parent joint) and the thing's world transform (7).
    func ragdollFrame(_ state: RagdollState) -> [Float] {
        let skeleton = state.skeleton
        var worldRotations = [Quat?](repeating: nil, count: skeleton.joints.count)
        var worldPositions = [Vec3?](repeating: nil, count: skeleton.joints.count)
        for part in state.parts {
            let (position, rotation) = world.transform(of: part.body)
            let joint = Transform(position: position, rotation: rotation) * part.jointFromBody
            worldRotations[part.joint] = joint.rotation
            worldPositions[part.joint] = joint.position
        }
        // Joints without a body keep their start turn under their parent.
        let startWorld = state.model.map { (state.world * $0).rotation }
        for index in skeleton.joints.indices where worldRotations[index] == nil {
            if let parent = skeleton.joints[index].parent, let parentRotation = worldRotations[parent] {
                worldRotations[index] = parentRotation * (startWorld[parent].inverse * startWorld[index])
            } else {
                worldRotations[index] = startWorld[index]
            }
        }
        var values: [Float] = []
        for index in skeleton.joints.indices {
            let rotation = worldRotations[index] ?? .identity
            let local: Quat = if let parent = skeleton.joints[index].parent {
                ((worldRotations[parent] ?? .identity).inverse * rotation).normalized
            } else {
                state.model[index].rotation
            }
            values += [Float(local.x), Float(local.y), Float(local.z), Float(local.w)]
        }
        // The thing itself follows its root joint.
        let root = skeleton.joints.firstIndex { $0.parent == nil } ?? 0
        let rootRotation = worldRotations[root] ?? state.world.rotation
        let thingRotation = (rootRotation * state.model[root].rotation.inverse).normalized
        let rootPosition = worldPositions[root] ?? (state.world * state.model[root]).position
        let thingPosition = rootPosition - thingRotation.act(state.model[root].position.scaled(by: state.world.scale))
        PhysicsFrames.write(thingPosition, thingRotation, into: &values)
        return values
    }
}

extension Vec3 {
    var floats: SIMD3<Float> { SIMD3<Float>(Float(x), Float(y), Float(z)) }
}
