import Foundation

/// Everything done to a shape between its recipe and the screen, in one order the stage, painting, rigging and every
/// export share: smoothed (subdivision) as it's built, then cut finer for bending (`bendDetail`), then the surface
/// brushes' strokes, the cage, and the whole-shape bend. Every step after building moves corners only, so a painted or
/// rigged shape still finds its corners.
public enum ShapeStack {
    /// What changes the shown shape after it's built, for keying caches (nil when nothing does).
    public struct Key: Hashable, Sendable {
        public var cuts: Int
        public var sculpt: UInt64?
        public var cage: DeformCage?
        public var deform: String?
        /// Bend amounts are kept to a tenth of a thousandth, so an animated bend reuses its meshes when it holds still.
        public var amount: Int64
        public var axis: String?
    }

    public static func key(of object: SceneObject) -> Key? {
        let cuts = object[.bendDetail]?.floatValue.map { Int($0) } ?? 0
        let deform = Deform.of(object)
        let shaping = object.shaping
        guard cuts >= 1 || deform != nil || shaping?.cage.map({ !$0.isAtRest }) == true || shaping?.sculpt != nil else { return nil }
        return Key(cuts: max(cuts, 0), sculpt: shaping?.sculpt?.fingerprint, cage: shaping?.cage?.isAtRest == false ? shaping?.cage : nil,
                   deform: deform?.kind.rawValue, amount: Int64(((deform?.amount ?? 0) * 10000).rounded()), axis: deform?.axis.rawValue)
    }

    // MARK: Building

    /// How many times the shape is smoothed (0…3).
    public static func subdivision(of object: SceneObject) -> Int {
        min(max(object[.subdivision]?.floatValue.map { Int($0) } ?? 0, 0), Subdivision.maximumLevels)
    }

    /// A modelled shape's triangles, smoothed when asked and shaded by its smooth angle (crisp by default).
    public static func render(_ mesh: EditableMesh, for object: SceneObject) -> MeshData {
        let levels = subdivision(of: object)
        let source = levels > 0 ? Subdivision.subdivide(mesh, levels: levels) : mesh
        let flat = object.shading == .flat
        if levels > 0, !flat { return source.renderMesh().autoSmoothed(angle: Float(object[.smoothAngle]?.floatValue ?? 180)) }
        if let angle = object[.smoothAngle]?.floatValue, !flat { return source.renderMesh().autoSmoothed(angle: Float(angle)) }
        return source.renderMesh()
    }

    /// A blockout shape smoothed as asked (its unit mesh; the object's scale is applied when drawn).
    public static func primitive(_ shape: PrimitiveShape, for object: SceneObject, shading: ShadingStyle) -> MeshData {
        let levels = subdivision(of: object)
        guard levels > 0 else { return PrimitiveMesh.make(shape, shading: shading) }
        let editable = MeshBuilder.mesh(from: PrimitiveMesh.make(shape, shading: .smooth))
        let smooth = Subdivision.subdivide(editable, levels: levels).renderMesh()
        return shading == .flat ? smooth.faceted() : smooth.autoSmoothed(angle: 180)
    }

    // MARK: After building

    /// The built mesh with the rest of the stack applied: cut finer, the strokes, the cage, the bend.
    public static func shaped(_ mesh: MeshData, for object: SceneObject) -> MeshData {
        var result = MeshDensify.apply(mesh, for: object)
        let bounds = result.bounds
        var moved = false
        if let sculpt = object.shaping?.sculpt, sculpt.vertexCount == result.positions.count {
            for (corner, offset) in sculpt.moved { result.positions[corner] += offset }
            moved = true
        }
        if let cage = object.shaping?.cage, !cage.isAtRest {
            result.positions = CageDeform.apply(cage, to: result.positions)
            moved = true
        }
        if let deform = Deform.of(object), let bounds {
            result.positions = deform.kind.apply(result.positions, amount: deform.amount, axis: deform.axis, bounds: bounds)
            moved = true
        }
        if moved { result.computeSmoothNormals() }
        return result
    }

    /// The object's mesh before the bend, cage and strokes (what brushes and the cage are measured on): built and cut.
    public static func unshaped(_ mesh: MeshData, for object: SceneObject) -> MeshData {
        MeshDensify.apply(mesh, for: object)
    }
}
