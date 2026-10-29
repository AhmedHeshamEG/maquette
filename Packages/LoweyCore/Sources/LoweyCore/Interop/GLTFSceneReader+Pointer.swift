import Foundation

/// Keyed numbers back in (X1): `KHR_animation_pointer` channels on a material, a light or a camera become keys on the
/// objects that use it, and the keys a Maquette file kept in its extras come back as they were.
extension GLTFSceneReader.Builder {
    /// The keys of a pointer channel; nil when the channel isn't one.
    func pointerTracks(_ channel: [String: Any], samplers: [[String: Any]], ids: inout IDFactory) throws -> (tracks: [Track], end: Double)? {
        guard let target = channel["target"] as? [String: Any], target["path"] as? String == "pointer" else { return nil }
        let pointer = ((target["extensions"] as? [String: Any])?["KHR_animation_pointer"] as? [String: Any])?["pointer"] as? String ?? ""
        guard let samplerIndex = channel["sampler"] as? Int, samplers.indices.contains(samplerIndex),
              let input = samplers[samplerIndex]["input"] as? Int, let output = samplers[samplerIndex]["output"] as? Int,
              let place = Self.place(pointer) else { return ([], 0) }
        let times = try GLTFReader.accessor(file, input).values
        let (values, components, _) = try GLTFReader.accessor(file, output)
        let interpolation = samplers[samplerIndex]["interpolation"] as? String ?? "LINEAR"
        let samples = Self.samples(times: times, values: values, components: components, cubic: interpolation == "CUBICSPLINE")
        let easing: Easing = interpolation == "STEP" ? .step : interpolation == "CUBICSPLINE" ? .easeInOut : .linear
        var tracks: [Track] = []
        for object in targets(place) {
            for (property, convert) in conversions(place, object: object) {
                let keys = samples.compactMap { sample in convert(sample.value).map { Keyframe(time: sample.time, value: $0, easing: easing) } }
                guard !keys.isEmpty, !(property == .opacity && keys.allSatisfy { $0.value.floatValue == 1 }) else { continue }
                tracks.append(Track(id: ids.next(), target: object, property: property, keyframes: keys))
            }
        }
        return (tracks, times.last ?? 0)
    }

    /// What a pointer names: a material's, camera's or light's number.
    enum Place: Equatable {
        case material(Int, String)
        case camera(Int, String)
        case light(Int, String)
    }

    static func place(_ pointer: String) -> Place? {
        let parts = pointer.split(separator: "/").map(String.init)
        if parts.count >= 3, parts[0] == "materials", let index = Int(parts[1]) { return .material(index, parts[2...].joined(separator: "/")) }
        if parts.count >= 3, parts[0] == "cameras", let index = Int(parts[1]) { return .camera(index, parts[2...].joined(separator: "/")) }
        if parts.count >= 5, parts[0] == "extensions", parts[1] == "KHR_lights_punctual", parts[2] == "lights", let index = Int(parts[3]) {
            return .light(index, parts[4...].joined(separator: "/"))
        }
        return nil
    }

    func targets(_ place: Place) -> [ObjectID] {
        switch place {
        case let .material(index, _): objectsOfMaterial[index] ?? []
        case let .camera(index, _): objectsOfCamera[index] ?? []
        case let .light(index, _): objectsOfLight[index] ?? []
        }
    }

    /// The properties a pointed number keys, each with how a sample becomes a value.
    func conversions(_ place: Place, object: ObjectID) -> [(PropertyKey, ([Double]) -> PropertyValue?)] {
        let srgb = SceneExport.srgb
        let colour: ([Double]) -> PropertyValue? = { $0.count >= 3 ? .color(.rgba(RGBA(srgb($0[0]), srgb($0[1]), srgb($0[2])))) : nil }
        let number: (Double) -> ([Double]) -> PropertyValue? = { scale in { $0.first.map { .float($0 * scale) } } }
        switch place {
        case let .material(_, path):
            switch path {
            case "pbrMetallicRoughness/baseColorFactor": return [(.color, colour), (.opacity, { $0.count == 4 ? .float($0[3]) : nil })]
            case "pbrMetallicRoughness/roughnessFactor": return [(.roughness, number(1))]
            case "pbrMetallicRoughness/metallicFactor": return [(.metallic, number(1))]
            case "extensions/KHR_materials_emissive_strength/emissiveStrength": return [(.emissiveIntensity, number(1))]
            case "emissiveFactor":
                // A glow up to white was written times its strength: the colour comes back without it.
                let strength = objects.first { $0.id == object }?.emissiveIntensity ?? 1
                let divisor = strength > 0 && strength < 1 ? strength : 1
                return [(.emissive, { colour($0.map { $0 / divisor }) })]
            default: return []
            }
        case let .camera(_, path):
            return path == "perspective/yfov" ? [(.fieldOfView, number(180 / .pi))] : []
        case let .light(_, path):
            switch path {
            case "color": return [(.lightColor, colour)]
            case "intensity": return [(.lightIntensity, number(1))]
            case "range": return [(.lightRange, number(1))]
            case "spot/outerConeAngle": return [(.spotAngle, number(360 / .pi))]
            default: return []
            }
        }
    }

    /// Each key's time and value (a cubic spline stores in-tangent, value, out-tangent per key).
    static func samples(times: [Double], values: [Double], components: Int, cubic: Bool) -> [(time: Double, value: [Double])] {
        times.enumerated().compactMap { index, time in
            let base = (cubic ? index * 3 + 1 : index) * components
            guard components > 0, base + components <= values.count else { return nil }
            return (time, Array(values[base ..< base + components]))
        }
    }

    /// The keys a Maquette file kept for itself, on the objects their ids name now.
    func keptTracks(ids: inout IDFactory) -> [Track] {
        guard let kept = ((file.json["extras"] as? [String: Any])?["maquette"] as? [String: Any])?["tracks"],
              let data = try? JSONSerialization.data(withJSONObject: kept),
              let tracks = try? JSONDecoder().decode([Track].self, from: data) else { return [] }
        return tracks.compactMap { track in
            objectOfWrittenID[track.target.raw].map { target in
                Track(id: ids.next(), target: target, property: track.property, keyframes: track.keyframes, cycle: track.cycle)
            }
        }
    }
}
