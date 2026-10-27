import Foundation

/// Pictures in three.js's scene format (X1): a material's `map`, `roughnessMap` / `metalnessMap` and `emissiveMap`, when
/// the file carries their images (as `toJSON` does, data URLs), are laid on the editable copy as paint like a glTF's
/// (`PaintImport`). The uvs are moved as three.js moves them: its texture's repeat, offset, rotation and centre, then
/// flipped when the picture is (`flipY`, three.js's default; glTF's pictures aren't).
extension ThreeReaderBuilder {
    /// The pictures on a buffer geometry's surface, with the images they need added to `textures`.
    mutating func pictures(_ material: [String: Any], geometry uuid: String?) -> GLTFPictures? {
        let slots = ["map", "roughnessMap", "emissiveMap"].map { material[$0] as? String }
        let metal = material["metalnessMap"] as? String
        guard slots.contains(where: { $0 != nil }) || metal != nil, let uuid, let geometry = geometries[uuid],
              geometry["type"] as? String == "BufferGeometry", let surface = buffer(geometry["data"] as? [String: Any] ?? [:], uvs: true),
              surface.uvs.count == surface.positions.count else { return nil }
        let textureList = Self.byUUID(json["textures"])
        // The surface's uvs as the colour's texture places them (else the first picture's).
        guard let placing = (slots + [metal]).lazy.compactMap({ $0.flatMap { textureList[$0] } }).first else { return nil }
        var moved = surface
        moved.uvs = surface.uvs.map { Self.placed($0, by: placing) }
        let indices = slots.map { $0.flatMap { textureIndex($0, textures: textureList) } }
        let color = (material["color"] as? Int).map(Self.colour) ?? RGBA(1, 1, 1)
        let emissive = (material["emissive"] as? Int).map(Self.colour) ?? RGBA(0, 0, 0)
        let glow = material["emissiveIntensity"] as? Double ?? 1
        return GLTFPictures(source: moved, color: indices[0], metallicRoughness: indices[1] ?? metal.flatMap { textureIndex($0, textures: textureList) },
                            emissive: indices[2], normal: nil, baseFactor: [color.r, color.g, color.b].map(ColorSpace.linear(fromSRGB:)) + [1],
                            emissiveFactor: [emissive.r, emissive.g, emissive.b].map { ColorSpace.linear(fromSRGB: $0) * glow },
                            roughness: material["roughness"] as? Double ?? 1, metallic: material["metalness"] as? Double ?? 0)
    }

    /// A texture's image as an index into `textures` (nil when the file doesn't carry it as a data URL).
    mutating func textureIndex(_ uuid: String, textures list: [String: [String: Any]]) -> Int? {
        guard let image = list[uuid]?["image"] as? String else { return nil }
        if let known = imageIndex[image] { return known }
        guard let url = Self.byUUID(json["images"])[image]?["url"] as? String, url.hasPrefix("data:"), let comma = url.firstIndex(of: ","),
              let data = Data(base64Encoded: String(url[url.index(after: comma)...])) else { return nil }
        let mime = url.dropFirst(5).prefix { $0 != ";" && $0 != "," }
        textures.append(ImportedTexture(data: data, mimeType: String(mime)))
        imageIndex[image] = textures.count - 1
        return textures.count - 1
    }

    /// A uv as three.js's texture matrix moves it (`Texture.updateMatrix`), flipped for a picture uploaded upside down.
    static func placed(_ uv: SIMD2<Float>, by texture: [String: Any]) -> SIMD2<Float> {
        let repeats = GLTFReader.numbers(texture["repeat"]) ?? [1, 1], offset = GLTFReader.numbers(texture["offset"]) ?? [0, 0]
        let centre = GLTFReader.numbers(texture["center"]) ?? [0, 0]
        let rotation = texture["rotation"] as? Double ?? 0
        guard repeats.count == 2, offset.count == 2, centre.count == 2 else { return uv }
        let (c, s) = (cos(rotation), sin(rotation))
        let x = Double(uv.x) - centre[0], y = Double(uv.y) - centre[1]
        var u = repeats[0] * (c * x + s * y) + centre[0] + offset[0]
        var v = repeats[1] * (-s * x + c * y) + centre[1] + offset[1]
        if texture["flipY"] as? Bool ?? true { v = 1 - v }
        u = u.isFinite ? u : 0
        return SIMD2<Float>(Float(u), Float(v.isFinite ? v : 0))
    }
}
