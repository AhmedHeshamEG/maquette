import Foundation

/// How far each point near a surface is from it, on a grid in the surface's own space: what fluids collide with. It's
/// unsigned (a wall pushes from whichever side a drop is on), so open shapes like a cup without a lid work as well as
/// closed ones. Beyond a few cells it holds the band's width.
struct DistanceField: Sendable {
    var origin: Vec3
    var cell: Double
    var size: SIMD3<Int32>
    var values: [Float]
    var band: Double

    static let maxCells: Int32 = 96

    static func make(_ mesh: MeshData, cell requested: Double) -> DistanceField? {
        guard let bounds = mesh.bounds, mesh.triangleCount > 0 else { return nil }
        var cell = requested
        let biggest = bounds.size.maxComponent + 6 * cell
        if biggest / cell > Double(maxCells - 1) { cell = biggest / Double(maxCells - 1) }
        let band = cell * 3
        let origin = bounds.min - Vec3(band, band, band)
        let extent = bounds.size + Vec3(band, band, band) * 2
        let size = SIMD3<Int32>(Int32((extent.x / cell).rounded(.up)) + 1, Int32((extent.y / cell).rounded(.up)) + 1, Int32((extent.z / cell).rounded(.up)) + 1)
        var field = DistanceField(origin: origin, cell: cell, size: size,
                                  values: Array(repeating: Float(band), count: Int(size.x) * Int(size.y) * Int(size.z)), band: band)
        for triangle in stride(from: 0, to: mesh.indices.count - 2, by: 3) {
            let a = Vec3(mesh.positions[Int(mesh.indices[triangle])])
            let b = Vec3(mesh.positions[Int(mesh.indices[triangle + 1])])
            let c = Vec3(mesh.positions[Int(mesh.indices[triangle + 2])])
            field.stamp(a, b, c)
        }
        return field
    }

    private mutating func stamp(_ a: Vec3, _ b: Vec3, _ c: Vec3) {
        let low = Vec3(min(a.x, b.x, c.x), min(a.y, b.y, c.y), min(a.z, b.z, c.z)) - Vec3(band, band, band)
        let high = Vec3(max(a.x, b.x, c.x), max(a.y, b.y, c.y), max(a.z, b.z, c.z)) + Vec3(band, band, band)
        let first = index(of: low)
        let last = index(of: high)
        guard first.x <= last.x, first.y <= last.y, first.z <= last.z else { return }
        for z in first.z ... last.z {
            for y in first.y ... last.y {
                for x in first.x ... last.x {
                    let point = origin + Vec3(Double(x), Double(y), Double(z)) * cell
                    let distance = Float(Self.closest(point, a, b, c).distance(to: point))
                    let slot = (Int(z) * Int(size.y) + Int(y)) * Int(size.x) + Int(x)
                    if distance < values[slot] { values[slot] = distance }
                }
            }
        }
    }

    private func index(of point: Vec3) -> SIMD3<Int32> {
        let p = (point - origin) / cell
        return SIMD3<Int32>(Int32(min(max(p.x.rounded(.down), 0), Double(size.x - 1))), Int32(min(max(p.y.rounded(.down), 0), Double(size.y - 1))),
                            Int32(min(max(p.z.rounded(.down), 0), Double(size.z - 1))))
    }

    /// The distance at a point in the field's space (the band's width outside the grid).
    func distance(at point: Vec3) -> Double {
        let p = (point - origin) / cell
        guard p.x >= 0, p.y >= 0, p.z >= 0, p.x < Double(size.x - 1), p.y < Double(size.y - 1), p.z < Double(size.z - 1) else { return band }
        let x = Int(p.x)
        let y = Int(p.y)
        let z = Int(p.z)
        let fx = p.x - Double(x)
        let fy = p.y - Double(y)
        let fz = p.z - Double(z)
        func v(_ dx: Int, _ dy: Int, _ dz: Int) -> Double {
            Double(values[((z + dz) * Int(size.y) + (y + dy)) * Int(size.x) + (x + dx)])
        }
        let c00 = v(0, 0, 0) * (1 - fx) + v(1, 0, 0) * fx
        let c10 = v(0, 1, 0) * (1 - fx) + v(1, 1, 0) * fx
        let c01 = v(0, 0, 1) * (1 - fx) + v(1, 0, 1) * fx
        let c11 = v(0, 1, 1) * (1 - fx) + v(1, 1, 1) * fx
        return (c00 * (1 - fy) + c10 * fy) * (1 - fz) + (c01 * (1 - fy) + c11 * fy) * fz
    }

    /// The way away from the surface at a point.
    func gradient(at point: Vec3) -> Vec3 {
        let h = cell * 0.5
        let g = Vec3(distance(at: point + Vec3(h, 0, 0)) - distance(at: point - Vec3(h, 0, 0)),
                     distance(at: point + Vec3(0, h, 0)) - distance(at: point - Vec3(0, h, 0)),
                     distance(at: point + Vec3(0, 0, h)) - distance(at: point - Vec3(0, 0, h)))
        return g.length > 1e-12 ? g.normalized : .unitY
    }

    /// The closest point of triangle abc to p (Ericson, Real-Time Collision Detection 5.1.5).
    static func closest(_ p: Vec3, _ a: Vec3, _ b: Vec3, _ c: Vec3) -> Vec3 {
        let ab = b - a
        let ac = c - a
        let ap = p - a
        let d1 = ab.dot(ap)
        let d2 = ac.dot(ap)
        if d1 <= 0, d2 <= 0 { return a }
        let bp = p - b
        let d3 = ab.dot(bp)
        let d4 = ac.dot(bp)
        if d3 >= 0, d4 <= d3 { return b }
        let vc = d1 * d4 - d3 * d2
        if vc <= 0, d1 >= 0, d3 <= 0 { return a + ab * (d1 / (d1 - d3)) }
        let cp = p - c
        let d5 = ab.dot(cp)
        let d6 = ac.dot(cp)
        if d6 >= 0, d5 <= d6 { return c }
        let vb = d5 * d2 - d1 * d6
        if vb <= 0, d2 >= 0, d6 <= 0 { return a + ac * (d2 / (d2 - d6)) }
        let va = d3 * d6 - d5 * d4
        if va <= 0, d4 - d3 >= 0, d5 - d6 >= 0 { return b + (c - b) * ((d4 - d3) / ((d4 - d3) + (d5 - d6))) }
        let denominator = 1 / (va + vb + vc)
        return a + ab * (vb * denominator) + ac * (vc * denominator)
    }
}
