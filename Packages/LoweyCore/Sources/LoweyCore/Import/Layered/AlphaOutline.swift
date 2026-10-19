import Foundation

/// The outline of what shows in a picture (L2, D-487): the picture is read as a grid of at most `maxCells` cells a
/// side, a cell is inside when its pixels are at least half opaque, and the borders between inside and outside cells
/// are walked into closed loops (outlines and holes), then straightened. Where two inside cells touch only at a corner,
/// the walk turns right, so each keeps its own loop and no outline crosses itself.
public enum AlphaOutline {
    /// Closed loops in the picture's pixels (x right, y down), without their closing point.
    public static func contours(_ image: RGBAImage, maxCells: Int = 256, threshold: UInt8 = 128) -> [[Vec2]] {
        guard image.width > 0, image.height > 0 else { return [] }
        let cell = max(1, Int((Double(max(image.width, image.height)) / Double(max(maxCells, 8))).rounded(.up)))
        let columns = (image.width + cell - 1) / cell
        let rows = (image.height + cell - 1) / cell
        var inside = [Bool](repeating: false, count: columns * rows)
        for row in 0 ..< rows {
            for column in 0 ..< columns {
                var sum = 0, count = 0
                for y in row * cell ..< min((row + 1) * cell, image.height) {
                    for x in column * cell ..< min((column + 1) * cell, image.width) {
                        sum += Int(image.pixels[(y * image.width + x) * 4 + 3])
                        count += 1
                    }
                }
                inside[row * columns + column] = count > 0 && sum >= Int(threshold) * count
            }
        }
        let loops = walk(inside, columns: columns, rows: rows)
        let scale = Double(cell)
        return loops.map { loop in
            LogoImport.simplified(loop.map { Vec2(min($0.x * scale, Double(image.width)), min($0.y * scale, Double(image.height))) },
                                  tolerance: scale * 0.75)
        }
        .filter { $0.count >= 3 }
    }

    private struct Point: Hashable {
        var x: Int
        var y: Int
    }

    /// The border edges between inside and outside cells (inside kept on the same hand), joined into loops.
    static func walk(_ inside: [Bool], columns: Int, rows: Int) -> [[Vec2]] {
        func filled(_ column: Int, _ row: Int) -> Bool {
            column >= 0 && row >= 0 && column < columns && row < rows && inside[row * columns + column]
        }
        var outgoing: [Point: [Point]] = [:]
        var edgeCount = 0
        func edge(_ from: Point, _ to: Point) {
            outgoing[from, default: []].append(to)
            edgeCount += 1
        }
        for row in 0 ..< rows {
            for column in 0 ..< columns where filled(column, row) {
                let x = column, y = row
                if !filled(column, row - 1) { edge(Point(x: x, y: y), Point(x: x + 1, y: y)) }
                if !filled(column + 1, row) { edge(Point(x: x + 1, y: y), Point(x: x + 1, y: y + 1)) }
                if !filled(column, row + 1) { edge(Point(x: x + 1, y: y + 1), Point(x: x, y: y + 1)) }
                if !filled(column - 1, row) { edge(Point(x: x, y: y + 1), Point(x: x, y: y)) }
            }
        }
        var loops: [[Vec2]] = []
        // The topmost, leftmost corner first, so the same picture always gives the same loops.
        while let start = outgoing.filter({ !$0.value.isEmpty }).keys.min(by: { ($0.y, $0.x) < ($1.y, $1.x) }) {
            var loop: [Point] = [start]
            var current = start
            var direction = Point(x: 0, y: 0)
            var guardSteps = edgeCount + 1
            while guardSteps > 0 {
                guardSteps -= 1
                guard var choices = outgoing[current], !choices.isEmpty else { break }
                // Turn right where two loops meet at a corner (largest cross product in y-down axes), else straight on.
                let pick = choices.indices.max { a, b in
                    turn(direction, from: current, to: choices[a]) < turn(direction, from: current, to: choices[b])
                } ?? 0
                let next = choices.remove(at: pick)
                outgoing[current] = choices
                direction = Point(x: next.x - current.x, y: next.y - current.y)
                current = next
                if current == start { break }
                loop.append(current)
            }
            loops.append(straightened(loop).map { Vec2(Double($0.x), Double($0.y)) })
        }
        return loops
    }

    private static func turn(_ direction: Point, from: Point, to: Point) -> Int {
        let step = Point(x: to.x - from.x, y: to.y - from.y)
        return direction.x * step.y - direction.y * step.x
    }

    /// Only the corners: points in the middle of a straight run go.
    private static func straightened(_ loop: [Point]) -> [Point] {
        guard loop.count > 3 else { return loop }
        return loop.indices.compactMap { index in
            let before = loop[(index + loop.count - 1) % loop.count]
            let point = loop[index]
            let after = loop[(index + 1) % loop.count]
            let collinear = (point.x - before.x) * (after.y - point.y) == (point.y - before.y) * (after.x - point.x)
            return collinear ? nil : point
        }
    }
}
