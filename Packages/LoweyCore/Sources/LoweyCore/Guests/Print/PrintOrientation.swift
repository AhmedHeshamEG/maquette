import Foundation

/// Which way up to print (G1, Print): the overhangs a printer can't bridge (faces leaning out past 45° from upright,
/// facing down, not on the bed), and the turn that needs the least support, rests on the most, and stands lowest.
public enum PrintOrientation {
    /// Faces leaning out further than this from upright (degrees) need support.
    public static let overhangLimit = 45.0

    /// The faces of a world-space solid that need support, and their area (square metres).
    public static func overhangs(_ mesh: EditableMesh, limit: Double = overhangLimit) -> (faces: [Int], area: Double) {
        guard let bed = mesh.bounds?.min.y else { return ([], 0) }
        let threshold = -sin(limit * .pi / 180)
        var faces: [Int] = [], area = 0.0
        for index in mesh.faces.indices {
            let normal = mesh.normal(of: index)
            guard normal.y < threshold else { continue }
            let lowest = mesh.faces[index].outline.map { mesh.vertices[$0].y }.max() ?? bed
            if normal.y < -0.999, lowest <= bed + 2e-4 { continue }
            faces.append(index)
            area += mesh.area(of: index)
        }
        return (faces, area)
    }

    public struct Choice: Sendable {
        /// The turn to give the thing (applied before its own).
        public var rotation: Quat
        /// What the printer would build under it (cubic millimetres) and what rests on the bed (square millimetres).
        public var support: Double
        public var contact: Double
    }

    /// The best way up for a world-space solid: every face of its hull and the six sides tried as the bottom.
    public static func best(_ mesh: EditableMesh) -> Choice {
        var candidates: [Vec3] = [.unitX, -Vec3.unitX, .unitY, -Vec3.unitY, .unitZ, -Vec3.unitZ]
        // The hull's flat sides, biggest first (coplanar triangles counted together).
        var sides: [(normal: Vec3, area: Double)] = []
        for (a, b, c) in QuickHull3D.hull(mesh.vertices) {
            let cross = (b - a).cross(c - a)
            let normal = cross.normalized
            if let index = sides.firstIndex(where: { $0.normal.dot(normal) > 0.9999 }) {
                sides[index].area += cross.length / 2
            } else {
                sides.append((normal, cross.length / 2))
            }
        }
        candidates += sides.sorted { $0.area > $1.area }.prefix(16).map(\.normal)
        var best: Choice?, bestScore = Double.infinity
        for down in candidates where down.length > 0.5 {
            let rotation = Quat.rotation(from: down, to: -Vec3.unitY)
            let (support, contact, height) = cost(mesh, turned: rotation)
            let score = support - contact * 2 + height * 0.5
            if score < bestScore - 1e-9 {
                bestScore = score
                best = Choice(rotation: rotation, support: support, contact: contact)
            }
        }
        return best ?? Choice(rotation: .identity, support: 0, contact: 0)
    }

    /// Support volume and bed contact (millimetres) and the height (millimetres) of the solid turned.
    static func cost(_ mesh: EditableMesh, turned rotation: Quat) -> (support: Double, contact: Double, height: Double) {
        let points = mesh.vertices.map { rotation.act($0) }
        guard let bed = points.map(\.y).min(), let top = points.map(\.y).max() else { return (0, 0, 0) }
        let limit = -sin(overhangLimit * .pi / 180)
        var support = 0.0, contact = 0.0
        for (a, b, c) in mesh.triangulated().triangles {
            let pa = points[a], pb = points[b], pc = points[c]
            let cross = (pb - pa).cross(pc - pa)
            let area = cross.length / 2 * 1e6
            guard area > 0 else { continue }
            let normal = cross.normalized
            let height = ((pa.y + pb.y + pc.y) / 3 - bed) * 1000
            if normal.y < -0.999, height < 0.2 {
                contact += area
            } else if normal.y < limit {
                support += area * -normal.y * height
            }
        }
        return (support, contact, (top - bed) * 1000)
    }
}
