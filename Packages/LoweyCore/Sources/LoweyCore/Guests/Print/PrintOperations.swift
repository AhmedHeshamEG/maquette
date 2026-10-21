import Foundation

/// Print's tools as commands (G1): each changes one part, or adds the printed pieces, as one undo step.
public extension ModelingOperations {
    /// A modelled part in world space, with its world transform (to put a changed shape back).
    internal static func worldSolid(_ id: ObjectID, in scene: Scene) throws(Failure) -> (EditableMesh, Transform) {
        guard let object = scene.objects[id], let local = editableMesh(of: object) else { throw .notEditable }
        let world = scene.worldTransform(of: id)
        return (local.transformed(by: world), world)
    }

    internal static func printFailure(_ failure: PrintTools.Failure) -> Failure {
        switch failure {
        case let .boolean(error): .boolean(error)
        case .missesIt: .noSuchRegion
        case let .shell(error): .shape(.shell(error))
        }
    }

    /// The part turned the way that needs the least support, standing where it stood.
    static func orientForPrinting(_ id: ObjectID, in scene: Scene) throws(Failure) -> EditCommand {
        guard let object = scene.objects[id] else { throw .notEditable }
        let (solid, _) = try worldSolid(id, in: scene)
        let choice = PrintOrientation.best(solid)
        let pivot = scene.worldTransform(of: id).position
        let turned = solid.vertices.map { pivot + choice.rotation.act($0 - pivot) }
        guard let oldFloor = solid.vertices.map(\.y).min(), let newFloor = turned.map(\.y).min() else { throw .notEditable }
        var transform = object.transform
        let parent = object.parent.map { scene.worldTransform(of: $0).rotation } ?? .identity
        let inverse = Quat(x: -parent.x, y: -parent.y, z: -parent.z, w: parent.w)
        transform.rotation = (inverse * choice.rotation * parent * transform.rotation).normalized
        transform.position += inverse.act(Vec3(0, oldFloor - newFloor, 0))
        return .batch("Orient for printing", [
            .setProperties([PropertyChange(object: id, key: .rotation, value: .quat(transform.rotation)),
                            PropertyChange(object: id, key: .position, value: .vec3(transform.position))])
        ])
    }

    /// The part cut in two (G1: Giulia's helmet): this keeps the side `normal` points to, with pegs; `newID` is the
    /// other side, with the holes, moved a centimetre away.
    static func splitForPrinting(_ id: ObjectID, point: Vec3, normal: Vec3, pegs: Bool, tolerance: Double, newID: ObjectID,
                                 in scene: Scene) throws(Failure) -> EditCommand {
        guard let object = scene.objects[id] else { throw .notEditable }
        let (solid, world) = try worldSolid(id, in: scene)
        let split: PrintTools.Split
        do throws(PrintTools.Failure) {
            split = try PrintTools.split(solid, point: point, normal: normal, pegs: pegs, tolerance: tolerance)
        } catch {
            throw printFailure(error)
        }
        var other = object
        other.id = newID
        other.name = object.name + " (2)"
        other.children = []
        other.kind = .mesh(split.second.untransformed(by: world))
        other.modelHistory = nil
        other.paint = nil
        return .batch("Split", [
            .setKind(id, .mesh(split.first.untransformed(by: world))),
            .insert(SceneFragment(object: other), parent: object.parent, index: nil)
        ])
    }

    static func hollowForPrinting(_ id: ObjectID, wall: Double, drain: Double, in scene: Scene) throws(Failure) -> EditCommand {
        let (solid, world) = try worldSolid(id, in: scene)
        do throws(PrintTools.Failure) {
            let result = try PrintTools.hollow(solid, wall: wall, drain: drain)
            return .batch("Hollow", [.setKind(id, .mesh(result.mesh.untransformed(by: world)))])
        } catch {
            throw printFailure(error)
        }
    }

    static func engrave(_ text: String, into id: ObjectID, at point: Vec3, normal: Vec3, size: Double, raised: Bool,
                        in scene: Scene) throws(Failure) -> EditCommand {
        let (solid, world) = try worldSolid(id, in: scene)
        do throws(PrintTools.Failure) {
            let result = try PrintTools.engrave(text, on: solid, at: point, normal: normal, size: size, raised: raised)
            return .batch(raised ? "Emboss" : "Engrave", [.setKind(id, .mesh(result.untransformed(by: world)))])
        } catch {
            throw printFailure(error)
        }
    }

    static func screwHole(_ kind: ScrewHole, _ screw: MetricScrew, in id: ObjectID, at point: Vec3, normal: Vec3, tolerance: Double,
                          in scene: Scene) throws(Failure) -> EditCommand {
        let (solid, world) = try worldSolid(id, in: scene)
        do throws(PrintTools.Failure) {
            let result = try PrintTools.hole(kind, screw, in: solid, at: point, normal: normal, tolerance: tolerance)
            return .batch("\(screw.rawValue) hole", [.setKind(id, .mesh(result.untransformed(by: world)))])
        } catch {
            throw printFailure(error)
        }
    }

    enum PrintPiece: String, CaseIterable, Sendable {
        case jar, bolt, nut

        public var title: String {
            switch self {
            case .jar: "Jar & lid"
            case .bolt: "Bolt"
            case .nut: "Nut"
            }
        }

        public var systemImage: String {
            switch self {
            case .jar: "cylinder.split.1x2"
            case .bolt: "screwdriver"
            case .nut: "hexagon"
            }
        }
    }

    /// Printed pieces standing on the bed at `point`: a jar and its screw-on lid (two things), a bolt or a nut.
    static func addPrintPiece(_ piece: PrintPiece, screw: MetricScrew = .m6, tolerance: Double = 0.0002, at point: Vec3,
                              ids: inout IDFactory) throws(Failure) -> EditCommand {
        var objects: [SceneObject] = []
        do throws(MeshBoolean.Failure) {
            switch piece {
            case .jar:
                let (jar, lid) = try Threads.Jar(tolerance: tolerance).make()
                for (mesh, name) in [(jar, "Jar"), (lid, "Lid")] {
                    var object = newSolid(mesh.transformed(by: Transform(position: point)), id: ids.next())
                    object.name = name
                    objects.append(object)
                }
            case .bolt:
                var object = try newSolid(Threads.bolt(screw, tolerance: tolerance).transformed(by: Transform(position: point)), id: ids.next())
                object.name = "\(screw.rawValue) bolt"
                objects.append(object)
            case .nut:
                var object = try newSolid(Threads.nut(screw, tolerance: tolerance).transformed(by: Transform(position: point)), id: ids.next())
                object.name = "\(screw.rawValue) nut"
                objects.append(object)
            }
        } catch {
            throw .boolean(error)
        }
        return .batch(piece.title, objects.map { .insert(SceneFragment(object: $0), parent: nil, index: nil) })
    }

    /// The part scaled evenly so its `axis` (or longest side) is `target` metres.
    static func scaleToSize(_ id: ObjectID, target: Double, axis: Axis?, in scene: Scene) throws(Failure) -> EditCommand {
        guard let object = scene.objects[id] else { throw .notEditable }
        let (solid, _) = try worldSolid(id, in: scene)
        guard let bounds = solid.bounds, let factor = PrintTools.scale(toSize: target, bounds: bounds, axis: axis) else { throw .notEditable }
        let scale = object.transform.scale * factor
        return .batch("Scale to size", [.setProperties([PropertyChange(object: id, key: .scale, value: .vec3(scale))])])
    }
}
