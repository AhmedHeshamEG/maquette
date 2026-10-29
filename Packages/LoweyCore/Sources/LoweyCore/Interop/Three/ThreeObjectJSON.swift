import Foundation

/// three.js's own scene format (X1): what `scene.toJSON()` writes and `ObjectLoader` reads (format 4.6), made from the
/// GLB written for the web so both say the same thing with the same names. Meshes, groups, bones and skinned meshes,
/// materials (standard, or physical with a clearcoat) and their pictures, cameras, lights with their targets, and every
/// clip, the material, light and lens keys included as tracks three.js plays on its own.
public enum ThreeObjectJSON {
    /// `scene.json` from a GLB (best written through `ThreeNames.prepared`).
    public static func data(fromGLB glb: Data) throws -> Data {
        var builder = try ThreeJSONBuilder(glb: glb)
        let json = builder.build()
        return try JSONSerialization.data(withJSONObject: json, options: [.sortedKeys])
    }
}

/// Builds the JSON; one pass over the glTF nodes, then the clips once every object has its name.
struct ThreeJSONBuilder {
    let file: GLTFReader.File
    var geometries: [[String: Any]] = []
    var materials: [[String: Any]] = []
    var textures: [[String: Any]] = []
    var images: [[String: Any]] = []
    var skeletons: [[String: Any]] = []
    /// Material UUIDs by glTF material and whether its geometry has vertex colours (three.js needs one of each).
    var materialUUID: [String: String] = [:]
    var textureUUID: [String: String] = [:]
    /// What keyed numbers land on: the three.js names of the meshes using each material, of each light and camera.
    var meshNamesOfMaterial: [Int: [String]] = [:]
    var namesOfLight: [Int: [String]] = [:]
    var namesOfCamera: [Int: [String]] = [:]
    /// Materials whose see-through is keyed (they're drawn transparent).
    var fadingMaterials: Set<Int> = []
    /// Each node's world matrix (column-major) for a skinned mesh's bind matrix.
    var worldMatrix: [Int: [Double]] = [:]

    init(glb: Data) throws {
        file = try GLTFReader.parse(glb, baseURL: nil)
        fadingMaterials = Set(pointerTargets().compactMap { pointer -> Int? in
            guard case let .material(index, path)? = GLTFSceneReader.Builder.place(pointer), path.hasSuffix("baseColorFactor") else { return nil }
            return index
        })
    }

    mutating func build() -> [String: Any] {
        let scenes = file.array("scenes")
        let sceneIndex = file.json["scene"] as? Int ?? 0
        let roots = sceneIndex < scenes.count ? scenes[sceneIndex]["nodes"] as? [Int] ?? [] : Array(file.array("nodes").indices)
        let name = sceneIndex < scenes.count ? scenes[sceneIndex]["name"] as? String ?? "Scene" : "Scene"
        let children = roots.map { object(for: $0, parentWorld: ThreeMatrix.identity) }
        var json: [String: Any] = [
            "metadata": ["version": 4.6, "type": "Object", "generator": "Maquette"],
            "object": ["uuid": "maquette-scene", "type": "Scene", "name": name, "layers": 1, "children": children,
                       "matrix": ThreeMatrix.identity, "up": [0, 1, 0]] as [String: Any],
            "geometries": geometries, "materials": materials
        ]
        if !textures.isEmpty {
            json["textures"] = textures
            json["images"] = images
        }
        if !skeletons.isEmpty { json["skeletons"] = skeletons }
        let clips = animations()
        if !clips.isEmpty {
            json["animations"] = clips
            // `ObjectLoader` gives the scene the clips it lists.
            var root = json["object"] as? [String: Any] ?? [:]
            root["animations"] = clips.compactMap { $0["uuid"] }
            json["object"] = root
        }
        return json
    }

    // MARK: Objects

    static func nodeUUID(_ index: Int) -> String { "maquette-node-\(index)" }

    func nodeName(_ index: Int) -> String {
        let nodes = file.array("nodes")
        return index < nodes.count ? nodes[index]["name"] as? String ?? "node_\(index)" : "node_\(index)"
    }

    mutating func object(for index: Int, parentWorld: [Double]) -> [String: Any] {
        let node = file.array("nodes")[index]
        let local = ThreeMatrix.local(node)
        let world = ThreeMatrix.multiply(parentWorld, local)
        worldMatrix[index] = world
        let name = nodeName(index)
        var object: [String: Any] = ["uuid": Self.nodeUUID(index), "name": name, "type": isJoint(index) ? "Bone" : "Object3D",
                                     "matrix": local, "layers": 1, "up": [0, 1, 0]]
        if let extras = node["extras"] as? [String: Any] { object["userData"] = extras }
        var children: [[String: Any]] = []
        if let camera = node["camera"] as? Int {
            writeCamera(camera, into: &object)
            namesOfCamera[camera, default: []].append(name)
        } else if let light = lightIndex(node) {
            if let target = writeLight(light, into: &object) { children.append(target) }
            namesOfLight[light, default: []].append(name)
        } else if let mesh = node["mesh"] as? Int {
            children += meshObjects(mesh, node: node, index: index, into: &object)
        }
        children += (node["children"] as? [Int] ?? []).map { self.object(for: $0, parentWorld: world) }
        if !children.isEmpty { object["children"] = children }
        return object
    }

    func isJoint(_ index: Int) -> Bool {
        file.array("skins").contains { ($0["joints"] as? [Int] ?? []).contains(index) }
    }

    func lightIndex(_ node: [String: Any]) -> Int? {
        ((node["extensions"] as? [String: Any])?["KHR_lights_punctual"] as? [String: Any])?["light"] as? Int
    }

    func writeCamera(_ index: Int, into object: inout [String: Any]) {
        let cameras = file.array("cameras")
        let perspective = index < cameras.count ? cameras[index]["perspective"] as? [String: Any] ?? [:] : [:]
        object["type"] = "PerspectiveCamera"
        object["fov"] = (perspective["yfov"] as? Double ?? 0.8) * 180 / .pi
        object["aspect"] = perspective["aspectRatio"] as? Double ?? 16.0 / 9.0
        object["near"] = perspective["znear"] as? Double ?? 0.01
        object["far"] = perspective["zfar"] as? Double ?? 1000
        object["zoom"] = 1
        object["focus"] = 10
        object["filmGauge"] = 35
        object["filmOffset"] = 0
    }

    /// A light; a directional or spot light gets its target a metre down its −Z, as `GLTFLoader` does.
    func writeLight(_ index: Int, into object: inout [String: Any]) -> [String: Any]? {
        let lights = ((file.json["extensions"] as? [String: Any])?["KHR_lights_punctual"] as? [String: Any])?["lights"] as? [[String: Any]] ?? []
        guard index < lights.count else { return nil }
        let light = lights[index]
        let colour = GLTFReader.numbers(light["color"]) ?? [1, 1, 1]
        object["color"] = ThreeMatrix.hex(colour)
        object["intensity"] = light["intensity"] as? Double ?? 1
        let range = light["range"] as? Double ?? 0
        switch light["type"] as? String {
        case "directional":
            object["type"] = "DirectionalLight"
        case "spot":
            let spot = light["spot"] as? [String: Any] ?? [:]
            let outer = spot["outerConeAngle"] as? Double ?? .pi / 4, inner = spot["innerConeAngle"] as? Double ?? 0
            object["type"] = "SpotLight"
            object["distance"] = range
            object["decay"] = 2
            object["angle"] = outer
            object["penumbra"] = outer > 0 ? 1 - inner / outer : 0
        default:
            object["type"] = "PointLight"
            object["distance"] = range
            object["decay"] = 2
        }
        guard object["type"] as? String != "PointLight" else { return nil }
        let target = "\(object["uuid"] as? String ?? "light")-target"
        object["target"] = target
        return ["uuid": target, "type": "Object3D", "name": "\(object["name"] as? String ?? "light")_target", "layers": 1,
                "matrix": ThreeMatrix.translation(0, 0, -1), "up": [0, 1, 0]]
    }

    // MARK: Pointers

    /// Every `KHR_animation_pointer` the file's clips point at.
    func pointerTargets() -> [String] {
        file.array("animations").flatMap { animation in
            (animation["channels"] as? [[String: Any]] ?? []).compactMap { channel in
                let target = channel["target"] as? [String: Any]
                return ((target?["extensions"] as? [String: Any])?["KHR_animation_pointer"] as? [String: Any])?["pointer"] as? String
            }
        }
    }
}

/// Column-major 4×4 matrices as three.js writes them.
enum ThreeMatrix {
    static let identity: [Double] = [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]

    static func translation(_ x: Double, _ y: Double, _ z: Double) -> [Double] {
        [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, x, y, z, 1]
    }

    /// A node's own matrix: its `matrix`, else translation × rotation × scale.
    static func local(_ node: [String: Any]) -> [Double] {
        if let matrix = GLTFReader.numbers(node["matrix"]), matrix.count == 16 { return matrix }
        let t = GLTFReader.numbers(node["translation"]) ?? [0, 0, 0]
        let r = GLTFReader.numbers(node["rotation"]) ?? [0, 0, 0, 1]
        let s = GLTFReader.numbers(node["scale"]) ?? [1, 1, 1]
        let x: Double = r[0], y: Double = r[1], z: Double = r[2], w: Double = r[3]
        let xx: Double = 2 * x * x, xy: Double = 2 * x * y, xz: Double = 2 * x * z
        let yy: Double = 2 * y * y, yz: Double = 2 * y * z, zz: Double = 2 * z * z
        let wx: Double = 2 * w * x, wy: Double = 2 * w * y, wz: Double = 2 * w * z
        let column0: [Double] = [(1 - yy - zz) * s[0], (xy + wz) * s[0], (xz - wy) * s[0], 0]
        let column1: [Double] = [(xy - wz) * s[1], (1 - xx - zz) * s[1], (yz + wx) * s[1], 0]
        let column2: [Double] = [(xz + wy) * s[2], (yz - wx) * s[2], (1 - xx - yy) * s[2], 0]
        return column0 + column1 + column2 + [t[0], t[1], t[2], 1]
    }

    static func multiply(_ a: [Double], _ b: [Double]) -> [Double] {
        var result = [Double](repeating: 0, count: 16)
        for column in 0 ..< 4 {
            for row in 0 ..< 4 {
                var sum = 0.0
                for k in 0 ..< 4 {
                    sum += a[k * 4 + row] * b[column * 4 + k]
                }
                result[column * 4 + row] = sum
            }
        }
        return result
    }

    /// A linear colour as three.js's sRGB hex number.
    static func hex(_ linear: [Double]) -> Int {
        let byte: (Double) -> Int = { Int((SceneExport.srgb($0) * 255).rounded()) }
        return linear.count >= 3 ? byte(linear[0]) << 16 | byte(linear[1]) << 8 | byte(linear[2]) : 0xFFFFFF
    }
}
