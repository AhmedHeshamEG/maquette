import Foundation

/// One copy's place, before any effect: where it sits in the thing's own directions (or, along a path, in the thing's
/// parent's space) and how the layout turns it.
struct CloneSlot: Sendable {
    var offset: Vec3
    var turn: Quat
    /// Along a path: the place in the parent's space, which replaces the thing's own place.
    var placed: Vec3?
}

/// Clones played at a moment: the thing becomes its first copy and the others join the shown scene as things of their own
/// (named after it, marked `cloneOf`, never stored), each placed by the layout, moved by the effects, and playing the
/// thing's motion at its own delayed moment.
public enum ClonePlayback {
    public static func anyone(in scene: Scene) -> Bool {
        scene.objects.values.contains { $0.motionDesign?.clones != nil }
    }

    public static func copyID(_ original: ObjectID, _ index: Int) -> ObjectID { ObjectID(raw: "\(original.raw)~clone\(index)") }

    /// Adds every cloner's copies to `scene` (the shown scene at `time`); `document` gives the edited places and the
    /// motion the delayed copies play.
    static func apply(to scene: inout Scene, document: Document, time: Double, animated: inout Set<ObjectID>) {
        let sources = scene.objects.values.filter { $0.motionDesign?.clones != nil && $0.kind != .camera && !$0.kind.isOverlay }
        for source in sources.sorted(by: { $0.id.raw < $1.id.raw }) {
            guard let clones = source.motionDesign?.clones, scene.isEffectivelyVisible(source.id),
                  let base = document.scene.objects[source.id]?.transform else { continue }
            let slots = slots(clones.layout, count: clones.count, base: base, parent: source.parent, in: scene)
            let shown = source.transform
            let strength = source[.effectStrength]?.floatValue ?? 1
            let delays = delayOffsets(clones, slots: slots)
            let solo = delays.contains { $0 != 0 } ? SoloMotion(source.id, in: document, withLinks: true) : nil
            for (index, slot) in slots.enumerated() {
                let delay = delays[index]
                let moved = solo.flatMap { delay == 0 ? nil : $0.transform(at: $0.earlier(time, by: delay)) } ?? shown
                let place = transform(slot: slot, index: index, clones: clones, base: base, moved: moved, time: time, strength: strength)
                if index == 0 {
                    scene.objects[source.id]?.transform = place
                } else {
                    addCopy(of: source.id, index: index, transform: place, to: &scene, animated: &animated)
                }
            }
            animated.insert(source.id)
        }
    }

    /// Each copy's slot: index 0 is where the thing stands.
    static func slots(_ layout: ObjectClones.Layout, count: Int, base: Transform, parent: ObjectID?, in scene: Scene) -> [CloneSlot] {
        switch layout {
        case let .grid(columns, rows, _, spacing):
            let c = max(columns, 1), r = max(rows, 1)
            return (0 ..< count).map { index in
                let column = index % c, row = (index / c) % r, layer = index / (c * r)
                let offset = Vec3((Double(column) - Double(c - 1) / 2) * spacing.x, Double(layer) * spacing.y,
                                  (Double(row) - Double(r - 1) / 2) * spacing.z)
                return CloneSlot(offset: offset, turn: .identity)
            }
        case let .circle(_, radius, facesOut):
            return (0 ..< count).map { index in
                let angle = 2 * Double.pi * Double(index) / Double(count)
                return CloneSlot(offset: Vec3(radius * sin(angle), 0, radius * cos(angle)),
                                 turn: facesOut ? Quat(angle: angle, axis: .unitY) : .identity)
            }
        case let .line(_, step):
            return (0 ..< count).map { CloneSlot(offset: step * Double($0), turn: .identity) }
        case let .path(_, path, along):
            return pathSlots(path, count: count, along: along, base: base, parent: parent, in: scene)
        }
    }

    private static func pathSlots(_ path: ObjectID, count: Int, along: Bool, base: Transform, parent: ObjectID?, in scene: Scene) -> [CloneSlot] {
        let curve = BehaviorEvaluator.path(.object(path), in: scene)
        guard !curve.points.isEmpty else { return (0 ..< count).map { _ in CloneSlot(offset: .zero, turn: .identity) } }
        let parentWorld = parent.map { scene.worldTransform(of: $0) } ?? .identity
        return (0 ..< count).map { index in
            let fraction = count > 1 ? Double(index) / Double(count - 1) : 0
            let sample = curve.sample(fraction) ?? (curve.points[0], .unitZ)
            let local = parentWorld.inverseApply(to: sample.position)
            let facing = along ? BehaviorEvaluator.facing(parentWorld.rotation.inverse.act(sample.tangent), cameraStyle: false) : .identity
            // Offsets are in the thing's own directions; along a path they're measured from the thing's own place.
            return CloneSlot(offset: base.rotation.inverse.act(local - base.position), turn: base.rotation.inverse * facing, placed: local)
        }
    }

    /// How long after the moment each copy plays the thing's motion.
    static func delayOffsets(_ clones: ObjectClones, slots: [CloneSlot]) -> [Double] {
        var delays = [Double](repeating: 0, count: slots.count)
        for effect in clones.effects where effect.kind == .delay && effect.delay != 0 {
            let ranks: [Int]
            if case .everywhere = effect.field {
                ranks = Array(slots.indices)
            } else {
                // Copies as far from the field's centre start together: rings ripple out.
                let distances = slots.map { (($0.offset - effect.field.centre).length * 1000).rounded() }
                let steps = Array(Set(distances)).sorted()
                ranks = distances.map { distance in steps.firstIndex(of: distance) ?? 0 }
            }
            for index in delays.indices {
                delays[index] += effect.delay * Double(ranks[index])
            }
        }
        return delays
    }

    /// A copy's place in the parent's space: the layout's slot from the edited place, the thing's motion (`moved`, at
    /// the copy's own moment), then the effects.
    static func transform(slot: CloneSlot, index: Int, clones: ObjectClones, base: Transform, moved: Transform, time: Double,
                          strength: Double) -> Transform {
        var shift = Vec3.zero
        var turn = Quat.identity
        var grow = 0.0
        for (number, effect) in clones.effects.enumerated() where effect.kind != .delay {
            let distance = (slot.offset - effect.field.centre).length
            var weight = effect.field.weight(distance: distance, time: time) * strength
            if effect.kind == .random {
                var random = SeededRandom(seed: clones.seed &+ UInt64(index) &* 7919 &+ UInt64(number) &* 104_729)
                let amounts = Vec3(random.range(-1, 1), random.range(-1, 1), random.range(-1, 1))
                shift += effect.move.scaled(by: amounts) * weight
                turn *= Quat(eulerDegrees: effect.turn.scaled(by: Vec3(random.range(-1, 1), random.range(-1, 1), random.range(-1, 1))) * weight)
                weight *= random.range(-1, 1)
            } else {
                shift += effect.move * weight
                turn *= Quat(eulerDegrees: effect.turn * weight)
            }
            grow += effect.grow * weight
        }
        let motion = moved.position - base.position
        let home = slot.placed ?? base.position + base.rotation.act(slot.offset)
        let size = max(1 + grow, 0.01)
        return Transform(position: home + motion + base.rotation.act(shift),
                         rotation: (moved.rotation * slot.turn * turn).normalized,
                         scale: moved.scale * size)
    }

    /// A copy of the thing and everything under it, under the thing's parent.
    private static func addCopy(of source: ObjectID, index: Int, transform: Transform, to scene: inout Scene, animated: inout Set<ObjectID>) {
        guard var root = scene.objects[source] else { return }
        let rootID = copyID(source, index)
        root.transform = transform
        root.motionDesign = nil
        copySubtree(root, as: rootID, parent: root.parent, index: index, source: source, into: &scene, animated: &animated)
        if let parent = root.parent {
            scene.objects[parent]?.children.append(rootID)
        } else {
            scene.roots.append(rootID)
        }
    }

    private static func copySubtree(_ object: SceneObject, as id: ObjectID, parent: ObjectID?, index: Int, source: ObjectID,
                                    into scene: inout Scene, animated: inout Set<ObjectID>) {
        var copy = object
        copy.id = id
        copy.parent = parent
        copy.children = object.children.map { copyID($0, index) }
        copy[.cloneOf] = .string(source.raw)
        copy.physics = nil
        scene.objects[id] = copy
        animated.insert(id)
        for child in object.children {
            guard let node = scene.objects[child] else { continue }
            copySubtree(node, as: copyID(child, index), parent: id, index: index, source: source, into: &scene, animated: &animated)
        }
    }
}
