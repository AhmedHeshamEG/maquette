import Foundation
import XAtlasCpp

/// Where every corner of a mesh lies on its paint texture. Seams split vertices, so an unwrap has its own vertices,
/// each pointing back at the mesh vertex it came from (`source`) and keeping where it was (`positions`, so paint can
/// be carried onto a changed shape), and its own triangles (the mesh's, in order). Stored in the project as a small
/// binary file, so paint never moves even if the unwrapper changes.
public struct PaintUnwrap: Hashable, Sendable {
    public var source: [UInt32]
    public var positions: [SIMD3<Float>]
    public var uvs: [SIMD2<Float>]
    public var indices: [UInt32]

    public init(source: [UInt32], positions: [SIMD3<Float>], uvs: [SIMD2<Float>], indices: [UInt32]) {
        self.source = source
        self.positions = positions
        self.uvs = uvs
        self.indices = indices
    }

    public var vertexCount: Int { source.count }
    public var triangleCount: Int { indices.count / 3 }

    public enum Failure: Error, Equatable, CustomStringConvertible {
        case empty, unwrapFailed, corrupt

        public var description: String {
            switch self {
            case .empty: "This object has no surface to paint"
            case .unwrapFailed: "This shape couldn't be laid flat for painting"
            case .corrupt: "The painting's surface file is damaged"
            }
        }
    }

    // MARK: Making one

    /// Lays a mesh flat with xatlas (one square atlas, charts padded for bilinear filtering). `scale` stretches the
    /// mesh first, so a long box gets as many pixels along its length as it shows (the renderer scales primitives).
    /// `seams` are edges marked by hand: no chart crosses one that closes off an area (D-349).
    public static func unwrap(_ mesh: MeshData, scale: SIMD3<Float> = SIMD3<Float>(1, 1, 1), padding: UInt32 = 3,
                              seams: [PaintSeam]? = nil) throws(Failure) -> PaintUnwrap {
        guard !mesh.isEmpty else { throw .empty }
        let positions = mesh.positions.flatMap { [$0.x * scale.x, $0.y * scale.y, $0.z * scale.z] }
        let normals = mesh.normals.count == mesh.positions.count ? mesh.normals.flatMap { [$0.x, $0.y, $0.z] } : nil
        let groups = seams.flatMap { $0.isEmpty ? nil : SeamGroups.groups(mesh, seams: $0) }
        var result = XAUnwrap()
        let status = positions.withUnsafeBufferPointer { p in
            mesh.indices.withUnsafeBufferPointer { i in
                (groups ?? []).withUnsafeBufferPointer { g in
                    let faceGroups = groups == nil ? nil : g.baseAddress
                    if let normals {
                        return normals.withUnsafeBufferPointer { n in
                            XAUnwrapMeshGrouped(p.baseAddress, n.baseAddress, mesh.positions.count, i.baseAddress, mesh.indices.count, faceGroups,
                                                1024, padding, &result)
                        }
                    }
                    return XAUnwrapMeshGrouped(p.baseAddress, nil, mesh.positions.count, i.baseAddress, mesh.indices.count, faceGroups, 1024,
                                               padding, &result)
                }
            }
        }
        defer { XAUnwrapFree(&result) }
        guard status == XAOk, result.vertexCount > 0 else { throw status == XAInvalidInput ? .empty : .unwrapFailed }
        let count = result.vertexCount
        let source = Array(UnsafeBufferPointer(start: result.xref, count: count))
        let flat = UnsafeBufferPointer(start: result.uvs, count: count * 2)
        let uvs = (0 ..< count).map { SIMD2<Float>(flat[$0 * 2], flat[$0 * 2 + 1]) }
        let indices = Array(UnsafeBufferPointer(start: result.indices, count: result.indexCount))
        return PaintUnwrap(source: source, positions: source.map { mesh.positions[Int($0)] }, uvs: uvs, indices: indices)
    }

    /// The mesh's own uvs, when they're good to paint on: every one inside 0…1 and no two triangles over each other
    /// (checked on a coarse grid). Imported models made for texturing keep their layout; anything else is unwrapped.
    public static func existing(_ mesh: MeshData, grid: Int = 256) -> PaintUnwrap? {
        guard !mesh.isEmpty, mesh.uvs.count == mesh.positions.count else { return nil }
        guard mesh.uvs.allSatisfy({ $0.x >= 0 && $0.x <= 1 && $0.y >= 0 && $0.y <= 1 && $0.x.isFinite && $0.y.isFinite }) else { return nil }
        var area: Float = 0
        var covered = [UInt16](repeating: 0, count: grid * grid)
        var overlaps = 0
        var total = 0
        for triangle in 0 ..< mesh.triangleCount {
            let a = mesh.uvs[Int(mesh.indices[triangle * 3])], b = mesh.uvs[Int(mesh.indices[triangle * 3 + 1])]
            let c = mesh.uvs[Int(mesh.indices[triangle * 3 + 2])]
            area += abs((b - a).x * (c - a).y - (b - a).y * (c - a).x) / 2
            PaintRaster.triangle(a * Float(grid), b * Float(grid), c * Float(grid), width: grid, height: grid) { x, y, _ in
                covered[y * grid + x] &+= 1
                total += 1
                if covered[y * grid + x] > 1 { overlaps += 1 }
            }
        }
        // Barely any area (every uv at 0) or more than a sliver over each other: lay it out again.
        guard area > 0.02, total > 0, Double(overlaps) / Double(total) < 0.01 else { return nil }
        return PaintUnwrap(source: (0 ..< UInt32(mesh.positions.count)).map { $0 }, positions: mesh.positions, uvs: mesh.uvs, indices: mesh.indices)
    }

    // MARK: The paint mesh

    /// The surface as it was unwrapped (its stored positions; normals left out).
    public var surfaceMesh: MeshData {
        MeshData(positions: positions, normals: [], uvs: uvs, indices: indices)
    }

    /// The mesh drawn with paint: the source mesh's positions and normals at the unwrap's vertices, the unwrap's uvs.
    public func mesh(over mesh: MeshData) -> MeshData? {
        guard source.allSatisfy({ Int($0) < mesh.positions.count }) else { return nil }
        let hasNormals = mesh.normals.count == mesh.positions.count
        return MeshData(positions: source.map { mesh.positions[Int($0)] },
                        normals: hasNormals ? source.map { mesh.normals[Int($0)] } : source.map { _ in SIMD3<Float>(0, 1, 0) },
                        uvs: uvs, indices: indices)
    }

    // MARK: File form

    private static let magic: [UInt8] = Array("MQUV".utf8)
    private static let version: UInt32 = 1

    /// "MQUV", version, vertex count, index count, then source indices, positions (float triples), uvs (float pairs)
    /// and triangle indices, little-endian.
    public var data: Data {
        var data = Data(Self.magic)
        func put(_ value: UInt32) {
            withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
        }
        put(Self.version)
        put(UInt32(source.count))
        put(UInt32(indices.count))
        source.forEach(put)
        for position in positions {
            put(position.x.bitPattern)
            put(position.y.bitPattern)
            put(position.z.bitPattern)
        }
        for uv in uvs {
            put(uv.x.bitPattern)
            put(uv.y.bitPattern)
        }
        indices.forEach(put)
        return data
    }

    public init(data: Data) throws(Failure) {
        let bytes = [UInt8](data)
        guard bytes.count >= 16, Array(bytes[0 ..< 4]) == Self.magic else { throw .corrupt }
        func word(_ offset: Int) -> UInt32 {
            UInt32(bytes[offset]) | UInt32(bytes[offset + 1]) << 8 | UInt32(bytes[offset + 2]) << 16 | UInt32(bytes[offset + 3]) << 24
        }
        guard word(4) == Self.version else { throw .corrupt }
        let vertices = Int(word(8)), count = Int(word(12))
        guard bytes.count == 16 + (vertices * 6 + count) * 4, count % 3 == 0 else { throw .corrupt }
        var offset = 16
        var source = [UInt32](repeating: 0, count: vertices)
        for index in 0 ..< vertices {
            source[index] = word(offset)
            offset += 4
        }
        var positions = [SIMD3<Float>](repeating: .zero, count: vertices)
        for index in 0 ..< vertices {
            positions[index] = SIMD3<Float>(Float(bitPattern: word(offset)), Float(bitPattern: word(offset + 4)), Float(bitPattern: word(offset + 8)))
            offset += 12
        }
        var uvs = [SIMD2<Float>](repeating: .zero, count: vertices)
        for index in 0 ..< vertices {
            uvs[index] = SIMD2<Float>(Float(bitPattern: word(offset)), Float(bitPattern: word(offset + 4)))
            offset += 8
        }
        var indices = [UInt32](repeating: 0, count: count)
        for index in 0 ..< count {
            indices[index] = word(offset)
            guard Int(indices[index]) < vertices else { throw .corrupt }
            offset += 4
        }
        self.init(source: source, positions: positions, uvs: uvs, indices: indices)
    }
}

/// Fingerprints of the meshes paint is made for (FNV-1a over positions and triangles), so a changed shape is noticed.
public enum PaintMesh {
    public static func fingerprint(_ mesh: MeshData) -> String {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        func mix(_ value: UInt32) {
            for shift in stride(from: 0, to: 32, by: 8) {
                hash ^= UInt64((value >> UInt32(shift)) & 0xFF)
                hash = hash &* 0x0000_0100_0000_01B3
            }
        }
        mix(UInt32(mesh.positions.count))
        for position in mesh.positions {
            mix(position.x.bitPattern)
            mix(position.y.bitPattern)
            mix(position.z.bitPattern)
        }
        mesh.indices.forEach(mix)
        return BrushKey.hex(hash)
    }
}

/// Hand-marked seams as groups of triangles: triangles are joined across every edge that isn't on a seam, so each
/// area a seam closes off is its own group and the unwrap cuts there.
enum SeamGroups {
    static func groups(_ mesh: MeshData, seams: [PaintSeam]) -> [UInt32] {
        let count = mesh.triangleCount
        guard count > 0 else { return [] }
        let tolerance = max(SurfaceTexels.diagonal(mesh) * 1e-4, 1e-6)
        let segments = seams.map { (SIMD3<Float>(Float($0.a.x), Float($0.a.y), Float($0.a.z)), SIMD3<Float>(Float($0.b.x), Float($0.b.y), Float($0.b.z))) }
        func onSeam(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> Bool {
            // An edge lies on a seam when both its ends do (a seam can span several edges of a finer mesh).
            segments.contains { SharpEdges.distance(a, $0.0, $0.1) < tolerance && SharpEdges.distance(b, $0.0, $0.1) < tolerance }
        }
        var welded: [SIMD3<Int32>: Int] = [:]
        func key(_ index: UInt32) -> Int {
            let p = mesh.positions[Int(index)] / tolerance
            let q = SIMD3<Int32>(Int32(clamping: Int(p.x.rounded())), Int32(clamping: Int(p.y.rounded())), Int32(clamping: Int(p.z.rounded())))
            if let known = welded[q] { return known }
            welded[q] = welded.count
            return welded.count - 1
        }
        var edges: [SIMD2<Int>: [Int]] = [:]
        var cut = Set<SIMD2<Int>>()
        for face in 0 ..< count {
            for (a, b) in [(0, 1), (1, 2), (2, 0)] {
                let ia = mesh.indices[face * 3 + a], ib = mesh.indices[face * 3 + b]
                let ka = key(ia), kb = key(ib)
                let edge = SIMD2<Int>(min(ka, kb), max(ka, kb))
                edges[edge, default: []].append(face)
                if !cut.contains(edge), onSeam(mesh.positions[Int(ia)], mesh.positions[Int(ib)]) { cut.insert(edge) }
            }
        }
        var neighbours = [[Int]](repeating: [], count: count)
        for (edge, faces) in edges where !cut.contains(edge) && faces.count > 1 {
            for face in faces {
                neighbours[face] += faces.filter { $0 != face }
            }
        }
        var group = [UInt32](repeating: .max, count: count)
        var next: UInt32 = 0
        for start in 0 ..< count where group[start] == .max {
            var stack = [start]
            group[start] = next
            while let face = stack.popLast() {
                for other in neighbours[face] where group[other] == .max {
                    group[other] = next
                    stack.append(other)
                }
            }
            next += 1
        }
        return group
    }
}
