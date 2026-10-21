import Foundation

/// The exploded view (G1, Study: Omar's gear train in one tap): a group's parts pulled apart from its middle, each
/// along the line from the middle to it, far enough that nothing touches. Where each part goes is worked out once (from
/// the parts' boxes) and kept on the part; how far apart is `explode` on the group, 0 … 1, keyed like anything else.
public enum Explode {
    /// Whether anything in the scene is pulled apart.
    public static func anyone(in scene: Scene) -> Bool {
        scene.objects.values.contains { $0.explodeAmount > 0 }
    }

    /// The Animator's step: each part of an exploded group moved by its offset times the group's amount.
    public static func apply(to scene: inout Scene, animated: inout Set<ObjectID>) {
        for object in Array(scene.objects.values) where object.explodeAmount > 0 {
            let amount = object.explodeAmount
            for child in object.children {
                guard var part = scene.objects[child], let offset = part[.explodeOffset]?.vec3Value else { continue }
                var transform = part.transform
                transform.position += offset * amount
                part.transform = transform
                scene.objects[child] = part
                animated.insert(child)
            }
        }
    }

    /// Where each part of `group` goes when it's fully exploded, in the group's space, from the parts' boxes in the
    /// world (`bounds`). Parts in the very middle spread along the group's longest side, in their order.
    public static func offsets(for group: ObjectID, in scene: Scene, bounds: (ObjectID) -> Bounds?) -> [ObjectID: Vec3] {
        guard let object = scene.objects[group], !object.children.isEmpty else { return [:] }
        let boxes = object.children.compactMap { child in bounds(child).map { (child, $0) } }
        guard let first = boxes.first?.1 else { return [:] }
        let whole = boxes.dropFirst().reduce(first) { $0.union($1.1) }
        let centre = whole.center, extent = whole.size.maxComponent
        let longest: Vec3 = whole.size.x >= whole.size.y && whole.size.x >= whole.size.z ? .unitX : whole.size.y >= whole.size.z ? .unitY : .unitZ
        let world = scene.worldTransform(of: group)
        let inverse = Quat(x: -world.rotation.x, y: -world.rotation.y, z: -world.rotation.z, w: world.rotation.w)
        var result: [ObjectID: Vec3] = [:]
        var middleIndex = 0
        let middles = boxes.filter { ($0.1.center - centre).length < extent * 0.02 }.count
        for (child, box) in boxes {
            let away = box.center - centre
            let offset: Vec3
            if away.length < extent * 0.02 {
                // Stacked on the middle: spread out along the longest side.
                offset = longest * (Double(middleIndex) - Double(middles - 1) / 2) * (extent * 0.6)
                middleIndex += 1
            } else {
                offset = away + away.normalized * (box.size.maxComponent * 0.5 + extent * 0.1)
            }
            let local = inverse.act(offset)
            result[child] = Vec3(local.x / nonZero(world.scale.x), local.y / nonZero(world.scale.y), local.z / nonZero(world.scale.z))
        }
        return result
    }

    static func nonZero(_ value: Double) -> Double { abs(value) > 1e-9 ? value : 1 }

    /// Explode a group (or put it back together): its parts' places and the amount, one undo step.
    public static func toggle(_ group: ObjectID, in scene: Scene, bounds: (ObjectID) -> Bounds?) -> EditCommand? {
        guard let object = scene.objects[group], !object.children.isEmpty else { return nil }
        if object.explodeAmount > 0 {
            return .batch("Put together", [.setProperties([PropertyChange(object: group, key: .explode, value: .float(0))])])
        }
        let offsets = offsets(for: group, in: scene, bounds: bounds)
        guard !offsets.isEmpty else { return nil }
        var changes = offsets.sorted { $0.key.raw < $1.key.raw }.map { PropertyChange(object: $0.key, key: .explodeOffset, value: .vec3($0.value)) }
        changes.append(PropertyChange(object: group, key: .explode, value: .float(1)))
        return .batch("Explode", [.setProperties(changes)])
    }
}
