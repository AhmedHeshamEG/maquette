import Foundation

/// glTF of a scene as it's built: one node per object with its own transform under its parent, a material per
/// surface, cameras and lights (KHR_lights_punctual), and the timeline's moves as animation. What other apps (Blender,
/// game engines, Maquette itself) need to carry on with the work, not a frozen picture of it.
public enum GLTFScene {
    /// A piece of a library model or prefab, in its object's own space.
    public struct LocalPart: Hashable, Sendable {
        public var name: String
        public var mesh: MeshData
        public var material: ExportMaterial
        /// A colour per vertex (sRGB), written as `COLOR_0` (a painted sculpt).
        public var colors: [SIMD4<Float>]
        /// Tangents for a normal map (`TANGENT`).
        public var tangents: [SIMD4<Float>]?

        public init(name: String, mesh: MeshData, material: ExportMaterial, colors: [SIMD4<Float>] = [], tangents: [SIMD4<Float>]? = nil) {
            self.name = name
            self.mesh = mesh
            self.material = material
            self.colors = colors
            self.tangents = tangents
        }
    }

    /// A GLB of the objects (and everything under them; the whole scene when nil). `parts` supplies the shapes Core
    /// can't make itself (library models, prefabs), in the object's own space.
    /// `painted` gives a painted object's paint mesh and texture.
    /// `posed` gives a rigged object's surface as its skeleton bends it; `skinned` gives it as a skin with its bones
    /// instead (game engines play those), and wins when both answer. `clearcoat` is the Look's lacquer on every surface.
    public static func glb(_ ids: [ObjectID]?, in scene: Scene, look: Look, parts: @escaping (SceneObject) -> [LocalPart] = { _ in [] },
                           painted: @escaping (SceneObject) -> PaintedExport? = { _ in nil },
                           posed: @escaping (SceneObject) -> [LocalPart]? = { _ in nil },
                           skinned: @escaping (SceneObject) -> SkinnedExport? = { _ in nil }, clearcoat: Double = 0,
                           generator: String = "Maquette") -> Data {
        var writer = GLTFSceneWriter(scene: scene, look: look, parts: parts)
        writer.clearcoat = clearcoat
        writer.painted = painted
        writer.posed = posed
        writer.skinned = skinned
        for root in ids ?? scene.roots {
            if let node = writer.addNode(root, isRoot: true) { writer.roots.append(node) }
        }
        writer.addAnimation()
        return writer.finish(generator: generator)
    }
}

/// Builds the buffer and the JSON of a scene GLB.
struct GLTFSceneWriter {
    static let arrayBuffer = 34962, elementBuffer = 34963, float = 5126, unsignedInt = 5125

    let scene: Scene
    let look: Look
    let parts: (SceneObject) -> [GLTFScene.LocalPart]
    var painted: (SceneObject) -> PaintedExport? = { _ in nil }
    var posed: (SceneObject) -> [GLTFScene.LocalPart]? = { _ in nil }
    var skinned: (SceneObject) -> GLTFScene.SkinnedExport? = { _ in nil }
    var skins: [[String: Any]] = []
    /// Each skinned object's joint nodes by joint name (where its `bone.` keys go).
    var jointNodes: [ObjectID: [String: Int]] = [:]
    var binary = Data()
    var bufferViews: [[String: Any]] = []
    var accessors: [[String: Any]] = []
    var meshes: [[String: Any]] = []
    var materials: [[String: Any]] = []
    var images: [[String: Any]] = []
    var textures: [[String: Any]] = []
    var nodes: [[String: Any]] = []
    var cameras: [[String: Any]] = []
    var lights: [[String: Any]] = []
    var roots: [Int] = []
    /// Collision shapes of real things (`OMI_physics_shape`), by index.
    var physicsShapes: [[String: Any]] = []
    /// Node index of each exported object, and the transform above it when its parent isn't exported.
    var nodeOf: [ObjectID: Int] = [:]
    var rootFrames: [ObjectID: Transform] = [:]
    /// What keyed properties point at (`KHR_animation_pointer`): each object's materials, camera and light.
    var materialsOf: [ObjectID: [Int]] = [:]
    var cameraOf: [ObjectID: Int] = [:]
    var lightOf: [ObjectID: Int] = [:]
    /// The properties each object has keys for.
    let animated: [ObjectID: Set<PropertyKey>]
    /// The Look's lacquer (Clean product's reflection) as every surface's clearcoat; 0 is none.
    var clearcoat = 0.0
    var extensionsUsed: Set<String> = []

    init(scene: Scene, look: Look, parts: @escaping (SceneObject) -> [GLTFScene.LocalPart]) {
        self.scene = scene
        self.look = look
        self.parts = parts
        animated = Dictionary(grouping: scene.timeline.tracks, by: \.target).mapValues { Set($0.map(\.property)) }
    }

    // MARK: Nodes

    mutating func addNode(_ id: ObjectID, isRoot: Bool) -> Int? {
        guard nodeOf[id] == nil, let object = scene.objects[id], scene.isEffectivelyVisible(id), Self.exports(object.kind) else { return nil }
        var transform = object.transform
        if isRoot, let parent = object.parent {
            let frame = scene.worldTransform(of: parent)
            rootFrames[id] = frame
            transform = frame * transform
        }
        var node: [String: Any] = [
            "name": object.name.isEmpty ? object.kind.typeName : object.name,
            "translation": [transform.position.x, transform.position.y, transform.position.z],
            "rotation": [transform.rotation.x, transform.rotation.y, transform.rotation.z, transform.rotation.w],
            "scale": [transform.scale.x, transform.scale.y, transform.scale.z]
        ]
        var extras: [String: Any] = ["id": id.raw, "kind": object.kind.typeName]
        let skin = skinned(object)
        if skin == nil, let mesh = addMesh(for: object) {
            node["mesh"] = mesh
            addCollider(for: id, mesh: mesh, to: &node)
        }
        addBody(object, to: &node)
        switch object.kind {
        case .camera:
            node["camera"] = addCamera(object)
            cameraOf[id] = cameras.count - 1
            extras["fieldOfView"] = object[.fieldOfView]?.floatValue ?? 50
        case let .light(type):
            let light = addLight(object, type: type)
            lightOf[id] = light
            node["extensions"] = ["KHR_lights_punctual": ["light": light]]
            extras["intensity"] = object[.lightIntensity]?.floatValue ?? 1
            extras["shadows"] = object[.lightShadows]?.boolValue ?? (type == .directional)
            if type == .area { extras["panel"] = [object[.lightWidth]?.floatValue ?? 1, object[.lightHeight]?.floatValue ?? 0.6] }
        default:
            break
        }
        node["extras"] = ["maquette": extras]
        let index = nodes.count
        nodes.append(node)
        nodeOf[id] = index
        let rig = skin.flatMap { addSkin($0, name: object.name.isEmpty ? object.kind.typeName : object.name, id: id) }
        let children = (rig.map { [$0] } ?? []) + object.children.compactMap { addNode($0, isRoot: false) }
        if !children.isEmpty { nodes[index]["children"] = children }
        return index
    }

    /// Construction lines, kept measurements, marks on the frame and effects stay in Maquette.
    static func exports(_ kind: ObjectKind) -> Bool {
        switch kind {
        case .overlay, .particles, .sketch, .dimension, .force, .fluid: false
        default: true
        }
    }

    mutating func addMesh(for object: SceneObject) -> Int? {
        var pieces: [GLTFScene.LocalPart] = []
        if let paint = painted(object) {
            var material = SceneExport.material(of: object, look: look).painted(paint.texture, maps: paint.maps)
            // Vertex colours carry the colour on their own (glTF multiplies them by the texture).
            if !paint.vertexColors.isEmpty { material.texture = nil }
            pieces = [GLTFScene.LocalPart(name: object.name, mesh: paint.mesh, material: material, colors: paint.vertexColors, tangents: paint.tangents)]
        } else if let bent = posed(object) {
            pieces = bent
        } else if let mesh = SceneExport.localMesh(of: object, look: look), !mesh.isEmpty {
            pieces = [GLTFScene.LocalPart(name: object.name, mesh: mesh, material: SceneExport.material(of: object, look: look))]
        } else if object.kind.hasSurface {
            pieces = parts(object).filter { !$0.mesh.isEmpty }
        }
        guard !pieces.isEmpty else { return nil }
        if let fur = FurSettings(object), let surface = pieces.first?.mesh {
            pieces += Self.furParts(fur, on: surface, name: object.name, material: SceneExport.material(of: object, look: look))
        }
        let keyed = animated[object.id] ?? []
        let primitives = pieces.map { piece -> [String: Any] in
            let material = addMaterial(piece, animated: keyed)
            materialsOf[object.id, default: []].append(material)
            return ["attributes": attributes(piece.mesh, colors: piece.colors, tangents: piece.tangents), "indices": indices(piece.mesh),
                    "material": material]
        }
        meshes.append(["name": object.name, "primitives": primitives])
        return meshes.count - 1
    }

    mutating func attributes(_ mesh: MeshData, colors: [SIMD4<Float>] = [], tangents: [SIMD4<Float>]? = nil) -> [String: Int] {
        let bounds = mesh.bounds ?? Bounds(min: .zero, max: .zero)
        var result = ["POSITION": addAccessor(Self.floats(mesh.positions.flatMap { [$0.x, $0.y, $0.z] }), target: Self.arrayBuffer,
                                              count: mesh.positions.count, type: "VEC3",
                                              extra: ["min": [bounds.min.x, bounds.min.y, bounds.min.z], "max": [bounds.max.x, bounds.max.y, bounds.max.z]])]
        if mesh.normals.count == mesh.positions.count {
            let normals = mesh.normals.flatMap { n -> [Float] in
                let length = (n.x * n.x + n.y * n.y + n.z * n.z).squareRoot()
                return length > 0 ? [n.x / length, n.y / length, n.z / length] : [0, 1, 0]
            }
            result["NORMAL"] = addAccessor(Self.floats(normals), target: Self.arrayBuffer, count: mesh.normals.count, type: "VEC3")
        }
        if mesh.uvs.count == mesh.positions.count {
            result["TEXCOORD_0"] = addAccessor(Self.floats(mesh.uvs.flatMap { [$0.x, $0.y] }), target: Self.arrayBuffer, count: mesh.uvs.count,
                                               type: "VEC2")
        }
        if colors.count == mesh.positions.count {
            // glTF keeps colours as linear light.
            let linear = colors.flatMap { color -> [Float] in
                [Float(ColorSpace.linear(fromSRGB: Double(color.x))), Float(ColorSpace.linear(fromSRGB: Double(color.y))),
                 Float(ColorSpace.linear(fromSRGB: Double(color.z))), color.w]
            }
            result["COLOR_0"] = addAccessor(Self.floats(linear), target: Self.arrayBuffer, count: colors.count, type: "VEC4")
        }
        if let tangents, tangents.count == mesh.positions.count {
            result["TANGENT"] = addAccessor(Self.floats(tangents.flatMap { [$0.x, $0.y, $0.z, $0.w] }), target: Self.arrayBuffer,
                                            count: tangents.count, type: "VEC4")
        }
        return result
    }

    mutating func indices(_ mesh: MeshData) -> Int {
        var data = Data(capacity: mesh.indices.count * 4)
        for value in mesh.indices {
            withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
        }
        return addAccessor(data, target: Self.elementBuffer, componentType: Self.unsignedInt, count: mesh.indices.count, type: "SCALAR")
    }

    mutating func addMaterial(_ piece: GLTFScene.LocalPart, animated: Set<PropertyKey> = []) -> Int {
        let linear = SceneExport.linear
        let surface = piece.material
        var material: [String: Any] = [
            "name": "\(piece.name) material",
            "pbrMetallicRoughness": [
                "baseColorFactor": [linear(surface.color.r), linear(surface.color.g), linear(surface.color.b), surface.color.a],
                "metallicFactor": surface.metallic, "roughnessFactor": surface.roughness
            ]
        ]
        if surface.color.a < 1 { material["alphaMode"] = "BLEND" }
        var pbr = material["pbrMetallicRoughness"] as? [String: Any] ?? [:]
        if let texture = surface.texture { pbr["baseColorTexture"] = ["index": addTexture(texture)] }
        if let cutout = surface.cutout {
            pbr["baseColorTexture"] = ["index": addTexture(cutout)]
            material["alphaMode"] = "MASK"
            material["alphaCutoff"] = 0.5
            material["doubleSided"] = true
        }
        if let packed = surface.maps.metallicRoughness {
            // The texture holds the values; the factors multiply it.
            pbr["metallicRoughnessTexture"] = ["index": addTexture(packed)]
            pbr["metallicFactor"] = 1.0
            pbr["roughnessFactor"] = 1.0
        }
        material["pbrMetallicRoughness"] = pbr
        if let emissive = surface.emissive, surface.emissiveStrength > 0 || animated.contains(.emissiveIntensity) {
            addGlow(emissive, strength: surface.emissiveStrength, keyed: animated.contains(.emissiveIntensity), to: &material)
        }
        if let glow = surface.maps.emissive {
            material["emissiveTexture"] = ["index": addTexture(glow)]
            material["emissiveFactor"] = [1.0, 1.0, 1.0]
        }
        if let normal = surface.maps.normal { material["normalTexture"] = ["index": addTexture(normal)] }
        if clearcoat > 0 {
            var extensions = material["extensions"] as? [String: Any] ?? [:]
            extensions["KHR_materials_clearcoat"] = ["clearcoatFactor": clearcoat, "clearcoatRoughnessFactor": 0.05]
            material["extensions"] = extensions
            extensionsUsed.insert("KHR_materials_clearcoat")
        }
        materials.append(material)
        return materials.count - 1
    }

    /// A PNG in the buffer as an image, with a repeating linear sampler.
    mutating func addTexture(_ png: Data) -> Int {
        while binary.count % 4 != 0 {
            binary.append(0)
        }
        bufferViews.append(["buffer": 0, "byteOffset": binary.count, "byteLength": png.count])
        binary.append(png)
        images.append(["bufferView": bufferViews.count - 1, "mimeType": "image/png"])
        textures.append(["source": images.count - 1, "sampler": 0])
        return textures.count - 1
    }

    mutating func addCamera(_ object: SceneObject) -> Int {
        let fieldOfView = (object[.fieldOfView]?.floatValue ?? 50) * .pi / 180
        cameras.append(["type": "perspective", "name": object.name,
                        "perspective": ["yfov": fieldOfView, "znear": 0.01, "zfar": 1000, "aspectRatio": 16.0 / 9.0]])
        return cameras.count - 1
    }

    // MARK: Animation

    /// The timeline's moves (position, rotation, size) of exported objects. Linear and held keys go as they are;
    /// eased ones are sampled at the timeline's frame rate so the motion is the same everywhere.
    mutating func addAnimation() {
        var samplers: [[String: Any]] = []
        var channels: [[String: Any]] = []
        let fps = Double(max(scene.timeline.fps, 1))
        for track in scene.timeline.tracks {
            // A joint's turn goes to its joint node; anything else the object's own node knows how to play.
            let joint = jointNode(for: track)
            guard let node = joint ?? nodeOf[track.target], !track.keyframes.isEmpty else { continue }
            guard let path = joint == nil ? Self.path(track.property) : "rotation" else {
                // A material, light or lens number points at its place; anything else rides along for Maquette.
                if !addPointer(track, samplers: &samplers, channels: &channels) { keptTracks.append(track) }
                continue
            }
            let (times, interpolation) = Self.times(track, fps: fps)
            var values: [Float] = []
            var previous: Quat?
            for time in times {
                guard let value = track.value(at: time, palette: look.palette) else { continue }
                values += componentValues(value, path: path, root: joint == nil ? rootFrames[track.target] : nil, previous: &previous)
            }
            let width = path == "rotation" ? 4 : 3
            guard values.count == times.count * width else { continue }
            let input = addAccessor(Self.floats(times.map(Float.init)), target: nil, count: times.count, type: "SCALAR",
                                    extra: ["min": [times.first ?? 0], "max": [times.last ?? 0]])
            let output = addAccessor(Self.floats(values), target: nil, count: times.count, type: width == 4 ? "VEC4" : "VEC3")
            samplers.append(["input": input, "output": output, "interpolation": interpolation])
            channels.append(["sampler": samplers.count - 1, "target": ["node": node, "path": path]])
        }
        guard !channels.isEmpty else { return }
        animations = [["name": scene.name.isEmpty ? "Timeline" : scene.name, "samplers": samplers, "channels": channels]]
    }

    var animations: [[String: Any]] = []
    /// Keys glTF has no place for (face states, a reveal, a stepping): kept in the file's extras for Maquette.
    var keptTracks: [Track] = []

    static func path(_ property: PropertyKey) -> String? {
        switch property {
        case .position: "translation"
        case .rotation: "rotation"
        case .scale: "scale"
        default: nil
        }
    }

    /// Key times when every segment is linear (or every one holds), else every frame between the first and last key
    /// plus the keys themselves.
    static func times(_ track: Track, fps: Double) -> ([Double], String) {
        let keys = track.keyframes
        // Repeats played out frame by frame (a loop that runs forever is its one stretch: players loop it).
        if let finish = track.cycle?.finish, let first = keys.first?.time, finish > (keys.last?.time ?? 0) {
            let frames = Int(((finish - first) * fps).rounded(.up))
            return ((0 ... frames).map { min(first + Double($0) / fps, finish) }, "LINEAR")
        }
        let segments = keys.dropLast()
        if segments.allSatisfy({ $0.easing == .linear }) { return (keys.map(\.time), "LINEAR") }
        if segments.allSatisfy({ $0.easing == .step }) { return (keys.map(\.time), "STEP") }
        guard let first = keys.first?.time, let last = keys.last?.time else { return ([], "LINEAR") }
        var times = Set(keys.map(\.time))
        var frame = (first * fps).rounded(.up)
        while frame / fps < last {
            times.insert(frame / fps)
            frame += 1
        }
        return (times.sorted(), "LINEAR")
    }

    func componentValues(_ value: PropertyValue, path: String, root frame: Transform?, previous: inout Quat?) -> [Float] {
        switch (path, value) {
        case let ("translation", .vec3(position)):
            let placed = frame.map { $0.apply(to: position) } ?? position
            return [Float(placed.x), Float(placed.y), Float(placed.z)]
        case let ("scale", .vec3(scale)):
            let placed = frame.map { $0.scale.scaled(by: scale) } ?? scale
            return [Float(placed.x), Float(placed.y), Float(placed.z)]
        case let ("rotation", .quat(rotation)):
            var turned = frame.map { ($0.rotation * rotation).normalized } ?? rotation.normalized
            // Keep each quaternion on the same side as the one before, so players take the short way round.
            if let before = previous, before.dot(turned) < 0 { turned = Quat(x: -turned.x, y: -turned.y, z: -turned.z, w: -turned.w) }
            previous = turned
            return [Float(turned.x), Float(turned.y), Float(turned.z), Float(turned.w)]
        default:
            return []
        }
    }

    // MARK: Buffer

    static func floats(_ values: [Float]) -> Data {
        var data = Data(capacity: values.count * 4)
        for value in values {
            withUnsafeBytes(of: value.bitPattern.littleEndian) { data.append(contentsOf: $0) }
        }
        return data
    }

    mutating func addAccessor(_ data: Data, target: Int?, componentType: Int = Self.float, count: Int, type: String,
                              extra: [String: Any] = [:]) -> Int {
        while binary.count % 4 != 0 {
            binary.append(0)
        }
        var view: [String: Any] = ["buffer": 0, "byteOffset": binary.count, "byteLength": data.count]
        if let target { view["target"] = target }
        bufferViews.append(view)
        binary.append(data)
        var accessor: [String: Any] = ["bufferView": bufferViews.count - 1, "componentType": componentType, "count": count, "type": type]
        accessor.merge(extra) { _, new in new }
        accessors.append(accessor)
        return accessors.count - 1
    }

    mutating func finish(generator: String) -> Data {
        while binary.count % 4 != 0 {
            binary.append(0)
        }
        var json: [String: Any] = [
            "asset": ["version": "2.0", "generator": generator],
            "scene": 0,
            "scenes": [["name": scene.name, "nodes": roots]],
            "nodes": nodes, "accessors": accessors, "bufferViews": bufferViews,
            "buffers": [["byteLength": binary.count]]
        ]
        if !meshes.isEmpty { json["meshes"] = meshes }
        if !materials.isEmpty { json["materials"] = materials }
        if !textures.isEmpty {
            json["images"] = images
            json["textures"] = textures
            // Linear filtering with mipmaps, repeating (the paint's charts sit inside 0…1 with padding).
            json["samplers"] = [["magFilter": 9729, "minFilter": 9987, "wrapS": 10497, "wrapT": 10497]]
        }
        if !cameras.isEmpty { json["cameras"] = cameras }
        if !animations.isEmpty { json["animations"] = animations }
        if !skins.isEmpty { json["skins"] = skins }
        var extensions: [String: Any] = [:]
        var used: [String] = []
        if !lights.isEmpty {
            extensions["KHR_lights_punctual"] = ["lights": lights]
            used.append("KHR_lights_punctual")
        }
        if !physicsShapes.isEmpty {
            extensions["OMI_physics_shape"] = ["shapes": physicsShapes]
            used += ["OMI_physics_body", "OMI_physics_shape"]
        }
        used += extensionsUsed.sorted()
        if !extensions.isEmpty { json["extensions"] = extensions }
        if !used.isEmpty { json["extensionsUsed"] = used }
        if let kept = keptTracksJSON() { json["extras"] = ["maquette": ["tracks": kept]] }
        return GLBContainer.pack(json: json, binary: binary)
    }
}

/// The GLB container: a header, the JSON chunk (space-padded) and the binary chunk (zero-padded).
enum GLBContainer {
    static func pack(json: [String: Any], binary: Data) -> Data {
        var jsonData = (try? JSONSerialization.data(withJSONObject: json, options: [.sortedKeys])) ?? Data("{}".utf8)
        while jsonData.count % 4 != 0 {
            jsonData.append(0x20)
        }
        var result = Data()
        func u32(_ value: Int) {
            withUnsafeBytes(of: UInt32(value).littleEndian) { result.append(contentsOf: $0) }
        }
        result.append(Data("glTF".utf8))
        u32(2)
        u32(12 + 8 + jsonData.count + (binary.isEmpty ? 0 : 8 + binary.count))
        u32(jsonData.count)
        result.append(Data("JSON".utf8))
        result.append(jsonData)
        if !binary.isEmpty {
            u32(binary.count)
            result.append(contentsOf: [0x42, 0x49, 0x4E, 0x00])
            result.append(binary)
        }
        return result
    }
}
