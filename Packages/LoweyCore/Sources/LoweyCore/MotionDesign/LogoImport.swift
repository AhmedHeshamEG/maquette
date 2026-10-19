import Foundation
import HmmVector

/// An SVG logo stood up in the world (D1): each fill colour becomes one solid, its shapes pulled out by `depth` with
/// their holes, upright and facing the front, standing on the ground, centred. Colours painted later in the file stand a
/// little proud of the ones under them, as an embossed sign does, so nothing fights for the same face. The solids are
/// ordinary modelled shapes, so they push, round, paint, break and export like anything modelled.
public enum LogoImport {
    public struct Piece: Sendable {
        public var name: String
        public var color: RGBA
        public var mesh: EditableMesh
    }

    /// How far each colour stands in front of the one under it, as a share of the depth.
    static let layerStep = 0.12

    /// The pieces of `drawing`, `width` metres across and `depth` deep, back colour first.
    public static func pieces(_ drawing: VectorDrawing, width: Double = 1, depth: Double = 0.08) -> [Piece] {
        guard let bounds = drawing.bounds else { return [] }
        let span = max(bounds.max.x - bounds.min.x, 1e-9)
        let scale = width / span
        let centre = (bounds.min.x + bounds.max.x) / 2
        let tolerance = width / 4000
        func metres(_ point: VectorPoint) -> Vec2 { Vec2((point.x - centre) * scale, (bounds.max.y - point.y) * scale) }
        var pieces: [Piece] = []
        for (layer, color) in drawing.colors.enumerated() {
            let front = depth / 2 + depth * layerStep * Double(layer)
            var solids: [EditableMesh] = []
            for shape in drawing.shapes where shape.fill == color {
                let contours = shape.contours.map { simplified($0.map(metres), tolerance: tolerance) }
                for (outer, holes) in Outlines.shapes(contours) {
                    let flat = { (loop: [Vec2]) in loop.map { Vec3($0.x, $0.y, 0) } }
                    solids.append(Prism.make(outline: flat(outer), holes: holes.map(flat), normal: .unitZ, from: -depth / 2, to: front))
                }
            }
            guard !solids.isEmpty else { continue }
            let name = drawing.shapes.first { $0.fill == color && $0.name != nil }?.name ?? color.hex
            pieces.append(Piece(name: name, color: RGBA(color.red, color.green, color.blue), mesh: joined(solids)))
        }
        return pieces
    }

    /// The pieces as things: one modelled solid, or a group named `name` holding one solid a colour.
    public static func objects(_ drawing: VectorDrawing, name: String, width: Double = 1, depth: Double = 0.08,
                               makeID: () -> ObjectID) -> (objects: [SceneObject], root: ObjectID)? {
        let pieces = pieces(drawing, width: width, depth: depth)
        guard !pieces.isEmpty else { return nil }
        func solid(_ piece: Piece, named: String, parent: ObjectID?) -> SceneObject {
            var object = SceneObject(id: makeID(), name: named, kind: .mesh(piece.mesh), parent: parent)
            object[.color] = .color(.rgba(piece.color))
            object[.smoothAngle] = .float(40)
            return object
        }
        if pieces.count == 1 {
            let object = solid(pieces[0], named: name, parent: nil)
            return ([object], object.id)
        }
        var group = SceneObject(id: makeID(), name: name, kind: .group)
        let children = pieces.map { solid($0, named: $0.name, parent: group.id) }
        group.children = children.map(\.id)
        return ([group] + children, group.id)
    }

    /// Solids side by side in one shape (their corners kept apart).
    static func joined(_ meshes: [EditableMesh]) -> EditableMesh {
        guard meshes.count > 1 else { return meshes.first ?? .empty }
        var vertices: [Vec3] = []
        var faces: [EditableMesh.Face] = []
        for mesh in meshes {
            let offset = vertices.count
            vertices += mesh.vertices
            faces += mesh.faces.map { face in EditableMesh.Face(loops: face.loops.map { loop in loop.map { $0 + offset } }) }
        }
        return EditableMesh(vertices: vertices, faces: faces)
    }

    /// A contour without the points that lie on the line through their neighbours (within `tolerance`), so a straight
    /// edge is one wall, not dozens.
    static func simplified(_ contour: [Vec2], tolerance: Double) -> [Vec2] {
        var points = Outlines.dropClosingPoint(contour)
        guard points.count > 3 else { return points }
        var index = 0
        var removed = true
        while removed, points.count > 3 {
            removed = false
            index = 0
            while index < points.count, points.count > 3 {
                let previous = points[(index + points.count - 1) % points.count]
                let next = points[(index + 1) % points.count]
                if distance(points[index], toLine: previous, next) < tolerance {
                    points.remove(at: index)
                    removed = true
                } else {
                    index += 1
                }
            }
        }
        return points
    }

    static func distance(_ point: Vec2, toLine a: Vec2, _ b: Vec2) -> Double {
        let dx = b.x - a.x, dy = b.y - a.y
        let length = (dx * dx + dy * dy).squareRoot()
        guard length > 1e-12 else { return ((point.x - a.x) * (point.x - a.x) + (point.y - a.y) * (point.y - a.y)).squareRoot() }
        return abs((point.x - a.x) * dy - (point.y - a.y) * dx) / length
    }
}
