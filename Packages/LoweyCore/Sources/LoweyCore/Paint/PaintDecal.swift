import Foundation

/// A picture placed on a surface (D-348): laid on the surface from in front, like a sticker pressed on, over a square
/// of `size` metres around `center`, facing out along `normal`, its top toward `up`. Only the surface that faces the
/// picture takes it (no smearing down the sides), and it wraps gently over curves.
public struct PaintDecal: Hashable, Sendable {
    public var center: SIMD3<Float>
    public var normal: SIMD3<Float>
    public var up: SIMD3<Float>
    /// The picture's width in metres (its height follows its shape).
    public var size: Float
    public var opacity: Float

    public init(center: SIMD3<Float>, normal: SIMD3<Float>, up: SIMD3<Float> = SIMD3<Float>(0, 1, 0), size: Float, opacity: Float = 1) {
        self.center = center
        self.normal = normalize3(normal, fallback: SIMD3<Float>(0, 0, 1))
        self.up = up
        self.size = max(size, 1e-4)
        self.opacity = min(max(opacity, 0), 1)
    }

    /// The picture on the paint mesh's unwrap, at `textureSize` (clear where it doesn't land).
    public func image(_ picture: RGBAImage, on paintMesh: MeshData, textureSize: Int) -> RGBAImage {
        var result = RGBAImage.clear(width: textureSize, height: textureSize)
        guard picture.width > 0, picture.height > 0 else { return result }
        var across = cross3(up, normal)
        if length3(across) < 1e-4 { across = cross3(SIMD3<Float>(1, 0, 0), normal) }
        across = normalize3(across, fallback: SIMD3<Float>(1, 0, 0))
        let upward = cross3(normal, across)
        let halfWidth = size / 2
        let halfHeight = halfWidth * Float(picture.height) / Float(picture.width)
        let depth = max(halfWidth, halfHeight)
        SurfaceTexels.visit(paintMesh, size: textureSize) { x, y, position, surfaceNormal in
            let facing = dot3(surfaceNormal, normal)
            guard facing > 0.2 else { return }
            let offset = position - center
            guard abs(dot3(offset, normal)) < depth else { return }
            let u = dot3(offset, across) / halfWidth * 0.5 + 0.5
            let v = 0.5 - dot3(offset, upward) / halfHeight * 0.5
            guard u >= 0, u <= 1, v >= 0, v <= 1 else { return }
            let colour = picture.sample(u: Double(u).clampedUnit, v: Double(v).clampedUnit)
            let alpha = colour.a * Double(opacity) * Double(min((facing - 0.2) / 0.2, 1))
            guard alpha > 0.002 else { return }
            result.setPixel(x, y, RGBA(colour.r, colour.g, colour.b, alpha))
        }
        return result
    }
}

extension Double {
    /// Kept inside 0…1 a hair from the edges, so a repeating sample never wraps to the other side.
    var clampedUnit: Double { min(max(self, 0.0005), 0.9995) }
}

public extension PaintOperations {
    /// The paint on a fresh unwrap of `source` (with `seams` when given), every layer's maps and mask carried by
    /// position, and its files. The baked normals are dropped (they described the old surface).
    static func rebased(_ paint: ObjectPaint, source: MeshData, file: (String) -> Data?, seams: [PaintSeam]?? = nil,
                        encode: (RGBAImage) -> Data = PNGCodec.encode) -> (paint: ObjectPaint, files: Files)? {
        var asked = paint
        if let seams { asked.surface.seams = seams }
        let unwrap: PaintUnwrap
        var layers: [String: RGBAImage]
        if let seams, seams != paint.surface.seams {
            // New seams: a new unwrap even when the shape is the same; the old one is the source of the carry.
            guard let stored = file(paint.surface.unwrap).flatMap({ try? PaintUnwrap(data: $0) }),
                  let fresh = try? PaintUnwrap.unwrap(source, seams: seams) else { return nil }
            let map = PaintTransfer.correspondence(from: stored, to: fresh, size: paint.surface.size)
            let pictures = withoutActuallyEscaping(file) { PaintPictures(paint, file: $0).all() }
            unwrap = fresh
            layers = pictures.mapValues { PaintTransfer.carry($0, through: map, size: paint.surface.size) }
        } else {
            guard let current = PaintExport.current(asked, source: source, file: file) else { return nil }
            unwrap = current.unwrap
            layers = current.layers
        }
        let data = unwrap.data
        let name = PaintFiles.unwrapName(for: data)
        var files: Files = [name: data]
        var rebased = asked
        rebased.surface = PaintSurface(size: paint.surface.size, unwrap: name, mesh: PaintMesh.fingerprint(source), seams: asked.surface.seams)
        if paint.normalMap != nil, rebased.surface.mesh != paint.surface.mesh || rebased.surface.unwrap != paint.surface.unwrap {
            rebased.normalMap = nil
            rebased.normalsFrom = nil
        }
        for index in rebased.layers.indices {
            let layer = rebased.layers[index]
            rebased.layers[index].tiles = [:]
            rebased.layers[index].maps = layer.hasMask ? [PaintMap.mask.rawValue: [:]] : [:]
            for map in PaintMap.allCases where !layer.tiles(of: map).isEmpty {
                let picture = layers[PaintPictures.key(layer.id, map)] ?? .clear(width: paint.surface.size, height: paint.surface.size)
                for (tile, image) in PaintComposer.tiles(of: picture, surface: rebased.surface) {
                    let png = encode(image)
                    let tileName = PaintFiles.tileName(for: png)
                    files[tileName] = png
                    rebased.layers[index][map, tile] = tileName
                }
            }
        }
        return (rebased, files)
    }
}
