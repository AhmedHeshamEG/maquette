import Foundation

/// Room's tools as commands (G1): each adds one thing, tagged with its part of the building, as one undo step.
public extension ModelingOperations {
    static func addRoof(_ kind: RoomParts.RoofKind, outline: [Vec3], pitch: Double = 30, id: ObjectID) throws(Failure) -> EditCommand {
        do throws(Architecture.Failure) {
            let mesh = try RoomParts.roof(kind, outline: outline, pitch: pitch)
            return part(mesh, name: "Roof", part: .roof, id: id)
        } catch {
            throw .shape(.architecture(error))
        }
    }

    static func addColumn(at point: Vec3, height: Double = Architecture.wallHeight, round: Bool = true, id: ObjectID) -> EditCommand {
        part(RoomParts.column(at: point, height: height, round: round), name: "Column", part: .column, id: id)
    }

    static func addBeam(from a: Vec3, to b: Vec3, id: ObjectID) throws(Failure) -> EditCommand {
        do throws(Architecture.Failure) {
            return try part(RoomParts.beam(from: a, to: b), name: "Beam", part: .beam, id: id)
        } catch {
            throw .shape(.architecture(error))
        }
    }

    static func addRailing(along path: [Vec3], id: ObjectID) throws(Failure) -> EditCommand {
        do throws(Architecture.Failure) {
            return try part(RoomParts.railing(along: path), name: "Railing", part: .railing, id: id)
        } catch {
            throw .shape(.architecture(error))
        }
    }

    /// A scale person at `point`, turned `yaw` degrees about the vertical (to face the camera).
    static func addPerson(at point: Vec3, yaw: Double, id: ObjectID) -> EditCommand {
        var object = SceneObject(id: id, name: "Person", kind: .mesh(RoomParts.person(at: .zero)),
                                 transform: Transform(position: point, rotation: Quat(angle: yaw * .pi / 180, axis: .unitY)))
        object.buildingPart = .person
        object[.color] = .color(.rgba(RGBA.hex("#8E8E93")))
        return .batch("Person", [.insert(SceneFragment(object: object), parent: nil, index: nil)])
    }

    static func addTerrain(width: Double, depth: Double, hills: Double, at point: Vec3, seed: UInt64, id: ObjectID) -> EditCommand {
        var object = SceneObject(id: id, name: "Terrain", kind: .mesh(RoomParts.terrain(width: width, depth: depth, hills: hills, seed: seed)),
                                 transform: Transform(position: point))
        object.buildingPart = .terrain
        object[.color] = .color(.rgba(RGBA.hex("#7A9A5B")))
        return .batch("Terrain", [.insert(SceneFragment(object: object), parent: nil, index: nil)])
    }

    /// A name lying on the floor (a room takes it on the plan): flat block letters, 30 cm tall.
    static func addLabel(_ text: String, at point: Vec3, id: ObjectID) -> EditCommand {
        let recipe = TextRecipe(text: text, style: .blocky, size: 0.3, depth: 0.05)
        let object = SceneObject(id: id, name: text, kind: .text(recipe),
                                 transform: Transform(position: point + Vec3(0, 0.01, 0), rotation: Quat(angle: -.pi / 2, axis: .unitX)))
        return .batch("Label", [.insert(SceneFragment(object: object), parent: nil, index: nil)])
    }

    private static func part(_ mesh: EditableMesh, name: String, part: BuildingPart, id: ObjectID) -> EditCommand {
        var object = newSolid(mesh, id: id)
        object.name = name
        object.buildingPart = part
        return .batch(name, [.insert(SceneFragment(object: object), parent: nil, index: nil)])
    }
}

/// A drawing to trace (G1): a DXF lands as a sketch on the ground at full size, a PDF page or a picture as a flat card
/// at the scale it was drawn at; either can be set to scale by two taps and the real length between them.
public enum Underlay {
    /// The DXF's lines as a sketch on the ground, centred where the drawing's middle lands on `point`.
    public static func sketch(_ drawing: DXF.Drawing, at point: Vec3, id: ObjectID) -> SceneObject {
        let bounds = drawing.bounds ?? (Vec2.zero, Vec2.zero)
        let middle = (bounds.min + bounds.max) * 0.5
        let curves = drawing.curves.map { moved($0, by: Vec2(point.x, -point.z) - middle) }
        let plane = PlaneFrame(origin: Vec3(0, point.y + 0.001, 0), normal: .unitY, u: .unitX, v: Vec3(0, 0, -1))
        var object = ModelingOperations.newSketch(on: plane, curves: curves, target: nil, id: id)
        object.name = "Underlay"
        object[.locked] = .bool(true)
        return object
    }

    /// A picture lying flat on the ground, `width` metres across (a page's width × its drawing scale), locked and faint.
    public static func card(image: String, aspect: Double, width: Double, at point: Vec3, id: ObjectID) -> SceneObject {
        let recipe = CardRecipe(image: image, aspect: aspect, thickness: 0.002, border: 0)
        let height = width / max(aspect, 1e-6)
        var object = SceneObject(id: id, name: "Underlay", kind: .card(recipe),
                                 transform: Transform(position: point + Vec3(0, -0.002, height / 2),
                                                      rotation: Quat(angle: -.pi / 2, axis: .unitX), scale: Vec3(height, height, 1)))
        object[.locked] = .bool(true)
        object[.opacity] = .float(0.6)
        object[.castsShadow] = .bool(false)
        return object
    }

    /// How wide a page drawn at `scale` (1:100 is 0.01) is in the world: its width in points over 72 inches.
    public static func width(pagePoints: Double, scale: Double) -> Double {
        pagePoints / 72 * 0.0254 / max(scale, 1e-9)
    }

    /// The factor that makes the distance between two points on an underlay the real length typed for it.
    public static func factor(from a: Vec3, to b: Vec3, real length: Double) -> Double? {
        let measured = Vec3(b.x - a.x, 0, b.z - a.z).length
        guard measured > 1e-6, length > 0 else { return nil }
        return length / measured
    }

    /// The underlay scaled about `anchor` (where the first tap was) by `factor`.
    public static func rescale(_ object: SceneObject, about anchor: Vec3, by factor: Double) -> SceneObject {
        var result = object
        switch object.kind {
        case var .sketch(sketch):
            let local = Vec2(anchor.x, -anchor.z)
            sketch.curves = sketch.curves.map { scaled($0, about: local, by: factor) }
            result.kind = .sketch(sketch)
        default:
            var transform = object.transform
            transform.position = anchor + (transform.position - anchor) * factor
            transform.scale = transform.scale.scaled(by: Vec3(factor, factor, 1))
            result.transform = transform
        }
        return result
    }

    static func moved(_ curve: SketchCurve, by offset: Vec2) -> SketchCurve {
        map(curve) { $0 + offset }
    }

    static func scaled(_ curve: SketchCurve, about anchor: Vec2, by factor: Double) -> SketchCurve {
        switch curve {
        case let .circle(centre, radius): .circle(center: anchor + (centre - anchor) * factor, radius: radius * factor)
        default: map(curve) { anchor + ($0 - anchor) * factor }
        }
    }

    static func map(_ curve: SketchCurve, _ transform: (Vec2) -> Vec2) -> SketchCurve {
        switch curve {
        case let .line(a, b): .line(transform(a), transform(b))
        case let .rectangle(a, b): .rectangle(transform(a), transform(b))
        case let .circle(centre, radius): .circle(center: transform(centre), radius: radius)
        case let .arc(a, m, b): .arc(transform(a), transform(m), transform(b))
        case let .spline(points, closed): .spline(points.map(transform), closed: closed)
        case let .polyline(points, closed): .polyline(points.map(transform), closed: closed)
        }
    }
}
