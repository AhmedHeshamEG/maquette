import Foundation

extension Papercraft {
    /// Each piece as lines on paper: cuts round it, folds inside it (mountain where the model's surface turns outward,
    /// valley where it turns in), a tab on one side of every edge where pieces part, and that edge's number on both.
    static func draw(_ pieces: [Piece], faces: [[Int]], edges: [MeshEdge: [Int]], vertices: [Vec3]) -> [LineArt] {
        var placements: [Int: (piece: Int, corners: [Vec2])] = [:]
        for (index, piece) in pieces.enumerated() {
            for face in piece.faces {
                placements[face.face] = (index, face.corners)
            }
        }
        var numbers: [MeshEdge: Int] = [:]
        let normals = faces.map { EditableMesh.newellNormal($0.map { vertices[$0] }) }
        let middles = faces.map { loop in loop.map { vertices[$0] }.reduce(Vec3.zero, +) / Double(loop.count) }
        var arts = [LineArt](repeating: LineArt(), count: pieces.count)
        let tolerance = 1e-7
        for (face, placed) in placements.sorted(by: { $0.key < $1.key }) {
            let loop = faces[face]
            let inside = centroid(placed.corners)
            for corner in loop.indices {
                let edge = MeshEdge(loop[corner], loop[(corner + 1) % loop.count])
                let p = placed.corners[corner], q = placed.corners[(corner + 1) % loop.count]
                let others = (edges[edge] ?? []).filter { $0 != face }
                guard others.count == 1, let other = others.first, let there = placements[other] else {
                    arts[placed.piece].strokes.append(LineArt.Stroke([p, q], pen: .cutLine))
                    continue
                }
                if there.piece == placed.piece, let otherCorners = cornersOf(edge, in: faces[other], placed: there.corners),
                   otherCorners.0.distance(to: p) < tolerance && otherCorners.1.distance(to: q) < tolerance
                   || otherCorners.0.distance(to: q) < tolerance && otherCorners.1.distance(to: p) < tolerance {
                    guard face < other else { continue }
                    let convex = (middles[other] - vertices[edge.a]).dot(normals[face]) < 0
                    arts[placed.piece].strokes.append(LineArt.Stroke([p, q], pen: convex ? .mountain : .valley))
                    continue
                }
                let number = numbers[edge] ?? {
                    let next = numbers.count + 1
                    numbers[edge] = next
                    return next
                }()
                let along = q - p
                let length = along.length
                let outward = outwardNormal(p, q, inside: inside)
                if face < other {
                    let height = min(0.006, length * 0.2)
                    let tab = [p, p + along * 0.2 + outward * height, q - along * 0.2 + outward * height, q]
                    arts[placed.piece].strokes.append(LineArt.Stroke(tab, pen: .cutLine))
                    arts[placed.piece].strokes.append(LineArt.Stroke([p, q], pen: .valley))
                } else {
                    arts[placed.piece].strokes.append(LineArt.Stroke([p, q], pen: .cutLine))
                }
                let label = (p + q) * 0.5 - outward * min(0.004, length * 0.18 + 0.0005)
                arts[placed.piece].labels.append(LineArt.Label("\(number)", at: label, size: min(2.5, max(1.2, length * 300))))
            }
        }
        return arts
    }

    /// Where an edge's two corners are on a placed face.
    static func cornersOf(_ edge: MeshEdge, in loop: [Int], placed: [Vec2]) -> (Vec2, Vec2)? {
        guard let a = loop.firstIndex(of: edge.a), let b = loop.firstIndex(of: edge.b) else { return nil }
        return (placed[a], placed[b])
    }

    /// The unit normal of p→q pointing away from `inside`.
    static func outwardNormal(_ p: Vec2, _ q: Vec2, inside: Vec2) -> Vec2 {
        let d = (q - p).normalizedVector
        let left = Vec2(-d.y, d.x)
        return (inside - p).dot(left) > 0 ? left * -1 : left
    }

    /// The pieces packed in rows onto pages, a few millimetres apart; the pages' drawings in paper metres.
    static func pack(_ arts: [LineArt], room: Vec2, margin: Double) -> [LineArt] {
        let gap = 0.004
        let order = arts.indices.sorted { lhs, rhs in
            let a = arts[lhs].bounds, b = arts[rhs].bounds
            return (a.map { $0.max.y - $0.min.y } ?? 0) > (b.map { $0.max.y - $0.min.y } ?? 0)
        }
        var pages: [LineArt] = [LineArt()]
        var x = 0.0, y = 0.0, row = 0.0
        for index in order {
            guard let box = arts[index].bounds else { continue }
            let size = Vec2(box.max.x - box.min.x, box.max.y - box.min.y)
            if x > 0, x + size.x > room.x {
                x = 0
                y += row + gap
                row = 0
            }
            if y > 0, y + size.y > room.y {
                pages.append(LineArt())
                x = 0
                y = 0
                row = 0
            }
            // Rows fill the page from its top.
            let corner = Vec2(margin + x, margin + room.y - y - size.y)
            pages[pages.count - 1].append(arts[index], offset: corner - box.min)
            x += size.x + gap
            row = max(row, size.y)
        }
        return pages.filter { !$0.isEmpty }
    }
}

public extension Papercraft.Net {
    /// The net to print: a page each, cut lines solid, folds dashed, numbers on the edges.
    func pdf(title: String, author: String?) -> Data {
        let width = paper.width / 0.0254 * 72, height = paper.height / 0.0254 * 72
        let placement = PaperPlacement(scale: 1, origin: .zero, at: .zero)
        let pdfPages = pages.enumerated().map { index, art in
            PDFWriter.Page(width: width, height: height, items: art.pdfItems(placement) + [
                .text("\(title)  ·  \(index + 1)/\(pages.count)  ·  \(PaperPlacement.title(of: scale))", x: 28, y: 14, size: 7, grey: 0.5)
            ])
        }
        return PDFWriter(pages: pdfPages, title: title, author: author).data()
    }

    /// A page for a laser cutter: red hairlines are cut, blue ones scored (folds).
    func svg(page: Int) -> String {
        pages[page].svg(PaperPlacement(scale: 1, origin: .zero, at: .zero), width: paper.width * 1000, height: paper.height * 1000, laser: true)
    }
}
