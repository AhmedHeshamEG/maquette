import LoweyCore

/// An object's surface twice: as built and cut (`base`: paint and rigs are found on it) and as shown (`shown`: moved by
/// brush strokes, a cage and a whole-shape bend; the same mesh when nothing moves it).
struct SurfaceMeshes {
    var base: GPUMesh
    var shown: GPUMesh

    var isMoved: Bool { base !== shown }
}
