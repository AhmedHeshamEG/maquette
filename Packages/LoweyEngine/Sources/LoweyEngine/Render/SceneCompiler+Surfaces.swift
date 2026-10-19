import CoreGraphics
import Foundation
import LoweyCore
import Metal
import simd

extension SceneCompiler {
    func compileSurface(_ object: SceneObject, state: Inherited, input: RenderInput, scene: inout RenderScene) {
        let pickID = state.pickAs ?? object.id
        let index = state.ghost ? 0 : scene.index(for: pickID, lineWeight: Float(object.lineWeight))
        let base = uniforms(for: object, state: state, input: input, scene: &scene, objectIndex: index)
        let world = state.world.matrix
        let casts = object[.castsShadow]?.boolValue ?? true
        let first = scene.items.count
        defer {
            if !state.ghost, let fur = FurSettings(object) { addFur(fur, object: object, from: first, scene: &scene) }
        }
        // Cloth and jelly in a run: the bent surface in place of the thing's own.
        if !state.ghost, let bent = input.simulated.meshes[object.id] {
            if let mesh = GPUMesh(device: device, mesh: bent, label: "\(object.name) bent") {
                add(mesh, world: world, uniforms: base, castsShadow: casts, scene: &scene)
            }
            return
        }
        // On its way into another thing's shape (D1).
        if !state.ghost, let morph = object.motionDesign?.morph,
           compileMorph(object, morph: morph, state: state, base: base, casts: casts, input: input, scene: &scene) {
            return
        }
        switch object.kind {
        case let .primitive(shape):
            compilePrimitive(shape, object: object, state: state, base: base, casts: casts, input: input, scene: &scene)
        case let .drawing(recipe) where recipe.style == .ink:
            compileInk(recipe, object: object, state: state, base: base, casts: object[.castsShadow]?.boolValue ?? false, input: input,
                       scene: &scene)
        case let .drawing(recipe):
            if let mesh = mesh(.drawing(recipe), object: object, label: object.name, make: {
                DrawingMesher.mesh(for: recipe).shaded(.smooth)
            }) {
                addSurface(mesh, object: object, state: state, world: world, base: base, casts: casts, input: input, scene: &scene)
            }
        case let .mesh(editable):
            let key = MeshKey.editable(editable, levels: ShapeStack.subdivision(of: object),
                                       angle: object[.smoothAngle]?.floatValue.map { Int32($0.rounded()) } ?? -1, flat: object.shading == .flat)
            if let mesh = mesh(key, object: object, label: object.name, make: { ShapeStack.render(editable, for: object) }) {
                addSurface(mesh, object: object, state: state, world: world, base: base, casts: casts, input: input, scene: &scene)
            }
        case let .text(recipe):
            compileText(recipe, object: object, world: world, base: base, casts: casts, input: input, scene: &scene)
        case let .asset(assetID):
            compileAsset(assetID, object: object, state: state, base: base, input: input, casts: casts, scene: &scene)
        case let .prefab(prefabID):
            compilePrefab(prefabID, object: object, state: state, input: input, scene: &scene, pickAs: pickID)
        case let .card(recipe):
            compileCard(recipe, object: object, world: world, base: base, input: input, casts: casts, scene: &scene)
        default:
            break
        }
    }

    /// A surface as drawn, or its paint mesh with the paint's composite when it's painted. Paint is found on the
    /// unmoved mesh (so an animated bend doesn't send it looking again every frame) and drawn over the moved corners.
    func addSurface(_ meshes: SurfaceMeshes, object: SceneObject, state: Inherited, world: simd_float4x4, base: ObjectUniforms, casts: Bool,
                    input: RenderInput, scene: inout RenderScene) {
        let mesh = meshes.shown
        let weightView = state.ghost ? nil : weightUniforms(base, object: object, input: input)
        if weightView == nil, let found = painted(object, source: meshes.base, state: state, input: input) {
            let painted = meshes.isMoved ? movedPaint(found, over: meshes, object: object) ?? found : found
            addPainted(painted, object: object, world: world, base: base, casts: casts, input: input, scene: &scene)
        } else if !state.ghost, let rig = rigWeights(object, input: input, vertexCount: mesh.data.positions.count)?.rig,
                  let skinned = riggedMesh(object, source: mesh, key: paints.fingerprint(of: mesh), input: input) {
            let palette = appendPalette(rig, object: object, input: input, scene: &scene)
            addRigged(skinned, rig: rig, palette: palette, world: world, base: weightView?.uniforms ?? base, texture: weightView?.texture,
                      casts: casts, scene: &scene)
        } else {
            add(mesh, world: world, uniforms: base, castsShadow: casts, scene: &scene)
        }
    }

    /// A painted surface's paint mesh rebuilt over the moved corners (same unwrap, same composite).
    func movedPaint(_ painted: PaintedSurface, over surface: SurfaceMeshes, object: SceneObject) -> PaintedSurface? {
        guard let shape = ShapeStack.key(of: object) else { return nil }
        var hasher = Hasher()
        hasher.combine(shape)
        let key = "\(painted.key) moved \(hasher.finalize())"
        let device = device
        let dabs = object.shadowDabs
        guard let mesh = meshes.mesh(.paintSurface(key, mesh: paints.fingerprint(of: surface.base), dabs: dabs), make: {
            Self.paintMesh(painted.unwrap, over: surface.shown.data, dabs: dabs, device: device, label: object.name)
        }) else { return nil }
        return PaintedSurface(mesh: mesh, texture: painted.texture, unwrap: painted.unwrap, key: painted.key, maps: painted.maps)
    }

    /// The object's mesh from the cache: cut finer when its rig asked for it (`MeshDensify`), with its Shadow Brush
    /// painting baked in; and that mesh moved by its strokes, cage and bend (`ShapeStack`) when it has any.
    func mesh(_ key: MeshKey, object: SceneObject, label: String, make: () -> MeshData) -> SurfaceMeshes? {
        let cuts = object[.bendDetail]?.floatValue.map { Int($0) } ?? 0
        let baseKey: MeshKey = cuts >= 1 ? .dense(key, cuts: cuts) : key
        let built: GPUMesh? = if cuts >= 1 {
            mesh(baseKey, dabs: object.shadowDabs, label: label) { MeshDensify.densified(make(), cuts: cuts) }
        } else {
            mesh(key, dabs: object.shadowDabs, label: label, make: make)
        }
        guard let built else { return nil }
        guard let shape = ShapeStack.key(of: object), let shown = mesh(.shaped(baseKey, shape), dabs: object.shadowDabs, label: label, make: {
            ShapeStack.moved(built.data, for: object)
        }) else { return SurfaceMeshes(base: built, shown: built) }
        return SurfaceMeshes(base: built, shown: shown)
    }

    /// A mesh from the cache, with the object's Shadow Brush painting baked into its vertices.
    func mesh(_ key: MeshKey, dabs: [ShadowDab] = [], label: String, make: () -> MeshData) -> GPUMesh? {
        let device = device
        guard !dabs.isEmpty else {
            return meshes.mesh(key) { GPUMesh(device: device, mesh: make(), label: label) }
        }
        return meshes.mesh(.painted(key, dabs: dabs)) {
            let data = make()
            return GPUMesh(device: device, mesh: data, shadowBias: ShadowPaint.biases(for: data, dabs: dabs), label: label)
        }
    }

    // MARK: Primitives

    func compilePrimitive(_ shape: PrimitiveShape, object: SceneObject, state: Inherited, base: ObjectUniforms, casts: Bool,
                          input: RenderInput, scene: inout RenderScene) {
        let scale = object.transform.scale
        if let bevel = BevelSpec(object), BevelSpec.applies(to: shape) {
            // Built at the object's own size so the bevel stays round; its scale is taken out of the matrix.
            let size = SIMD3<Float>(Float(abs(scale.x)), Float(abs(scale.y)), Float(abs(scale.z)))
            let key = MeshKey.bevelled(shape, size: SIMD3<Int32>(MeshKey.mm(Double(size.x)), MeshKey.mm(Double(size.y)),
                                                                 MeshKey.mm(Double(size.z))),
                                       radius: MeshKey.mm(bevel.radius), segments: bevel.segments)
            guard let mesh = mesh(key, object: object, label: shape.rawValue, make: {
                BevelMesh.make(shape, size: size, bevel: bevel) ?? PrimitiveMesh.make(shape, shading: .smooth)
            }) else { return }
            let signs = SIMD3<Float>(scale.x < 0 ? -1 : 1, scale.y < 0 ? -1 : 1, scale.z < 0 ? -1 : 1)
            let unscale = simd_float4x4(diagonal: SIMD4<Float>(signs / simd_max(size, SIMD3<Float>(repeating: 1e-4)), 1))
            addSurface(mesh, object: object, state: state, world: state.world.matrix * unscale, base: base, casts: casts, input: input,
                       scene: &scene)
            return
        }
        let levels = ShapeStack.subdivision(of: object)
        let key: MeshKey = levels > 0 ? .subdivided(shape, levels: levels, flat: object.shading == .flat) : .primitive(shape, faceted: false)
        guard let mesh = mesh(key, object: object, label: shape.rawValue, make: {
            ShapeStack.primitive(shape, for: object, shading: object.shading == .flat ? .flat : .smooth)
        }) else { return }
        addSurface(mesh, object: object, state: state, world: state.world.matrix, base: base, casts: casts && shape != .plane, input: input,
                   scene: &scene)
    }

    // MARK: Cards

    func compileCard(_ recipe: CardRecipe, object _: SceneObject, world: simd_float4x4, base: ObjectUniforms, input: RenderInput, casts: Bool,
                     scene: inout RenderScene) {
        let size = recipe.cardSize
        let device = device
        let slabSize = SIMD3<Float>(Float(size.width), Float(size.height), Float(size.depth))
        let slabKey = MeshKey.card(width: MeshKey.mm(size.width), height: MeshKey.mm(size.height), depth: MeshKey.mm(size.depth))
        if let slab = meshes.mesh(slabKey, make: {
            let radius = min(size.depth * 0.45, 0.012)
            let data = BevelMesh.make(.cube, size: slabSize, bevel: BevelSpec(radius: radius, segments: 2))
                ?? PrimitiveMesh.box(size: slabSize)
            return GPUMesh(device: device, mesh: data, label: "card")
        }) {
            var slabUniforms = base
            if base.baseColor.xyz4 == RGBA.blockout.linear { slabUniforms.baseColor = SIMD4<Float>(RGBA(0.96, 0.95, 0.92).linear, 1) }
            add(slab, world: world, uniforms: slabUniforms, castsShadow: casts, scene: &scene)
        }
        let picture = recipe.pictureSize
        let pictureKey = MeshKey.picture(width: MeshKey.mm(picture.width), height: MeshKey.mm(picture.height))
        guard let quad = meshes.mesh(pictureKey, make: {
            GPUMesh(device: device, mesh: Self.pictureQuad(width: Float(picture.width), height: Float(picture.height),
                                                           center: SIMD3<Float>(0, Float(size.height / 2), Float(size.depth / 2) + 0.0015)),
                    label: "picture")
        }) else { return }
        var face = base
        face.baseColor = SIMD4<Float>(1, 1, 1, base.baseColor.w)
        face.emissive = .zero
        face.ids.z |= ObjectFlags.unlit.rawValue
        let texture = recipe.frameKey(at: input.time).flatMap { key in
            input.mediaImage(key).flatMap { textures.texture(for: $0, key: key, maxSide: recipe.video != nil ? 1280 : 2048) }
        }
        if texture == nil { face.baseColor = SIMD4<Float>(0.03, 0.03, 0.035, base.baseColor.w) }
        add(quad, world: world, uniforms: face, texture: texture, castsShadow: false, scene: &scene)
    }

    /// A front-facing (+Z) quad, uv origin at the top left.
    static func pictureQuad(width: Float, height: Float, center: SIMD3<Float>) -> MeshData {
        var mesh = MeshData()
        let normal = SIMD3<Float>(0, 0, 1)
        let a = mesh.addVertex(center + SIMD3<Float>(-width / 2, -height / 2, 0), normal: normal, uv: SIMD2<Float>(0, 1))
        let b = mesh.addVertex(center + SIMD3<Float>(width / 2, -height / 2, 0), normal: normal, uv: SIMD2<Float>(1, 1))
        let c = mesh.addVertex(center + SIMD3<Float>(width / 2, height / 2, 0), normal: normal, uv: SIMD2<Float>(1, 0))
        let d = mesh.addVertex(center + SIMD3<Float>(-width / 2, height / 2, 0), normal: normal, uv: SIMD2<Float>(0, 0))
        mesh.addTriangle(a, b, c)
        mesh.addTriangle(a, c, d)
        return mesh
    }

    // MARK: Prefabs

    func compilePrefab(_ prefabID: PrefabID, object: SceneObject, state: Inherited, input: RenderInput, scene: inout RenderScene,
                       pickAs: ObjectID) {
        guard state.depth < 6, let prefab = input.catalog.manifest.prefab(prefabID) else { return }
        let byID = Dictionary(uniqueKeysWithValues: prefab.fragment.objects.map { ($0.id, $0) })
        var lights: [(LightData, Float)] = []
        func visit(_ id: ObjectID, _ parent: Inherited) {
            guard let child = byID[id], child.isVisible else { return }
            var childState = parent
            childState.world = parent.world * child.transform
            childState.opacity *= child.opacity
            childState.depth = state.depth + 1
            childState.pickAs = pickAs
            // An instance-level colour tints every part (few decisions, big results).
            if object.color != nil, child.kind.hasSurface { childState.tint = object.color }
            compileObject(child, state: childState, input: input, scene: &scene, lights: &lights, cameraPosition: .zero)
            for grandchild in child.children {
                visit(grandchild, childState)
            }
        }
        for root in prefab.fragment.roots {
            visit(root, state)
        }
        scene.lights += lights.map(\.0)
    }

    // MARK: Particles

    func compileParticles(_ object: SceneObject, state: Inherited, input: RenderInput, scene: inout RenderScene) {
        guard case let .particles(recipe) = object.kind else { return }
        if input.showsHelpers {
            scene.helpers.append(HelperItem(kind: .emitter, object: object.id, transform: state.world, color: RGBA(1, 0.6, 0.2), radius: 0.1))
        }
        let timeline = input.document.scene.timeline
        let track = timeline.track(for: object.id, .emission)
        let amount = max(object.transform.scale.x, 0)
        // The scene's wind carries them and the ground stops them (in the emitter's own turned space).
        let physics = input.document.scene.physics
        let air = physics.map { state.world.rotation.inverse.act($0.wind(at: input.time)) } ?? .zero
        let upright = state.world.rotation.act(.unitY).y > 0.999
        let ground: Double? = (physics?.ground ?? true) && upright ? -state.world.position.y : nil
        let particles = ParticleSimulator.particles(recipe, at: input.time, amount: amount, air: air, ground: ground) { birth in
            track?.value(at: birth)?.floatValue ?? object[.emission]?.floatValue ?? 1
        }
        guard !particles.isEmpty else { return }
        let index = scene.index(for: object.id, lineWeight: 0)
        // The object's scale is the amount, not a size: particles keep their own size.
        let scale = object.transform.scale
        let unscale = simd_float4x4(diagonal: SIMD4<Float>(1 / Float(max(abs(scale.x), 1e-3)), 1 / Float(max(abs(scale.y), 1e-3)),
                                                           1 / Float(max(abs(scale.z), 1e-3)), 1))
        for band in ParticleMesher.bands(particles, recipe: recipe) {
            guard let mesh = GPUMesh(device: device, mesh: band.mesh, label: "particles") else { continue }
            var uniforms = ObjectUniforms()
            uniforms.baseColor = SIMD4<Float>(band.color.linear, Float(band.opacity * state.opacity))
            uniforms.emissive = SIMD4<Float>(band.color.linear * 0.6, 0)
            uniforms.ids = SIMD4<UInt32>(index, 0, ObjectFlags.unlit.rawValue, 0)
            add(mesh, world: state.world.matrix * unscale, uniforms: uniforms, castsShadow: false, scene: &scene)
        }
    }
}
