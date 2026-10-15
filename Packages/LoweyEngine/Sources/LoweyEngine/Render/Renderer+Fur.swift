import LoweyCore
import Metal
import simd

/// Painted maps in the shading pass, and fur (U7): shells drawn over a surface one by one, each a little further out,
/// keeping only the strands' cross-sections; hair cards drawn as strips with their strands cut out.
extension LoweyRenderer {
    /// Binds a draw's painted maps (textures 3 … 7); every slot gets a texture, white where nothing paints it.
    func bindMaps(_ maps: PaintMapTextures?, encoder: MTLRenderCommandEncoder) {
        let white = editorMeshes.white
        encoder.setFragmentTexture(maps?.roughness ?? white, index: 3)
        encoder.setFragmentTexture(maps?.metal ?? white, index: 4)
        encoder.setFragmentTexture(maps?.glow ?? white, index: 5)
        encoder.setFragmentTexture(maps?.bumps ?? white, index: 6)
        encoder.setFragmentTexture(maps?.normals ?? white, index: 7)
    }

    /// Fur shells and hair cards, after the surfaces they grow on (they test against their depth).
    func encodeFur(ordered: [DrawItem], gpu: FrameBuffers, encoder: MTLRenderCommandEncoder) -> Int {
        var draws = 0
        encoder.setDepthStencilState(device.pipelines.depthWrite)
        for (index, item) in ordered.enumerated() {
            if item.furCards {
                encoder.setRenderPipelineState(device.pipelines.furCards)
                encoder.setFragmentTexture(item.texture ?? editorMeshes.white, index: 0)
                bindMaps(nil, encoder: encoder)
                draw(item.mesh, run: Run(start: index, count: 1), encoder: encoder, objects: gpu.objects)
                draws += 1
                continue
            }
            guard let fur = item.fur, fur.length > 0, fur.shells > 0 else { continue }
            encoder.setRenderPipelineState(item.mesh.isSkinned ? device.pipelines.furSkinned : device.pipelines.furStatic)
            encoder.setFragmentTexture(item.texture ?? editorMeshes.white, index: 0)
            bindMaps(item.maps, encoder: encoder)
            encoder.setFragmentTexture(fur.map ?? editorMeshes.white, index: 8)
            for shell in 1 ... fur.shells {
                let t = Float(shell) / Float(fur.shells)
                // x: how far out (m), y: how far it has dropped (m), z: strands across the texture, w: how far up the strand.
                var shellData = SIMD4<Float>(fur.length * t, fur.droop * t * t * fur.length * 0.5, fur.density, t)
                encoder.setVertexBytes(&shellData, length: MemoryLayout<SIMD4<Float>>.stride, index: BufferIndex.cascade)
                encoder.setFragmentBytes(&shellData, length: MemoryLayout<SIMD4<Float>>.stride, index: BufferIndex.cascade)
                draw(item.mesh, run: Run(start: index, count: 1), encoder: encoder, objects: gpu.objects)
                draws += 1
            }
        }
        return draws
    }
}

extension SceneCompiler {
    /// Fur on what an object just added (`items` from `first`): shells over each surface, or hair cards beside them.
    func addFur(_ fur: FurSettings, object: SceneObject, from first: Int, scene: inout RenderScene) {
        guard first < scene.items.count else { return }
        let diagonal = Float(scene.items[first].mesh.bounds.size.length)
        switch fur.style {
        case .shells:
            for index in first ..< scene.items.count where !scene.items[index].ghost && !scene.items[index].blended {
                let draw = FurDraw(length: Float(fur.length), density: Float(fur.strandsPerMetre) * max(diagonal, 0.05) * 0.5,
                                   droop: Float(fur.droop), shells: furShells, map: scene.items[index].maps?.fur)
                scene.items[index].fur = draw
            }
        case .cards:
            let count = scene.items.count
            for index in first ..< count where !scene.items[index].ghost && !scene.items[index].blended && !scene.items[index].mesh.isSkinned {
                let item = scene.items[index]
                let device = device
                guard let cards = meshes.mesh(.furCards(paints.fingerprint(of: item.mesh), fur), make: {
                    GPUMesh(device: device, mesh: FurGeometry.cards(on: item.mesh.data, fur: fur), label: "\(object.name) hair cards")
                }) else { continue }
                // The cards' uvs run along each strip, not over the paint: they take the thing's own colour.
                var card = item
                card.mesh = cards
                card.texture = nil
                card.maps = nil
                card.fur = nil
                card.hull = 0
                card.furCards = true
                card.castsShadow = false
                card.uniforms.ids.z &= ~(ObjectFlags.textured.rawValue | ObjectFlags.painted.rawValue | ObjectFlags.roughness.rawValue
                    | ObjectFlags.metal.rawValue | ObjectFlags.glow.rawValue | ObjectFlags.bumps.rawValue | ObjectFlags.normals.rawValue)
                card.worldBounds = cards.bounds.transformed(by: item.uniforms.model)
                scene.add(card)
            }
        }
    }
}
