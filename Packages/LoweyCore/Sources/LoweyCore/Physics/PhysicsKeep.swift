import Foundation

/// "Keep it": a run turned into ordinary keys, one undo step. Things that fell get position and rotation keys and from
/// then on follow them (they still push what they meet); ragdolls get their joints' turns; broken things' pieces become
/// things of their own that appear when it breaks. Cloth, jelly and fluids aren't keys: they keep playing from the run.
public enum PhysicsKeep {
    /// `following`: the things that fell follow their keys from now on (Keep it); an export leaves them as they were made,
    /// so an engine that simulates gets them falling, and one that doesn't plays the keys.
    public static func keep(_ frames: PhysicsFrames, in document: Document, ids: inout IDFactory, following: Bool = true) -> EditCommand? {
        guard !frames.frames.isEmpty else { return nil }
        let baked = tracks(frames, in: document, ids: &ids)
        guard !baked.edits.isEmpty else { return nil }
        var commands: [EditCommand] = []
        if !baked.pieces.isEmpty { commands.append(.insert(SceneFragment(objects: baked.pieces, roots: baked.pieces.map(\.id)), parent: nil, index: nil)) }
        commands.append(.setTracks(baked.edits))
        for id in baked.kept where following {
            guard var physics = document.scene.objects[id]?.physics else { continue }
            physics.motion = .follows
            commands.append(.setPhysics(id, physics))
        }
        for broken in baked.broken where following {
            commands.append(.setPhysics(broken, nil))
        }
        return .batch("Keep it", commands)
    }

    /// The document with a run baked into its timeline (and broken things' pieces added): what an export writes.
    public static func baked(_ frames: PhysicsFrames, into document: Document) -> Document {
        var ids = IDFactory.sequential("baked")
        guard let command = keep(frames, in: document, ids: &ids, following: false) else { return document }
        var result = document
        _ = try? command.apply(to: &result)
        return result
    }

    struct Baked {
        var edits: [TrackEdit] = []
        var pieces: [SceneObject] = []
        var kept: [ObjectID] = []
        var broken: [ObjectID] = []
    }

    static func tracks(_ frames: PhysicsFrames, in document: Document, ids: inout IDFactory) -> Baked {
        var baked = Baked()
        let timeline = document.scene.timeline
        let times = frames.frames.indices.map { frames.start + Double($0) / Double(max(frames.fps, 1)) }
        let keyed = times.map { Animator.keyedScene(document, at: $0) }
        var samples: [ObjectID: [PropertyKey: [Keyframe]]] = [:]
        for (index, time) in times.enumerated() {
            let values = PhysicsPlayback.overrides(frames, scene: keyed[index], at: time)
            for (id, properties) in values {
                for (key, value) in properties {
                    samples[id, default: [:]][key, default: []].append(Keyframe(time: time, value: value, easing: .linear))
                }
            }
        }
        let breakables = Set(frames.breakables.filter { $0.brokeAt != nil }.map(\.object))
        for id in samples.keys.sorted() {
            for (property, keys) in (samples[id] ?? [:]).sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
                let tolerance = property == .position ? 0.0005 : 0.001
                baked.edits.append(TrackEdit(Simulation.bake(id, property, PerformBaker.simplify(keys, tolerance: tolerance), timeline: timeline, ids: &ids)))
            }
            if !breakables.contains(id) { baked.kept.append(id) }
        }
        for breakable in frames.breakables {
            guard let broke = breakable.brokeAt, let original = document.scene.objects[breakable.object] else { continue }
            let brokeTime = frames.start + Double(broke) / Double(max(frames.fps, 1))
            baked.edits.append(TrackEdit(visibility(of: breakable.object, until: brokeTime, shown: true, timeline: timeline, ids: &ids)))
            baked.broken.append(breakable.object)
            pieces(of: breakable, original: original, from: broke, frames: frames, times: times, timeline: timeline, ids: &ids, into: &baked)
        }
        return baked
    }

    private static func pieces(of breakable: PhysicsFrames.Breakable, original: SceneObject, from broke: Int, frames: PhysicsFrames, times: [Double],
                               timeline: Timeline, ids: inout IDFactory, into baked: inout Baked) {
        guard let index = frames.breakables.firstIndex(where: { $0.object == breakable.object }) else { return }
        for (piece, mesh) in breakable.pieces.enumerated() {
            var positions: [Keyframe] = []
            var rotations: [Keyframe] = []
            for frame in broke ..< frames.frames.count {
                let values = frames.frames[frame].pieces[index]
                guard values.count >= piece * 7 + 7 else { continue }
                let (position, rotation) = PhysicsFrames.read(values, at: piece * 7)
                positions.append(Keyframe(time: times[frame], value: .vec3(position), easing: .linear))
                rotations.append(Keyframe(time: times[frame], value: .quat(rotation.normalized), easing: .linear))
            }
            guard let first = positions.first, case let .vec3(start) = first.value, case let .quat(turn)? = rotations.first?.value else { continue }
            let id = PhysicsPlayback.pieceID(breakable.object, piece)
            var object = SceneObject(id: id, name: "\(original.name) piece \(piece + 1)", kind: .mesh(mesh),
                                     transform: Transform(position: start, rotation: turn))
            for key in [PropertyKey.color, .emissive, .emissiveIntensity, .shading, .roughness, .metallic, .opacity] {
                object[key] = original[key]
            }
            object[.visible] = .bool(false)
            baked.pieces.append(object)
            let empty = Timeline(fps: timeline.fps, duration: timeline.duration)
            baked.edits.append(TrackEdit(Simulation.bake(id, .position, PerformBaker.simplify(positions, tolerance: 0.0005), timeline: empty, ids: &ids)))
            baked.edits.append(TrackEdit(Simulation.bake(id, .rotation, PerformBaker.simplify(rotations, tolerance: 0.001), timeline: empty, ids: &ids)))
            baked.edits.append(TrackEdit(visibility(of: id, until: first.time, shown: false, timeline: empty, ids: &ids)))
        }
    }

    /// Shown (or hidden) until a moment, then the other way, by two held keys.
    static func visibility(of id: ObjectID, until time: Double, shown: Bool, timeline: Timeline, ids: inout IDFactory) -> Track {
        let keys = [Keyframe(time: max(time - 1e-3, 0), value: .bool(shown), easing: .step), Keyframe(time: time, value: .bool(!shown), easing: .step)]
        return Simulation.bake(id, .visible, keys, timeline: timeline, ids: &ids)
    }
}
