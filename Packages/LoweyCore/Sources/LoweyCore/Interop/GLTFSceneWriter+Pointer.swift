import Foundation

/// Keys on more than a place (X1): a material's colour, see-through, roughness, metal and glow, a light's colour,
/// strength, reach and cone, a camera's lens, as `KHR_animation_pointer` channels at the number they change. Readers
/// that don't know the extension skip those channels and play the rest; three.js plays them through the folder's
/// `pointer.js`, Maquette reads them back as keys.
extension GLTFSceneWriter {
    static let pointerExtension = "KHR_animation_pointer"

    /// Adds the channels for a keyed number that has a place in the file; false when it has none here.
    mutating func addPointer(_ track: Track, samplers: inout [[String: Any]], channels: inout [[String: Any]]) -> Bool {
        let id = track.target
        guard let object = scene.objects[id] else { return false }
        let keyed = animated[id] ?? []
        switch track.property {
        case .color, .opacity:
            // One channel carries both: the colour with its see-through as alpha.
            if track.property == .opacity, keyed.contains(.color) { return true }
            let targets = (materialsOf[id] ?? []).filter { !hasTexture($0, "baseColorTexture") }
            let values = sampled(colourTracks(id)) { time in baseColour(object, at: time) }
            return addMaterialChannels(targets, path: "pbrMetallicRoughness/baseColorFactor", values, width: 4, samplers: &samplers, channels: &channels)
        case .roughness, .metallic:
            let targets = (materialsOf[id] ?? []).filter { !hasTexture($0, "metallicRoughnessTexture") }
            let path = track.property == .roughness ? "pbrMetallicRoughness/roughnessFactor" : "pbrMetallicRoughness/metallicFactor"
            let values = sampled([track]) { [Float(track.value(at: $0)?.floatValue ?? 0)] }
            return addMaterialChannels(targets, path: path, values, width: 1, samplers: &samplers, channels: &channels)
        case .emissive:
            let strength = keyed.contains(.emissiveIntensity) ? 1 : min(object.emissiveIntensity, 1)
            let palette = look.palette
            let values = sampled([track]) { linearRGB(track.value(at: $0, palette: palette)?.colorValue).map { $0 * Float(strength) } }
            return addMaterialChannels(materialsOf[id] ?? [], path: "emissiveFactor", values, width: 3, samplers: &samplers, channels: &channels)
        case .emissiveIntensity:
            let values = sampled([track]) { [Float(max(track.value(at: $0)?.floatValue ?? 0, 0))] }
            return addMaterialChannels(materialsOf[id] ?? [], path: "extensions/KHR_materials_emissive_strength/emissiveStrength", values,
                                       width: 1, samplers: &samplers, channels: &channels)
        default:
            return addLightOrLens(track, samplers: &samplers, channels: &channels)
        }
    }

    mutating func addLightOrLens(_ track: Track, samplers: inout [[String: Any]], channels: inout [[String: Any]]) -> Bool {
        let number: (Double) -> Float = { Float(track.value(at: $0)?.floatValue ?? 0) }
        if track.property == .fieldOfView, let camera = cameraOf[track.target] {
            addChannel(sampled([track]) { [number($0) * .pi / 180] }, pointer: "/cameras/\(camera)/perspective/yfov", width: 1,
                       samplers: &samplers, channels: &channels)
            return true
        }
        guard let light = lightOf[track.target] else { return false }
        let base = "/extensions/KHR_lights_punctual/lights/\(light)/"
        switch track.property {
        case .lightColor:
            let palette = look.palette
            addChannel(sampled([track]) { linearRGB(track.value(at: $0, palette: palette)?.colorValue) }, pointer: base + "color", width: 3,
                       samplers: &samplers, channels: &channels)
        case .lightIntensity:
            addChannel(sampled([track]) { [number($0)] }, pointer: base + "intensity", width: 1, samplers: &samplers, channels: &channels)
        case .lightRange:
            addChannel(sampled([track]) { [number($0)] }, pointer: base + "range", width: 1, samplers: &samplers, channels: &channels)
        case .spotAngle:
            guard scene.objects[track.target]?.kind == .light(.spot) else { return false }
            let outer: (Double) -> Float = { number($0) * .pi / 360 }
            addChannel(sampled([track]) { [outer($0)] }, pointer: base + "spot/outerConeAngle", width: 1, samplers: &samplers, channels: &channels)
            addChannel(sampled([track]) { [outer($0) * Float(Self.innerCone)] }, pointer: base + "spot/innerConeAngle", width: 1,
                       samplers: &samplers, channels: &channels)
        default:
            return false
        }
        return true
    }

    // MARK: Values

    /// The tracks that change an object's base colour: its colour and its see-through.
    func colourTracks(_ id: ObjectID) -> [Track] {
        scene.timeline.tracks.filter { $0.target == id && ($0.property == .color || $0.property == .opacity) }
    }

    /// The base colour at a moment, linear, its alpha the colour's own times the see-through (as `SceneExport.material`).
    func baseColour(_ object: SceneObject, at time: Double) -> [Float] {
        let tracks = colourTracks(object.id)
        let colour = tracks.first { $0.property == .color }?.value(at: time, palette: look.palette)?.colorValue ?? object.color
        let rgba = colour?.resolved(in: look.palette) ?? .blockout
        let opacity = tracks.first { $0.property == .opacity }?.value(at: time)?.floatValue ?? object[.opacity]?.floatValue ?? 1
        let linear = SceneExport.linear
        return [Float(linear(rgba.r)), Float(linear(rgba.g)), Float(linear(rgba.b)), Float(rgba.a * min(max(opacity, 0), 1))]
    }

    func linearRGB(_ colour: ColorValue?) -> [Float] {
        let rgba = colour?.resolved(in: look.palette) ?? .black
        let linear = SceneExport.linear
        return [Float(linear(rgba.r)), Float(linear(rgba.g)), Float(linear(rgba.b))]
    }

    func hasTexture(_ material: Int, _ key: String) -> Bool {
        (materials[material]["pbrMetallicRoughness"] as? [String: Any])?[key] != nil
    }

    // MARK: Channels

    /// Keys sampled at the times their tracks need, with how they're played between.
    struct Sampled {
        var times: [Double]
        var interpolation: String
        var values: [Float]
    }

    func sampled(_ tracks: [Track], value: (Double) -> [Float]) -> Sampled {
        let (times, interpolation) = Self.times(tracks, fps: Double(max(scene.timeline.fps, 1)))
        return Sampled(times: times, interpolation: interpolation, values: times.flatMap(value))
    }

    /// The same values to each material (an object with several pieces has a material per piece).
    mutating func addMaterialChannels(_ targets: [Int], path: String, _ sampled: Sampled, width: Int, samplers: inout [[String: Any]],
                                      channels: inout [[String: Any]]) -> Bool {
        guard !targets.isEmpty, let sampler = addSampler(sampled, width: width, samplers: &samplers) else { return false }
        for material in targets {
            channels.append(Self.pointerChannel(sampler, "/materials/\(material)/\(path)"))
        }
        return true
    }

    mutating func addChannel(_ sampled: Sampled, pointer: String, width: Int, samplers: inout [[String: Any]], channels: inout [[String: Any]]) {
        guard let sampler = addSampler(sampled, width: width, samplers: &samplers) else { return }
        channels.append(Self.pointerChannel(sampler, pointer))
    }

    mutating func addSampler(_ sampled: Sampled, width: Int, samplers: inout [[String: Any]]) -> Int? {
        let times = sampled.times
        guard !times.isEmpty, sampled.values.count == times.count * width else { return nil }
        let input = addAccessor(Self.floats(times.map(Float.init)), target: nil, count: times.count, type: "SCALAR",
                                extra: ["min": [times.first ?? 0], "max": [times.last ?? 0]])
        let type = [1: "SCALAR", 3: "VEC3", 4: "VEC4"][width] ?? "SCALAR"
        let output = addAccessor(Self.floats(sampled.values), target: nil, count: times.count, type: type)
        samplers.append(["input": input, "output": output, "interpolation": sampled.interpolation])
        extensionsUsed.insert(Self.pointerExtension)
        return samplers.count - 1
    }

    static func pointerChannel(_ sampler: Int, _ pointer: String) -> [String: Any] {
        ["sampler": sampler, "target": ["path": "pointer", "extensions": [pointerExtension: ["pointer": pointer]]]]
    }

    /// Times for several tracks played as one: every time either needs, held only when all of them hold.
    static func times(_ tracks: [Track], fps: Double) -> ([Double], String) {
        let each = tracks.map { times($0, fps: fps) }
        guard each.count > 1 else { return each.first ?? ([], "LINEAR") }
        let held = each.allSatisfy { $0.1 == "STEP" }
        return (Array(Set(each.flatMap(\.0))).sorted(), held ? "STEP" : "LINEAR")
    }

    // MARK: Kept

    /// The keys glTF can't hold, as Maquette's own tracks (their targets are the nodes' `extras.maquette.id`).
    func keptTracksJSON() -> Any? {
        let kept = keptTracks.filter { nodeOf[$0.target] != nil }
        guard !kept.isEmpty, let data = try? JSONEncoder().encode(kept) else { return nil }
        return try? JSONSerialization.jsonObject(with: data)
    }
}
