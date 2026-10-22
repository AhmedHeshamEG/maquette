import Foundation

/// The rooms a building's walls close off (G1, Sara's plan with room areas): the walls are cut low (under the
/// windows) and high (over the doors) so openings don't let a room leak, laid on a fine grid, the outside flooded from
/// the edge, and what's left is rooms. Each outline's corners are snapped to the walls' own corners, so a square room
/// measures exactly.
public enum RoomFinder {
    public struct Room: Hashable, Sendable {
        public var name: String
        /// Square metres.
        public var area: Double
        /// On the plan (x, −z), counter-clockwise.
        public var outline: [Vec2]
        /// Where its name sits: the point inside furthest from its walls.
        public var label: Vec2
    }

    /// Heights above the floor the walls are cut at: under a window's sill, and over a door's head.
    public static let cutHeights = [0.3, 2.25]
    /// Smaller enclosed spaces (inside a wall's corner, a shaft) aren't rooms.
    public static let smallestRoom = 1.0

    /// Rooms on the level at `floor` from the things in `soup` that close rooms off (`enclosing`: owners; all when nil),
    /// named by the labels lying inside them.
    public static func rooms(_ soup: TriangleSoup, floor: Double = 0, enclosing: Set<Int>? = nil,
                             labels: [(text: String, at: Vec2)] = []) -> [Room] {
        var shapes: [[[Vec2]]] = []
        for height in cutHeights {
            for cut in Section.cut(soup, point: Vec3(0, floor + height, 0), normal: .unitY)
                where enclosing?.contains(cut.owner) ?? true && !cut.loops.isEmpty {
                shapes.append(cut.loops.map { $0.map { Vec2($0.x, -$0.z) } })
            }
        }
        return rooms(walls: shapes, labels: labels)
    }

    /// Rooms between filled shapes (each a set of loops filled even-odd) on the plan.
    public static func rooms(walls shapes: [[[Vec2]]], labels: [(text: String, at: Vec2)] = []) -> [Room] {
        let corners = shapes.flatMap { $0.flatMap(\.self) }
        guard let first = corners.first, corners.contains(where: { $0.distance(to: first) > 0.5 }),
              var grid = Grid(around: corners) else { return [] }
        for loops in shapes {
            grid.fill(loops)
        }
        grid.floodOutside()
        var rooms: [Room] = []
        for component in grid.components() where Double(component.count) * grid.cell * grid.cell >= smallestRoom {
            guard let outline = grid.outline(of: component) else { continue }
            let snapped = snap(outline, to: corners, within: grid.cell * 2.5)
            let area = abs(PolygonTriangulator.signedArea(snapped))
            let label = grid.pole(of: component)
            rooms.append(Room(name: "", area: area, outline: PolygonTriangulator.signedArea(snapped) < 0 ? snapped.reversed() : snapped,
                              label: label))
        }
        rooms.sort { ($0.label.y, $0.label.x) > ($1.label.y, $1.label.x) }
        for index in rooms.indices {
            rooms[index].name = labels.first { contains(rooms[index].outline, $0.at) }?.text ?? "Room \(index + 1)"
        }
        return rooms
    }

    /// Each corner moved onto the nearest wall corner close enough (the grid's stairs straightened onto the walls).
    static func snap(_ outline: [Vec2], to corners: [Vec2], within distance: Double) -> [Vec2] {
        var bucket: [SIMD2<Int64>: [Vec2]] = [:]
        func key(_ p: Vec2) -> SIMD2<Int64> { SIMD2(Int64((p.x / distance).rounded(.down)), Int64((p.y / distance).rounded(.down))) }
        for corner in corners {
            bucket[key(corner), default: []].append(corner)
        }
        var result: [Vec2] = []
        for point in outline {
            let home = key(point)
            var best: Vec2?, bestDistance = distance
            for dx in -1 ... 1 {
                for dy in -1 ... 1 {
                    for corner in bucket[home &+ SIMD2(Int64(dx), Int64(dy))] ?? [] where corner.distance(to: point) < bestDistance {
                        best = corner
                        bestDistance = corner.distance(to: point)
                    }
                }
            }
            let next = best ?? point
            if let last = result.last, last.distance(to: next) < 1e-9 { continue }
            result.append(next)
        }
        if result.count > 1, let first = result.first, let last = result.last, first.distance(to: last) < 1e-9 { result.removeLast() }
        return result.count >= 3 ? result : outline
    }

    static func contains(_ polygon: [Vec2], _ point: Vec2) -> Bool {
        var inside = false
        var j = polygon.count - 1
        for i in polygon.indices {
            let a = polygon[i], b = polygon[j]
            if (a.y > point.y) != (b.y > point.y), point.x < (b.x - a.x) * (point.y - a.y) / (b.y - a.y) + a.x { inside.toggle() }
            j = i
        }
        return inside
    }

    /// The plan laid on square cells.
    struct Grid {
        let origin: Vec2
        let cell: Double
        let columns: Int
        let rows: Int
        /// 0 free, 1 wall, 2 outside.
        var cells: [UInt8]

        /// A grid over the points with `margin` round them, cells `size` across (by default two centimetres, coarser
        /// for a big site so it stays under 3000 cells a side).
        init?(around points: [Vec2], size: Double? = nil, margin: Double = 1) {
            guard let first = points.first else { return nil }
            var lo = first, hi = first
            for p in points {
                lo = Vec2(min(lo.x, p.x), min(lo.y, p.y))
                hi = Vec2(max(hi.x, p.x), max(hi.y, p.y))
            }
            let span = max(hi.x - lo.x, hi.y - lo.y)
            guard span > 1e-6 else { return nil }
            cell = size ?? max(0.02, (span + margin * 2) / 3000)
            origin = lo - Vec2(margin, margin)
            columns = Int(((hi.x - lo.x) + margin * 2) / cell) + 2
            rows = Int(((hi.y - lo.y) + margin * 2) / cell) + 2
            cells = [UInt8](repeating: 0, count: columns * rows)
        }

        /// Loops filled even-odd (a wall ring keeps its inside free).
        mutating func fill(_ loops: [[Vec2]]) {
            for row in 0 ..< rows {
                let y = origin.y + (Double(row) + 0.5) * cell
                var crossings: [Double] = []
                for loop in loops where loop.count >= 3 {
                    for index in loop.indices {
                        let a = loop[index], b = loop[(index + 1) % loop.count]
                        if (a.y > y) != (b.y > y) { crossings.append(a.x + (y - a.y) / (b.y - a.y) * (b.x - a.x)) }
                    }
                }
                crossings.sort()
                var index = 0
                while index + 1 < crossings.count {
                    // A wall a cell thin still blocks: anything the span touches is filled.
                    let from = max(Int(((crossings[index] - origin.x) / cell).rounded(.down)), 0)
                    let to = min(Int(((crossings[index + 1] - origin.x) / cell).rounded(.down)), columns - 1)
                    if from <= to {
                        for column in from ... to {
                            cells[row * columns + column] = 1
                        }
                    }
                    index += 2
                }
            }
        }

        mutating func floodOutside() {
            var stack: [Int] = []
            for column in 0 ..< columns {
                stack.append(column)
                stack.append((rows - 1) * columns + column)
            }
            for row in 0 ..< rows {
                stack.append(row * columns)
                stack.append(row * columns + columns - 1)
            }
            while let at = stack.popLast() {
                guard cells[at] == 0 else { continue }
                cells[at] = 2
                let row = at / columns, column = at % columns
                if column > 0 { stack.append(at - 1) }
                if column < columns - 1 { stack.append(at + 1) }
                if row > 0 { stack.append(at - columns) }
                if row < rows - 1 { stack.append(at + columns) }
            }
        }

        /// The free cells left, in groups that touch.
        func components() -> [[Int]] {
            var seen = [Bool](repeating: false, count: cells.count)
            var result: [[Int]] = []
            for start in cells.indices where cells[start] == 0 && !seen[start] {
                var group: [Int] = []
                var stack = [start]
                seen[start] = true
                while let at = stack.popLast() {
                    group.append(at)
                    let row = at / columns, column = at % columns
                    for (next, ok) in [(at - 1, column > 0), (at + 1, column < columns - 1), (at - columns, row > 0), (at + columns, row < rows - 1)]
                        where ok && cells[next] == 0 && !seen[next] {
                        seen[next] = true
                        stack.append(next)
                    }
                }
                result.append(group)
            }
            return result
        }

        /// The group's outer outline on the plan.
        func outline(of component: [Int]) -> [Vec2]? {
            var inside = [Bool](repeating: false, count: cells.count)
            for at in component {
                inside[at] = true
            }
            let loops = AlphaOutline.walk(inside, columns: columns, rows: rows)
            guard let outer = loops.max(by: { abs(PolygonTriangulator.signedArea($0)) < abs(PolygonTriangulator.signedArea($1)) }) else { return nil }
            return outer.map { Vec2(origin.x + $0.x * cell, origin.y + $0.y * cell) }
        }

        /// The cell furthest from the group's edge (where its name reads best).
        func pole(of component: [Int]) -> Vec2 {
            var distance = [Int](repeating: -1, count: cells.count)
            var queue: [Int] = []
            let members = Set(component)
            for at in component {
                let row = at / columns, column = at % columns
                let neighbours = [(at - 1, column > 0), (at + 1, column < columns - 1), (at - columns, row > 0), (at + columns, row < rows - 1)]
                if neighbours.contains(where: { !$0.1 || !members.contains($0.0) }) {
                    distance[at] = 0
                    queue.append(at)
                }
            }
            var head = 0
            var best = component[0]
            while head < queue.count {
                let at = queue[head]
                head += 1
                if distance[at] > distance[best] { best = at }
                let row = at / columns, column = at % columns
                for (next, ok) in [(at - 1, column > 0), (at + 1, column < columns - 1), (at - columns, row > 0), (at + columns, row < rows - 1)]
                    where ok && members.contains(next) && distance[next] < 0 {
                    distance[next] = distance[at] + 1
                    queue.append(next)
                }
            }
            return Vec2(origin.x + (Double(best % columns) + 0.5) * cell, origin.y + (Double(best / columns) + 0.5) * cell)
        }
    }
}
