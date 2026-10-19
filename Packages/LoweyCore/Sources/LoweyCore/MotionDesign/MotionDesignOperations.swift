import Foundation

/// A morph as one step: the thing gets its target, the target is hidden (it's the shape to reach), and `morph` is keyed
/// from 0 to 1 over `duration` from `start`. The app's hold menu and the bridge both make it here.
public enum MorphOperations {
    public static func command(_ id: ObjectID, into target: ObjectID, design: MotionDesign, from start: Double, duration: Double,
                               in document: Document, ids: inout IDFactory) -> EditCommand {
        let timeline = document.scene.timeline
        var track = timeline.track(for: id, .morph) ?? Track(id: ids.next(), target: id, property: .morph)
        track.setKey(Keyframe(time: start, value: .float(0), easing: .linear))
        track.setKey(Keyframe(time: start + duration, value: .float(1), easing: .linear))
        var commands: [EditCommand] = [.setMotionDesign(id, design), .setTracks([TrackEdit(track)])]
        if document.scene.objects[target]?.isVisible ?? false {
            commands.append(.setProperties([PropertyChange(object: target, key: .visible, value: .bool(false))]))
        }
        return .batch("Morph", commands)
    }

    /// Undoing a morph's choice: the target shows again, the keys go, the thing keeps the rest of its motion design.
    public static func removing(_ id: ObjectID, in document: Document) -> EditCommand? {
        guard let object = document.scene.objects[id], var design = object.motionDesign, let morph = design.morph else { return nil }
        design.morph = nil
        var commands: [EditCommand] = [.setMotionDesign(id, design.orNil)]
        if let track = document.scene.timeline.track(for: id, .morph) { commands.append(.setTracks([TrackEdit(id: track.id, track: nil)])) }
        commands.append(.setProperties([PropertyChange(object: id, key: .morph, value: nil)]))
        if document.scene.objects[morph.target] != nil {
            commands.append(.setProperties([PropertyChange(object: morph.target, key: .visible, value: .bool(true))]))
        }
        return .batch("No morph", commands)
    }
}
