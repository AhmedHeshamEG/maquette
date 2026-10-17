import Foundation

/// Face states at a moment (the Animator's step after the face rig): each mouth and brow shows the state its character's
/// channels choose (lip sync's `mouthShape`, the brows, face capture), bent from the part as made; a drawing of a state
/// shows in its part's place while that state is on. The bent shapes reach the renderer like a physics run's bent
/// surfaces, so the stage and every export see the same face.
public extension FaceStates {
    /// Bends and swaps every made face in `scene`; returns the bent shapes (each in its part's own space).
    static func apply(to scene: inout Scene, animated: inout Set<ObjectID>) -> [ObjectID: MeshData] {
        let parts = scene.objects.values.filter { object in
            guard let part = object.part else { return false }
            return part.job == .mouth || part.job == .brow || part.job == .eye
        }
        guard !parts.isEmpty else { return [:] }
        var shapes: [ObjectID: MeshData] = [:]
        var roots: [ObjectID: ObjectID?] = [:]
        // Which drawn states each character has, by job, side and state.
        var drawn: [ObjectID: Set<String>] = [:]
        for object in parts {
            guard let root = root(of: object.id, in: scene, cache: &roots), let part = object.part, let state = part.shows else { continue }
            drawn[root, default: []].insert(key(part, state))
        }
        for object in parts {
            guard let root = root(of: object.id, in: scene, cache: &roots), let character = scene.objects[root], let part = object.part else { continue }
            let active = FaceStates.active(part, values: { character[$0] })
            var visible: Bool
            if let shows = part.shows {
                visible = shows == active.state
            } else {
                visible = !(drawn[root]?.contains(key(part, active.state)) ?? false)
                if visible, !active.bend.isNone, let mesh = PaintSource.mesh(of: object), let bounds = mesh.bounds {
                    shapes[object.id] = active.bend.bend(mesh, bounds: bounds, side: part.side.sign)
                }
            }
            visible = visible && object.isVisible
            if (scene.objects[object.id]?.isVisible ?? true) != visible {
                scene.objects[object.id]?[.visible] = .bool(visible)
                animated.insert(object.id)
            }
            if shapes[object.id] != nil { animated.insert(object.id) }
        }
        return shapes
    }

    private static func key(_ part: CharacterPart, _ state: String) -> String {
        "\(part.job.rawValue)|\(part.side.rawValue)|\(state)"
    }

    /// The made character a part belongs to (cached per walk).
    private static func root(of id: ObjectID, in scene: Scene, cache: inout [ObjectID: ObjectID?]) -> ObjectID? {
        if let known = cache[id] { return known }
        let found = CharacterMaker.character(of: id, in: scene)
        cache[id] = found
        return found
    }
}
