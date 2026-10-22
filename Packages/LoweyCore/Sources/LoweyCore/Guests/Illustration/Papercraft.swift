import Foundation

/// A model unfolded flat (G1: papercraft to print and fold, or a net for a laser cutter). Its faces are joined along
/// their longest edges into pieces that lie flat without overlapping; every edge where pieces part gets a matching
/// number on both sides and a glue tab on one; folds are marked mountain (dash-dot) or valley (dashed); the pieces are
/// packed onto pages, at the model's real size when they fit.
public enum Papercraft {
    public struct Net: Sendable {
        /// One drawing a page, in metres on the paper, its bottom-left corner the page's.
        public var pages: [LineArt]
        /// Paper metres a model metre (1 is real size).
        public var scale: Double
        public var pieces: Int
        public var paper: (width: Double, height: Double)
    }

    struct Piece {
        var faces: [(face: Int, corners: [Vec2])]
        /// The face edges drawn: from, to, the pen, and the edge's number if it's a cut.
        var edges: [(Vec2, Vec2, LineArt.Pen)] = []
        var labels: [LineArt.Label] = []
    }

    /// The net of a closed (or open) mesh at `scale`, on pages of `paper` with `margin` metres round them. When a piece
    /// is bigger than a page the whole net is scaled down to fit.
    public static func unfold(_ mesh: EditableMesh, scale requested: Double = 1, paper: PaperSize = .a4, margin: Double = 0.01) -> Net {
        let faces = polygons(mesh)
        let edges = sharedEdges(faces)
        let tree = spanningTree(faces: faces, edges: edges, vertices: mesh.vertices)
        var pieces = place(faces: faces, tree: tree, vertices: mesh.vertices)
        let page = (width: paper.points.width / 72 * 0.0254, height: paper.points.height / 72 * 0.0254)
        let room = Vec2(page.width - margin * 2, page.height - margin * 2)
        // Each piece turned to its smallest box, its long side along the page's.
        var boxes: [(min: Vec2, max: Vec2)] = []
        for index in pieces.indices {
            pieces[index] = squared(pieces[index], tall: room.y > room.x)
            let points = pieces[index].faces.flatMap(\.corners)
            boxes.append(bounds(points))
        }
        let biggest = boxes.map { max(($0.max.x - $0.min.x) / room.x, ($0.max.y - $0.min.y) / room.y) }.max() ?? 0
        let tabRoom = 1.15
        let scale = biggest * requested * tabRoom > 1 ? 1 / (biggest * tabRoom) : requested
        for index in pieces.indices {
            pieces[index].faces = pieces[index].faces.map { ($0.face, $0.corners.map { $0 * scale }) }
        }
        let drawn = draw(pieces, faces: faces, edges: edges, vertices: mesh.vertices)
        let pages = pack(drawn, room: room, margin: margin)
        return Net(pages: pages, scale: scale, pieces: pieces.count, paper: page)
    }

    // MARK: Faces and edges

    /// The mesh's faces as corner loops (faces with holes split into their triangles).
    static func polygons(_ mesh: EditableMesh) -> [[Int]] {
        mesh.faces.indices.flatMap { index -> [[Int]] in
            let face = mesh.faces[index]
            if face.holes.isEmpty { return [face.outline] }
            return mesh.triangulate(face: index).map { [$0.0, $0.1, $0.2] }
        }
    }

    /// Each edge shared by exactly two faces, with the two faces.
    static func sharedEdges(_ faces: [[Int]]) -> [MeshEdge: [Int]] {
        var result: [MeshEdge: [Int]] = [:]
        for (index, loop) in faces.enumerated() {
            for corner in loop.indices {
                result[MeshEdge(loop[corner], loop[(corner + 1) % loop.count]), default: []].append(index)
            }
        }
        return result
    }

    /// The edges to fold along: the longest first, joining faces that aren't joined yet.
    static func spanningTree(faces: [[Int]], edges: [MeshEdge: [Int]], vertices: [Vec3]) -> [Int: [(Int, MeshEdge)]] {
        var parent = Array(faces.indices)
        func root(_ index: Int) -> Int {
            var at = index
            while parent[at] != at {
                parent[at] = parent[parent[at]]
                at = parent[at]
            }
            return at
        }
        let candidates = edges.filter { $0.value.count == 2 }.sorted { lhs, rhs in
            let a = vertices[lhs.key.a].distance(to: vertices[lhs.key.b]), b = vertices[rhs.key.a].distance(to: vertices[rhs.key.b])
            return a != b ? a > b : (lhs.key.a, lhs.key.b) < (rhs.key.a, rhs.key.b)
        }
        var tree: [Int: [(Int, MeshEdge)]] = [:]
        for (edge, pair) in candidates {
            let a = root(pair[0]), b = root(pair[1])
            guard a != b else { continue }
            parent[a] = b
            tree[pair[0], default: []].append((pair[1], edge))
            tree[pair[1], default: []].append((pair[0], edge))
        }
        return tree
    }

    /// The faces laid flat piece by piece: each face folded out from the one before it, unless it would land on the
    /// piece, when it starts a piece of its own.
    static func place(faces: [[Int]], tree: [Int: [(Int, MeshEdge)]], vertices: [Vec3]) -> [Piece] {
        var placed = [Bool](repeating: false, count: faces.count)
        var pieces: [Piece] = []
        func flat(_ face: Int) -> [Vec2] {
            let points = faces[face].map { vertices[$0] }
            let frame = PlaneFrame(normal: EditableMesh.newellNormal(points), origin: points[0])
            return points.map { frame.project($0) }
        }
        let order = faces.indices.sorted { area(flat($0)) > area(flat($1)) }
        for start in order where !placed[start] {
            var queue: [(face: Int, corners: [Vec2], piece: Int)] = [(start, flat(start), pieces.count)]
            pieces.append(Piece(faces: []))
            placed[start] = true
            while !queue.isEmpty {
                let (face, corners, piece) = queue.removeFirst()
                pieces[piece].faces.append((face, corners))
                for (next, edge) in tree[face] ?? [] where !placed[next] {
                    placed[next] = true
                    let laid = folded(next, onto: face, corners: corners, edge: edge, faces: faces, flat: flat(next))
                    if overlaps(laid, pieces[piece].faces.map(\.corners) + queue.filter { $0.piece == piece }.map(\.corners)) {
                        queue.append((next, flat(next), pieces.count))
                        pieces.append(Piece(faces: []))
                    } else {
                        queue.append((next, laid, piece))
                    }
                }
            }
        }
        return pieces.filter { !$0.faces.isEmpty }
    }

    /// A face's flat corners turned and moved so its edge lies on the same edge of the face it folds from.
    static func folded(_ face: Int, onto parent: Int, corners parentCorners: [Vec2], edge: MeshEdge, faces: [[Int]], flat: [Vec2]) -> [Vec2] {
        let parentLoop = faces[parent], loop = faces[face]
        guard let pa = parentLoop.firstIndex(of: edge.a), let pb = parentLoop.firstIndex(of: edge.b),
              let ca = loop.firstIndex(of: edge.a), let cb = loop.firstIndex(of: edge.b) else { return flat }
        let from = flat[cb] - flat[ca], to = parentCorners[pb] - parentCorners[pa]
        let turn = atan2(to.y, to.x) - atan2(from.y, from.x)
        let c = cos(turn), s = sin(turn)
        return flat.map { point in
            let p = point - flat[ca]
            return parentCorners[pa] + Vec2(p.x * c - p.y * s, p.x * s + p.y * c)
        }
    }

    /// Whether a polygon overlaps any of the others (sharing an edge or a corner isn't overlapping).
    static func overlaps(_ polygon: [Vec2], _ others: [[Vec2]]) -> Bool {
        let box = bounds(polygon)
        let span = max(box.max.x - box.min.x, box.max.y - box.min.y)
        let eps = span * 1e-6
        let shrunk = shrink(polygon, by: eps * 10)
        for other in others {
            let otherBox = bounds(other)
            guard box.min.x < otherBox.max.x - eps, otherBox.min.x < box.max.x - eps, box.min.y < otherBox.max.y - eps,
                  otherBox.min.y < box.max.y - eps else { continue }
            let small = shrink(other, by: eps * 10)
            for i in shrunk.indices {
                for j in small.indices where segmentsCross(shrunk[i], shrunk[(i + 1) % shrunk.count], small[j], small[(j + 1) % small.count]) {
                    return true
                }
            }
            if RoomFinder.contains(other, centroid(shrunk)) || RoomFinder.contains(polygon, centroid(small)) { return true }
        }
        return false
    }

    static func segmentsCross(_ p: Vec2, _ q: Vec2, _ a: Vec2, _ b: Vec2) -> Bool {
        let d1 = (q - p).cross(a - p), d2 = (q - p).cross(b - p), d3 = (b - a).cross(p - a), d4 = (b - a).cross(q - a)
        return d1 * d2 < 0 && d3 * d4 < 0
    }

    /// A convex-enough polygon pulled toward its middle a hair, so touching edges don't count as crossing.
    static func shrink(_ polygon: [Vec2], by amount: Double) -> [Vec2] {
        let middle = centroid(polygon)
        return polygon.map { point in
            let away = point - middle
            let length = away.length
            return length > amount ? middle + away * ((length - amount) / length) : point
        }
    }

    static func centroid(_ polygon: [Vec2]) -> Vec2 {
        polygon.reduce(Vec2.zero, +) * (1 / Double(max(polygon.count, 1)))
    }

    static func area(_ polygon: [Vec2]) -> Double { abs(PolygonTriangulator.signedArea(polygon)) }

    static func bounds(_ points: [Vec2]) -> (min: Vec2, max: Vec2) {
        var lo = Vec2(.infinity, .infinity), hi = Vec2(-.infinity, -.infinity)
        for p in points {
            lo = Vec2(min(lo.x, p.x), min(lo.y, p.y))
            hi = Vec2(max(hi.x, p.x), max(hi.y, p.y))
        }
        return lo.x.isFinite ? (lo, hi) : (.zero, .zero)
    }

    /// The piece turned so its smallest box lies with its long side across (or up a `tall` page).
    static func squared(_ piece: Piece, tall: Bool) -> Piece {
        let points = piece.faces.flatMap(\.corners)
        let box = RoomParts.smallestRectangle(points)
        guard box.count == 4 else { return piece }
        let along = (box[1] - box[0]).normalizedVector
        let turn = -atan2(along.y, along.x) + (tall ? .pi / 2 : 0)
        let c = cos(turn), s = sin(turn)
        var result = piece
        result.faces = piece.faces.map { face in (face.face, face.corners.map { Vec2($0.x * c - $0.y * s, $0.x * s + $0.y * c) }) }
        return result
    }
}
