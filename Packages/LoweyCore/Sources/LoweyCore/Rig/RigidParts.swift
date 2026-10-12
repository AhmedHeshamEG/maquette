import Foundation

/// Rigging a group: its parts stay solid and each rides one bone, so a dot between two parts hinges them (no skin).
/// The rig lives on the group; each part names its joint in `attachBone` and `LiveRig.carryParts` moves it with that
/// joint, the way a prop rides a hand.
public enum RigidParts {
    /// The joint each part rides: the one whose bone runs nearest the part's middle. A joint at the end of a chain
    /// has a bone that goes on past it the way its chain was going (a hand past the wrist); the first joint of all
    /// holds what's around it. `centres` are the parts' middles in the group's space.
    public static func joints(for centres: [ObjectID: Vec3], rig: ObjectRig) -> [ObjectID: String] {
        let rest = rig.restPositions
        let joints = rig.skeleton.joints
        guard !joints.isEmpty else { return [:] }
        let size = Bounds(points: rest + Array(centres.values))?.size.length ?? 1
        var regions: [(joint: Int, distance: (Vec3) -> Double)] = []
        for index in joints.indices {
            let children = rig.skeleton.children(of: index)
            for child in children {
                let bone = BoneSegment(joint: index, head: rest[index], tail: rest[child])
                regions.append((index, { bone.distance(to: $0) }))
            }
            if children.isEmpty {
                let head = rest[index]
                let direction = joints[index].parent.map { (head - rest[$0]).normalized } ?? .zero
                regions.append((index, { point in
                    guard direction.lengthSquared > 0.5 else { return head.distance(to: point) }
                    let along = max((point - head).dot(direction), 0)
                    return (head + direction * along).distance(to: point)
                }))
            }
        }
        var result: [ObjectID: String] = [:]
        for (part, centre) in centres {
            // Ties go to the deeper joint: a part sitting exactly on a joint rides the bone that starts there.
            let best = regions.min { lhs, rhs in
                let a = lhs.distance(centre), b = rhs.distance(centre)
                return abs(a - b) > size * 1e-6 ? a < b : depth(lhs.joint, in: rig.skeleton) > depth(rhs.joint, in: rig.skeleton)
            }
            if let best { result[part] = joints[best.joint].name }
        }
        return result
    }

    static func depth(_ index: Int, in skeleton: Skeleton) -> Int {
        var depth = 0
        var current = skeleton.joints[index].parent
        while let parent = current, depth < skeleton.joints.count {
            depth += 1
            current = skeleton.joints[parent].parent
        }
        return depth
    }

    /// The changes that bind the group's parts to its rig (each part's `attachBone`), and unbind parts that no
    /// longer ride anything.
    public static func binding(_ group: ObjectID, rig: ObjectRig?, in scene: Scene) -> [PropertyChange] {
        guard let object = scene.objects[group] else { return [] }
        var centres: [ObjectID: Vec3] = [:]
        for child in object.children {
            guard let part = scene.objects[child] else { continue }
            centres[child] = centre(of: child, in: scene, group: group) ?? part.transform.position
        }
        let chosen = rig.map { joints(for: centres, rig: $0) } ?? [:]
        return object.children.compactMap { child in
            let value = chosen[child].map(PropertyValue.string)
            return scene.objects[child]?[.attachBone] == value ? nil : PropertyChange(object: child, key: .attachBone, value: value)
        }
    }

    /// A part's middle in the group's space: the middle of its own shape when Core knows it, else where it stands.
    static func centre(of part: ObjectID, in scene: Scene, group: ObjectID) -> Vec3? {
        guard let object = scene.objects[part] else { return nil }
        var local = PaintSource.mesh(of: object)?.bounds?.center ?? .zero
        // A bevelled shape is built at its size; its transform's scale would count twice.
        if let toObject = PaintSource.toObjectSpace(of: object) {
            local = local.scaled(by: Vec3(Double(toObject.x), Double(toObject.y), Double(toObject.z)))
        }
        let world = scene.worldTransform(of: part).apply(to: local)
        return scene.worldTransform(of: group).inverseApply(to: world)
    }
}
