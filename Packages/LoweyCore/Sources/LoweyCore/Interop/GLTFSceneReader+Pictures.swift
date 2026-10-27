import Foundation

/// A glTF piece's pictures, kept to be laid on its editable copy as paint (`PaintImport`): the piece's own triangles and
/// uvs (in the object's space, any `KHR_texture_transform` applied), which image each map shows, and the factors that
/// multiply them (as written: colours linear).
public struct GLTFPictures: Sendable {
    public var source: MeshData
    public var color: Int?
    /// Roughness in green, metal in blue (glTF's packing).
    public var metallicRoughness: Int?
    public var emissive: Int?
    /// Tangent-space normals, as glTF reads them.
    public var normal: Int?
    public var baseFactor: [Double]
    public var emissiveFactor: [Double]
    public var roughness: Double
    public var metallic: Double
    /// How strongly, and which way, the normal picture's red and green lean (glTF's `scale`; three.js's `normalScale`,
    /// turned to glTF's way up).
    public var normalScale = SIMD2<Float>(1, 1)

    /// The images it needs, by image index.
    public var images: Set<Int> {
        Set([color, metallicRoughness, emissive, normal].compactMap { $0 })
    }
}

extension GLTFSceneReader.Builder {
    /// The pictures a material shows, with the piece they lie on; nil when it shows none or the piece has no uvs.
    func pictures(of materialIndex: Int, source: MeshData) -> GLTFPictures? {
        let materials = file.array("materials")
        guard materials.indices.contains(materialIndex), let factors = material(materialIndex) else { return nil }
        let json = materials[materialIndex]
        let pbr = json["pbrMetallicRoughness"] as? [String: Any] ?? [:]
        let infos = [pbr["baseColorTexture"], pbr["metallicRoughnessTexture"], json["emissiveTexture"], json["normalTexture"]].map { $0 as? [String: Any] }
        let images = infos.map { info in info.flatMap { $0["index"] as? Int }.flatMap { GLTFMeshReader.imageIndex(file, texture: $0) } }
        guard images.contains(where: { $0 != nil }), source.uvs.count == source.positions.count, !source.isEmpty else { return nil }
        var moved = source
        // One transform for the piece: the colour's, else the first map's that has one.
        if let transform = infos.lazy.compactMap({ ($0?["extensions"] as? [String: Any])?["KHR_texture_transform"] as? [String: Any] }).first {
            moved.uvs = moved.uvs.map { Self.transformed($0, by: transform) }
        }
        let strength = Float(infos[3]?["scale"] as? Double ?? 1)
        return GLTFPictures(source: moved, color: images[0], metallicRoughness: images[1], emissive: images[2], normal: images[3], baseFactor: factors.base,
                            emissiveFactor: GLTFReader.numbers(json["emissiveFactor"]) ?? [0, 0, 0], roughness: factors.roughness,
                            metallic: factors.metallic, normalScale: SIMD2(strength, strength))
    }

    /// `KHR_texture_transform`: scale, then rotate, then offset (the extension's T · R · S).
    static func transformed(_ uv: SIMD2<Float>, by transform: [String: Any]) -> SIMD2<Float> {
        let offset = GLTFReader.numbers(transform["offset"]) ?? [0, 0]
        let scale = GLTFReader.numbers(transform["scale"]) ?? [1, 1]
        let rotation = transform["rotation"] as? Double ?? 0
        guard offset.count == 2, scale.count == 2 else { return uv }
        let u = Double(uv.x) * scale[0], v = Double(uv.y) * scale[1]
        let (sine, cosine) = (sin(rotation), cos(rotation))
        return SIMD2<Float>(Float(offset[0] + cosine * u + sine * v), Float(offset[1] - sine * u + cosine * v))
    }
}
