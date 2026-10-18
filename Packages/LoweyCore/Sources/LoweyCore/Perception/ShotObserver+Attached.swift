import Foundation

// MARK: - Parts of a grouped thing

extension ShotObserver {
    /// How the grounding of a part inside a group is judged: the group stands or floats as one thing. Its lowest parts
    /// take the group's verdict; a part that touches a chain of parts reaching them is attached (a rim on a wheel, a wing
    /// on the boot), not floating. A part touching nothing keeps its own verdict: that one really is in the air.
    static func attachedGrounding(_ parts: [(id: ObjectID, world: Bounds)], in scene: Scene,
                                  solver: RelationSolver) -> [ObjectID: (grounded: Bool, gap: Double)] {
        var byRoot: [ObjectID: [(id: ObjectID, world: Bounds)]] = [:]
        for part in parts {
            guard let root = root(of: part.id, in: scene), root != part.id else { continue }
            byRoot[root, default: []].append(part)
        }
        var result: [ObjectID: (grounded: Bool, gap: Double)] = [:]
        for (root, members) in byRoot where members.count > 1 {
            let group = solver.isGrounded(root)
            guard let base = members.map(\.world.min.y).min() else { continue }
            var reached = Set(members.filter { $0.world.min.y < base + 0.01 }.map(\.id))
            for id in reached { result[id] = group }
            var frontier = Array(reached)
            while let current = frontier.popLast(), let box = members.first(where: { $0.id == current })?.world {
                for other in members where !reached.contains(other.id) && touches(box, other.world, within: 0.02) {
                    reached.insert(other.id)
                    frontier.append(other.id)
                    result[other.id] = (true, 0)
                }
            }
        }
        return result
    }

    static func root(of id: ObjectID, in scene: Scene) -> ObjectID? {
        var current = id
        while let parent = scene.objects[current]?.parent {
            current = parent
        }
        return scene.objects[current] == nil ? nil : current
    }

    static func touches(_ a: Bounds, _ b: Bounds, within margin: Double) -> Bool {
        a.min.x <= b.max.x + margin && b.min.x <= a.max.x + margin && a.min.y <= b.max.y + margin && b.min.y <= a.max.y + margin
            && a.min.z <= b.max.z + margin && b.min.z <= a.max.z + margin
    }
}
