import Foundation

/// The surface brushes: grab pulls a patch of the surface along, smooth evens it out, inflate puffs it up. Enough to
/// touch up a shape or a sculpt while building a scene (Nomad Sculpt owns sculpting). They move the corners of the
/// surface the stage shows, and keep how far each moved (`SculptLayer`).
public enum SculptBrush: String, Codable, Sendable, CaseIterable {
    case grab, smooth, inflate

    public var title: String {
        switch self {
        case .grab: "Grab"
        case .smooth: "Smooth"
        case .inflate: "Inflate"
        }
    }
}

/// A surface ready for brushing: corners at the same place move together (a cube's three corners at one point are one),
/// and each knows its neighbours. Built once per stroke from the shape before its strokes.
public struct SculptSurface: Sendable {
    /// The welded point each corner belongs to.
    public let pointOf: [Int]
    /// Each point's rest place (before any stroke).
    public let rest: [SIMD3<Float>]
    let corners: [[Int]]
    let neighbours: [[Int]]

    public init(_ mesh: MeshData) {
        let size = mesh.bounds.map { Float($0.size.maxComponent) } ?? 1
        let scale = 1 / max(size * 1e-5, 1e-9)
        var keys: [SIMD3<Int32>: Int] = [:]
        var pointOf: [Int] = []
        var rest: [SIMD3<Float>] = []
        var corners: [[Int]] = []
        for (corner, position) in mesh.positions.enumerated() {
            let key = SIMD3<Int32>(Int32((position.x * scale).rounded()), Int32((position.y * scale).rounded()), Int32((position.z * scale).rounded()))
            if let point = keys[key] {
                pointOf.append(point)
                corners[point].append(corner)
            } else {
                keys[key] = rest.count
                pointOf.append(rest.count)
                corners.append([corner])
                rest.append(position)
            }
        }
        var neighbours = [Set<Int>](repeating: [], count: rest.count)
        for triangle in stride(from: 0, to: mesh.indices.count - 2, by: 3) {
            let a = pointOf[Int(mesh.indices[triangle])], b = pointOf[Int(mesh.indices[triangle + 1])], c = pointOf[Int(mesh.indices[triangle + 2])]
            neighbours[a].formUnion([b, c])
            neighbours[b].formUnion([a, c])
            neighbours[c].formUnion([a, b])
        }
        self.pointOf = pointOf
        self.rest = rest
        self.corners = corners
        self.neighbours = neighbours.enumerated().map { Array($0.element.subtracting([$0.offset])).sorted() }
    }

    public var cornerCount: Int { pointOf.count }

    /// Offsets per point from offsets per corner (a corner's offset is its point's).
    public func pointOffsets(_ cornerOffsets: [SIMD3<Float>]?) -> [SIMD3<Float>] {
        guard let cornerOffsets, cornerOffsets.count == pointOf.count else { return Array(repeating: .zero, count: rest.count) }
        return corners.map { cornerOffsets[$0[0]] }
    }

    /// Offsets per corner, for the file.
    public func cornerOffsets(_ pointOffsets: [SIMD3<Float>]) -> [SIMD3<Float>] {
        pointOf.map { pointOffsets[$0] }
    }

    /// Each point's normal on the surface as it is now (the average of its triangles').
    func normals(_ positions: [SIMD3<Float>], mesh triangles: [UInt32]) -> [SIMD3<Float>] {
        var sums = Array(repeating: SIMD3<Float>(0, 0, 0), count: rest.count)
        for triangle in stride(from: 0, to: triangles.count - 2, by: 3) {
            let a = pointOf[Int(triangles[triangle])], b = pointOf[Int(triangles[triangle + 1])], c = pointOf[Int(triangles[triangle + 2])]
            let normal = cross3(positions[b] - positions[a], positions[c] - positions[a])
            sums[a] += normal
            sums[b] += normal
            sums[c] += normal
        }
        return sums.map { normalize3($0, fallback: SIMD3<Float>(0, 1, 0)) }
    }
}

/// One stroke of a surface brush: the offsets it started from, and for grab the patch it holds.
public struct SculptStroke: Sendable {
    public let brush: SculptBrush
    public let surface: SculptSurface
    let triangles: [UInt32]
    /// Mirror the stroke across this axis through the shape's middle (nil = no symmetry).
    public let symmetry: Axis?
    let middle: SIMD3<Float>
    let start: [SIMD3<Float>]
    public private(set) var offsets: [SIMD3<Float>]
    /// Grab's held patch: point → weight, for each side of the mirror.
    private var held: [[Int: Float]] = []

    public init(brush: SculptBrush, mesh: MeshData, cornerOffsets: [SIMD3<Float>]?, symmetry: Axis?) {
        self.brush = brush
        surface = SculptSurface(mesh)
        triangles = mesh.indices
        self.symmetry = symmetry
        let bounds = mesh.bounds
        middle = bounds.map { SIMD3<Float>(Float($0.center.x), Float($0.center.y), Float($0.center.z)) } ?? .zero
        start = surface.pointOffsets(cornerOffsets)
        offsets = start
    }

    /// The surface's points where they are now.
    public var positions: [SIMD3<Float>] {
        zip(surface.rest, offsets).map { $0 + $1 }
    }

    /// The offsets per corner (what the layer stores).
    public var cornerOffsets: [SIMD3<Float>] { surface.cornerOffsets(offsets) }

    /// A dab at `centre` (object space) of `radius`, at `strength` 0…1. Grab is handed the whole drag so far as `moved`.
    public mutating func dab(at centre: SIMD3<Float>, radius: Float, strength: Float, moved: SIMD3<Float> = .zero) {
        let centres = mirrored(centre)
        switch brush {
        case .grab:
            if held.isEmpty { held = centres.map { weights(around: $0, radius: radius, of: positions(at: start)) } }
            offsets = start
            for (side, patch) in held.enumerated() {
                let delta = side == 0 ? moved : flip(moved)
                for (point, weight) in patch { offsets[point] += delta * weight }
            }
        case .smooth:
            for centre in centres { smooth(around: centre, radius: radius, strength: strength) }
        case .inflate:
            for centre in centres { inflate(around: centre, radius: radius, strength: strength) }
        }
    }

    private func positions(at offsets: [SIMD3<Float>]) -> [SIMD3<Float>] {
        zip(surface.rest, offsets).map { $0 + $1 }
    }

    /// The centre and, with symmetry, its mirror image.
    private func mirrored(_ point: SIMD3<Float>) -> [SIMD3<Float>] {
        guard symmetry != nil else { return [point] }
        let image = flipped(point)
        return simd_distance3(image, point) < 1e-6 ? [point] : [point, image]
    }

    private func flipped(_ point: SIMD3<Float>) -> SIMD3<Float> {
        guard let axis = symmetry else { return point }
        var result = point
        result[axis.index] = 2 * middle[axis.index] - point[axis.index]
        return result
    }

    private func flip(_ vector: SIMD3<Float>) -> SIMD3<Float> {
        guard let axis = symmetry else { return vector }
        var result = vector
        result[axis.index] = -vector[axis.index]
        return result
    }

    /// Points within the radius and their falloff: (1 − (d/r)²)², full at the centre, nothing at the edge.
    private func weights(around centre: SIMD3<Float>, radius: Float, of positions: [SIMD3<Float>]) -> [Int: Float] {
        var result: [Int: Float] = [:]
        let r2 = radius * radius
        for (point, position) in positions.enumerated() {
            let d2 = simd_length_squared3(position - centre)
            guard d2 < r2 else { continue }
            let f = 1 - d2 / r2
            result[point] = f * f
        }
        return result
    }

    private mutating func smooth(around centre: SIMD3<Float>, radius: Float, strength: Float) {
        let now = positions
        for (point, weight) in weights(around: centre, radius: radius, of: now) {
            let around = surface.neighbours[point]
            guard !around.isEmpty else { continue }
            let average = around.reduce(SIMD3<Float>(0, 0, 0)) { $0 + now[$1] } / Float(around.count)
            offsets[point] += (average - now[point]) * min(strength * weight, 1)
        }
    }

    private mutating func inflate(around centre: SIMD3<Float>, radius: Float, strength: Float) {
        let now = positions
        let normals = surface.normals(now, mesh: triangles)
        for (point, weight) in weights(around: centre, radius: radius, of: now) {
            offsets[point] += normals[point] * (radius * 0.08 * strength * weight)
        }
    }
}

@inline(__always) func simd_length_squared3(_ v: SIMD3<Float>) -> Float { v.x * v.x + v.y * v.y + v.z * v.z }

@inline(__always) func simd_distance3(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> Float { simd_length_squared3(a - b).squareRoot() }
