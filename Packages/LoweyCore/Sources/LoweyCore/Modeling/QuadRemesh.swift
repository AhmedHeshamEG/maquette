import Foundation
import InstantMeshesCpp

/// Clean topology: a messy surface (a sculpt, a scan, a boolean's slivers) becomes an even mesh of quads a game engine
/// or a rig is happy with, through Instant Meshes (vendored, `Packages/InstantMeshes`). The shape stays; only how its
/// surface is cut changes.
public enum QuadRemesh {
    public enum Failure: Error, Equatable, CustomStringConvertible {
        case empty
        case failed(Int32)

        public var description: String {
            switch self {
            case .empty: "There's no surface to clean up"
            case .failed: "This shape couldn't be cleaned up (try a closed shape, or fewer faces)"
            }
        }
    }

    /// How the result is cut.
    public struct Options: Hashable, Sendable {
        /// About how many faces the result has.
        public var faces: Int
        /// Only quads (each face of the guide split in four), else mostly quads with a few triangles.
        public var pureQuads: Bool
        /// Edges sharper than this stay sharp (degrees; nil keeps none).
        public var sharpAngle: Double?

        public init(faces: Int, pureQuads: Bool = false, sharpAngle: Double? = 40) {
            self.faces = faces
            self.pureQuads = pureQuads
            self.sharpAngle = sharpAngle
        }
    }

    /// A good face count for a surface: an eighth of its triangles, kept between 200 and 20 000.
    public static func suggestedFaces(for mesh: MeshData) -> Int {
        let triangles = mesh.triangleCount
        return min(max(triangles / 8, 200), 20000)
    }

    /// The surface, welded and remeshed into quads (object space in, object space out).
    public static func remesh(_ mesh: MeshData, options: Options) throws(Failure) -> EditableMesh {
        let welded = mesh.welded(tolerance: weldTolerance(mesh))
        guard welded.triangleCount > 0, welded.positions.count >= 3 else { throw .empty }
        let positions = welded.positions.flatMap { [$0.x, $0.y, $0.z] }
        var out = IMSurface()
        let settings = IMOptions(targetFaces: UInt32(max(options.faces, 8)), creaseDegrees: Float(options.sharpAngle ?? 0),
                                 pureQuads: options.pureQuads ? 1 : 0, alignToBoundaries: 1, smoothIterations: 2)
        let code = positions.withUnsafeBufferPointer { points in
            welded.indices.withUnsafeBufferPointer { triangles in
                IMRemesh(points.baseAddress, UInt32(welded.positions.count), triangles.baseAddress, UInt32(welded.triangleCount), settings, &out)
            }
        }
        defer { IMFree(&out) }
        guard code == 0, out.faceCount > 0 else { throw .failed(code) }
        return surface(out, facingLike: welded)
    }

    private static func weldTolerance(_ mesh: MeshData) -> Float {
        let size = mesh.bounds.map { $0.size.maxComponent } ?? 1
        return Float(max(size, 1e-3) * 1e-6)
    }

    /// The C result as faces; turned inside out when its faces point the other way from the input's.
    private static func surface(_ out: IMSurface, facingLike input: MeshData) -> EditableMesh {
        let points = UnsafeBufferPointer(start: out.positions, count: Int(out.vertexCount) * 3)
        let indices = UnsafeBufferPointer(start: out.indices, count: Int(out.faceCount) * 4)
        let vertices = (0 ..< Int(out.vertexCount)).map { Vec3(Double(points[$0 * 3]), Double(points[$0 * 3 + 1]), Double(points[$0 * 3 + 2])) }
        var faces: [EditableMesh.Face] = []
        faces.reserveCapacity(Int(out.faceCount))
        for face in 0 ..< Int(out.faceCount) {
            var corners = (0 ..< 4).map { Int(indices[face * 4 + $0]) }
            if corners[2] == corners[3] { corners.removeLast() }
            guard Set(corners).count == corners.count else { continue }
            faces.append(EditableMesh.Face(corners))
        }
        let result = EditableMesh(vertices: vertices, faces: faces)
        let inputVolume = signedVolume(input)
        return inputVolume * result.volume < 0 ? result.flipped() : result
    }

    static func signedVolume(_ mesh: MeshData) -> Double {
        var total = 0.0
        for triangle in stride(from: 0, to: mesh.indices.count - 2, by: 3) {
            let a = mesh.positions[Int(mesh.indices[triangle])], b = mesh.positions[Int(mesh.indices[triangle + 1])]
            let c = mesh.positions[Int(mesh.indices[triangle + 2])]
            total += Double(dot3(a, cross3(b, c)))
        }
        return total / 6
    }
}

public extension EditableMesh {
    /// Every face walked the other way (inside out).
    func flipped() -> EditableMesh {
        EditableMesh(vertices: vertices, faces: faces.map { face in Face(loops: face.loops.map { Array($0.reversed()) }) })
    }

    /// Faces with holes cut into triangles, so every face is a single loop (subdivision and loop cuts need that).
    func withoutHoles() -> EditableMesh {
        guard faces.contains(where: { $0.loops.count > 1 }) else { return self }
        var result: [Face] = []
        for index in faces.indices {
            if faces[index].loops.count == 1 {
                result.append(faces[index])
            } else {
                result += triangulate(face: index).map { Face([$0.0, $0.1, $0.2]) }
            }
        }
        return EditableMesh(vertices: vertices, faces: result)
    }

    /// How many triangles the renderer draws for it.
    var triangleCount: Int {
        faces.reduce(0) { total, face in total + face.vertices.count - 2 + 2 * max(face.loops.count - 1, 0) }
    }
}
