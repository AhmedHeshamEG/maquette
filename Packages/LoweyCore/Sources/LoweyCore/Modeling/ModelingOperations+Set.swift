import Foundation

/// U6's modelling set as commands, each one labelled undo step on the object's baked mesh (its scale in its corners,
/// as every Model edit), keeping live symmetry.
public extension ModelingOperations {
    enum SetFailure: Error, Equatable, CustomStringConvertible {
        case bridge(MeshRepair.BridgeFailure)
        case remesh(QuadRemesh.Failure)
        case profile(ProfileSolids.Failure)
        case nothingToFill
        case nothingToMerge

        public var description: String {
            switch self {
            case let .bridge(failure): failure.description
            case let .remesh(failure): failure.description
            case let .profile(failure): failure.description
            case .nothingToFill: "There's no hole to fill"
            case .nothingToMerge: "Pick two or more corners to merge"
            }
        }
    }

    /// The space modelling edits happen in: the object's place and turn, with its scale baked into the mesh when it
    /// will be (the lengths are real), else kept.
    static func modellingSpace(of id: ObjectID, in scene: Scene) -> Transform {
        var world = scene.worldTransform(of: id)
        if let object = scene.objects[id], let (_, bakes) = bakedMesh(of: object), bakes { world.scale = .one }
        return world
    }

    // MARK: Topology

    /// Makes the Smooth switch's look real: the shape subdivided into its corners (the switch goes off).
    static func subdivide(_ id: ObjectID, levels: Int, in scene: Scene) throws(Failure) -> EditCommand {
        let command = try reshape(id, label: "Subdivide", in: scene, near: { _ in nil }) { mesh in Subdivision.subdivide(mesh, levels: levels) }
        return .batch("Subdivide", [command, .setProperties([PropertyChange(object: id, key: .subdivision, value: nil)])])
    }

    static func loopCut(_ id: ObjectID, across edge: MeshEdge, cuts: Int, position: Double = 0.5, in scene: Scene) throws(Failure) -> EditCommand {
        try reshape(id, label: "Loop cut", in: scene, near: { mesh in edgeMiddle(edge, in: mesh) }) { mesh in
            LoopCut.cut(mesh.withoutHoles(), across: edge, cuts: cuts, position: position)
        }
    }

    /// The knife, with its plane and its reach in modelling space (`modellingSpace`).
    static func knife(_ id: ObjectID, planePoint: Vec3, planeNormal: Vec3, within: (Vec3) -> Bool, in scene: Scene) throws(Failure) -> EditCommand {
        try reshape(id, label: "Knife", in: scene, near: { _ in planePoint }) { mesh in
            Knife.cut(mesh, planePoint: planePoint, planeNormal: planeNormal, within: within)
        }
    }

    static func fillHoles(_ id: ObjectID, near corners: Set<Int>?, in scene: Scene) throws -> EditCommand {
        guard let object = scene.objects[id], let (mesh, _) = bakedMesh(of: object), !MeshRepair.holes(in: mesh).isEmpty else {
            throw SetFailure.nothingToFill
        }
        return try reshape(id, label: "Fill hole", in: scene, near: { _ in nil }) { mesh in MeshRepair.fillHoles(mesh, near: corners) }
    }

    static func merge(_ id: ObjectID, corners: Set<Int>, in scene: Scene) throws -> EditCommand {
        guard corners.count >= 2 else { throw SetFailure.nothingToMerge }
        return try reshape(id, label: "Merge", in: scene, near: { mesh in
            let valid = corners.filter(mesh.vertices.indices.contains)
            return valid.isEmpty ? nil : valid.reduce(Vec3.zero) { $0 + mesh.vertices[$1] } / Double(valid.count)
        }) { mesh in MeshRepair.merge(corners, in: mesh) }
    }

    static func mergeByDistance(_ id: ObjectID, distance: Double, in scene: Scene) throws(Failure) -> EditCommand {
        try reshape(id, label: "Merge by distance", in: scene, near: { _ in nil }) { mesh in MeshRepair.merge(within: distance, in: mesh) }
    }

    static func bridge(_ id: ObjectID, faces first: Int, _ second: Int, in scene: Scene) throws -> EditCommand {
        guard let object = scene.objects[id], let (mesh, _) = bakedMesh(of: object) else { throw Failure.notEditable }
        do {
            _ = try MeshRepair.bridge(first, second, in: mesh)
        } catch {
            throw SetFailure.bridge(error)
        }
        return try reshape(id, label: "Bridge", in: scene, near: { centroid(ofFaces: [first, second], in: $0) }) { mesh in
            (try? MeshRepair.bridge(first, second, in: mesh)) ?? mesh
        }
    }

    /// Clean topology: the shape as shown (`source`, its own space before its scale) remeshed into quads. Everything
    /// that shaped it (smoothing, the bend, the cage, brush strokes, the cuts for bending) is baked in and switched off.
    static func cleanTopology(_ id: ObjectID, source: MeshData, options: QuadRemesh.Options, in scene: Scene) throws -> EditCommand {
        guard let object = scene.objects[id] else { throw Failure.notEditable }
        let scale = object.children.isEmpty ? object.transform.scale : .one
        var scaled = source
        scaled.positions = source.positions.map { $0 * SIMD3<Float>(Float(scale.x), Float(scale.y), Float(scale.z)) }
        let mesh: EditableMesh
        do {
            mesh = try QuadRemesh.remesh(scaled, options: options)
        } catch {
            throw SetFailure.remesh(error)
        }
        var commands: [EditCommand] = [.setKind(id, .mesh(mesh))]
        var changes = [PropertyKey.subdivision, .deform, .deformAmount, .deformAxis, .bendDetail, .smoothAngle].map {
            PropertyChange(object: id, key: $0, value: nil)
        }
        if object.children.isEmpty { changes.append(PropertyChange(object: id, key: .scale, value: .vec3(.one))) }
        commands.append(.setProperties(changes))
        if object.shaping != nil { commands.append(.setShaping(id, nil)) }
        return .batch("Clean up the shape", commands)
    }

    internal static func edgeMiddle(_ edge: MeshEdge, in mesh: EditableMesh) -> Vec3? {
        guard mesh.vertices.indices.contains(edge.a), mesh.vertices.indices.contains(edge.b) else { return nil }
        return (mesh.vertices[edge.a] + mesh.vertices[edge.b]) / 2
    }

    // MARK: Profiles

    /// A sketch region swept along a path (world points) into a new solid; the region is used up.
    static func sweep(sketch id: ObjectID, region index: Int, along path: [Vec3], closed: Bool, in scene: Scene,
                      ids: inout IDFactory) throws -> EditCommand {
        let (sketch, region) = try profile(id, index, in: scene)
        let solid: EditableMesh
        do {
            solid = try ProfileSolids.sweep(ProfileSolids.loops(of: region, on: sketch.plane), plane: sketch.plane, along: path, closed: closed)
        } catch {
            throw SetFailure.profile(error)
        }
        return profileSolid(solid, label: "Sweep", using: [(id, sketch, region)], ids: &ids)
    }

    /// A sketch region turned around a line (world space) into a new solid; the region is used up.
    static func revolve(sketch id: ObjectID, region index: Int, axisPoint: Vec3, axisDirection: Vec3, degrees: Double, in scene: Scene,
                        ids: inout IDFactory) throws -> EditCommand {
        let (sketch, region) = try profile(id, index, in: scene)
        let solid: EditableMesh
        do {
            solid = try ProfileSolids.revolve(ProfileSolids.loops(of: region, on: sketch.plane), plane: sketch.plane, axisPoint: axisPoint,
                                              axisDirection: axisDirection, degrees: degrees)
        } catch {
            throw SetFailure.profile(error)
        }
        return profileSolid(solid, label: "Revolve", using: [(id, sketch, region)], ids: &ids)
    }

    /// A skin through several sketch regions in order (their outlines); the regions are used up.
    static func loft(_ profiles: [(sketch: ObjectID, region: Int)], in scene: Scene, ids: inout IDFactory) throws -> EditCommand {
        let used = try profiles.map { entry -> (ObjectID, Sketch, SketchRegion) in
            let (sketch, region) = try profile(entry.sketch, entry.region, in: scene)
            return (entry.sketch, sketch, region)
        }
        let solid: EditableMesh
        do {
            let outlines = used.map { entry in entry.2.outline.map { entry.1.plane.lift($0) } }
            solid = try ProfileSolids.loft(outlines, normals: used.map(\.1.plane.normal))
        } catch {
            throw SetFailure.profile(error)
        }
        return profileSolid(solid, label: "Loft", using: used, ids: &ids)
    }

    private static func profile(_ id: ObjectID, _ index: Int, in scene: Scene) throws(Failure) -> (Sketch, SketchRegion) {
        guard let object = scene.objects[id], case let .sketch(sketch) = object.kind else { throw .noSuchRegion }
        let regions = sketch.regions
        guard regions.indices.contains(index) else { throw .noSuchRegion }
        return (sketch, regions[index])
    }

    private static func profileSolid(_ solid: EditableMesh, label: String, using profiles: [(ObjectID, Sketch, SketchRegion)],
                                     ids: inout IDFactory) -> EditCommand {
        var commands: [EditCommand] = [.insert(SceneFragment(object: newSolid(solid, id: ids.next())), parent: nil, index: nil)]
        var remaining: [ObjectID: Sketch] = [:]
        for (id, sketch, region) in profiles {
            remaining[id] = (remaining[id] ?? sketch).removing(region)
        }
        for (id, rest) in remaining.sorted(by: { $0.key.raw < $1.key.raw }) {
            commands.append(rest.curves.isEmpty ? .delete([id]) : .setKind(id, .sketch(rest)))
        }
        return .batch(label, commands)
    }
}
