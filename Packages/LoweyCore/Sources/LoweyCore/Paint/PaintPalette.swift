import Foundation

/// How a painted thing's colour leaves in a 3D file (D-356): as its texture, as a colour per corner (game engines that
/// read vertex colours), or as a palette texture: every face one flat colour from a small picture of swatches, the
/// low-poly game artist's way.
public enum PaintColorOutput: String, Codable, Sendable, CaseIterable {
    case texture, vertexColors, palette

    public var title: String {
        switch self {
        case .texture: "Texture"
        case .vertexColors: "Vertex colours"
        case .palette: "Palette"
        }
    }
}

/// A palette texture: each triangle's colour (at its middle) as a swatch, the mesh split so each triangle's corners
/// sit on its swatch.
public enum PaintPalette {
    public static let swatch = 4

    /// The mesh with its uvs on the swatches and the palette picture (colours as sRGB, opaque).
    public static func make(_ mesh: MeshData, colour: RGBAImage) -> (mesh: MeshData, palette: RGBAImage) {
        var colours: [UInt32] = []
        var index: [UInt32: Int] = [:]
        var faceSwatch: [Int] = []
        for face in 0 ..< mesh.triangleCount {
            let uv = (0 ..< 3).map { mesh.uvs.indices.contains(Int(mesh.indices[face * 3 + $0])) ? mesh.uvs[Int(mesh.indices[face * 3 + $0])] : .zero }
            let middle = (uv[0] + uv[1] + uv[2]) / 3
            let c = colour.sample(u: Double(middle.x), v: Double(middle.y))
            let (r, g, b, _) = RGBAImage.bytes(RGBA(c.r, c.g, c.b, 1))
            let packed = UInt32(r) << 16 | UInt32(g) << 8 | UInt32(b)
            if let known = index[packed] {
                faceSwatch.append(known)
            } else {
                index[packed] = colours.count
                faceSwatch.append(colours.count)
                colours.append(packed)
            }
        }
        let perSide = max(Int(Double(max(colours.count, 1)).squareRoot().rounded(.up)), 1)
        let side = perSide * swatch
        var palette = RGBAImage(width: side, height: side, color: .white)
        for (number, packed) in colours.enumerated() {
            let colour = RGBA(Double(packed >> 16 & 0xFF) / 255, Double(packed >> 8 & 0xFF) / 255, Double(packed & 0xFF) / 255, 1)
            for y in 0 ..< swatch {
                for x in 0 ..< swatch {
                    palette.setPixel(number % perSide * swatch + x, number / perSide * swatch + y, colour)
                }
            }
        }
        var split = MeshData(positions: [], normals: [], uvs: [], indices: [])
        let hasNormals = mesh.normals.count == mesh.positions.count
        for face in 0 ..< mesh.triangleCount {
            let number = faceSwatch[face]
            let centre = SIMD2<Float>(Float(number % perSide) + 0.5, Float(number / perSide) + 0.5) / Float(perSide)
            for corner in 0 ..< 3 {
                let vertex = Int(mesh.indices[face * 3 + corner])
                split.positions.append(mesh.positions[vertex])
                split.normals.append(hasNormals ? mesh.normals[vertex] : SIMD3<Float>(0, 1, 0))
                split.uvs.append(centre)
                split.indices.append(UInt32(split.indices.count))
            }
        }
        return (split, palette)
    }
}
