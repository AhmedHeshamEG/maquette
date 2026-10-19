import Foundation
import LoweyCore
import simd

/// Motion design on the GPU (D1): 3D text in a font brought in and letters that move on their own, and a shape on its way
/// into another's. Clones need nothing here: their copies are things in the shown scene, picked as the thing they copy.
extension SceneCompiler {
    // MARK: Text

    func compileText(_ recipe: TextRecipe, object: SceneObject, world: simd_float4x4, base: ObjectUniforms, casts: Bool,
                     input: RenderInput, scene: inout RenderScene) {
        if let letters = object.motionDesign?.letters {
            compileLetters(recipe, letters: letters, world: world, base: base, casts: casts, time: input.time, scene: &scene)
            return
        }
        let reveal = min(max(object[.reveal]?.floatValue ?? 1, 0), 1)
        var shown = recipe
        shown.text = String(recipe.text.prefix(Int((Double(recipe.text.count) * reveal).rounded(.down))))
        guard !shown.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let key: MeshKey = shown.coreMeshable ? .blockText(shown) : .systemText(shown)
        let fonts = fonts
        guard let mesh = mesh(key, label: "text", make: {
            shown.coreMeshable ? BlockFont.mesh(for: shown) : TextMesher.mesh(for: shown, fonts: fonts)
        }) else { return }
        add(mesh, world: world, uniforms: base, castsShadow: casts, scene: &scene)
    }

    /// Each letter at its pose: moved, turned and sized about its own middle, faded by its opacity.
    func compileLetters(_ recipe: TextRecipe, letters: TextAnimator, world: simd_float4x4, base: ObjectUniforms, casts: Bool, time: Double,
                        scene: inout RenderScene) {
        let set = letterSet(recipe)
        let indices = TextAnimator.letterIndices(recipe.text)
        let poses = letters.poses(count: indices.compactMap(\.self).count, at: time, size: recipe.size)
        let device = device
        for letter in set {
            guard indices.indices.contains(letter.index), let number = indices[letter.index], poses.indices.contains(number) else { continue }
            let pose = poses[number]
            guard pose.opacity > 0.001, pose.scale > 0.001,
                  let mesh = meshes.mesh(.letter(recipe, index: letter.index), make: { GPUMesh(device: device, mesh: letter.mesh, label: "letter") })
            else { continue }
            var uniforms = base
            uniforms.baseColor.w *= Float(min(max(pose.opacity, 0), 1))
            let centre = Vec3(Double(letter.centre.x), Double(letter.centre.y), Double(letter.centre.z))
            let about = LoweyCore.Transform(position: centre + pose.offset, rotation: Quat(eulerDegrees: pose.turn),
                                            scale: Vec3(pose.scale, pose.scale, pose.scale))
            let local = about.matrix * LoweyCore.Transform(position: centre * -1).matrix
            add(mesh, world: world * local, uniforms: uniforms, castsShadow: casts && pose.opacity > 0.99, scene: &scene)
        }
    }

    /// A text's letters, meshed once per recipe (a few are kept).
    private func letterSet(_ recipe: TextRecipe) -> [TextLetter] {
        if let known = letterSets[recipe] { return known }
        if letterSets.count > 16 { letterSets.removeAll() }
        let made = TextMesher.letters(for: recipe, fonts: fonts)
        letterSets[recipe] = made
        return made
    }

    // MARK: Morph

    /// The thing on its way into its target's shape (`morph` 0…1), its colour going the same way; at 1 it is the target's
    /// shape. False when there's nothing to draw (no morph yet, or a shape this can't reach).
    func compileMorph(_ object: SceneObject, morph: ObjectMorph, state: Inherited, base: ObjectUniforms, casts: Bool, input: RenderInput,
                      scene: inout RenderScene) -> Bool {
        let amount = object.morphAmount
        guard amount > 0.001, let target = input.document.scene.objects[morph.target] else { return false }
        let look = input.document.effectiveLook
        let ratio = input.document.scene.worldTransform(of: target.id).scale.divided(by: state.world.scale)
        let key = MorphKey(source: object.kind, target: target.kind, ratio: SIMD3<Int32>(MeshKey.mm(ratio.x), MeshKey.mm(ratio.y), MeshKey.mm(ratio.z)))
        var uniforms = base
        let to = (target.color?.resolved(in: input.document.palette) ?? .blockout).linear
        let eased = Float(CloneField.smooth(amount))
        uniforms.baseColor = SIMD4<Float>(simd_mix(base.baseColor.xyz4, to, SIMD3<Float>(repeating: eased)), base.baseColor.w)
        let device = device
        let mesh: GPUMesh?
        if amount >= 0.999 {
            mesh = meshes.mesh(.morphTarget(key.target, ratio: key.ratio)) {
                Self.scaledTarget(target, look: look, ratio: ratio).flatMap { GPUMesh(device: device, mesh: $0, label: "morph") }
            }
        } else {
            guard let pair = morphPair(key, source: object, target: target, look: look, ratio: ratio) else { return false }
            mesh = GPUMesh(device: device, mesh: pair.mesh(at: amount), label: "\(object.name) morphing")
        }
        guard let mesh else { return false }
        add(mesh, world: state.world.matrix, uniforms: uniforms, castsShadow: casts, scene: &scene)
        return true
    }

    private func morphPair(_ key: MorphKey, source: SceneObject, target: SceneObject, look: Look, ratio: Vec3) -> MorphPair? {
        if let known = morphPairs[key] { return known }
        guard let from = SceneExport.localMesh(of: source, look: look), let to = Self.scaledTarget(target, look: look, ratio: ratio) else { return nil }
        if morphPairs.count > 8 { morphPairs.removeAll() }
        let pair = MorphPair(source: from, target: to)
        morphPairs[key] = pair
        return pair
    }

    /// The target's shape in the morphing thing's space, at the target's own size.
    static func scaledTarget(_ target: SceneObject, look: Look, ratio: Vec3) -> MeshData? {
        guard var mesh = SceneExport.localMesh(of: target, look: look), !mesh.isEmpty else { return nil }
        let scale = SIMD3<Float>(Float(ratio.x), Float(ratio.y), Float(ratio.z))
        mesh.positions = mesh.positions.map { $0 * scale }
        return mesh
    }
}

/// What a morph's correspondence depends on.
struct MorphKey: Hashable {
    var source: ObjectKind
    var target: ObjectKind
    var ratio: SIMD3<Int32>
}

private extension Vec3 {
    func divided(by other: Vec3) -> Vec3 {
        Vec3(other.x != 0 ? x / other.x : 1, other.y != 0 ? y / other.y : 1, other.z != 0 ? z / other.z : 1)
    }
}
