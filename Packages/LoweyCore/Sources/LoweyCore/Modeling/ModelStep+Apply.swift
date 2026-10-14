import Foundation

/// Running a step on a shape and handing its faces' tags on (H1).
public extension ModelStep {
    /// A shape and its faces' tags.
    struct Shape: Sendable {
        public var mesh: EditableMesh
        public var tags: [PartTags.Tag]

        public init(mesh: EditableMesh, tags: [PartTags.Tag]) {
            self.mesh = mesh
            self.tags = tags.count == mesh.faces.count ? tags : PartTags.base(count: mesh.faces.count)
        }
    }

    /// What was picked when the step was made (it runs on exactly those); a replay finds them by their tags instead.
    enum Picks: Sendable {
        case faces([Int])
        case edges(Set<MeshEdge>)
    }

    /// The shape after this step.
    func apply(to shape: Shape, picks: Picks? = nil) throws(ModelingOperations.Failure) -> Shape {
        var result = try applyAction(to: shape, picks: picks)
        if let symmetry {
            result = try Self.symmetrize(result, axis: symmetry, keepsPositive: keepsPositive, seed: tag)
        }
        return result
    }

    private func applyAction(to shape: Shape, picks: Picks?) throws(ModelingOperations.Failure) -> Shape {
        switch action {
        case let .pushPull(refs, distance):
            return try pushPull(shape, faces: faces(refs, picks, in: shape), distance: distance)
        case let .inset(refs, distance):
            let faces = try faces(refs, picks, in: shape)
            let mesh: EditableMesh
            do throws(Inset.Failure) {
                mesh = try Inset.apply(shape.mesh, faces: Set(faces), distance: distance)
            } catch {
                throw .shape(.inset(error))
            }
            let made = (0 ..< max(mesh.faces.count - shape.mesh.faces.count, 0)).map { PartTags.derive(tag, PartTags.Tag($0)) }
            return Shape(mesh: mesh, tags: shape.tags + made)
        case let .bevel(refs, size, style):
            let edges = try edges(refs, picks, in: shape)
            do throws(EdgeBevel.Failure) {
                let mesh = try EdgeBevel.apply(shape.mesh, edges: edges, size: size, style: style)
                return Shape(mesh: mesh, tags: PartTags.carry(from: [.init(mesh: shape.mesh, tags: shape.tags)], to: mesh, seed: tag))
            } catch {
                throw .shape(.bevel(error))
            }
        case let .shell(thickness, refs):
            return try shell(shape, thickness: thickness, open: refs.isEmpty ? [] : faces(refs, picks, in: shape))
        case let .sketch(cut):
            return try sketch(shape, cut: cut, resolving: picks == nil)
        case let .combine(tool, operation):
            return try combine(shape, with: tool, operation)
        }
    }

    // MARK: Actions

    private func pushPull(_ shape: Shape, faces: [Int], distance: Double) throws(ModelingOperations.Failure) -> Shape {
        let mesh: EditableMesh
        do throws(PushPull.Failure) {
            mesh = try PushPull.apply(shape.mesh, faces: faces, distance: distance)
        } catch {
            throw .pushPull(error)
        }
        if mesh.faces.count == shape.mesh.faces.count, PushPull.slides(shape.mesh, faces: faces) {
            return Shape(mesh: mesh, tags: shape.tags)
        }
        let unique = Array(Set(faces)).sorted()
        let moved = unique.map { face in
            let normal = shape.mesh.normal(of: face)
            let offset = normal.dot(shape.mesh.vertices[shape.mesh.faces[face].outline[0]]) + distance
            return PartTags.MovedPlane(normal: normal, offset: offset, tag: shape.tags[face])
        }
        let tools = unique.enumerated().map { ordinal, face in
            let prism = Prism.make(shape.mesh, face: face, distance: distance)
            let tags = prism.faces.indices.map { PartTags.derive(tag, PartTags.Tag(ordinal << 16 | $0)) }
            return PartTags.Source(mesh: prism, tags: tags, flipped: distance < 0)
        }
        let tags = PartTags.carry(from: [.init(mesh: shape.mesh, tags: shape.tags)] + tools, moved: moved, to: mesh, seed: tag)
        return Shape(mesh: mesh, tags: tags)
    }

    private func shell(_ shape: Shape, thickness: Double, open: [Int]) throws(ModelingOperations.Failure) -> Shape {
        do throws(Shell.Failure) {
            let mesh = try Shell.apply(shape.mesh, thickness: thickness, open: Set(open))
            let cavity = PartTags.Source(mesh: Shell.offset(shape.mesh, by: -thickness),
                                         tags: shape.tags.map { PartTags.derive(tag, $0) }, flipped: true)
            let tags = PartTags.carry(from: [.init(mesh: shape.mesh, tags: shape.tags), cavity], to: mesh, seed: tag)
            return Shape(mesh: mesh, tags: tags)
        } catch {
            throw .shape(.shell(error))
        }
    }

    private func sketch(_ shape: Shape, cut: SketchCut, resolving: Bool) throws(ModelingOperations.Failure) -> Shape {
        var plane = cut.plane
        if resolving, let ref = cut.onFace {
            // The face it was drawn on may have moved: the drawing moves with it.
            guard let face = PartTags.resolve(ref, in: shape.mesh, tags: shape.tags) else { throw .partLost }
            let normal = shape.mesh.normal(of: face)
            if abs(normal.dot(plane.normal)) > 1 - 1e-6 {
                plane.origin += plane.normal * plane.normal.dot(shape.mesh.vertices[shape.mesh.faces[face].outline[0]] - plane.origin)
            }
        }
        let sketch = Sketch(plane: plane, curves: cut.curves)
        let regions = sketch.regions
        guard regions.indices.contains(cut.region) else { throw .noSuchRegion }
        let region = regions[cut.region]
        if cut.distance > 0 {
            return try combine(shape, with: sketch.prism(of: region, distance: cut.distance), .union)
        }
        let depth = cut.through ? ModelStep.deepest(shape.mesh, below: plane) : cut.distance
        return try combine(shape, with: ModelingOperations.cutPrism(sketch, region, depth: depth, into: shape.mesh), .subtract)
    }

    /// How far below a plane the shape reaches (negative), for a cut that goes right through.
    static func deepest(_ mesh: EditableMesh, below plane: PlaneFrame) -> Double {
        min(mesh.vertices.map { plane.normal.dot($0 - plane.origin) }.min() ?? 0, 0)
    }

    private func combine(_ shape: Shape, with tool: EditableMesh, _ operation: MeshBoolean.Operation) throws(ModelingOperations.Failure) -> Shape {
        do throws(MeshBoolean.Failure) {
            let mesh = try MeshBoolean.combine(shape.mesh, tool, operation)
            let toolTags = tool.faces.indices.map { PartTags.derive(tag, PartTags.Tag($0)) }
            let tags = PartTags.carry(from: [.init(mesh: shape.mesh, tags: shape.tags),
                                             .init(mesh: tool, tags: toolTags, flipped: operation == .subtract)], to: mesh, seed: tag)
            return Shape(mesh: mesh, tags: tags)
        } catch {
            throw .boolean(error)
        }
    }

    /// Live symmetry after the step: the kept side keeps its names, its mirror image takes mirrored ones.
    static func symmetrize(_ shape: Shape, axis: SymmetryAxis, keepsPositive: Bool, seed: PartTags.Tag) throws(ModelingOperations.Failure) -> Shape {
        do throws(MeshBoolean.Failure) {
            let mesh = try MeshMirror.symmetrize(shape.mesh, across: axis.plane, keepPositive: keepsPositive)
            let mirror = PartTags.Source(mesh: MeshMirror.reflected(shape.mesh, across: axis.plane),
                                         tags: shape.tags.map { PartTags.derive($0, 0x5EED) })
            let tags = PartTags.carry(from: [.init(mesh: shape.mesh, tags: shape.tags), mirror], to: mesh, seed: PartTags.derive(seed, 0x5EED))
            return Shape(mesh: mesh, tags: tags)
        } catch {
            throw .boolean(error)
        }
    }

    // MARK: Finding the parts

    private func faces(_ refs: [FaceRef], _ picks: Picks?, in shape: Shape) throws(ModelingOperations.Failure) -> [Int] {
        if case let .faces(picked) = picks { return picked }
        var faces: [Int] = []
        for ref in refs {
            guard let face = PartTags.resolve(ref, in: shape.mesh, tags: shape.tags) else { throw .partLost }
            faces.append(face)
        }
        return faces
    }

    private func edges(_ refs: [EdgeRef], _ picks: Picks?, in shape: Shape) throws(ModelingOperations.Failure) -> Set<MeshEdge> {
        if case let .edges(picked) = picks { return picked }
        let topology = MeshTopology(shape.mesh)
        var edges = Set<MeshEdge>()
        for ref in refs {
            guard let edge = PartTags.resolve(ref, in: shape.mesh, topology: topology, tags: shape.tags) else { throw .partLost }
            edges.insert(edge)
        }
        return edges
    }
}
