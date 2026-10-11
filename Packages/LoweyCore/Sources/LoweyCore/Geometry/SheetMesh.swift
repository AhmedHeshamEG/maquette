import Foundation

/// What the stage draws for the sheet under the Pencil (never exported): a see-through fill and a fine border, in
/// world space. A sheet on an object shows only a small disc where it was laid: the object is the surface.
public enum SheetMesh {
    /// The see-through surface.
    public static func fill(_ sheet: DrawingSheet, in scene: Scene) -> MeshData {
        guard let frame = sheet.worldFrame(in: scene) else { return MeshData() }
        let local: MeshData = switch sheet.shape {
        case .flat: rectangle(width: sheet.width, height: sheet.height)
        case .around: band(radius: sheet.radius, height: sheet.height, segments: 48)
        case .dome: dome(radius: sheet.radius, rings: 16, segments: 32)
        case .onObject: disc(radius: max(min(sheet.width, sheet.height) * 0.06, 0.02), segments: 24)
        }
        return placed(local, origin: frame.origin, rotation: frame.rotation)
    }

    /// The border: a flat sheet's four edges, the rims of one wrapped around (nothing for a dome or an object).
    public static func border(_ sheet: DrawingSheet, in scene: Scene, thickness: Double) -> MeshData {
        guard let frame = sheet.worldFrame(in: scene) else { return MeshData() }
        var mesh = MeshData()
        switch sheet.shape {
        case .flat:
            let halfWidth = sheet.width / 2, halfHeight = sheet.height / 2
            let corners = [Vec3(-halfWidth, -halfHeight, 0), Vec3(halfWidth, -halfHeight, 0), Vec3(halfWidth, halfHeight, 0), Vec3(-halfWidth, halfHeight, 0)]
            for index in corners.indices {
                mesh.append(strip(from: corners[index], to: corners[(index + 1) % 4], thickness: thickness))
            }
        case .around:
            for y in [-sheet.height / 2, sheet.height / 2] {
                mesh.append(band(radius: sheet.radius, height: thickness, segments: 48, centreY: y))
            }
        case .dome, .onObject:
            return MeshData()
        }
        return placed(mesh, origin: frame.origin, rotation: frame.rotation)
    }

    // MARK: Pieces, in the sheet's frame (+z faces the person who placed it)

    static func rectangle(width: Double, height: Double) -> MeshData {
        let x = Float(width / 2), y = Float(height / 2)
        return MeshData(positions: [SIMD3(-x, -y, 0), SIMD3(x, -y, 0), SIMD3(x, y, 0), SIMD3(-x, y, 0)],
                        normals: Array(repeating: SIMD3(0, 0, 1), count: 4), uvs: [SIMD2(0, 0), SIMD2(1, 0), SIMD2(1, 1), SIMD2(0, 1)],
                        indices: [0, 1, 2, 0, 2, 3])
    }

    /// A thin quad in the sheet's plane along one edge.
    static func strip(from start: Vec3, to end: Vec3, thickness: Double) -> MeshData {
        let along = (end - start).normalized
        let side = Vec3(-along.y, along.x, 0) * (thickness / 2)
        let points = [start - side, end - side, end + side, start + side].map(\.float3)
        return MeshData(positions: points, normals: Array(repeating: SIMD3(0, 0, 1), count: 4), uvs: Array(repeating: .zero, count: 4),
                        indices: [0, 1, 2, 0, 2, 3])
    }

    /// The side of a standing cylinder whose front (+z) passes through the frame's origin.
    static func band(radius: Double, height: Double, segments: Int, centreY: Double = 0) -> MeshData {
        var mesh = MeshData()
        for index in 0 ... segments {
            let angle = 2 * Double.pi * Double(index) / Double(segments)
            let normal = Vec3(sin(angle), 0, cos(angle))
            for y in [centreY - height / 2, centreY + height / 2] {
                mesh.positions.append(Vec3(radius * normal.x, y, radius * normal.z - radius).float3)
                mesh.normals.append(normal.float3)
                mesh.uvs.append(SIMD2(Float(index) / Float(segments), y > centreY ? 1 : 0))
            }
        }
        for index in 0 ..< UInt32(segments) {
            let a = index * 2, b = a + 1, c = a + 2, d = a + 3
            mesh.indices += [a, c, d, a, d, b]
        }
        return mesh
    }

    /// A sphere whose front passes through the frame's origin.
    static func dome(radius: Double, rings: Int, segments: Int) -> MeshData {
        var mesh = MeshData()
        for ring in 0 ... rings {
            let up = -Double.pi / 2 + Double.pi * Double(ring) / Double(rings)
            for segment in 0 ... segments {
                let across = 2 * Double.pi * Double(segment) / Double(segments)
                let normal = Vec3(cos(up) * sin(across), sin(up), cos(up) * cos(across))
                mesh.positions.append((normal * radius - Vec3(0, 0, radius)).float3)
                mesh.normals.append(normal.float3)
                mesh.uvs.append(SIMD2(Float(segment) / Float(segments), Float(ring) / Float(rings)))
            }
        }
        let row = UInt32(segments + 1)
        for ring in 0 ..< UInt32(rings) {
            for segment in 0 ..< UInt32(segments) {
                let a = ring * row + segment, b = a + 1, c = a + row, d = c + 1
                mesh.indices += [a, b, d, a, d, c]
            }
        }
        return mesh
    }

    static func disc(radius: Double, segments: Int) -> MeshData {
        var mesh = MeshData(positions: [SIMD3(0, 0, 0.002)], normals: [SIMD3(0, 0, 1)], uvs: [SIMD2(0.5, 0.5)], indices: [])
        for index in 0 ... segments {
            let angle = 2 * Double.pi * Double(index) / Double(segments)
            mesh.positions.append(SIMD3(Float(radius * cos(angle)), Float(radius * sin(angle)), 0.002))
            mesh.normals.append(SIMD3(0, 0, 1))
            mesh.uvs.append(.zero)
        }
        for index in 1 ... UInt32(segments) {
            mesh.indices += [0, index, index + 1]
        }
        return mesh
    }

    static func placed(_ mesh: MeshData, origin: Vec3, rotation: Quat) -> MeshData {
        var result = mesh
        result.positions = mesh.positions.map { (origin + rotation.act(Vec3($0))).float3 }
        result.normals = mesh.normals.map { rotation.act(Vec3($0)).float3 }
        return result
    }
}
