import CoreGraphics
import Foundation
import ImageIO
import LoweyCore
import Metal
import simd

/// Painted objects in the frame: the mesh the renderer draws for the object, re-made with the paint's uvs, and the
/// paint's composite as its texture. When the shape changed since it was painted, the paint is carried onto the new
/// shape by position (off the main thread on the stage; until then the object shows unpainted).
extension SceneCompiler {
    /// The paint mesh and composite for an object drawn with `source`, or nil when it has no paint (or isn't ready).
    func painted(_ object: SceneObject, source: GPUMesh, state: Inherited, input: RenderInput) -> PaintedSurface? {
        guard let paint = object.paint, !state.ghost else { return nil }
        let file = input.paintFile
        let fingerprint = paints.fingerprint(of: source)
        let device = device
        let dabs = object.shadowDabs
        if fingerprint == paint.surface.mesh, let unwrap = paints.unwrap(paint.surface.unwrap, file: file) {
            guard let mesh = meshes.mesh(.paintSurface(paint.surface.unwrap, mesh: fingerprint, dabs: dabs), make: {
                Self.paintMesh(unwrap, over: source.data, dabs: dabs, device: device, label: object.name)
            }), let texture = paints.texture(for: object.id, paint: paint, unwrap: paint.surface.unwrap, mesh: mesh, file: file) else { return nil }
            return PaintedSurface(mesh: mesh, texture: texture, unwrap: unwrap, key: paint.surface.unwrap,
                                  maps: paints.maps(for: object.id, paint: paint, file: file))
        }
        var hasher = Hasher()
        hasher.combine(paint)
        let key = "carried \(fingerprint) \(hasher.finalize())"
        let ready = paints.onNeedsFrame ?? {}
        guard let carried = paints.carried.result(for: object.id, key: key, paint: paint, source: source.data, file: file,
                                                  synchronously: !paints.streams, ready: ready),
            let mesh = meshes.mesh(.paintSurface(key, mesh: fingerprint, dabs: dabs), make: {
                Self.paintMesh(carried.unwrap, over: source.data, dabs: dabs, device: device, label: object.name)
            }),
            let texture = paints.texture(for: object.id, paint: paint, unwrap: key, mesh: mesh, pictures: carried.layers, file: file)
        else { return nil }
        // Baked normals described the old surface: a carried paint shows without them.
        var shown = paint
        shown.normalMap = nil
        return PaintedSurface(mesh: mesh, texture: texture, unwrap: carried.unwrap, key: key, maps: paints.maps(for: object.id, paint: shown, file: file))
    }

    static func paintMesh(_ unwrap: PaintUnwrap, over source: MeshData, dabs: [ShadowDab], device: MTLDevice, label: String) -> GPUMesh? {
        guard let mesh = unwrap.mesh(over: source) else { return nil }
        return GPUMesh(device: device, mesh: mesh, shadowBias: ShadowPaint.biases(for: mesh, dabs: dabs), label: "\(label) paint")
    }

    /// Draws a painted surface: its paint mesh, the composite over the object's colour. A rigged object's paint mesh
    /// is skinned too: each of its vertices takes the weights of the vertex it was made from.
    func addPainted(_ painted: PaintedSurface, object: SceneObject, world: simd_float4x4, base: ObjectUniforms, casts: Bool, input: RenderInput,
                    scene: inout RenderScene) {
        var uniforms = base
        uniforms.ids.z |= ObjectFlags.painted.rawValue | (painted.maps?.flags.rawValue ?? 0)
        defer { finishPainted(painted, object: object, scene: &scene) }
        if let rig = object.rig, let file = rig.skin, let weights = skins.weights(file, read: input.paintFile),
           painted.unwrap.source.allSatisfy({ Int($0) < weights.count }) {
            let device = device
            let source = painted.unwrap.source.map(Int.init)
            if let skinned = meshes.mesh(.rigged("paint \(painted.key)", skin: file, dabs: object.shadowDabs), make: {
                GPUMesh(device: device, mesh: painted.mesh.data, joints: source.map { weights.joints[$0] }, weights: source.map { weights.weights[$0] },
                        label: "\(object.name) paint rigged")
            }) {
                let palette = appendPalette(rig, object: object, input: input, scene: &scene)
                addRigged(skinned, rig: rig, palette: palette, world: world, base: uniforms, texture: painted.texture, casts: casts, scene: &scene)
                return
            }
        }
        add(painted.mesh, world: world, uniforms: uniforms, texture: painted.texture, castsShadow: casts, scene: &scene)
    }

    /// The draw just added shows the object's paint: its maps, and its fur's map.
    private func finishPainted(_ painted: PaintedSurface, object: SceneObject, scene: inout RenderScene) {
        guard !scene.items.isEmpty else { return }
        scene.items[scene.items.count - 1].painted = object.id
        scene.items[scene.items.count - 1].maps = painted.maps
    }

    /// A placed model with paint: its parts as one mesh (in the model's space, as the parts are drawn).
    func paintedAsset(_ id: AssetID, model: ImportedModel, object: SceneObject, state: Inherited, base: ObjectUniforms, input: RenderInput,
                      casts: Bool, scene: inout RenderScene) -> Bool {
        guard object.paint != nil, !state.ghost, !model.parts.contains(where: \.isSkinned) else { return false }
        let device = device
        guard let source = meshes.mesh(.assetPaint(id), make: {
            AssetPaint.mergedMesh(model).flatMap { GPUMesh(device: device, mesh: $0, label: "\(object.name) parts") }
        }),
            let found = painted(object, source: source, state: state, input: input) else { return false }
        // Strokes, a cage and a bend move the one surface's corners.
        let shown = ShapeStack.key(of: object).flatMap { shape in
            meshes.mesh(.shaped(.assetPaint(id), shape)) {
                GPUMesh(device: device, mesh: ShapeStack.moved(source.data, for: object), label: "\(object.name) shaped")
            }
        } ?? source
        let surface = SurfaceMeshes(base: source, shown: shown)
        let painted = surface.isMoved ? movedPaint(found, over: surface, object: object) ?? found : found
        var uniforms = base
        if object.color == nil, state.tint == nil { uniforms.baseColor = SIMD4<Float>(1, 1, 1, base.baseColor.w) }
        addPainted(painted, object: object, world: state.world.matrix, base: uniforms, casts: casts, input: input, scene: &scene)
        return true
    }
}

/// A painted surface ready to draw: the paint mesh, the colour composite, its other maps, the unwrap it was made with
/// (and its key).
struct PaintedSurface {
    var mesh: GPUMesh
    var texture: MTLTexture
    var unwrap: PaintUnwrap
    var key: String
    var maps: PaintMapTextures?
}

/// Placed models as one paintable surface, and their own colours baked into a first layer.
public enum AssetPaint {
    /// The model's parts as one mesh with their own uvs (nil when a part moves with a skeleton: characters are painted
    /// once they're rigged the new way).
    public static func mergedMesh(_ model: ImportedModel) -> MeshData? {
        guard !model.parts.isEmpty, !model.parts.contains(where: \.isSkinned) else { return nil }
        var merged = MeshData()
        for part in model.parts {
            merged.append(part.mesh)
        }
        return merged.isEmpty ? nil : merged
    }

    /// Which part each triangle of the merged mesh came from.
    public static func partOfTriangle(_ model: ImportedModel) -> [Int] {
        model.parts.enumerated().flatMap { index, part in Array(repeating: index, count: part.mesh.triangleCount) }
    }

    /// Each merged vertex's own colour (white where a part has none), when any part has them.
    static func mergedColors(_ model: ImportedModel) -> [SIMD4<Float>]? {
        guard model.hasVertexColors else { return nil }
        return model.parts.flatMap { part in
            part.hasColors ? part.colors : Array(repeating: SIMD4<Float>(1, 1, 1, 1), count: part.mesh.positions.count)
        }
    }

    /// The model's colours (material colour times its texture at the part's own uvs, times a sculpt's vertex colours)
    /// on the unwrap.
    public static func bake(_ model: ImportedModel, merged: MeshData, unwrap: PaintUnwrap, size: Int) -> RGBAImage {
        let parts = partOfTriangle(model)
        let vertexColors = mergedColors(model).flatMap { $0.count == merged.positions.count ? $0 : nil }
        var textures: [Int: RGBAImage] = [:]
        for (index, texture) in model.textures.enumerated() {
            if let image = decode(texture.data) { textures[index] = image }
        }
        return PaintTransfer.bake(unwrap, size: size) { triangle, weights in
            guard triangle < parts.count else { return nil }
            let part = model.parts[parts[triangle]]
            let material = model.materials.indices.contains(part.material) ? model.materials[part.material] : ImportedMaterial()
            var color = RGBA(material.baseColor.r, material.baseColor.g, material.baseColor.b, 1)
            if let index = material.baseColorTexture, let image = textures[index], merged.uvs.count == merged.positions.count {
                let corners = (Int(merged.indices[triangle * 3]), Int(merged.indices[triangle * 3 + 1]), Int(merged.indices[triangle * 3 + 2]))
                let uv = merged.uvs[corners.0] * weights.x + merged.uvs[corners.1] * weights.y + merged.uvs[corners.2] * weights.z
                let texel = image.sample(u: Double(uv.x), v: Double(uv.y))
                color = RGBA(color.r * texel.r, color.g * texel.g, color.b * texel.b, 1)
            }
            if let vertexColors {
                let corners = (Int(merged.indices[triangle * 3]), Int(merged.indices[triangle * 3 + 1]), Int(merged.indices[triangle * 3 + 2]))
                let painted = vertexColors[corners.0] * weights.x + vertexColors[corners.1] * weights.y + vertexColors[corners.2] * weights.z
                color = RGBA(color.r * Double(painted.x), color.g * Double(painted.y), color.b * Double(painted.z), 1)
            }
            return color
        }
    }

    /// A model's embedded picture (PNG or JPEG) as straight RGBA.
    public static func decode(_ data: Data) -> RGBAImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil), let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return nil
        }
        let width = image.width, height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let space = CGColorSpace(name: CGColorSpace.sRGB),
                  let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                          space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        return drawn ? PaintPixels.straight(bytes, width: width, height: height) : nil
    }
}
