import Foundation

/// The file's clips as three.js `AnimationClip`s: node motion, morph weights, and each `KHR_animation_pointer` channel
/// as the track three.js plays on its own (`Lantern.material.color`, `Spot.angle`, `Shot.fov`).
extension ThreeJSONBuilder {
    func animations() -> [[String: Any]] {
        file.array("animations").enumerated().compactMap { number, animation in
            let samplers = animation["samplers"] as? [[String: Any]] ?? []
            var tracks: [[String: Any]] = []
            var duration = 0.0
            for channel in animation["channels"] as? [[String: Any]] ?? [] {
                guard let samplerIndex = channel["sampler"] as? Int, samplers.indices.contains(samplerIndex),
                      let keys = keys(samplers[samplerIndex]) else { continue }
                duration = max(duration, keys.times.last ?? 0)
                tracks += self.tracks(channel["target"] as? [String: Any] ?? [:], keys: keys)
            }
            guard !tracks.isEmpty else { return nil }
            return ["name": animation["name"] as? String ?? "animation_\(number)", "duration": duration, "tracks": tracks,
                    "uuid": "maquette-clip-\(number)", "blendMode": 2500]
        }
    }

    struct Keys {
        var times: [Double]
        /// One value (of `width` numbers) per time.
        var values: [[Double]]
        var held: Bool
    }

    func keys(_ sampler: [String: Any]) -> Keys? {
        guard let input = sampler["input"] as? Int, let output = sampler["output"] as? Int,
              let times = try? GLTFReader.accessor(file, input).values, let out = try? GLTFReader.accessor(file, output) else { return nil }
        let interpolation = sampler["interpolation"] as? String ?? "LINEAR"
        let width = times.isEmpty ? 0 : out.values.count / (times.count * (interpolation == "CUBICSPLINE" ? 3 : 1))
        let samples = GLTFSceneReader.Builder.samples(times: times, values: out.values, components: width, cubic: interpolation == "CUBICSPLINE")
        guard !samples.isEmpty else { return nil }
        return Keys(times: samples.map(\.time), values: samples.map(\.value), held: interpolation == "STEP")
    }

    func tracks(_ target: [String: Any], keys: Keys) -> [[String: Any]] {
        if let node = target["node"] as? Int {
            let property: (String, String)? = switch target["path"] as? String {
            case "translation": ("position", "vector")
            case "rotation": ("quaternion", "quaternion")
            case "scale": ("scale", "vector")
            case "weights": ("morphTargetInfluences", "number")
            default: nil
            }
            return property.map { [track("\(nodeName(node)).\($0.0)", type: $0.1, keys: keys)] } ?? []
        }
        let pointer = ((target["extensions"] as? [String: Any])?["KHR_animation_pointer"] as? [String: Any])?["pointer"] as? String ?? ""
        guard let place = GLTFSceneReader.Builder.place(pointer) else { return [] }
        switch place {
        case let .material(index, path):
            return (meshNamesOfMaterial[index] ?? []).flatMap { materialTracks($0, path: path, keys: keys) }
        case let .light(index, path):
            let property: (String, String, (Double) -> Double)? = switch path {
            case "color": ("color", "color", { $0 })
            case "intensity": ("intensity", "number", { $0 })
            case "range": ("distance", "number", { $0 })
            case "spot/outerConeAngle": ("angle", "number", { $0 })
            default: nil
            }
            guard let property else { return [] }
            return (namesOfLight[index] ?? []).map { track("\($0).\(property.0)", type: property.1, keys: keys, map: property.2) }
        case let .camera(index, path):
            guard path == "perspective/yfov" else { return [] }
            return (namesOfCamera[index] ?? []).map { track("\($0).fov", type: "number", keys: keys) { $0 * 180 / .pi } }
        }
    }

    func materialTracks(_ mesh: String, path: String, keys: Keys) -> [[String: Any]] {
        switch path {
        case "pbrMetallicRoughness/baseColorFactor":
            var result = [track("\(mesh).material.color", type: "color", keys: Keys(times: keys.times, values: keys.values.map { Array($0.prefix(3)) },
                                                                                    held: keys.held))]
            let alpha = keys.values.map { $0.count > 3 ? $0[3] : 1 }
            if alpha.contains(where: { $0 < 1 }) {
                result.append(track("\(mesh).material.opacity", type: "number", keys: Keys(times: keys.times, values: alpha.map { [$0] }, held: keys.held)))
            }
            return result
        case "pbrMetallicRoughness/roughnessFactor": return [track("\(mesh).material.roughness", type: "number", keys: keys)]
        case "pbrMetallicRoughness/metallicFactor": return [track("\(mesh).material.metalness", type: "number", keys: keys)]
        case "emissiveFactor": return [track("\(mesh).material.emissive", type: "color", keys: keys)]
        case "extensions/KHR_materials_emissive_strength/emissiveStrength": return [track("\(mesh).material.emissiveIntensity", type: "number", keys: keys)]
        default: return []
        }
    }

    /// A three.js track; held keys use `InterpolateDiscrete` (2300).
    func track(_ name: String, type: String, keys: Keys, map: (Double) -> Double = { $0 }) -> [String: Any] {
        var json: [String: Any] = ["name": name, "type": type, "times": Self.rounded(keys.times),
                                   "values": Self.rounded(keys.values.flatMap { $0.map(map) })]
        if keys.held { json["interpolation"] = 2300 }
        return json
    }
}
