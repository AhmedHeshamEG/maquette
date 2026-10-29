import Foundation

/// Lights, glow and fur: what glTF's light extension holds, a glow brighter than white (or keyed) through
/// `KHR_materials_emissive_strength`, so three.js, Blender and engines see the strength Maquette draws, and fur as cards
/// or shells.
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

    /// Fur in a 3D file (D-355): hair cards as they are, or a few shells (8: enough to read as fur, light enough for an
    /// engine), each cut out by the strand picture, in the thing's own colour.
    static func furParts(_ fur: FurSettings, on surface: MeshData, name: String, material: ExportMaterial) -> [GLTFScene.LocalPart] {
        var strands = material
        strands.texture = nil
        strands.maps = ExportMaps()
        strands.roughness = 0.9
        switch fur.style {
        case .cards:
            strands.cutout = PNGCodec.encode(FurGeometry.strandPicture(cards: true))
            let cards = FurGeometry.cards(on: surface, fur: fur)
            return cards.isEmpty ? [] : [GLTFScene.LocalPart(name: "\(name) hair cards", mesh: cards, material: strands)]
        case .shells:
            strands.cutout = PNGCodec.encode(FurGeometry.strandPicture(cards: false))
            return FurGeometry.shells(of: surface, fur: fur, count: 8).enumerated().map { index, shell in
                GLTFScene.LocalPart(name: "\(name) fur \(index + 1)", mesh: shell, material: strands)
            }
        }
    }
}
