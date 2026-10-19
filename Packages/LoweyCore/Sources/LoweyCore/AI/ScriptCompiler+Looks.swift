import Foundation

/// L2 on the `look` and `effect` verbs: what the ground is made of, the Finish any Look can take, and where the drawn
/// effects aim.
extension ScriptState {
    /// `"ground": "rock" | … | "plain"` and `"finish": {"misregistration": true, "boil": 0.4, "benDay": 0.6,
    /// "texture": "newsprint", "textureStrength": 0.7}`.
    mutating func lookExtras(_ action: JSONValue, into look: inout Look) throws {
        if let ground = string(action, "ground") {
            if ground == "plain" || ground == "none" {
                look.ground = look.ground.made(of: nil)
            } else if let surface = GroundSurface(rawValue: ground) {
                look.ground = look.ground.made(of: surface)
            } else {
                throw fail("unknown ground “\(ground)” (plain, \(GroundSurface.allCases.map(\.rawValue).joined(separator: ", ")))")
            }
        }
        guard case .object? = action["finish"], let finish = action["finish"] else { return }
        if let on = finish["misregistration"]?.boolValue { look.post.misregistration = on }
        if let boil = finish["boil"]?.numberValue { look.post.boil = min(max(boil, 0), 1) }
        if let dots = finish["benDay"]?.numberValue { look.post.benDay = min(max(dots, 0), 1) }
        if let name = finish["texture"]?.stringValue {
            guard let texture = PostSettings.Texture(rawValue: name) else {
                throw fail("unknown texture “\(name)” (\(PostSettings.Texture.allCases.map(\.rawValue).joined(separator: ", ")))")
            }
            look.post.texture = texture
        }
        if let strength = finish["textureStrength"]?.numberValue { look.post.textureStrength = min(max(strength, 0), 1) }
    }

    /// A drawn effect's aim: `"center": [0.3, 0.6]` (0…1 from the frame's top left) or `"target": "Hero"` (it follows).
    mutating func aim(_ action: JSONValue, _ effect: inout ScreenEffect) throws {
        if let point = action["center"]?.arrayValue?.compactMap(\.numberValue), point.count == 2 {
            effect.center = Vec2(min(max(point[0], 0), 1), min(max(point[1], 0), 1))
        }
        if action["target"] != nil {
            effect.target = try target(action["target"])
        }
    }
}
