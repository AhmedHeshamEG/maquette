import LoweyCore
import Metal
import simd

extension SceneCompiler {
    /// A fluid as the run left it at this moment: water as a glossy surface in its colour, smoke as soft puffs and fire
    /// as glowing ones, both drawn the way the scene's particles are. Before its run reaches here, only its helper shows.
    func compileFluid(_ object: SceneObject, state: Inherited, input: RenderInput, scene: inout RenderScene) {
        guard case let .fluid(recipe) = object.kind else { return }
        if input.showsHelpers {
            scene.helpers.append(HelperItem(kind: .emitter, object: object.id, transform: state.world, color: recipe.color, radius: 0.1))
        }
        guard let look = input.simulated.fluids[object.id] else { return }
        let index = scene.index(for: object.id, lineWeight: 0)
        if let surface = look.surface, !surface.isEmpty, let mesh = GPUMesh(device: device, mesh: surface, label: "\(object.name) water") {
            var water = uniforms(for: object, state: state, input: input, scene: &scene, objectIndex: index)
            water.baseColor = SIMD4<Float>(recipe.color.linear, Float(0.82 * state.opacity))
            water.params.z = 1
            water.ids.z |= ObjectFlags.glossy.rawValue
            add(mesh, world: matrix_identity_float4x4, uniforms: water, castsShadow: true, scene: &scene)
        }
        guard !look.puffs.isEmpty else { return }
        var style = ParticleRecipe.preset(recipe.kind == .fire ? .fire : .smoke)
        style.shape = .puff
        for band in ParticleMesher.bands(look.puffs, recipe: style) {
            guard let mesh = GPUMesh(device: device, mesh: band.mesh, label: "\(object.name) puffs") else { continue }
            var uniforms = ObjectUniforms()
            uniforms.baseColor = SIMD4<Float>(band.color.linear, Float(band.opacity * state.opacity))
            uniforms.emissive = SIMD4<Float>(band.color.linear * (recipe.kind == .fire ? 1.4 : 0.25), recipe.kind == .fire ? 1 : 0)
            uniforms.ids = SIMD4<UInt32>(index, 0, ObjectFlags.unlit.rawValue, 0)
            add(mesh, world: matrix_identity_float4x4, uniforms: uniforms, castsShadow: false, scene: &scene)
        }
    }
}
