import Foundation

/// Everything done to a shape between its recipe and the screen, in one order the stage, painting, rigging and every
/// export share: smoothed (subdivision) as it's built, then cut finer for bending (`bendDetail`), then moved: the
/// surface brushes' strokes, the cage, and the whole-shape bend. Moving keeps every corner (none added, none taken
/// away, same order), so paint and rigs found on the unmoved mesh carry over corner for corner.
public enum ShapeStack {
    /// What moves the shape's corners after it's built, for keying caches (nil when nothing does).
    public struct Key: Hashable, Sendable {
        public var sculpt: UInt64?
        public var cage: DeformCage?
        public var deform: String?
        /// Bend amounts are kept to a ten-thousandth, so an animated bend reuses its meshes when it holds still.
        public var amount: Int64
        public var axis: String?
    }

    public static func key(of object: SceneObject) -> Key? {
        let deform = Deform.of(object)
        let cage = object.shaping?.cage.flatMap { $0.isAtRest ? nil : $0 }
        let sculpt = object.shaping?.sculpt?.fingerprint
        guard deform != nil || cage != nil || sculpt != nil else { return nil }
        return Key(sculpt: sculpt, cage: cage, deform: deform?.kind.rawValue, amount: Int64(((deform?.amount ?? 0) * 10000).rounded()),
                   axis: deform?.axis.rawValue)
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

    /// The built mesh cut finer and moved: what's shown.
    public static func shaped(_ mesh: MeshData, for object: SceneObject) -> MeshData {
        moved(unshaped(mesh, for: object), for: object)
    }

    /// The built mesh cut finer for bending: what brushes, the cage, paint and rigs are measured on.
    public static func unshaped(_ mesh: MeshData, for object: SceneObject) -> MeshData {
        MeshDensify.apply(mesh, for: object)
    }

    /// The unmoved mesh's corners moved by the strokes, the cage and the bend (the same corners, in order).
    public static func moved(_ mesh: MeshData, for object: SceneObject) -> MeshData {
        guard key(of: object) != nil else { return mesh }
        var result = mesh
        result.positions = movedPositions(mesh.positions, for: object, bounds: mesh.bounds)
        result.computeSmoothNormals()
        return result
    }

    /// Positions moved as `moved` does; the bend is measured over `bounds` (a placed model's parts use the whole
    /// model's box). Strokes apply only when they were made for this many corners (and `strokes` allows them: a placed
    /// model's separate parts never take them).
    public static func movedPositions(_ positions: [SIMD3<Float>], for object: SceneObject, bounds: Bounds?,
                                      strokes: Bool = true) -> [SIMD3<Float>] {
        var result = positions
        if strokes, let sculpt = object.shaping?.sculpt, sculpt.vertexCount == result.count {
            for (corner, offset) in sculpt.moved {
                result[corner] += offset
            }
        }
        if let cage = object.shaping?.cage, !cage.isAtRest {
            result = CageDeform.apply(cage, to: result)
        }
        if let deform = Deform.of(object), let bounds {
            result = deform.kind.apply(result, amount: deform.amount, axis: deform.axis, bounds: bounds)
        }
        return result
    }
}
