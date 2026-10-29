import Foundation

/// three.js clips as keys: each track (`Lantern.position`, `Lantern.material.color`, `Spot.angle`, `Shot.fov`) on the
/// thing it names, by name or uuid.
extension ThreeReaderBuilder {
    func tracks(ids: inout IDFactory) -> ([Track], Double) {
        var result: [Track] = []
        var end = 0.0
        for clip in json["animations"] as? [[String: Any]] ?? [] {
            for track in clip["tracks"] as? [[String: Any]] ?? [] {
                if let turns = boneTracks(track, ids: &ids) {
                    result += turns
                    end = max(end, turns.compactMap { $0.keyframes.last?.time }.max() ?? 0)
                    continue
                }
                guard let made = self.track(track, ids: &ids) else { continue }
                end = max(end, made.keyframes.last?.time ?? 0)
                result.append(made)
            }
        }
        return (result, end)
    }

    func track(_ source: [String: Any], ids: inout IDFactory) -> Track? {
        guard let name = source["name"] as? String, let times = GLTFReader.numbers(source["times"]),
              let values = GLTFReader.numbers(source["values"]), !times.isEmpty else { return nil }
        // "node.property" or "node.material.property"; the node is a name or a uuid.
        let parts = name.split(separator: ".").map(String.init)
        guard parts.count >= 2, let target = objectOf[parts[0]] ?? named[parts[0]],
              let object = objects.first(where: { $0.id == target }) else { return nil }
        let path = parts.dropFirst().joined(separator: ".")
        guard let (property, width, convert) = Self.property(path, kind: object.kind) else { return nil }
        let easing: Easing = switch source["interpolation"] as? Int {
        case 2300: .step
        case 2302: .easeInOut
        default: .linear
        }
        let keys = times.enumerated().compactMap { index, time -> Keyframe? in
            let start = index * width
            guard start + width <= values.count, let value = convert(Array(values[start ..< start + width])) else { return nil }
            return Keyframe(time: time, value: value, easing: easing)
        }
        guard !keys.isEmpty else { return nil }
        return Track(id: ids.next(), target: target, property: property, keyframes: keys)
    }

    /// What a three.js property path keys here, how many numbers a key holds, and how they become a value.
    static func property(_ path: String, kind: ObjectKind) -> (PropertyKey, Int, ([Double]) -> PropertyValue?)? {
        let srgb = SceneExport.srgb
        let colour: ([Double]) -> PropertyValue? = { .color(.rgba(RGBA(srgb($0[0]), srgb($0[1]), srgb($0[2])))) }
        let number: (Double) -> ([Double]) -> PropertyValue? = { scale in { .float($0[0] * scale) } }
        let isLight = if case .light = kind {
            true
        } else {
            false
        }
        switch path {
        case "position": return (.position, 3, { .vec3(Vec3($0[0], $0[1], $0[2])) })
        case "quaternion": return (.rotation, 4, { .quat(Quat(x: $0[0], y: $0[1], z: $0[2], w: $0[3]).normalized) })
        case "scale": return (.scale, 3, { .vec3(Vec3($0[0], $0[1], $0[2])) })
        case "visible": return (.visible, 1, { .bool($0[0] != 0) })
        case "material.color": return (.color, 3, colour)
        case "material.opacity": return (.opacity, 1, number(1))
        case "material.roughness": return (.roughness, 1, number(1))
        case "material.metalness": return (.metallic, 1, number(1))
        case "material.emissive": return (.emissive, 3, colour)
        case "material.emissiveIntensity": return (.emissiveIntensity, 1, number(1))
        case "color" where isLight: return (.lightColor, 3, colour)
        case "intensity" where isLight: return (.lightIntensity, 1, number(1))
        case "distance" where isLight: return (.lightRange, 1, number(1))
        case "angle" where isLight: return (.spotAngle, 1, number(360 / .pi))
        case "fov" where kind == .camera: return (.fieldOfView, 1, number(1))
        default: return nil
        }
    }
}
