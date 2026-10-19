import Foundation

/// Lighting setups: a key on the subject, the world kept cooler or darker, a rim where the silhouette needs it.
/// Each is placed relative to the camera and the subject, so "key from camera left" means the same in every shot.
/// The first four are the film set's classics (F1); the rest are the toon recipes the bridge has had since 2.0.
public enum LightRecipe: String, Codable, Sendable, CaseIterable, Identifiable {
    case threePoint = "three-point"
    case goldenHour = "golden-hour"
    case moonlit
    case neon
    case keyWarmWorldCool = "key-warm-world-cool"
    case noirSingleSource = "noir-single-source"
    case goldenRim = "golden-rim"
    case monitorGlow = "monitor-glow"
    case studioSoft = "studio-soft"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .threePoint: "Three-point"
        case .goldenHour: "Golden hour"
        case .moonlit: "Moonlight"
        case .neon: "Neon"
        case .keyWarmWorldCool: "Warm key, cool world"
        case .noirSingleSource: "Noir"
        case .goldenRim: "Golden rim"
        case .monitorGlow: "Screen glow"
        case .studioSoft: "Soft studio"
        }
    }

    /// Why you'd reach for it (the skill's lighting module says the same).
    public var reason: String {
        switch self {
        case .threePoint: "A soft key, a gentle fill and a rim from behind: the subject reads round and stands off the background."
        case .goldenHour: "The sun low and warm, long shadows, a golden haze: the hour before sunset."
        case .moonlit: "Blue, soft and low: calm or eerie night exteriors."
        case .neon: "Night, two coloured signs from either side, a little haze: a street after the rain."
        case .keyWarmWorldCool: "The subject warm and lit, the world cool and dimmer: the eye goes to the warm."
        case .noirSingleSource: "One hard light, deep shadows: mystery, secrets, night."
        case .goldenRim: "Low sun behind the subject outlines it in gold: warmth, endings, hope."
        case .monitorGlow: "A cold glow from below and in front: someone at a screen at night."
        case .studioSoft: "Even, soft light from the front-left: explainers, clean product shots."
        }
    }

    /// A lamp of the recipe: where it goes relative to the subject as the camera sees it (x camera-right, y up,
    /// z toward the camera, in subject sizes), and how it looks. Spots and panels face the subject.
    public struct Lamp: Hashable, Sendable {
        public var name: String
        public var offset: Vec3
        public var color: RGBA
        public var intensity: Double
        /// Range in subject sizes.
        public var range: Double
        public var type: LightType = .point
        /// A panel's width and height in subject sizes.
        public var size: Vec2?
    }

    /// The sun and sky for the recipe: where the sun comes from as the camera sees it (degrees around from the
    /// camera's back: 0 behind the camera, 90 camera-right, 180 behind the subject) and its height.
    public struct Sun: Hashable, Sendable {
        public var around: Double
        public var elevation: Double
        public var color: RGBA
        public var intensity: Double
        public var ambient: Double
    }

    public var sun: Sun {
        switch self {
        case .threePoint: Sun(around: -30, elevation: 50, color: RGBA.hex("#FFF4E6"), intensity: 0.35, ambient: 0.3)
        case .goldenHour: Sun(around: 125, elevation: 9, color: RGBA.hex("#FFB067"), intensity: 1.5, ambient: 0.35)
        case .moonlit: Sun(around: 120, elevation: 35, color: RGBA.hex("#8FA8FF"), intensity: 0.45, ambient: 0.18)
        case .neon: Sun(around: 150, elevation: 50, color: RGBA.hex("#5D6BA8"), intensity: 0.08, ambient: 0.14)
        case .keyWarmWorldCool: Sun(around: 140, elevation: 35, color: RGBA.hex("#9DB4FF"), intensity: 0.45, ambient: 0.3)
        case .noirSingleSource: Sun(around: 100, elevation: 60, color: RGBA.hex("#C9D2E8"), intensity: 0.06, ambient: 0.08)
        case .goldenRim: Sun(around: 175, elevation: 12, color: RGBA.hex("#FFB25C"), intensity: 1.4, ambient: 0.3)
        case .monitorGlow: Sun(around: 160, elevation: 40, color: RGBA.hex("#6F86C8"), intensity: 0.08, ambient: 0.12)
        case .studioSoft: Sun(around: -40, elevation: 45, color: RGBA.hex("#FFF6EC"), intensity: 0.9, ambient: 0.55)
        }
    }

    public var lamps: [Lamp] {
        switch self {
        case .threePoint:
            [Lamp(name: "Key light", offset: Vec3(-1.1, 0.9, 1.1), color: RGBA.hex("#FFF1DE"), intensity: 2.4, range: 5, type: .area,
                  size: Vec2(0.7, 0.5)),
             Lamp(name: "Fill light", offset: Vec3(1.2, 0.35, 1.0), color: RGBA.hex("#E8EEFF"), intensity: 0.8, range: 5, type: .area,
                  size: Vec2(0.9, 0.6)),
             Lamp(name: "Rim light", offset: Vec3(0.6, 1.1, -1.2), color: RGBA.hex("#FFFFFF"), intensity: 2.2, range: 4, type: .spot)]
        case .goldenHour:
            [Lamp(name: "Fill light", offset: Vec3(-0.9, 0.3, 1.2), color: RGBA.hex("#FFD7A6"), intensity: 0.7, range: 4, type: .area,
                  size: Vec2(1.2, 0.8))]
        case .moonlit:
            [Lamp(name: "Rim light", offset: Vec3(0.8, 0.9, -1.1), color: RGBA.hex("#B8C8FF"), intensity: 1.4, range: 3)]
        case .neon:
            [Lamp(name: "Key light", offset: Vec3(-1.2, 0.6, 0.5), color: RGBA.hex("#FF3FA4"), intensity: 2.6, range: 4, type: .area,
                  size: Vec2(0.25, 1.2)),
             Lamp(name: "Rim light", offset: Vec3(1.1, 0.7, -0.6), color: RGBA.hex("#2FE0FF"), intensity: 2.4, range: 4, type: .area,
                  size: Vec2(0.25, 1.2))]
        case .keyWarmWorldCool:
            [Lamp(name: "Key light", offset: Vec3(-0.9, 0.9, 1.1), color: RGBA.hex("#FFC27A"), intensity: 2.6, range: 4)]
        case .noirSingleSource:
            [Lamp(name: "Key light", offset: Vec3(1.3, 1.4, 0.3), color: RGBA.hex("#FFE2B0"), intensity: 3.2, range: 3.5)]
        case .goldenRim:
            [Lamp(name: "Fill light", offset: Vec3(-0.8, 0.4, 1.2), color: RGBA.hex("#FFD9A8"), intensity: 0.9, range: 4)]
        case .monitorGlow:
            [Lamp(name: "Glow light", offset: Vec3(0.1, 0.55, 0.7), color: RGBA.hex("#7FD4FF"), intensity: 2.2, range: 2.5)]
        case .studioSoft:
            [Lamp(name: "Fill light", offset: Vec3(1.1, 0.3, 1), color: RGBA.hex("#FFFFFF"), intensity: 0.7, range: 4)]
        }
    }

    /// The mood the recipe needs around it (nil keeps the scene's).
    public var mood: LightingPreset? {
        switch self {
        case .goldenHour: .goldenHour
        case .moonlit, .noirSingleSource, .neon: .night
        default: nil
        }
    }

    /// The air it wants (nil leaves the Look's as it is).
    public var atmosphere: Atmosphere? {
        switch self {
        case .goldenHour: Atmosphere(haze: 0.35, godRays: 0.5)
        case .neon: Atmosphere(haze: 0.3, godRays: 0)
        default: nil
        }
    }

    /// The recipe's lamps' names (re-lighting replaces them instead of piling up).
    public static let lampNames: Set<String> = ["Key light", "Fill light", "Rim light", "Glow light"]

    /// The lighting the recipe gives, for a camera at `eye` looking at a subject at `subject`.
    public func lighting(from base: Lighting, eye: Vec3, subject: Vec3, intensity: Double = 1) -> Lighting {
        var lighting = base
        let back = Vec3(eye.x - subject.x, 0, eye.z - subject.z)
        let cameraYaw = back.length > 1e-6 ? atan2(back.x, back.z) * 180 / .pi : 0
        // Degrees "around" from the camera's back toward camera-right is clockwise seen from above.
        lighting.sunAzimuth = (cameraYaw + sun.around).truncatingRemainder(dividingBy: 360)
        lighting.sunElevation = sun.elevation
        lighting.sunColor = sun.color
        lighting.sunIntensity = sun.intensity * intensity
        lighting.ambientIntensity = sun.ambient
        return lighting
    }

    /// Where a lamp goes in the world for this camera and a subject of `size` metres.
    public static func position(of lamp: Lamp, eye: Vec3, subject: Vec3, size: Double) -> Vec3 {
        var toward = Vec3(eye.x - subject.x, 0, eye.z - subject.z)
        toward = toward.length > 1e-6 ? toward.normalized : Vec3(0, 0, 1)
        let right = Vec3.unitY.cross(toward).normalized
        let scale = max(size, 0.3)
        return subject + right * (lamp.offset.x * scale) + Vec3(0, lamp.offset.y * scale, 0) + toward * (lamp.offset.z * scale)
    }
}
