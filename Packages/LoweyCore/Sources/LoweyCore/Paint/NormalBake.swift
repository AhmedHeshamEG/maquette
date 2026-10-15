import Foundation

/// Normal maps (D-352): a detailed surface's normals baked onto a lighter one's unwrap, and painted bumps turned into a
/// normal map for export. Tangent space as glTF reads it: x along the texture's u, y up the picture (against v), z out
/// of the surface; each triangle's frame comes from how its uvs run over it.
public enum NormalBake {
    /// The high surface's normals on the low one's unwrap. For each texel a ray starts `reach` above the low surface
    /// and looks down through it for the high one (then from below, for spots the high one dips under). Texels that
    /// find nothing keep the low surface's own normal (flat in tangent space).
    public static func bake(low paintMesh: MeshData, high: MeshData, size: Int, reach: Float? = nil) -> RGBAImage {
        // Flat everywhere first, so filtering at a chart's edge never reads a normal pointing nowhere.
        var image = RGBAImage(width: size, height: size, color: RGBA(0.5, 0.5, 1, 1))
        var covered = [UInt8](repeating: 0, count: size * size)
        let bvh = TriangleBVH(high)
        let distance = reach ?? SurfaceTexels.diagonal(paintMesh) * 0.05
        let highNormals = high.normals.count == high.positions.count
        let frames = triangleFrames(paintMesh)
        let scale = Float(size)
        for face in 0 ..< paintMesh.triangleCount {
            let i = (Int(paintMesh.indices[face * 3]), Int(paintMesh.indices[face * 3 + 1]), Int(paintMesh.indices[face * 3 + 2]))
            let p = (paintMesh.positions[i.0], paintMesh.positions[i.1], paintMesh.positions[i.2])
            let flat = normalize3(cross3(p.1 - p.0, p.2 - p.0), fallback: SIMD3<Float>(0, 1, 0))
            let n = paintMesh.normals.count == paintMesh.positions.count
                ? (paintMesh.normals[i.0], paintMesh.normals[i.1], paintMesh.normals[i.2]) : (flat, flat, flat)
            PaintRaster.triangle(paintMesh.uvs[i.0] * scale, paintMesh.uvs[i.1] * scale, paintMesh.uvs[i.2] * scale, width: size, height: size) { x, y, w in
                let position = p.0 * w.x + p.1 * w.y + p.2 * w.z
                let normal = normalize3(n.0 * w.x + n.1 * w.y + n.2 * w.z, fallback: flat)
                var detail = normal
                let hit = bvh.nearest(origin: position + normal * distance, direction: -normal, limit: distance * 2)
                    ?? bvh.nearest(origin: position - normal * distance, direction: normal, limit: distance * 2)
                if let hit {
                    let h = (Int(high.indices[hit.triangle * 3]), Int(high.indices[hit.triangle * 3 + 1]), Int(high.indices[hit.triangle * 3 + 2]))
                    if highNormals {
                        detail = normalize3(high.normals[h.0] * hit.weights.x + high.normals[h.1] * hit.weights.y + high.normals[h.2] * hit.weights.z,
                                            fallback: normal)
                    } else {
                        detail = normalize3(cross3(high.positions[h.1] - high.positions[h.0], high.positions[h.2] - high.positions[h.0]), fallback: normal)
                    }
                }
                let (tangent, bitangent) = orthonormal(frames[face], normal: normal)
                let local = SIMD3<Float>(dot3(detail, tangent), dot3(detail, bitangent), dot3(detail, normal))
                image.write((y * size + x) * 4, local * 0.5 + 0.5)
                covered[y * size + x] = 1
            }
        }
        // Each chart's normals pushed a few texels past its edge (as paint is), so bilinear filtering stays on it.
        PaintRaster.dilate(&image, coverage: covered)
        return image
    }

    /// Painted bumps (heights, 0.5 = the surface; clear texels are flat) as a tangent normal map, laid over a baked
    /// normal map when there is one. `strength` is how many texels one unit of height rises over (D-353).
    public static func fromBumps(_ heights: RGBAImage?, baked: RGBAImage?, coverage: [UInt8]?, size: Int, strength: Float? = nil) -> RGBAImage {
        var image = RGBAImage(width: size, height: size, color: RGBA(0.5, 0.5, 1, 1))
        let rise = strength ?? 6 * Float(size) / 2048
        func height(_ x: Int, _ y: Int) -> Float {
            guard let heights, heights.width == size else { return 0.5 }
            let index = (y * size + x) * 4
            let alpha = Float(heights.pixels[index + 3]) / 255
            return 0.5 + (Float(heights.pixels[index]) / 255 - 0.5) * alpha
        }
        func covered(_ x: Int, _ y: Int) -> Bool {
            guard let coverage else { return true }
            return coverage[y * size + x] != 0
        }
        for y in 0 ..< size {
            for x in 0 ..< size {
                let here = height(x, y)
                // Across a chart's edge the neighbour isn't this surface: the texel's own height stands in.
                let left = x > 0 && covered(x - 1, y) ? height(x - 1, y) : here
                let right = x < size - 1 && covered(x + 1, y) ? height(x + 1, y) : here
                let up = y > 0 && covered(x, y - 1) ? height(x, y - 1) : here
                let down = y < size - 1 && covered(x, y + 1) ? height(x, y + 1) : here
                let bump = normalize3(SIMD3<Float>(-(right - left) * 0.5 * rise, (down - up) * 0.5 * rise, 1), fallback: SIMD3<Float>(0, 0, 1))
                var normal = bump
                if let baked, baked.width == size {
                    let index = (y * size + x) * 4
                    let base = SIMD3<Float>(Float(baked.pixels[index]), Float(baked.pixels[index + 1]), Float(baked.pixels[index + 2])) / 255 * 2 - 1
                    // Whiteout blend: the bumps' slopes added to the baked normal's.
                    normal = normalize3(SIMD3<Float>(base.x + bump.x, base.y + bump.y, base.z * bump.z), fallback: base)
                }
                image.write((y * size + x) * 4, normal * 0.5 + 0.5)
            }
        }
        return image
    }

    /// Each vertex's tangent (x, y, z, and w = ±1: the bitangent is cross(normal, tangent) × w), as glTF's TANGENT.
    public static func tangents(_ paintMesh: MeshData) -> [SIMD4<Float>] {
        var sums = [(SIMD3<Float>, SIMD3<Float>)](repeating: (.zero, .zero), count: paintMesh.positions.count)
        for (face, frame) in triangleFrames(paintMesh).enumerated() {
            for corner in 0 ..< 3 {
                let vertex = Int(paintMesh.indices[face * 3 + corner])
                sums[vertex].0 += frame.0
                sums[vertex].1 += frame.1
            }
        }
        let hasNormals = paintMesh.normals.count == paintMesh.positions.count
        return sums.enumerated().map { vertex, sum in
            let normal = hasNormals ? paintMesh.normals[vertex] : SIMD3<Float>(0, 1, 0)
            let (tangent, bitangent) = orthonormal(sum, normal: normal)
            let w: Float = dot3(cross3(normal, tangent), bitangent) < 0 ? -1 : 1
            return SIMD4<Float>(tangent.x, tangent.y, tangent.z, w)
        }
    }

    /// Per triangle: the direction the texture's u runs over it and the direction "up the picture" (−v) runs.
    static func triangleFrames(_ mesh: MeshData) -> [(SIMD3<Float>, SIMD3<Float>)] {
        (0 ..< mesh.triangleCount).map { face in
            let i = (Int(mesh.indices[face * 3]), Int(mesh.indices[face * 3 + 1]), Int(mesh.indices[face * 3 + 2]))
            let e1 = mesh.positions[i.1] - mesh.positions[i.0], e2 = mesh.positions[i.2] - mesh.positions[i.0]
            let d1 = mesh.uvs[i.1] - mesh.uvs[i.0], d2 = mesh.uvs[i.2] - mesh.uvs[i.0]
            let determinant = d1.x * d2.y - d2.x * d1.y
            guard abs(determinant) > 1e-12 else { return (SIMD3<Float>(1, 0, 0), SIMD3<Float>(0, 1, 0)) }
            let r = 1 / determinant
            let alongU = (e1 * d2.y - e2 * d1.y) * r
            let alongV = (e2 * d1.x - e1 * d2.x) * r
            return (alongU, -alongV)
        }
    }

    /// A frame's two directions made square to the normal (Gram–Schmidt); the second keeps its side.
    static func orthonormal(_ frame: (SIMD3<Float>, SIMD3<Float>), normal: SIMD3<Float>) -> (SIMD3<Float>, SIMD3<Float>) {
        let fallback = WearBake.basis(normal)
        let tangent = normalize3(frame.0 - normal * dot3(normal, frame.0), fallback: fallback.0)
        var bitangent = cross3(normal, tangent)
        if dot3(bitangent, frame.1) < 0 { bitangent = -bitangent }
        return (tangent, bitangent)
    }
}
