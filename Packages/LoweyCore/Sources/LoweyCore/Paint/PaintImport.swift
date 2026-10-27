import Foundation

/// A model's own pictures laid on its editable copy as paint (X1): the copy is laid flat as any shape is, each of its
/// pixels finds its point on the model's own surface, and the pictures there (times the material's factors) become a
/// first layer, "Model", with every map they had: colour, roughness, metal and glow. An empty layer sits above it. A
/// normal map is turned from the model's own tangent frames into the new surface's and becomes the paint's normals.
public enum PaintImport {
    /// The paint of an object whose surface is `mesh` (its own space, as `PaintSource.unshaped` gives it).
    public static func paint(onto mesh: MeshData, pictures: GLTFPictures, images: [Int: RGBAImage], size: Int = PaintSurface.defaultSize,
                             encode: (RGBAImage) -> Data = PNGCodec.encode) throws(PaintUnwrap.Failure) -> (paint: ObjectPaint, files: PaintOperations.Files) {
        let prepared = try PaintOperations.prepare(mesh: mesh, keepOwnUVs: false, size: size)
        let source = pictures.source
        let own = PaintUnwrap(source: (0 ..< UInt32(source.positions.count)).map { $0 }, positions: source.positions, uvs: source.uvs,
                              indices: source.indices)
        let map = PaintTransfer.correspondence(from: own, to: prepared.unwrap, size: size)
        var paint = prepared.paint, files = prepared.files
        var model = PaintLayer(id: "model", name: "Model")
        for (kind, picture) in maps(pictures, images: images, map: map, size: size) {
            for (tile, image) in PaintComposer.tiles(of: picture, surface: paint.surface) {
                let png = encode(image)
                let name = PaintFiles.tileName(for: png)
                files[name] = png
                model[kind, tile] = name
            }
        }
        if let normal = pictures.normal.flatMap({ images[$0] }), let paintMesh = prepared.unwrap.mesh(over: mesh) {
            let png = encode(normals(normal, source: source, paintMesh: paintMesh, size: size))
            let name = PaintFiles.tileName(for: png)
            files[name] = png
            paint.normalMap = name
        }
        guard !model.isEmpty else { return (paint, files) }
        paint.layers.insert(model, at: 0)
        return (paint, files)
    }

    /// Each map the pictures paint, on the new surface: colours in sRGB as paint keeps them, values as grey.
    static func maps(_ pictures: GLTFPictures, images: [Int: RGBAImage], map: [SIMD2<Float>?], size: Int) -> [(PaintMap, RGBAImage)] {
        let color = pictures.color.flatMap { images[$0] }
        let packed = pictures.metallicRoughness.flatMap { images[$0] }
        let glow = pictures.emissive.flatMap { images[$0] }
        let base = pictures.baseFactor.count >= 3 ? pictures.baseFactor : [1, 1, 1, 1]
        let emissive = pictures.emissiveFactor.count >= 3 ? pictures.emissiveFactor : [1, 1, 1]
        var result: [(PaintMap, RGBAImage)] = []
        if let color {
            result.append((.color, carried(color, map: map, size: size) { texel in
                RGBA(tinted(texel.r, by: base[0]), tinted(texel.g, by: base[1]), tinted(texel.b, by: base[2]), 1)
            }))
        }
        if let packed {
            result.append((.roughness, carried(packed, map: map, size: size) { texel in
                let value = min(max(texel.g * pictures.roughness, 0), 1)
                return RGBA(value, value, value, 1)
            }))
            result.append((.metal, carried(packed, map: map, size: size) { texel in
                let value = min(max(texel.b * pictures.metallic, 0), 1)
                return RGBA(value, value, value, 1)
            }))
        }
        if let glow {
            // The strength stays the object's (the reader set it); the map is the colour.
            let strongest = max(emissive[0], emissive[1], emissive[2], 1e-6)
            result.append((.glow, carried(glow, map: map, size: size) { texel in
                RGBA(tinted(texel.r, by: emissive[0] / strongest), tinted(texel.g, by: emissive[1] / strongest),
                     tinted(texel.b, by: emissive[2] / strongest), 1)
            }))
        }
        return result
    }

    /// A normal map on the model's own surface, each texel turned into the new surface's tangent frame (glTF's: x along u,
    /// y up the picture, z out), so the same bumps catch the light.
    static func normals(_ image: RGBAImage, source: MeshData, paintMesh: MeshData, size: Int) -> RGBAImage {
        var result = RGBAImage(width: size, height: size, color: RGBA(0.5, 0.5, 1, 1))
        var covered = [UInt8](repeating: 0, count: size * size)
        guard let bounds = source.bounds, source.normals.count == source.positions.count else { return result }
        let grid = TriangleGrid(source, cell: Float(max(bounds.size.length * 0.02, 1e-4)))
        let sourceFrames = NormalBake.triangleFrames(source), frames = NormalBake.triangleFrames(paintMesh)
        let hasNormals = paintMesh.normals.count == paintMesh.positions.count
        let scale = Float(size)
        var hint: Int?
        for face in 0 ..< paintMesh.triangleCount {
            let i = (0 ..< 3).map { Int(paintMesh.indices[face * 3 + $0]) }
            let p = i.map { paintMesh.positions[$0] }
            let flat = normalize3(cross3(p[1] - p[0], p[2] - p[0]), fallback: SIMD3<Float>(0, 1, 0))
            PaintRaster.triangle(paintMesh.uvs[i[0]] * scale, paintMesh.uvs[i[1]] * scale, paintMesh.uvs[i[2]] * scale, width: size, height: size) { x, y, w in
                let position = p[0] * w.x + p[1] * w.y + p[2] * w.z
                let normal = hasNormals ? normalize3(paintMesh.normals[i[0]] * w.x + paintMesh.normals[i[1]] * w.y + paintMesh.normals[i[2]] * w.z,
                                                     fallback: flat) : flat
                guard let hit = grid.closest(to: position, within: grid.cell * 2, hint: hint) else { return }
                hint = hit.triangle
                let s = (0 ..< 3).map { Int(source.indices[hit.triangle * 3 + $0]) }
                let uv = source.uvs[s[0]] * hit.weights.x + source.uvs[s[1]] * hit.weights.y + source.uvs[s[2]] * hit.weights.z
                let own = normalize3(source.normals[s[0]] * hit.weights.x + source.normals[s[1]] * hit.weights.y + source.normals[s[2]] * hit.weights.z,
                                     fallback: normal)
                let texel = image.sample(u: Double(uv.x), v: Double(uv.y))
                let t = SIMD3<Float>(Float(texel.r), Float(texel.g), Float(texel.b)) * 2 - 1
                let (tangent, bitangent) = NormalBake.orthonormal(sourceFrames[hit.triangle], normal: own)
                let detail = normalize3(tangent * t.x + bitangent * t.y + own * t.z, fallback: own)
                let (newTangent, newBitangent) = NormalBake.orthonormal(frames[face], normal: normal)
                let local = SIMD3<Float>(dot3(detail, newTangent), dot3(detail, newBitangent), dot3(detail, normal))
                result.write((y * size + x) * 4, local * 0.5 + 0.5)
                covered[y * size + x] = 1
            }
        }
        PaintRaster.dilate(&result, coverage: covered)
        return result
    }

    /// An sRGB value times a linear factor, back in sRGB.
    static func tinted(_ value: Double, by factor: Double) -> Double {
        guard factor != 1 else { return value }
        return ColorSpace.srgb(fromLinear: min(max(ColorSpace.linear(fromSRGB: value) * factor, 0), 1))
    }

    /// A picture sampled through the correspondence, each texel changed by `value` (pixels without a place stay clear).
    static func carried(_ image: RGBAImage, map: [SIMD2<Float>?], size: Int, value: (RGBA) -> RGBA) -> RGBAImage {
        var result = RGBAImage.clear(width: size, height: size)
        for index in 0 ..< min(map.count, size * size) {
            guard let uv = map[index] else { continue }
            result.setPixel(index % size, index / size, value(image.sample(u: Double(uv.x), v: Double(uv.y))))
        }
        return result
    }
}

public extension GLTFSceneReader.Result {
    /// Every pictured object's paint and the files it needs, as `setPaint` commands (to perform after the objects are
    /// in). `decode` reads a picture (the app's reads JPEG too; the portable one PNG); `surface` gives an object's mesh.
    func paints(in fragment: SceneFragment, size: Int = PaintSurface.defaultSize, decode: (ImportedTexture) -> RGBAImage? = { try? PNGCodec.decode($0.data) },
                encode: (RGBAImage) -> Data = PNGCodec.encode) -> (commands: [EditCommand], files: PaintOperations.Files) {
        var decoded: [Int: RGBAImage] = [:]
        for index in Set(pictures.values.flatMap(\.images)) where textures.indices.contains(index) {
            decoded[index] = decode(textures[index])
        }
        var commands: [EditCommand] = []
        var files: PaintOperations.Files = [:]
        for object in fragment.objects {
            guard let pictures = pictures[object.id], !pictures.images.isDisjoint(with: decoded.keys), let mesh = PaintSource.unshaped(of: object),
                  let made = try? PaintImport.paint(onto: mesh, pictures: pictures, images: decoded, size: size, encode: encode) else { continue }
            files.merge(made.files) { first, _ in first }
            commands.append(.setPaint(object.id, made.paint))
        }
        return (commands, files)
    }
}
