import Foundation

/// How much a thing moves at each frame (A1's timeline rows draw it): its speed through the world plus how fast it
/// turns, from its keys and its parents' (cheap: no behaviours, clips or physics), scaled so the busiest frame is 1.
public enum MotionCurve {
    /// One value per frame of the timeline, 0 (still) … 1 (the thing's fastest). Empty when nothing moves it.
    public static func amounts(of id: ObjectID, in document: Document) -> [Double] {
        let scene = document.scene
        let timeline = scene.timeline
        let chain = Set([id] + scene.ancestors(of: id))
        guard timeline.tracks.contains(where: { chain.contains($0.target) && [.position, .rotation, .scale].contains($0.property) })
        else { return [] }
        let rates = FrameRates(document)
        let fps = Double(max(timeline.fps, 1))
        let count = max(timeline.frameCount, 1)
        var previous = MotionPath.worldTransform(of: id, in: document, at: 0, rates: rates)
        var amounts = [0.0]
        for frame in 1 ... count {
            let now = MotionPath.worldTransform(of: id, in: document, at: Double(frame) / fps, rates: rates)
            let travel = now.position.distance(to: previous.position)
            let turn = DrawnMotion.angle(between: now.rotation, and: previous.rotation)
            let grow = (now.scale - previous.scale).length
            // A turn of a radian or a growth of a metre counts like a metre travelled.
            amounts.append((travel + turn + grow) * fps)
            previous = now
        }
        amounts[0] = amounts.count > 1 ? amounts[1] : 0
        guard let top = amounts.max(), top > 1e-6 else { return amounts.map { _ in 0 } }
        return amounts.map { $0 / top }
    }
}

/// Animate any property (A1): what a thing has that can be keyed, in the order its panel shows them, so Animate ▸
/// Properties can start a track for any of them at the playhead.
public enum PropertyAnimation {
    public struct Choice: Hashable, Sendable, Identifiable {
        public var key: PropertyKey
        public var title: String
        public var id: String { key.rawValue }
    }

    /// The keyable properties of `object`: its place, turn and size, whether it shows and how see-through it is, then
    /// what its kind has (a surface's colours and finish, a light's, a camera's lens, words revealing, an emitter's rate,
    /// a face's channels).
    public static func choices(for object: SceneObject, in scene: Scene) -> [Choice] {
        var keys: [PropertyKey] = [.position, .rotation, .scale, .visible, .opacity]
        switch object.kind {
        case .light:
            keys += [.lightColor, .lightIntensity, .lightRange, .spotAngle]
        case .camera:
            keys += [.fieldOfView, .focusDistance, .aperture, .portraitZoom, .portraitShift]
        case .particles:
            keys += [.emission]
        case .text, .overlay:
            keys += [.color, .reveal, .accentColor, .emissive, .emissiveIntensity]
        default:
            keys += [.color, .emissive, .emissiveIntensity, .roughness, .metallic, .lineWeight, .rimStrength, .smear]
        }
        if isCharacter(object.id, in: scene) {
            keys += [.jawOpen, .smile, .brows, .blinkLeft, .blinkRight, .headYaw, .headPitch, .headRoll, .lookX, .lookY]
        }
        return keys.compactMap { key in key.spec.map { Choice(key: key, title: $0.label) } }
    }

    static func isCharacter(_ id: ObjectID, in scene: Scene) -> Bool {
        guard let object = scene.objects[id] else { return false }
        return object[.characterStart] != nil || object[.rigStandard] != nil || object.rig != nil
    }

    /// A key of the property at `time` holding the value it has there (the first key of a new track). Later changes to
    /// it key themselves.
    public static func key(_ key: PropertyKey, of id: ObjectID, at time: Double, shown: Scene, timeline: Timeline,
                           ids: inout IDFactory) -> EditCommand? {
        guard key.spec?.animatable == true, let object = shown.objects[id],
              let value = object.properties[key] ?? PropertyDefaults.value(for: key) else { return nil }
        var operations = KeyOperations(ids: ids)
        let edit = operations.setKey(id, key, value: value, at: time, previous: nil, in: timeline)
        ids = operations.ids
        return .batch("Animate \(key.spec?.label ?? key.rawValue)", [.setTracks([edit])])
    }
}
