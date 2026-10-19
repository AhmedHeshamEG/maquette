import Foundation

/// One thing's motion driving another's, or a sound driving a thing (Make it move ▸ Link, Follow the music): a gear
/// turning its neighbour the other way, a light that glows with the voice, letters that jump on the beat, a ripple on
/// the bass. The link adds to whatever else moves the thing.
public struct MotionLink: Codable, Hashable, Sendable, Identifiable {
    /// A way a thing moves or looks, as one number.
    public enum Channel: String, Codable, Sendable, CaseIterable, Identifiable {
        case moveX, moveY, moveZ, turnX, turnY, turnZ, size, glow, opacity, effect, morph, reveal

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .moveX: "Move sideways"
            case .moveY: "Move up"
            case .moveZ: "Move forward"
            case .turnX: "Tip forward"
            case .turnY: "Turn"
            case .turnZ: "Lean"
            case .size: "Grow"
            case .glow: "Glow"
            case .opacity: "Fade"
            case .effect: "Clone effects"
            case .morph: "Morph"
            case .reveal: "Reveal"
            }
        }

        /// What a thing's motion can drive from (its place, turn and size).
        public static let motion: [Channel] = [.moveX, .moveY, .moveZ, .turnX, .turnY, .turnZ, .size]

        /// How much a sound at full strength moves this, at first (metres, degrees, a fraction, glow, …).
        public var soundAmount: Double {
            switch self {
            case .moveX, .moveY, .moveZ: 0.5
            case .turnX, .turnY, .turnZ: 45
            case .size: 0.5
            case .glow: 3
            case .opacity: -1
            case .effect, .morph, .reveal: 1
            }
        }
    }

    /// What a sound gives: how loud it is, its bass, or a hit on each beat.
    public enum SoundFeature: String, Codable, Sendable, CaseIterable, Identifiable {
        case loudness, bass, beat

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .loudness: "Loudness"
            case .bass: "Bass"
            case .beat: "Beat"
            }
        }
    }

    public enum Driver: Codable, Hashable, Sendable {
        /// Another thing's change in `channel` since its edited place.
        case thing(id: ObjectID, channel: Channel)
        /// An audio clip of the timeline, by id.
        case sound(clip: String, feature: SoundFeature)
    }

    public var id: String
    public var target: ObjectID
    public var channel: Channel
    public var driver: Driver
    /// Thing: how much of the driver's change (−1 turns a gear the other way). Sound: the change at full strength.
    public var amount: Double
    /// Thing: seconds behind the driver.
    public var delay: Double

    public init(id: String, target: ObjectID, channel: Channel, driver: Driver, amount: Double = 1, delay: Double = 0) {
        self.id = id
        self.target = target
        self.channel = channel
        self.driver = driver
        self.amount = amount
        self.delay = delay
    }
}

/// Links played at a moment: each driver's value, scaled, added to its target.
public enum MotionLinks {
    /// Applies `links` to `scene` (keys and behaviours already in) at `time`. Things are read as they stand in `scene`, or
    /// at their own earlier moment when the link waits.
    static func apply(_ links: [MotionLink], to scene: inout Scene, document: Document, time: Double, animated: inout Set<ObjectID>) {
        for link in links where scene.objects[link.target] != nil {
            guard let value = driverValue(link, scene: scene, document: document, time: time) else { continue }
            add(value * link.amount, to: link.channel, of: link.target, in: &scene, base: document.scene)
            animated.insert(link.target)
        }
    }

    static func apply(_ links: [MotionLink], to scene: inout Scene, document: Document, time: Double) {
        var ignored = Set<ObjectID>()
        apply(links, to: &scene, document: document, time: time, animated: &ignored)
    }

    static func driverValue(_ link: MotionLink, scene: Scene, document: Document, time: Double) -> Double? {
        switch link.driver {
        case let .thing(id, channel):
            guard let base = document.scene.objects[id] else { return nil }
            if link.delay == 0, channel.isTurn == false, let object = scene.objects[id] { return change(channel, of: object, from: base) }
            return LinkTurns.change(channel, of: id, in: document, at: time, delay: link.delay, base: base)
        case let .sound(clipID, feature):
            guard let clip = document.scene.timeline.audio.first(where: { $0.id == clipID }) else { return nil }
            return soundValue(clip, feature: feature, at: time)
        }
    }

    /// A clip's feature at a timeline moment, through its fades (0 when muted or outside it).
    public static func soundValue(_ clip: AudioClip, feature: MotionLink.SoundFeature, at time: Double) -> Double {
        guard let levels = clip.levels, let fileTime = clip.fileTime(at: time), !clip.muted else { return 0 }
        let fades = clip.gain(at: time) / max(clip.volume, 1e-6)
        let value = switch feature {
        case .loudness: levels.loudness(at: fileTime)
        case .bass: levels.bass(at: fileTime)
        case .beat: levels.pulse(at: fileTime)
        }
        return value * min(max(fades, 0), 1)
    }

    /// A thing's change in a channel since `base` (metres, degrees, a fraction for size).
    static func change(_ channel: MotionLink.Channel, of object: SceneObject, from base: SceneObject) -> Double {
        let now = object.transform
        let was = base.transform
        switch channel {
        case .moveX: return now.position.x - was.position.x
        case .moveY: return now.position.y - was.position.y
        case .moveZ: return now.position.z - was.position.z
        case .turnX, .turnY, .turnZ:
            return LinkTurns.twist(of: was.rotation.inverse * now.rotation, about: channel.axis)
        case .size:
            return (now.scale.y / max(abs(was.scale.y), 1e-9)) - 1
        case .glow: return object.emissiveIntensity - base.emissiveIntensity
        case .opacity: return object.opacity - base.opacity
        case .effect: return (object[.effectStrength]?.floatValue ?? 1) - (base[.effectStrength]?.floatValue ?? 1)
        case .morph: return object.morphAmount - base.morphAmount
        case .reveal: return (object[.reveal]?.floatValue ?? 1) - (base[.reveal]?.floatValue ?? 1)
        }
    }

    static func add(_ value: Double, to channel: MotionLink.Channel, of id: ObjectID, in scene: inout Scene, base: Scene) {
        guard var object = scene.objects[id] else { return }
        var place = object.transform
        switch channel {
        case .moveX: place.position.x += value
        case .moveY: place.position.y += value
        case .moveZ: place.position.z += value
        case .turnX, .turnY, .turnZ:
            place.rotation = (place.rotation * Quat(angle: value * .pi / 180, axis: channel.axis)).normalized
        case .size:
            place.scale *= max(1 + value, 0.01)
        case .glow:
            object[.emissiveIntensity] = .float(max(object.emissiveIntensity + value, 0))
            if object.emissive == nil { object[.emissive] = object[.color] ?? .color(.rgba(RGBA(1, 1, 1))) }
        case .opacity: object[.opacity] = .float(min(max(object.opacity + value, 0), 1))
        case .effect: object[.effectStrength] = .float(max((object[.effectStrength]?.floatValue ?? 1) + value, 0))
        case .morph: object[.morph] = .float(min(max(object.morphAmount + value, 0), 1))
        case .reveal: object[.reveal] = .float(min(max((object[.reveal]?.floatValue ?? 1) + value, 0), 1))
        }
        if MotionLink.Channel.motion.contains(channel) { object.transform = place }
        scene.objects[id] = object
    }
}

extension MotionLink.Channel {
    var isTurn: Bool { self == .turnX || self == .turnY || self == .turnZ }

    var axis: Vec3 {
        switch self {
        case .turnX: .unitX
        case .turnZ: .unitZ
        default: .unitY
        }
    }
}

/// Turns read through whole revolutions: a gear driven at half speed must keep turning, not jump back at 180°, so a
/// driver's turn is followed from the start in small steps and the steps added up.
enum LinkTurns {
    /// The angle (degrees, −180…180) of `rotation` about `axis` (its twist).
    static func twist(of rotation: Quat, about axis: Vec3) -> Double {
        let vector = Vec3(rotation.x, rotation.y, rotation.z)
        let along = axis * vector.dot(axis)
        var angle = 2 * atan2(along.length * (along.dot(axis) < 0 ? -1 : 1), rotation.w) * 180 / .pi
        if angle > 180 { angle -= 360 }
        if angle < -180 { angle += 360 }
        return angle
    }

    /// A thing's change in `channel` at `time` (its keys, behaviours; not its links), turns unwrapped.
    static func change(_ channel: MotionLink.Channel, of id: ObjectID, in document: Document, at now: Double, delay: Double,
                       base: SceneObject) -> Double? {
        let solo = SoloMotion(id, in: document, withLinks: false)
        let time = solo.earlier(now, by: delay)
        guard channel.isTurn else {
            return solo.transform(at: time).map { place in
                var moved = base
                moved.transform = place
                return MotionLinks.change(channel, of: moved, from: base)
            }
        }
        func turn(at moment: Double) -> Double? {
            solo.transform(at: moment).map { twist(of: base.transform.rotation.inverse * $0.rotation, about: channel.axis) }
        }
        // Steps of a tenth of a second (at most 600 of them), so a spin up to 300° a second stays countable.
        guard time > 0, var previous = turn(at: 0) else { return turn(at: time) }
        let steps = min(max(Int((time * 10).rounded(.up)), 1), 600)
        var total = previous
        for step in 1 ... steps {
            guard let angle = turn(at: time * Double(step) / Double(steps)) else { return nil }
            var delta = angle - previous
            if delta > 180 { delta -= 360 }
            if delta < -180 { delta += 360 }
            total += delta
            previous = angle
        }
        return total
    }
}
