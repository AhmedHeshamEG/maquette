import Foundation

/// Lights and glow: what glTF's light extension holds, and a glow brighter than white (or keyed) through
/// `KHR_materials_emissive_strength`, so three.js, Blender and engines see the strength Maquette draws.
extension GLTFSceneWriter {
    mutating func addLight(_ object: SceneObject, type: LightType) -> Int {
        let color = object[.lightColor]?.colorValue?.resolved(in: look.palette) ?? .white
        var light: [String: Any] = [
            // glTF has no area light: a soft panel travels as a wide, soft spot (its size rides in the node's extras).
            "name": object.name, "type": type == .area ? LightType.spot.rawValue : type.rawValue,
            "color": [SceneExport.linear(color.r), SceneExport.linear(color.g), SceneExport.linear(color.b)],
            "intensity": object[.lightIntensity]?.floatValue ?? 1
        ]
        if type != .directional, let range = object[.lightRange]?.floatValue { light["range"] = range }
        if type == .spot {
            let outer = (object[.spotAngle]?.floatValue ?? 45) * .pi / 180 / 2
            light["spot"] = ["innerConeAngle": outer * Self.innerCone, "outerConeAngle": outer]
        } else if type == .area {
            light["spot"] = ["innerConeAngle": 0.0, "outerConeAngle": 80 * Double.pi / 180]
        }
        lights.append(light)
        return lights.count - 1
    }

    /// A spot's soft edge: its inner cone is this share of the outer one.
    static let innerCone = 0.8

    /// A glow up to white is the factor alone (every reader knows it); brighter, or keyed, the factor is the colour and
    /// the strength its own number.
    mutating func addGlow(_ emissive: RGBA, strength: Double, keyed: Bool, to material: inout [String: Any]) {
        let linear = SceneExport.linear
        let colour = [linear(emissive.r), linear(emissive.g), linear(emissive.b)]
        guard strength > 1 || keyed else {
            material["emissiveFactor"] = colour.map { $0 * strength }
            return
        }
        material["emissiveFactor"] = colour
        var extensions = material["extensions"] as? [String: Any] ?? [:]
        extensions["KHR_materials_emissive_strength"] = ["emissiveStrength": max(strength, 0)]
        material["extensions"] = extensions
        extensionsUsed.insert("KHR_materials_emissive_strength")
    }
}
