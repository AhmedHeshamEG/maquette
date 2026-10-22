import Foundation

/// The maker's tools (G1, Print): split a part too big for the bed into two with pegs that line them up, hollow it
/// with drain holes, write a name into it or onto it, and scale it to a size. Every shape here is in world space.
public enum PrintTools {
    public enum Failure: Error, Equatable, CustomStringConvertible {
        case missesIt
        case boolean(MeshBoolean.Failure)
        case shell(Shell.Failure)

        public var description: String {
            switch self {
            case .missesIt: "The cut doesn't go through the part: move it so it crosses."
            case let .boolean(failure): failure.description
            case let .shell(failure): failure.description
            }
        }
    }

    // MARK: Split

    public struct Split: Sendable {
        /// The side the plane's normal points to (with the pegs) and the other side (with the holes), moved apart.
        public var first: EditableMesh
        public var second: EditableMesh
        public var pegs: Int
    }

    /// The part cut by the plane through `point` square to `normal`, pegs on the first part fitting holes in the
    /// second (`tolerance` per side), the second moved `gap` away.
    public static func split(_ mesh: EditableMesh, point: Vec3, normal: Vec3, pegs wantsPegs: Bool = true, tolerance: Double = 0.0002,
                             gap: Double = 0.01) throws(Failure) -> Split {
        let n = normal.normalized
        guard let bounds = mesh.bounds else { throw .missesIt }
        let reach = bounds.size.length * 2 + 1
        let frame = PlaneFrame(normal: n, origin: point)
        let square = [(-1.0, -1.0), (1.0, -1.0), (1.0, 1.0), (-1.0, 1.0)].map { point + frame.u * ($0.0 * reach) + frame.v * ($0.1 * reach) }
        let above = Prism.make(outline: square, holes: [], normal: n, from: 0, to: reach)
        let below = Prism.make(outline: square, holes: [], normal: n, from: -reach, to: 0)
        var first: EditableMesh, second: EditableMesh
        do throws(MeshBoolean.Failure) {
            first = try MeshBoolean.combine(mesh, above, .intersect)
            second = try MeshBoolean.combine(mesh, below, .intersect)
        } catch {
            throw .boolean(error)
        }
        guard !first.isEmpty, !second.isEmpty else { throw .missesIt }
        var placed = 0
        if wantsPegs {
            let spots = pegSpots(mesh, frame: frame)
            for spot in spots {
                let length = max(spot.radius * 4, 0.004)
                let peg = Threads.cylinder(radius: spot.radius, from: -length, to: 0.0003, axis: n, at: spot.centre)
                let hole = Threads.cylinder(radius: spot.radius + tolerance, from: -(length + tolerance * 2), to: 0.0005, axis: n, at: spot.centre)
                do throws(MeshBoolean.Failure) {
                    let withPeg = try MeshBoolean.combine(first, peg, .union)
                    let withHole = try MeshBoolean.combine(second, hole, .subtract)
                    first = withPeg
                    second = withHole
                    placed += 1
                } catch {
                    continue
                }
            }
        }
        second = second.transformed(by: Transform(position: n * -gap))
        return Split(first: first, second: second, pegs: placed)
    }

    /// Where pegs go on a cut: the thickest spot of the cross-section (and a second as far from it as the section
    /// allows, when it's long), each a peg up to 3 mm across that leaves a wall round it.
    static func pegSpots(_ mesh: EditableMesh, frame: PlaneFrame) -> [(centre: Vec3, radius: Double)] {
        let cuts = Section.cut(TriangleSoup(mesh), point: frame.origin, normal: frame.normal)
        let loops = cuts.flatMap(\.loops).map { $0.map { frame.project($0) } }
        let points = loops.flatMap(\.self)
        guard let first = points.first else { return [] }
        let span = points.reduce(0.0) { max($0, $1.distance(to: first)) }
        guard var grid = RoomFinder.Grid(around: points, size: max(span / 160, 0.0001), margin: span / 40 + 0.0002) else { return [] }
        grid.fill(loops)
        let inside = grid.cells.indices.filter { grid.cells[$0] == 1 }
        guard !inside.isEmpty else { return [] }
        let distance = grid.distances(of: inside)
        guard let best = inside.max(by: { distance[$0] < distance[$1] }) else { return [] }
        func centre(_ at: Int) -> Vec2 {
            Vec2(grid.origin.x + (Double(at % grid.columns) + 0.5) * grid.cell, grid.origin.y + (Double(at / grid.columns) + 0.5) * grid.cell)
        }
        let room = Double(distance[best]) * grid.cell
        let radius = min(0.0015, room * 0.4)
        guard radius >= 0.0006 else { return [] }
        var spots = [centre(best)]
        let apart = radius * 8
        let others = inside.filter { Double(distance[$0]) * grid.cell >= radius * 2.2 && centre($0).distance(to: spots[0]) >= apart }
        if let far = others.max(by: { centre($0).distance(to: spots[0]) < centre($1).distance(to: spots[0]) }) {
            spots.append(centre(far))
        }
        return spots.map { (frame.lift($0), radius) }
    }

    // MARK: Hollow

    /// The part hollowed to `wall`-thick walls, with `drain` holes (their diameter) through the floor so resin or
    /// powder can run out.
    public static func hollow(_ mesh: EditableMesh, wall: Double = 0.002, drain: Double = 0.003) throws(Failure) -> (mesh: EditableMesh, drains: Int) {
        var result: EditableMesh
        do throws(Shell.Failure) {
            result = try Shell.apply(mesh, thickness: wall)
        } catch {
            throw .shell(error)
        }
        guard drain > 0, let bounds = result.bounds else { return (result, 0) }
        let triangles = result.triangulated().triangles.map { (result.vertices[$0.0], result.vertices[$0.1], result.vertices[$0.2]) }
        let size = bounds.size, centre = bounds.center
        let along = size.x >= size.z ? Vec3.unitX * (size.x * 0.25) : Vec3.unitZ * (size.z * 0.25)
        var made = 0
        for spot in [centre - along, centre + along] {
            let start = Vec3(spot.x, bounds.min.y - 0.01, spot.z)
            let hits = triangles.compactMap { PrintCheck.intersect(Ray(origin: start, direction: .unitY), $0) }.sorted()
            guard hits.count >= 2 else { continue }
            let top = start.y + hits[1] + 0.0005
            let hole = EditableMesh.cylinder(base: Vec3(spot.x, bounds.min.y - 0.001, spot.z), radius: drain / 2, height: top - bounds.min.y + 0.001)
            if let cut = try? MeshBoolean.combine(result, hole, .subtract) {
                result = cut
                made += 1
            }
        }
        return (result, made)
    }

    // MARK: Writing on it

    /// Block letters `size` tall written on the surface at `point` (facing `normal`, reading upright): cut `depth`
    /// into it, or raised `depth` out of it.
    public static func engrave(_ text: String, on mesh: EditableMesh, at point: Vec3, normal: Vec3, size: Double = 0.006, depth: Double = 0.0006,
                               raised: Bool = false) throws(Failure) -> EditableMesh {
        let n = normal.normalized
        let overlap = raised ? 0.0002 : 0.0005
        let thickness = depth + overlap
        let recipe = TextRecipe(text: text, style: .blocky, size: size, depth: thickness / size, alignment: .center)
        // The font keeps letters at least a millimetre deep; a fine engraving is squeezed to its exact depth.
        let made = MeshBuilder.mesh(from: BlockFont.mesh(for: recipe))
        guard let raw = made.bounds, raw.size.z > 1e-9 else { throw .missesIt }
        let letters = made.scaled(by: Vec3(1, 1, thickness / raw.size.z))
        guard let box = letters.bounds else { throw .missesIt }
        var up = Vec3.unitY - n * n.dot(.unitY)
        if up.length < 0.1 { up = Vec3(0, 0, -1) - n * n.dot(Vec3(0, 0, -1)) }
        up = up.normalized
        let across = up.cross(n).normalized
        let rotation = PhotoMatch.rotation(right: across, up: up, back: n)
        let middle = box.center
        let along = raised ? (depth - overlap) / 2 : (overlap - depth) / 2
        let placed = letters.transformed(by: Transform(position: point - rotation.act(middle) + n * along, rotation: rotation))
        do throws(MeshBoolean.Failure) {
            return try MeshBoolean.combine(mesh, placed, raised ? .union : .subtract)
        } catch {
            throw .boolean(error)
        }
    }

    // MARK: Holes

    /// A screw hole into the part at `point` on its surface facing `normal`: through to the far side for clearance,
    /// counterbored and threaded holes, blind for inserts.
    public static func hole(_ kind: ScrewHole, _ screw: MetricScrew, in mesh: EditableMesh, at point: Vec3, normal: Vec3,
                            tolerance: Double = 0.0002) throws(Failure) -> EditableMesh {
        let inward = -normal.normalized
        let triangles = mesh.triangulated().triangles.map { (mesh.vertices[$0.0], mesh.vertices[$0.1], mesh.vertices[$0.2]) }
        let start = point - inward * 0.001
        let through = triangles.compactMap { PrintCheck.intersect(Ray(origin: start, direction: inward), $0) }.max().map { $0 - 0.001 + 0.0005 }
        let depth = through ?? screw.diameter * 3
        let cutter = kind.cutter(screw, at: point, inward: inward, depth: depth, tolerance: kind == .threaded ? tolerance : 0)
        do throws(MeshBoolean.Failure) {
            return try MeshBoolean.combine(mesh, cutter, .subtract)
        } catch {
            throw .boolean(error)
        }
    }

    // MARK: Size

    /// The factor that makes a part `target` metres along `axis` (or along its longest side when nil).
    public static func scale(toSize target: Double, bounds: Bounds, axis: Axis? = nil) -> Double? {
        let size = bounds.size
        let current = axis.map { size[$0] } ?? size.maxComponent
        guard current > 1e-9, target > 0 else { return nil }
        return target / current
    }
}

extension RoomFinder.Grid {
    /// Each cell's distance (in cells, 4-connected) from the edge of the group it's in; -1 outside it.
    func distances(of component: [Int]) -> [Int] {
        var distance = [Int](repeating: -1, count: cells.count)
        var members = [Bool](repeating: false, count: cells.count)
        for at in component {
            members[at] = true
        }
        var queue: [Int] = []
        for at in component {
            let row = at / columns, column = at % columns
            let edge = column == 0 || row == 0 || column == columns - 1 || row == rows - 1
                || !members[at - 1] || !members[at + 1] || !members[at - columns] || !members[at + columns]
            if edge {
                distance[at] = 0
                queue.append(at)
            }
        }
        var head = 0
        while head < queue.count {
            let at = queue[head]
            head += 1
            let row = at / columns, column = at % columns
            for (next, ok) in [(at - 1, column > 0), (at + 1, column < columns - 1), (at - columns, row > 0), (at + columns, row < rows - 1)]
                where ok && members[next] && distance[next] < 0 {
                distance[next] = distance[at] + 1
                queue.append(next)
            }
        }
        return distance
    }
}
