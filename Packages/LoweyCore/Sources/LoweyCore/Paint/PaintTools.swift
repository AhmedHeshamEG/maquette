import Foundation

/// The paint mesh under a ray: where a dab lands in the texture. Smudging and the Faces brush work in the texture,
/// so each dab is found on the surface first (object space ray in, uv out).
public struct PaintSurfacePick: Sendable {
    public let mesh: MeshData
    let bvh: TriangleBVH

    public init(paintMesh: MeshData) {
        mesh = paintMesh
        bvh = TriangleBVH(paintMesh)
    }

    public struct Hit: Hashable, Sendable {
        public var uv: SIMD2<Float>
        public var triangle: Int
        public var position: SIMD3<Float>
        public var normal: SIMD3<Float>
        /// Texels per metre of surface around the hit, for turning a dab's size into texels.
        public var density: Float
    }

    /// The nearest point of the surface along the ray (object space), for a texture of `size`.
    public func hit(origin: SIMD3<Float>, direction: SIMD3<Float>, size: Int) -> Hit? {
        guard let found = bvh.nearest(origin: origin, direction: direction) else { return nil }
        let i = (Int(mesh.indices[found.triangle * 3]), Int(mesh.indices[found.triangle * 3 + 1]), Int(mesh.indices[found.triangle * 3 + 2]))
        let w = found.weights
        let uv = mesh.uvs[i.0] * w.x + mesh.uvs[i.1] * w.y + mesh.uvs[i.2] * w.z
        let p = (mesh.positions[i.0], mesh.positions[i.1], mesh.positions[i.2])
        let normal = normalize3(cross3(p.1 - p.0, p.2 - p.0), fallback: SIMD3<Float>(0, 1, 0))
        let world = length3(p.1 - p.0) + length3(p.2 - p.1) + length3(p.0 - p.2)
        let texels = (length3(SIMD3<Float>(mesh.uvs[i.1] - mesh.uvs[i.0], 0)) + length3(SIMD3<Float>(mesh.uvs[i.2] - mesh.uvs[i.1], 0))
            + length3(SIMD3<Float>(mesh.uvs[i.0] - mesh.uvs[i.2], 0))) * Float(size)
        return Hit(uv: uv, triangle: found.triangle, position: p.0 * w.x + p.1 * w.y + p.2 * w.z, normal: normal,
                   density: world > 1e-9 ? texels / world : Float(size))
    }

    /// The triangles of the flat face a triangle belongs to: its neighbours across shared corners that lie in its
    /// plane, and theirs (D-357).
    public func face(of triangle: Int, tolerance: Float = 0.999) -> [Int] {
        guard triangle >= 0, triangle < mesh.triangleCount else { return [] }
        let normals = (0 ..< mesh.triangleCount).map { face -> SIMD3<Float> in
            let p = (0 ..< 3).map { mesh.positions[Int(mesh.indices[face * 3 + $0])] }
            return normalize3(cross3(p[1] - p[0], p[2] - p[0]), fallback: .zero)
        }
        var byCorner: [SIMD3<Int32>: [Int]] = [:]
        func key(_ p: SIMD3<Float>) -> SIMD3<Int32> {
            SIMD3<Int32>(Int32(clamping: Int((p.x * 1e4).rounded())), Int32(clamping: Int((p.y * 1e4).rounded())), Int32(clamping: Int((p.z * 1e4).rounded())))
        }
        for face in 0 ..< mesh.triangleCount {
            for corner in 0 ..< 3 {
                byCorner[key(mesh.positions[Int(mesh.indices[face * 3 + corner])]), default: []].append(face)
            }
        }
        let plane = normals[triangle]
        let offset = dot3(plane, mesh.positions[Int(mesh.indices[triangle * 3])])
        var found: Set<Int> = [triangle]
        var stack = [triangle]
        while let face = stack.popLast() {
            for corner in 0 ..< 3 {
                for other in byCorner[key(mesh.positions[Int(mesh.indices[face * 3 + corner])])] ?? [] where !found.contains(other) {
                    let first = mesh.positions[Int(mesh.indices[other * 3])]
                    guard dot3(normals[other], plane) >= tolerance, abs(dot3(plane, first) - offset) < 1e-4 else { continue }
                    found.insert(other)
                    stack.append(other)
                }
            }
        }
        return found.sorted()
    }
}

/// Smudge on painted surfaces (D-346): each dab carries the paint under the last one a little further, in the
/// texture, so it drags colour (or any map) along the surface the way a finger drags it on paper.
public enum PaintSmudge {
    public struct Dab: Hashable, Sendable {
        /// Where the dab lands, in texels.
        public var center: SIMD2<Float>
        public var radius: Float
        /// 0 nothing moves … 1 the paint is carried whole.
        public var strength: Float

        public init(center: SIMD2<Float>, radius: Float, strength: Float) {
            self.center = center
            self.radius = radius
            self.strength = strength
        }
    }

    /// Applies dabs in order to the picture; returns the tiles it changed. Each dab picks up what's under the previous
    /// one (premultiplied, so clear paint carries no colour) and lays it down soft-edged.
    @discardableResult
    public static func apply(_ dabs: [Dab], to image: inout RGBAImage, tileSize: Int = PaintSurface.tileSize) -> Set<PaintTileIndex> {
        var changed = Set<PaintTileIndex>()
        guard dabs.count > 1 else { return changed }
        let width = image.width, height = image.height
        for (previous, dab) in zip(dabs, dabs.dropFirst()) {
            let shift = previous.center - dab.center
            let r = max(dab.radius, 1)
            let minX = max(Int((dab.center.x - r).rounded(.down)), 0), maxX = min(Int((dab.center.x + r).rounded(.up)), width - 1)
            let minY = max(Int((dab.center.y - r).rounded(.down)), 0), maxY = min(Int((dab.center.y + r).rounded(.up)), height - 1)
            guard minX <= maxX, minY <= maxY else { continue }
            // Only the dab's area and the area it carries from are read, before anything is written.
            let source = Patch(image, x0: minX + Int(shift.x.rounded(.down)) - 1, y0: minY + Int(shift.y.rounded(.down)) - 1,
                               x1: maxX + Int(shift.x.rounded(.up)) + 1, y1: maxY + Int(shift.y.rounded(.up)) + 1, also: (minX, minY, maxX, maxY))
            for y in minY ... maxY {
                for x in minX ... maxX {
                    let offset = SIMD2<Float>(Float(x) + 0.5, Float(y) + 0.5) - dab.center
                    let distance = (offset * offset).sum().squareRoot() / r
                    guard distance < 1 else { continue }
                    let falloff = (1 - distance * distance) * (1 - distance * distance) * dab.strength
                    let carried = source.sample(Float(x) + 0.5 + shift.x, Float(y) + 0.5 + shift.y)
                    let index = (y * width + x) * 4
                    let here = source.at(x, y)
                    let mixed = here + (carried - here) * falloff
                    let a = mixed.w
                    image.write(index, a > 1e-5 ? SIMD3<Float>(mixed.x, mixed.y, mixed.z) / a : .zero, alpha: a)
                    changed.insert(PaintTileIndex(column: x / tileSize, row: y / tileSize))
                }
            }
        }
        return changed
    }

    /// A copy of part of a picture, premultiplied, read while the picture itself is written.
    struct Patch {
        let x0: Int, y0: Int, width: Int, height: Int
        let imageWidth: Int, imageHeight: Int
        var pixels: [SIMD4<Float>]

        init(_ image: RGBAImage, x0: Int, y0: Int, x1: Int, y1: Int, also box: (Int, Int, Int, Int)) {
            let left = max(min(x0, box.0), 0), top = max(min(y0, box.1), 0)
            let right = min(max(x1, box.2), image.width - 1), bottom = min(max(y1, box.3), image.height - 1)
            self.x0 = left
            self.y0 = top
            width = max(right - left + 1, 1)
            height = max(bottom - top + 1, 1)
            imageWidth = image.width
            imageHeight = image.height
            pixels = [SIMD4<Float>](repeating: .zero, count: width * height)
            for y in 0 ..< height where top + y < image.height {
                for x in 0 ..< width where left + x < image.width {
                    let index = ((top + y) * image.width + left + x) * 4
                    let alpha = Float(image.pixels[index + 3]) / 255
                    pixels[y * width + x] = SIMD4<Float>(Float(image.pixels[index]) / 255 * alpha, Float(image.pixels[index + 1]) / 255 * alpha,
                                                         Float(image.pixels[index + 2]) / 255 * alpha, alpha)
                }
            }
        }

        func at(_ x: Int, _ y: Int) -> SIMD4<Float> {
            let px = min(max(x - x0, 0), width - 1), py = min(max(y - y0, 0), height - 1)
            return pixels[py * width + px]
        }

        /// Bilinear at a texel position (clamped at the picture's edges).
        func sample(_ x: Float, _ y: Float) -> SIMD4<Float> {
            let fx = min(max(x - 0.5, 0), Float(imageWidth - 1)), fy = min(max(y - 0.5, 0), Float(imageHeight - 1))
            let ix = Int(fx), iy = Int(fy)
            let tx = fx - Float(ix), ty = fy - Float(iy)
            let top = at(ix, iy) * (1 - tx) + at(min(ix + 1, imageWidth - 1), iy) * tx
            let bottom = at(ix, min(iy + 1, imageHeight - 1)) * (1 - tx) + at(min(ix + 1, imageWidth - 1), min(iy + 1, imageHeight - 1)) * tx
            return top * (1 - ty) + bottom * ty
        }
    }
}

public extension PaintOperations {
    /// The Faces brush (D-357): whole flat faces filled with one colour (or value) in a layer's map, edge to edge, as a
    /// low-poly artist colours a model. Returns the changed tiles' files and changes, through the usual tile command.
    static func fillFaces(_ triangles: [Int], color: RGBA, map: PaintMap = .color, layer: PaintLayer, surface: PaintSurface, paintMesh: MeshData,
                          image: RGBAImage, encode: (RGBAImage) -> Data = PNGCodec.encode) -> (changes: [PaintTileChange], files: Files) {
        var picture = image
        var touched = Set<PaintTileIndex>()
        let scale = Float(surface.size)
        for face in triangles where face >= 0 && face < paintMesh.triangleCount {
            let uv = (0 ..< 3).map { paintMesh.uvs[Int(paintMesh.indices[face * 3 + $0])] * scale }
            // A texel past the edge too, so the face's colour reaches its border with no seam of the colour under it.
            let middle = (uv[0] + uv[1] + uv[2]) / 3
            let grown = uv.map { $0 + normalize2($0 - middle) * 1.0 }
            PaintRaster.triangle(grown[0], grown[1], grown[2], width: surface.size, height: surface.size) { x, y, _ in
                picture.setPixel(x, y, color)
                touched.insert(PaintTileIndex(column: x / PaintSurface.tileSize, row: y / PaintSurface.tileSize))
            }
        }
        return tileChanges(picture, tiles: touched, map: map, layer: layer, encode: encode)
    }

    /// The given tiles of a picture as a layer map's tile changes (clear tiles clear theirs).
    static func tileChanges(_ image: RGBAImage, tiles: Set<PaintTileIndex>, map: PaintMap, layer: PaintLayer,
                            encode: (RGBAImage) -> Data = PNGCodec.encode) -> (changes: [PaintTileChange], files: Files) {
        var changes: [PaintTileChange] = []
        var files: Files = [:]
        for index in tiles.sorted() {
            let tile = image.tile(index, size: PaintSurface.tileSize)
            if tile.isClear {
                if layer[map, index] != nil { changes.append(PaintTileChange(layer: layer.id, tile: index, file: nil, map: map)) }
                continue
            }
            let png = encode(tile)
            let name = PaintFiles.tileName(for: png)
            files[name] = png
            if layer[map, index] != name { changes.append(PaintTileChange(layer: layer.id, tile: index, file: name, map: map)) }
        }
        return (changes, files)
    }

    /// Every layer (each map and mask) resampled to a new texture size (D-350), and the baked normals dropped when they
    /// can't follow (they're baked again at the new size).
    static func resized(_ paint: ObjectPaint, to size: Int, pictures: PaintPictures, encode: (RGBAImage) -> Data = PNGCodec.encode)
        -> (paint: ObjectPaint, files: Files)? {
        let target = PaintSurface(size: size, unwrap: paint.surface.unwrap, mesh: paint.surface.mesh, seams: paint.surface.seams)
        guard target.size != paint.surface.size else { return nil }
        var changed = paint
        changed.surface = target
        changed.normalMap = nil
        changed.normalsFrom = nil
        var files: Files = [:]
        for (index, layer) in paint.layers.enumerated() {
            var result = layer
            result.tiles = [:]
            result.maps = layer.hasMask ? [PaintMap.mask.rawValue: [:]] : [:]
            for map in PaintMap.allCases where !layer.tiles(of: map).isEmpty {
                let scaled = pictures.image(layer, map).resampled(to: target.size)
                for (tile, picture) in PaintComposer.tiles(of: scaled, surface: target) {
                    let png = encode(picture)
                    let name = PaintFiles.tileName(for: png)
                    files[name] = png
                    result[map, tile] = name
                }
            }
            changed.layers[index] = result
        }
        return (changed, files)
    }
}

public extension RGBAImage {
    /// The picture at another size (bilinear, alpha-weighted).
    func resampled(to side: Int) -> RGBAImage {
        guard side != width || side != height else { return self }
        var result = RGBAImage.clear(width: side, height: side)
        for y in 0 ..< side {
            for x in 0 ..< side {
                let c = sample(u: (Double(x) + 0.5) / Double(side), v: (Double(y) + 0.5) / Double(side))
                if c.a > 0 { result.setPixel(x, y, c) }
            }
        }
        return result
    }
}

@inline(__always) func normalize2(_ v: SIMD2<Float>) -> SIMD2<Float> {
    let length = (v * v).sum().squareRoot()
    return length > 1e-9 ? v / length : .zero
}
