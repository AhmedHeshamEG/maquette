import Foundation

/// The pictures a fill layer is made of (D-340): one per map it writes, over the whole surface. A plain colour (or a
/// material with nothing varying) is one tile repeated, so it costs one small file per map whatever the size.
public enum PaintFills {
    /// What a fill needs besides the surface: the shape's wear bake (for wear) and the decoded pictures of an imported
    /// material set.
    public struct Inputs: Sendable {
        public var wear: WearBake?
        public var pictures: MaterialPictureSource?

        public init(wear: WearBake? = nil, pictures: MaterialPictureSource? = nil) {
            self.wear = wear
            self.pictures = pictures
        }
    }

    /// One picture per map the fill writes, at the surface's size (texels no triangle covers are left clear).
    public static func images(_ fill: PaintFill, paintMesh: MeshData, size: Int, inputs: Inputs = Inputs()) -> [PaintMap: RGBAImage] {
        switch fill {
        case let .color(color):
            return [.color: RGBAImage(width: size, height: size, color: RGBA(color.r, color.g, color.b, 1))]
        case let .material(material):
            if material.pattern == .none, material.pictures == nil { return uniform(material, size: size) }
            return materialImages(material, paintMesh: paintMesh, size: size, pictures: inputs.pictures)
        case let .wear(wear):
            let bake = inputs.wear ?? WearBake.make(paintMesh)
            return wearImages(wear, bake: bake, paintMesh: paintMesh, size: size)
        }
    }

    /// A material with no pattern: every map one value everywhere.
    static func uniform(_ material: PaintMaterial, size: Int) -> [PaintMap: RGBAImage] {
        var result: [PaintMap: RGBAImage] = [
            .color: RGBAImage(width: size, height: size, color: RGBA(material.color.r, material.color.g, material.color.b, 1)),
            .roughness: RGBAImage(width: size, height: size, color: RGBA(material.roughness, material.roughness, material.roughness, 1)),
            .metal: RGBAImage(width: size, height: size, color: RGBA(material.metal, material.metal, material.metal, 1))
        ]
        if material.maps.contains(.glow) {
            result[.glow] = RGBAImage(width: size, height: size, color: RGBA(material.glow.r, material.glow.g, material.glow.b, 1))
        }
        return result
    }

    static func materialImages(_ material: PaintMaterial, paintMesh: MeshData, size: Int, pictures: MaterialPictureSource?) -> [PaintMap: RGBAImage] {
        let maps = material.maps
        var images = Dictionary(uniqueKeysWithValues: maps.map { ($0, RGBAImage.clear(width: size, height: size)) })
        var color = images[.color] ?? .clear(width: size, height: size)
        var rough = images[.roughness] ?? .clear(width: size, height: size)
        var metal = images[.metal] ?? .clear(width: size, height: size)
        var glow = images[.glow]
        var bumps = images[.bumps]
        SurfaceTexels.visit(paintMesh, size: size) { x, y, position, normal in
            let sample = material.sample(at: position, normal: normal, pictures: pictures)
            let index = (y * size + x) * 4
            color.write(index, sample.color)
            rough.write(index, SIMD3<Float>(repeating: sample.roughness))
            metal.write(index, SIMD3<Float>(repeating: sample.metal))
            glow?.write(index, sample.glow)
            bumps?.write(index, SIMD3<Float>(repeating: sample.height))
        }
        images[.color] = color
        images[.roughness] = rough
        images[.metal] = metal
        images[.glow] = glow
        images[.bumps] = bumps
        return images
    }

    /// Wear: the wear's colour and roughness wherever it gathers, as much as `amount` asks, broken up by noise so it
    /// never reads as a gradient.
    static func wearImages(_ wear: PaintWear, bake: WearBake, paintMesh: MeshData, size: Int) -> [PaintMap: RGBAImage] {
        var color = RGBAImage.clear(width: size, height: size)
        var rough = RGBAImage.clear(width: size, height: size)
        let breakup = 8 / SurfaceTexels.diagonal(paintMesh)
        let tint = SIMD3<Float>(Float(wear.color.r), Float(wear.color.g), Float(wear.color.b))
        let roughness = Float(wear.roughness)
        let amount = Float(wear.amount)
        let seed = SIMD3<Float>(Float(wear.seed % 977), Float(wear.seed % 101) * 3.1, 0)
        let scale = Float(size)
        for face in 0 ..< paintMesh.triangleCount {
            let i = (Int(paintMesh.indices[face * 3]), Int(paintMesh.indices[face * 3 + 1]), Int(paintMesh.indices[face * 3 + 2]))
            let uv = (paintMesh.uvs[i.0], paintMesh.uvs[i.1], paintMesh.uvs[i.2])
            let p = (paintMesh.positions[i.0], paintMesh.positions[i.1], paintMesh.positions[i.2])
            PaintRaster.triangle(uv.0 * scale, uv.1 * scale, uv.2 * scale, width: size, height: size) { x, y, w in
                let at = uv.0 * w.x + uv.1 * w.y + uv.2 * w.z
                let position = p.0 * w.x + p.1 * w.y + p.2 * w.z
                let baked = bake.sample(u: at.x, v: at.y)
                let gathered: Float = switch wear.kind {
                case .dirt: max(1 - baked.occlusion, baked.concave * 0.9)
                case .edges: baked.convex
                }
                let noise = PatternNoise.fbm(position * breakup + seed, octaves: 4)
                let value = MaterialPatterns.smooth(1.02 - amount, 1.22 - amount, gathered + (noise - 0.5) * 0.6 * amount)
                guard value > 0.004 else { return }
                let index = (y * size + x) * 4
                color.write(index, tint, alpha: value)
                rough.write(index, SIMD3<Float>(repeating: roughness), alpha: value)
            }
        }
        return [.color: color, .roughness: rough]
    }
}

extension RGBAImage {
    /// Writes an sRGB colour (0…1) at a byte index.
    @inline(__always) mutating func write(_ index: Int, _ rgb: SIMD3<Float>, alpha: Float = 1) {
        pixels[index] = UInt8((min(max(rgb.x, 0), 1) * 255).rounded())
        pixels[index + 1] = UInt8((min(max(rgb.y, 0), 1) * 255).rounded())
        pixels[index + 2] = UInt8((min(max(rgb.z, 0), 1) * 255).rounded())
        pixels[index + 3] = UInt8((min(max(alpha, 0), 1) * 255).rounded())
    }
}

public extension PaintOperations {
    /// A fill layer's tiles made again from its pictures (its mask, name and settings stay). Returns the layer as it
    /// should be and the files to write first.
    static func filled(_ layer: PaintLayer, with images: [PaintMap: RGBAImage], surface: PaintSurface,
                       encode: (RGBAImage) -> Data = PNGCodec.encode) -> (layer: PaintLayer, files: Files) {
        var result = layer
        result.tiles = [:]
        let mask = layer.maps[PaintMap.mask.rawValue]
        result.maps = mask.map { [PaintMap.mask.rawValue: $0] } ?? [:]
        var files: Files = [:]
        var encoded: [[UInt8]: String] = [:]
        for (map, image) in images.sorted(by: { $0.key.rawValue < $1.key.rawValue }) where map != .mask {
            for (tile, picture) in PaintComposer.tiles(of: image, surface: surface) {
                let name: String
                if let known = encoded[picture.pixels] {
                    name = known
                } else {
                    let png = encode(picture)
                    name = PaintFiles.tileName(for: png)
                    files[name] = png
                    encoded[picture.pixels] = name
                }
                result[map, tile] = name
            }
        }
        return (result, files)
    }

    /// A new fill layer on top (or above `id`): its pictures made by `images`, its name the fill's.
    static func addFill(_ fill: PaintFill, to paint: ObjectPaint, above id: String?, object: ObjectID, images: [PaintMap: RGBAImage],
                        encode: (RGBAImage) -> Data = PNGCodec.encode) -> (command: EditCommand, layer: String, files: Files)? {
        guard paint.layers.count < ObjectPaint.maximumLayers else { return nil }
        var changed = paint
        let blank = PaintLayer(id: paint.newLayerID(), name: fill.title, fill: fill)
        let (layer, files) = filled(blank, with: images, surface: paint.surface, encode: encode)
        let index = id.flatMap(paint.layerIndex).map { $0 + 1 } ?? paint.layers.count
        changed.layers.insert(layer, at: min(index, changed.layers.count))
        return (.setPaint(object, changed), layer.id, files)
    }

    /// A fill layer whose fill changed (a wear's amount, a material swapped): its tiles made again.
    static func changeFill(_ id: String, to fill: PaintFill, in paint: ObjectPaint, object: ObjectID, images: [PaintMap: RGBAImage],
                           encode: (RGBAImage) -> Data = PNGCodec.encode) -> (command: EditCommand, files: Files)? {
        guard let index = paint.layerIndex(id) else { return nil }
        var layer = paint.layers[index]
        layer.fill = fill
        let (made, files) = filled(layer, with: images, surface: paint.surface, encode: encode)
        var changed = paint
        changed.layers[index] = made
        return changed == paint ? nil : (.setPaint(object, changed), files)
    }

    /// Gives a layer a mask that shows all of it (every tile opaque white), or takes its mask away.
    static func setMask(_ on: Bool, layer id: String, in paint: ObjectPaint, object: ObjectID,
                        encode: (RGBAImage) -> Data = PNGCodec.encode) -> (command: EditCommand, files: Files)? {
        guard let index = paint.layerIndex(id), paint.layers[index].hasMask != on else { return nil }
        var changed = paint
        var files: Files = [:]
        if on {
            let png = encode(RGBAImage(width: PaintSurface.tileSize, height: PaintSurface.tileSize, color: .white))
            let name = PaintFiles.tileName(for: png)
            files[name] = png
            changed.layers[index].maps[PaintMap.mask.rawValue] = Dictionary(uniqueKeysWithValues: paint.surface.allTiles.map { ($0.key, name) })
        } else {
            changed.layers[index].maps[PaintMap.mask.rawValue] = nil
        }
        return (.setPaint(object, changed), files)
    }
}
