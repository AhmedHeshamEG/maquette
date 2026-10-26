import Foundation
import LoweyCore
import simd

/// The 3D formats Maquette writes.
public enum ModelExportFormat: String, CaseIterable, Sendable, Identifiable, Codable {
    case glb, usdz, obj, stl
    /// A three.js folder (X1): the scene, a player, a React component and notes for agents.
    case web
    case threeMF = "3mf"
    case blender
    case fbx
    /// Every painted map as PNG pictures (U7).
    case textures

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .glb: "glTF (.glb)"
        case .web: "three.js folder"
        case .usdz: "USDZ"
        case .obj: "OBJ"
        case .stl: "STL"
        case .threeMF: "3MF"
        case .blender: "Blender"
        case .fbx: "FBX"
        case .textures: "Maps (PNG)"
        }
    }

    /// One line on what it's for.
    public var purpose: String {
        switch self {
        case .glb: "For Blender, game engines and other 3D apps: objects, materials, cameras, lights and animation."
        case .web: "For the web: a folder that plays in any browser with its cameras, timeline and Look, ready to build on."
        case .usdz: "For Apple's Quick Look and Reality Composer: opens on any iPhone or iPad."
        case .obj: "The oldest format every 3D app opens: shapes and colours."
        case .stl: "For 3D printing: every slicer reads it. Millimetres, standing on the bed."
        case .threeMF: "For 3D printing: millimetres, a colour per part, closed shapes slicers trust."
        case .blender: "Render on your computer: a folder Blender turns into the scene with its Look, lights and cameras."
        case .fbx: "For Unity and other game engines: the rigged thing with its bones and their keys."
        case .textures: "Every painted map as pictures: colour, roughness, metal, glow and normal, for any 3D app or engine."
        }
    }

    public var isForPrinting: Bool { self == .stl || self == .threeMF }
}

/// 3D export of the selection or the scene. Blockout and drawn objects come from LoweyCore (exact recipes);
/// library models use their loaded parts (geometry and colours, textures not carried over).
@MainActor
public enum ModelExport {
    /// The meshes as placed in the world (USDZ, OBJ, STL, 3MF); `painted` gives painted objects their paint mesh and
    /// texture (left out for printing).
    public static func meshes(_ ids: [ObjectID]?, scene: CoreScene, look: Look, catalog: AssetCatalog, models: ModelLibrary = .shared,
                              painted: (SceneObject) -> PaintedExport? = { _ in nil },
                              posed: (SceneObject) -> [GLTFScene.LocalPart]? = { _ in nil }) -> [ExportMesh] {
        SceneExport.meshes(ids, in: scene, look: look, extra: { object, world in
            localParts(object, look: look, catalog: catalog, models: models).map { part in
                ExportMesh(name: object.name, transform: world, mesh: part.mesh, color: part.material.color, emissive: part.material.emissive,
                           emissiveStrength: part.material.emissiveStrength, roughness: part.material.roughness, metallic: part.material.metallic)
            }
        }, painted: painted, posed: posed)
    }

    /// A rigged object's surface as its skeleton bends it, in its own space with its materials: `pose` is the animator's
    /// pose (the scene as shown), else the joints as turned by hand (the scene as edited). Nil when the object has no rig
    /// whose weights fit, and for a drawing already bent by the animator.
    public static func posedParts(_ object: SceneObject, pose: [LoweyCore.Transform]?, look: Look, catalog: AssetCatalog,
                                  models: ModelLibrary = .shared, file: (String) -> Data?) -> [GLTFScene.LocalPart]? {
        guard let rig = object.rig else { return nil }
        let skeleton = rig.skeleton
        let bind = skeleton.modelRest
        let posedModel = skeleton.modelSpace(RigPoses.posed(pose ?? skeleton.restPose, skeleton: skeleton, by: object))
        if case let .drawing(recipe) = object.kind {
            guard pose == nil, let weights = rig.points, let bent = RigPoses.bend(recipe, weights: weights, bind: bind, pose: posedModel) else { return nil }
            var shaped = object
            shaped.kind = .drawing(bent)
            return SceneExport.localMesh(of: shaped, look: look).map {
                [GLTFScene.LocalPart(name: object.name, mesh: $0, material: SceneExport.material(of: object, look: look))]
            }
        }
        guard let name = rig.skin, let weights = file(name).flatMap({ try? SkinWeights(data: $0) }) else { return nil }
        if object.kind.assetID != nil {
            let pieces = localParts(object, look: look, catalog: catalog, models: models)
            guard pieces.reduce(0, { $0 + $1.mesh.positions.count }) == weights.count else { return nil }
            var start = 0
            return pieces.map { piece in
                let range = start ..< start + piece.mesh.positions.count
                start = range.upperBound
                let slice = SkinWeights(joints: Array(weights.joints[range]), weights: Array(weights.weights[range]))
                return GLTFScene.LocalPart(name: piece.name, mesh: Skinning.deform(piece.mesh, weights: slice, bind: bind, pose: posedModel),
                                           material: piece.material)
            }
        }
        guard let source = PaintSource.mesh(of: object), source.positions.count == weights.count else { return nil }
        var mesh = Skinning.deform(source, weights: weights, bind: bind, pose: posedModel)
        if let factor = PaintSource.toObjectSpace(of: object) {
            mesh.positions = mesh.positions.map { $0 * factor }
            mesh.normals = mesh.normals.map { simd_normalize($0 / factor) }
        }
        return [GLTFScene.LocalPart(name: object.name, mesh: mesh, material: SceneExport.material(of: object, look: look))]
    }

    /// A rigged solid as a skin for glTF (game engines play its bones): its surface at rest with its weights, a placed
    /// model's parts each with their slice. Nil for drawings and painted objects, which leave posed.
    public static func skinned(_ object: SceneObject, look: Look, catalog: AssetCatalog, models: ModelLibrary = .shared,
                               file: (String) -> Data?) -> GLTFScene.SkinnedExport? {
        guard let rig = object.rig, object.paint == nil, let name = rig.skin,
              let weights = file(name).flatMap({ try? SkinWeights(data: $0) }) else { return nil }
        let pose = RigPoses.posed(rig.skeleton.restPose, skeleton: rig.skeleton, by: object)
        if object.kind.assetID != nil {
            let pieces = localParts(object, look: look, catalog: catalog, models: models)
            guard pieces.reduce(0, { $0 + $1.mesh.positions.count }) == weights.count else { return nil }
            var start = 0
            let slices = pieces.map { piece in
                let range = start ..< start + piece.mesh.positions.count
                start = range.upperBound
                return SkinWeights(joints: Array(weights.joints[range]), weights: Array(weights.weights[range]))
            }
            return GLTFScene.SkinnedExport(rig: rig, parts: pieces, weights: slices, pose: pose)
        }
        guard let source = PaintSource.mesh(of: object), source.positions.count == weights.count else { return nil }
        let factor = PaintSource.toObjectSpace(of: object).map { Vec3(Double($0.x), Double($0.y), Double($0.z)) } ?? .one
        let part = GLTFScene.LocalPart(name: object.name, mesh: source, material: SceneExport.material(of: object, look: look))
        return GLTFScene.SkinnedExport(rig: rig, parts: [part], weights: [weights], toObject: factor, pose: pose)
    }

    /// A painted object's paint mesh and texture (its shape from Core, or a placed model's parts as one).
    /// A rigged object's paint lies on its surface as `pose` bends it (see `posedParts`).
    public static func painted(_ object: SceneObject, look: Look, catalog: AssetCatalog, models: ModelLibrary = .shared,
                               file: (String) -> Data?, pose: [LoweyCore.Transform]? = nil, colors: PaintColorOutput = .texture) -> PaintedExport? {
        guard object.paint != nil else { return nil }
        // Paint is found on the unmoved surface; the strokes, cage and bend move its corners (as on the stage).
        var source = PaintSource.unshaped(of: object)
        var base = SceneExport.material(of: object, look: look).paintBase
        if source == nil, let id = object.kind.assetID, let asset = catalog.manifest.asset(id), let model = models.model(asset, catalog: catalog) {
            source = AssetPaint.mergedMesh(model)
            if object.color == nil { base.color = .white }
        }
        let shown = source.map { ShapeStack.moved($0, for: object) }
        var posed: MeshData? = ShapeStack.key(of: object) == nil ? nil : shown
        if let shown, let rig = object.rig, let name = rig.skin, let weights = file(name).flatMap({ try? SkinWeights(data: $0) }),
           weights.count == shown.positions.count {
            let skeleton = rig.skeleton
            let model = skeleton.modelSpace(RigPoses.posed(pose ?? skeleton.restPose, skeleton: skeleton, by: object))
            posed = Skinning.deform(shown, weights: weights, bind: skeleton.modelRest, pose: model)
        }
        return PaintExport.painted(object, source: source, base: base, file: file, posed: posed, colors: colors, encode: PaintPixels.png)
    }

    /// A library model's or a prefab's pieces in the object's own space (the glTF scene keeps them under their node).
    public static func localParts(_ object: SceneObject, look: Look, catalog: AssetCatalog, models: ModelLibrary = .shared) -> [GLTFScene.LocalPart] {
        if let prefabID = object.kind.prefabID, let prefab = catalog.manifest.prefab(prefabID) {
            // A prefab instance: its fragment as a little scene, baked into the instance's space.
            let fragment = CoreScene(id: SceneID(raw: "prefab"), name: prefab.name,
                                     objects: Dictionary(uniqueKeysWithValues: prefab.fragment.objects.map { ($0.id, $0) }),
                                     roots: prefab.fragment.roots)
            return meshes(nil, scene: fragment, look: look, catalog: catalog, models: models).map { part in
                GLTFScene.LocalPart(name: part.name, mesh: part.mesh.transformed(part.transform),
                                    material: ExportMaterial(color: part.color, emissive: part.emissive, emissiveStrength: part.emissiveStrength,
                                                             roughness: part.roughness, metallic: part.metallic))
            }
        }
        guard let assetID = object.kind.assetID, let asset = catalog.manifest.asset(assetID),
              let model = models.model(asset, catalog: catalog) else { return [] }
        let tint = object.color?.resolved(in: look.palette)
        // A cage or a bend moves every unskinned part, measured over the whole model (as the stage draws it).
        let bounds = model.bounds
        return model.parts.map { part in
            var mesh = part.mesh
            if !part.isSkinned { mesh.positions = ShapeStack.movedPositions(mesh.positions, for: object, bounds: bounds, strokes: false) }
            mesh.computeSmoothNormals()
            let material = model.materials.indices.contains(part.material) ? model.materials[part.material] : ImportedMaterial()
            return GLTFScene.LocalPart(name: part.name, mesh: mesh,
                                       material: ExportMaterial(color: tint ?? material.baseColor, emissive: nil, emissiveStrength: 0,
                                                                roughness: material.roughness, metallic: material.metallic))
        }
    }

    /// The files of one export, named after `name`: one file, or an OBJ with its materials.
    /// `paintFile` reads the project's paint files: painted objects carry their texture (glTF, Blender, USDZ, OBJ).
    /// Rigged objects leave as they're posed: `poses` are the animator's (the scene as shown); without them, the joints as
    /// turned by hand.
    public static func files(_ format: ModelExportFormat, ids: [ObjectID]?, scene: CoreScene, look: Look, preset: LookPreset,
                             catalog: AssetCatalog, models: ModelLibrary = .shared, name: String,
                             paintFile: @escaping (String) -> Data? = { _ in nil },
                             poses: [ObjectID: [LoweyCore.Transform]] = [:], colors: PaintColorOutput = .texture,
                             engine: GameEngine? = nil) -> [(name: String, data: Data)] {
        let parts: (SceneObject) -> [GLTFScene.LocalPart] = { localParts($0, look: look, catalog: catalog, models: models) }
        let paintOf: (SceneObject) -> PaintedExport? = {
            Self.painted($0, look: look, catalog: catalog, models: models, file: paintFile, pose: poses[$0.id], colors: colors)
        }
        let posed: (SceneObject) -> [GLTFScene.LocalPart]? = {
            posedParts($0, pose: poses[$0.id], look: look, catalog: catalog, models: models, file: paintFile)
        }
        let skinnedOf: (SceneObject) -> GLTFScene.SkinnedExport? = {
            skinned($0, look: look, catalog: catalog, models: models, file: paintFile)
        }
        switch format {
        case .glb:
            return [("\(name).glb", GLTFScene.glb(ids, in: scene, look: look, parts: parts, painted: paintOf, posed: posed, skinned: skinnedOf))]
        case .web:
            let glb = GLTFScene.glb(ids, in: scene, look: look, parts: parts, painted: paintOf, posed: posed, skinned: skinnedOf,
                                    clearcoat: preset.shading.reflection ?? 0)
            return webFolder(glb, scene: scene, look: look, preset: preset, name: name)
        case .fbx:
            // One rigged thing: the first the export holds.
            let candidates = (ids ?? scene.roots).flatMap { scene.subtree(of: $0) }
            guard let object = candidates.compactMap({ scene.objects[$0] }).first(where: { skinnedOf($0) != nil }),
                  let skin = skinnedOf(object) else { return [] }
            let tracks = scene.timeline.tracks.filter { $0.target == object.id }
            // FBX ▸ for Unity / for Unreal: the joints and their keys named for the engine's retargeting.
            let (named, keys) = engine.map { ExportPrep.renamed(skin, tracks: tracks, for: $0) } ?? (skin, tracks)
            return [("\(name).fbx", FBXSkin.file(named, name: object.name, tracks: keys, fps: scene.timeline.fps))]
        case .blender:
            let selected = ids.map { scene.restricted(to: $0) } ?? scene
            return [("\(name) for Blender.zip", BlenderPackage.archive(selected, look: look, preset: preset, parts: parts, painted: paintOf,
                                                                       posed: posed))]
        case .textures:
            // Each painted thing's maps, named after it (the colour as a texture: a PNG set is pictures).
            let colourOf: (SceneObject) -> PaintedExport? = {
                Self.painted($0, look: look, catalog: catalog, models: models, file: paintFile, pose: poses[$0.id])
            }
            let objects = (ids ?? scene.roots).flatMap { scene.subtree(of: $0) }.compactMap { scene.objects[$0] }
            return objects.flatMap { object in colourOf(object).map { PaintExport.pngSet($0, name: Self.fileName(object.name)) } ?? [] }
                .map { (name: $0.0, data: $0.1) }
        default:
            break
        }
        let carriesColour = format == .usdz || format == .obj
        let meshes = meshes(ids, scene: scene, look: look, catalog: catalog, models: models, painted: carriesColour ? paintOf : { _ in nil },
                            posed: posed)
        guard !meshes.isEmpty else { return [] }
        switch format {
        case .usdz: return [("\(name).usdz", SceneExport.usdz(meshes))]
        case .stl: return [("\(name).stl", STLFile.binary(meshes, name: name))]
        case .threeMF: return [("\(name).3mf", ThreeMFFile.data(meshes))]
        case .obj:
            let (obj, mtl) = OBJFile.text(meshes, materialFile: "\(name).mtl")
            return [("\(name).obj", Data(obj.utf8)), ("\(name).mtl", Data(mtl.utf8))] + OBJFile.textures(meshes)
        case .glb, .web, .blender, .fbx, .textures: return []
        }
    }

    /// A thing's name as a file name (letters, numbers, spaces, dashes).
    static func fileName(_ name: String) -> String {
        let kept = String(name.map { $0.isLetter || $0.isNumber || $0 == " " || $0 == "-" ? $0 : "_" }).trimmingCharacters(in: .whitespaces)
        return kept.isEmpty ? "Painted" : kept
    }
}

extension CoreScene {
    /// The scene with only these objects (and what's under them) at the top, placed where they are in the world.
    func restricted(to ids: [ObjectID]) -> CoreScene {
        var copy = self
        var keep = Set<ObjectID>()
        for id in ids {
            keep.formUnion(subtree(of: id))
        }
        copy.objects = objects.filter { keep.contains($0.key) || $0.value.kind == .camera }
        let tops = ids.filter { id in objects[id]?.parent.map { !keep.contains($0) } ?? true }
        for id in tops {
            copy.objects[id]?.parent = nil
            copy.objects[id]?.transform = worldTransform(of: id)
        }
        let cameras = copy.objects.values.filter { $0.kind == .camera && !keep.contains($0.id) }.map(\.id)
        for id in cameras {
            copy.objects[id]?.parent = nil
            copy.objects[id]?.transform = worldTransform(of: id)
            copy.objects[id]?.children = []
        }
        copy.roots = tops + cameras.sorted { $0.raw < $1.raw }
        return copy
    }
}
