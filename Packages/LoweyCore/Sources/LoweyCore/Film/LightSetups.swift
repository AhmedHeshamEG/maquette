import Foundation

/// A light setup applied to a scene (F1): the mood it needs, the sun and sky, its lamps placed around the subject as
/// the camera sees it (spots and panels aimed at it), and the air. Re-lighting replaces the last setup's lamps. One
/// labelled batch, the same from the light's panel and from the bridge.
public enum LightSetups {
    public struct Options: Sendable {
        public var intensity: Double = 1
        /// −1 cooler … 1 warmer.
        public var warmth: Double = 0

        public init(intensity: Double = 1, warmth: Double = 0) {
            self.intensity = intensity
            self.warmth = warmth
        }
    }

    /// - Parameters:
    ///   - eye: where the camera is; `subject` and `size` where the subject is and how big (metres).
    public static func apply(_ recipe: LightRecipe, look current: Look, scope: LookScope, eye: Vec3, subject: Vec3, size: Double,
                             in scene: Scene, ids: inout IDFactory, options: Options = Options()) -> EditCommand {
        var look = current
        if let mood = recipe.mood { look = look.applying(mood) }
        look.lighting = recipe.lighting(from: look.lighting, eye: eye, subject: subject, intensity: options.intensity)
        if let air = recipe.atmosphere { look.atmosphere = air }
        var commands: [EditCommand] = [.setLook(look, scope: scope)]
        let old = scene.objects.values.filter { object in
            if case .light = object.kind { return LightRecipe.lampNames.contains(object.name) }
            return false
        }.map(\.id).sorted()
        if !old.isEmpty {
            // Their keys and cuts go with them.
            let cleaned = TimelineTools.removingReferences(to: Set(old), from: scene.timeline)
            if cleaned != scene.timeline { commands.append(.setTimeline(cleaned)) }
            commands.append(.delete(old))
        }
        var factory = ObjectFactory(ids: ids)
        var added: [SceneObject] = []
        for lamp in recipe.lamps {
            let color = options.warmth == 0 ? lamp.color : warmed(lamp.color, by: options.warmth)
            let position = LightRecipe.position(of: lamp, eye: eye, subject: subject, size: size)
            var object = factory.light(lamp.type, at: position, color: color)
            object.name = lamp.name
            object[.lightIntensity] = .float(lamp.intensity * options.intensity)
            object[.lightRange] = .float(lamp.range * max(size, 0.5))
            if lamp.type != .point {
                object.transform.rotation = BehaviorEvaluator.facing(subject - position, cameraStyle: true)
            }
            if let panel = lamp.size {
                object[.lightWidth] = .float(panel.x * max(size, 0.5))
                object[.lightHeight] = .float(panel.y * max(size, 0.5))
            }
            added.append(object)
        }
        ids = factory.ids
        commands += added.map { .insert(SceneFragment(object: $0), parent: nil, index: nil) }
        return .batch("Lighting: \(recipe.title)", commands)
    }

    /// Shifts a colour warmer (positive) or cooler (negative).
    public static func warmed(_ color: RGBA, by amount: Double) -> RGBA {
        let shift = min(max(amount, -1), 1) * 0.12
        return RGBA(min(max(color.r + shift, 0), 1), color.g, min(max(color.b - shift, 0), 1), color.a)
    }
}
