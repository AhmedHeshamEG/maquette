import Foundation

/// Paint layers as pictures: assembled from their tiles, composited map by map with their blend modes, opacity and
/// masks (the W3C formulas on the stored sRGB values, the same maths as the stage's GPU composite), split back into
/// tiles.
public enum PaintComposer {
    /// A layer's whole picture of one map; missing or unreadable tiles are transparent.
    public static func layerImage(_ layer: PaintLayer, map: PaintMap = .color, surface: PaintSurface, tile: (String) -> RGBAImage?) -> RGBAImage {
        var image = RGBAImage.clear(width: surface.size, height: surface.size)
        let size = PaintSurface.tileSize
        for (key, file) in layer.tiles(of: map) {
            guard let index = PaintTileIndex(key: key), index.column < surface.tilesPerSide, index.row < surface.tilesPerSide,
                  let picture = tile(file), picture.width == size, picture.height == size else { continue }
            image.place(picture, x: index.column * size, y: index.row * size)
        }
        return image
    }

    /// The picture's tiles that hold any paint (a transparent tile is left out: it's no file at all).
    public static func tiles(of image: RGBAImage, surface: PaintSurface) -> [PaintTileIndex: RGBAImage] {
        var result: [PaintTileIndex: RGBAImage] = [:]
        for index in surface.allTiles {
            let tile = image.tile(index, size: PaintSurface.tileSize)
            if !tile.isClear { result[index] = tile }
        }
        return result
    }

    /// Every visible layer's `map`, bottom first, into one straight-alpha picture (alpha 0 where nothing is painted:
    /// the object's own value shows there). A layer with a mask shows only where the mask's alpha is.
    public static func composite(_ paint: ObjectPaint, map: PaintMap = .color, image: (PaintLayer, PaintMap) -> RGBAImage) -> RGBAImage {
        let size = paint.surface.size
        let count = size * size
        var premultiplied = [Float](repeating: 0, count: count * 4)
        for layer in paint.layers where layer.visible && layer.opacity > 0 && !layer.tiles(of: map).isEmpty {
            let picture = image(layer, map)
            guard picture.width == size, picture.height == size else { continue }
            let mask = layer.hasMask ? image(layer, .mask) : nil
            let masked = mask.map { $0.width == size && $0.height == size } ?? false
            let opacity = Float(layer.opacity)
            for index in 0 ..< count {
                var alpha = Float(picture.pixels[index * 4 + 3]) / 255 * opacity
                if let mask {
                    alpha *= masked ? Float(mask.pixels[index * 4 + 3]) / 255 : 0
                }
                guard alpha > 0 else { continue }
                let source = SIMD3<Float>(Float(picture.pixels[index * 4]), Float(picture.pixels[index * 4 + 1]), Float(picture.pixels[index * 4 + 2])) / 255
                let backdrop = SIMD4<Float>(premultiplied[index * 4], premultiplied[index * 4 + 1], premultiplied[index * 4 + 2], premultiplied[index * 4 + 3])
                let out = blend(source: source, alpha: alpha, mode: layer.blend, backdrop: backdrop)
                for channel in 0 ..< 4 {
                    premultiplied[index * 4 + channel] = out[channel]
                }
            }
        }
        var pixels = [UInt8](repeating: 0, count: count * 4)
        for index in 0 ..< count {
            let alpha = premultiplied[index * 4 + 3]
            guard alpha > 1e-6 else { continue }
            for channel in 0 ..< 3 {
                pixels[index * 4 + channel] = UInt8((min(max(premultiplied[index * 4 + channel] / alpha, 0), 1) * 255).rounded())
            }
            pixels[index * 4 + 3] = UInt8((min(alpha, 1) * 255).rounded())
        }
        return RGBAImage(width: size, height: size, pixels: pixels)
    }

    /// One source pixel over a premultiplied backdrop: Cs' = (1 − αb)·Cs + αb·B(Cb, Cs), then source-over.
    public static func blend(source: SIMD3<Float>, alpha: Float, mode: PaintBlend, backdrop: SIMD4<Float>) -> SIMD4<Float> {
        let backdropAlpha = backdrop.w
        let straight = backdropAlpha > 1e-6 ? SIMD3<Float>(backdrop.x, backdrop.y, backdrop.z) / backdropAlpha : .zero
        var mixed = source
        if mode != .normal, backdropAlpha > 0 {
            let blended = SIMD3<Float>(Float(mode.mix(Double(straight.x), Double(source.x))), Float(mode.mix(Double(straight.y), Double(source.y))),
                                       Float(mode.mix(Double(straight.z), Double(source.z))))
            mixed = source * (1 - backdropAlpha) + blended * backdropAlpha
        }
        let color = mixed * alpha + SIMD3<Float>(backdrop.x, backdrop.y, backdrop.z) * (1 - alpha)
        return SIMD4<Float>(color.x, color.y, color.z, alpha + backdropAlpha * (1 - alpha))
    }

    /// The paint's texture with the object's own colour under it (opaque): what a viewer without layers shows.
    public static func flattened(_ texture: RGBAImage, over base: RGBA) -> RGBAImage {
        var result = texture
        let (r, g, b, _) = RGBAImage.bytes(base)
        for index in 0 ..< texture.width * texture.height {
            let alpha = Int(texture.pixels[index * 4 + 3])
            for (channel, under) in [(0, Int(r)), (1, Int(g)), (2, Int(b))] {
                let over = Int(texture.pixels[index * 4 + channel])
                result.pixels[index * 4 + channel] = UInt8((over * alpha + under * (255 - alpha) + 127) / 255)
            }
            result.pixels[index * 4 + 3] = 255
        }
        return result
    }

    /// A value map over the object's own value (0…1), as an opaque grey picture.
    public static func flattened(_ texture: RGBAImage, over value: Double) -> RGBAImage {
        let grey = min(max(value, 0), 1)
        return flattened(texture, over: RGBA(grey, grey, grey, 1))
    }
}

/// The pictures of a paint's layers, decoded from their tiles once and kept while they're asked for again.
public final class PaintPictures {
    private let paint: ObjectPaint
    private let file: (String) -> Data?
    private var tiles: [String: RGBAImage?] = [:]
    private var images: [String: RGBAImage] = [:]

    public init(_ paint: ObjectPaint, file: @escaping (String) -> Data?) {
        self.paint = paint
        self.file = file
    }

    /// Pictures already decoded (carried paint, a stroke's result) are used as they are.
    public init(_ paint: ObjectPaint, images: [String: RGBAImage]) {
        self.paint = paint
        file = { _ in nil }
        self.images = images
    }

    /// The key a layer's map is kept under ("l1", "l1#roughness").
    public static func key(_ layer: String, _ map: PaintMap) -> String {
        map == .color ? layer : "\(layer)#\(map.rawValue)"
    }

    /// A key back into its layer and map ("l1#bumps" → l1, bumps); a key naming no map this app knows is colour.
    public static func split(_ key: String) -> (layer: String, map: PaintMap) {
        guard let mark = key.lastIndex(of: "#"), let map = PaintMap(rawValue: String(key[key.index(after: mark)...])) else { return (key, .color) }
        return (String(key[..<mark]), map)
    }

    public func image(_ layer: PaintLayer, _ map: PaintMap) -> RGBAImage {
        let key = Self.key(layer.id, map)
        if let known = images[key] { return known }
        let made = PaintComposer.layerImage(layer, map: map, surface: paint.surface) { name in
            if let known = tiles[name] { return known }
            let decoded = file(name).flatMap { try? PNGCodec.decode($0) }
            tiles[name] = decoded
            return decoded
        }
        images[key] = made
        return made
    }

    /// Every picture of every layer that has tiles (and its mask), by key.
    public func all() -> [String: RGBAImage] {
        for layer in paint.layers {
            for map in PaintMap.allCases where !layer.tiles(of: map).isEmpty || (map == .mask && layer.hasMask) {
                _ = image(layer, map)
            }
        }
        return images
    }
}
