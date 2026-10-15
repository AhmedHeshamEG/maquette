import Foundation

/// Real things leave with their physics in the form Godot reads (OMI_physics_body and OMI_physics_shape; Khronos'
/// own physics extension once it's ratified): how each moves and its mass on its node, and a collider made of the
/// node's own mesh (its convex hull when it moves, its triangles when it stays). The motion of a run is baked into
/// the animation separately, so engines without physics play it too.
extension GLTFSceneWriter {
    /// The motion of a real thing, on its node.
    mutating func addBody(_ object: SceneObject, to node: inout [String: Any]) {
        guard let physics = object.physics else { return }
        var motion: [String: Any] = ["type": Self.motionType(physics.motion)]
        if physics.motion == .falls, let mass = mass(of: object, physics: physics) { motion["mass"] = mass }
        var body = (node["extensions"] as? [String: Any])?["OMI_physics_body"] as? [String: Any] ?? [:]
        body["motion"] = motion
        merge(["OMI_physics_body": body], into: &node)
    }

    /// A collider for a real thing's mesh, or a part of a real group's.
    mutating func addCollider(for id: ObjectID, mesh: Int, to node: inout [String: Any]) {
        guard let motion = realMotion(of: id) else { return }
        let kind = motion == .falls ? "convex" : "trimesh"
        physicsShapes.append(["type": kind, kind: ["mesh": mesh]])
        var body = (node["extensions"] as? [String: Any])?["OMI_physics_body"] as? [String: Any] ?? [:]
        body["collider"] = ["shape": physicsShapes.count - 1]
        merge(["OMI_physics_body": body], into: &node)
    }

    /// How the real thing this object belongs to moves (itself or its nearest real ancestor).
    func realMotion(of id: ObjectID) -> ObjectPhysics.Motion? {
        var current: ObjectID? = id
        while let at = current {
            if let physics = scene.objects[at]?.physics { return physics.motion }
            current = scene.objects[at]?.parent
        }
        return nil
    }

    static func motionType(_ motion: ObjectPhysics.Motion) -> String {
        switch motion {
        case .falls: "dynamic"
        case .stays: "static"
        case .follows: "kinematic"
        }
    }

    /// Its mass in kg: as set, else its material times the volume of its hull at its size.
    func mass(of object: SceneObject, physics: ObjectPhysics) -> Double? {
        if let mass = physics.mass { return mass }
        let scale = scene.worldTransform(of: object.id).scale.map(abs)
        let points = scene.subtree(of: object.id).flatMap { id -> [Vec3] in
            guard let part = scene.objects[id] else { return [] }
            let mesh = SceneExport.localMesh(of: part, look: look) ?? parts(part).reduce(into: MeshData()) { $0.append($1.mesh) }
            let place = Transform.relative(world: scene.worldTransform(of: id), toParent: scene.worldTransform(of: object.id))
            return mesh.positions.map { place.apply(to: Vec3($0)).scaled(by: scale) }
        }
        let volume = ConvexVolume.volume(of: points)
        return volume > 0 ? volume * physics.material.density : nil
    }

    private func merge(_ extensions: [String: Any], into node: inout [String: Any]) {
        var current = node["extensions"] as? [String: Any] ?? [:]
        for (key, value) in extensions {
            current[key] = value
        }
        node["extensions"] = current
    }
}
