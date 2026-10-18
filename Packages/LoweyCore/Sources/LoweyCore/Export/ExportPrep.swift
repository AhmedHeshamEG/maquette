import Foundation

/// What a named 3D preset changes about the scene before it's written (A1, "formats first": glTF ▸ for Godot, FBX ▸
/// for Unity…). Each one is a real difference, never just a label.
public enum ExportPrep {
    /// Cameras and lights stay behind: a game engine brings its own, and a stray scene light doubles its lighting.
    public static func withoutCamerasAndLights(_ scene: Scene) -> Scene {
        var result = scene
        for (id, object) in scene.objects {
            switch object.kind {
            case .camera, .light: result.objects[id]?[.visible] = .bool(false)
            default: break
            }
        }
        return result
    }

    /// Real things leave as plain things (colliders are what Godot reads; other apps would carry them as clutter).
    public static func withoutPhysics(_ scene: Scene) -> Scene {
        var result = scene
        for id in scene.objects.keys where scene.objects[id]?.physics != nil {
            result.objects[id]?.physics = nil
        }
        result.physics = nil
        return result
    }

    /// Only the chosen things and what's under them (an export of the selection keeps its place in the world).
    public static func only(_ ids: [ObjectID], in scene: Scene) -> Scene {
        let kept = Set(ids.flatMap { scene.subtree(of: $0) + scene.ancestors(of: $0) })
        var result = scene
        for id in scene.objects.keys where !kept.contains(id) {
            result.objects[id]?[.visible] = .bool(false)
        }
        return result
    }

    /// A rigged thing's skeleton and its keys with each joint named for an engine (Unity's humanoid names, Unreal's
    /// mannequin's), so the engine's retargeting finds them.
    public static func renamed(_ skin: GLTFScene.SkinnedExport, tracks: [Track], for engine: GameEngine) -> (GLTFScene.SkinnedExport, [Track]) {
        var renamed = skin
        renamed.rig.skeleton.joints = skin.rig.skeleton.joints.map { joint in
            var copy = joint
            copy.name = engine.name(of: joint.name)
            return copy
        }
        let keys = tracks.map { track -> Track in
            guard let joint = track.property.boneJoint else { return track }
            var copy = track
            copy.property = .boneTurn(engine.name(of: joint))
            return copy
        }
        return (renamed, keys)
    }
}
