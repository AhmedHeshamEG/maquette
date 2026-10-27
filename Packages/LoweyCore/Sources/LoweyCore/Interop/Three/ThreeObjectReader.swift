import Foundation

/// three.js's own scene format in (X1 step 3): what `scene.toJSON()` writes (format 4.x), the way vibe-coded scenes are
/// often saved. Meshes become editable things (buffer geometry, boxes, spheres, cylinders, cones and planes), standard
/// and physical materials become colour, roughness, metal, glow and see-through, cameras and lights become ours, an
/// instanced mesh becomes one thing cloned where its copies stand, and every clip's tracks become keys. What can't
/// become ours is said in one line a kind (`notes`); nothing is asked first.
public enum ThreeObjectReader {
    public struct Result: Sendable {
        public var scene: GLTFSceneReader.Result
        /// One plain line a kind of thing that was changed or left out ("Points: left out, …").
        public var notes: [String]
        /// The file used toon materials: a toon Look would suit it.
        public var suggestsToon: Bool
    }

    public enum Failure: Error, Equatable, CustomStringConvertible {
        case notThreeJSON
        case empty

        public var description: String {
            switch self {
            case .notThreeJSON: "That isn't a three.js scene file."
            case .empty: "That three.js file has nothing to bring in."
            }
        }
    }

    public static func read(_ data: Data, ids: inout IDFactory) throws -> Result {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let root = json["object"] as? [String: Any],
              (json["metadata"] as? [String: Any])?["type"] as? String == "Object" else { throw Failure.notThreeJSON }
        var builder = ThreeReaderBuilder(json: json)
        // A scene's children are the roots; any other object is a root itself.
        let tops = root["type"] as? String == "Scene" ? root["children"] as? [[String: Any]] ?? [] : [root]
        var roots: [ObjectID] = []
        for object in tops {
            if let id = builder.object(object, parent: nil, ids: &ids) { roots.append(id) }
        }
        guard !roots.isEmpty else { throw Failure.empty }
        guard builder.triangles <= GLTFSceneReader.triangleLimit else { throw GLTFSceneReader.Failure.tooBig(builder.triangles) }
        let (tracks, duration) = builder.tracks(ids: &ids)
        var scene = GLTFSceneReader.Result(fragment: SceneFragment(objects: builder.objects, roots: roots), tracks: tracks, duration: duration)
        scene.pictures = builder.pictures
        scene.textures = builder.textures
        scene.files = builder.files
        return Result(scene: scene, notes: builder.notes.sorted(), suggestsToon: builder.suggestsToon)
    }
}

/// One pass over three.js's object tree.
struct ThreeReaderBuilder {
    let json: [String: Any]
    let geometries: [String: [String: Any]]
    let materials: [String: [String: Any]]
    /// Objects a light aims at (they aren't things of their own).
    let lightTargets: Set<String>
    var objects: [SceneObject] = []
    var objectOf: [String: ObjectID] = [:]
    var named: [String: ObjectID] = [:]
    var notes = Set<String>()
    var suggestsToon = false
    var triangles = 0
    /// Pictures carried in the file, laid on surfaces as paint (`PaintImport`).
    var pictures: [ObjectID: GLTFPictures] = [:]
    var textures: [ImportedTexture] = []
    var imageIndex: [String: Int] = [:]
    /// Skins: the object tree (parents, bones, names), which rigged things each bone turns (by uuid and name), and the
    /// `.skin` files they need.
    let tree: (parents: [String: String], bones: Set<String>, names: [String: String])
    var boneTargets: [String: [(object: ObjectID, joint: String)]] = [:]
    var files: [String: Data] = [:]

    init(json: [String: Any]) {
        self.json = json
        geometries = Self.byUUID(json["geometries"])
        materials = Self.byUUID(json["materials"])
        var targets = Set<String>()
        func collect(_ object: [String: Any]) {
            if let target = object["target"] as? String { targets.insert(target) }
            (object["children"] as? [[String: Any]] ?? []).forEach(collect)
        }
        if let root = json["object"] as? [String: Any] { collect(root) }
        lightTargets = targets
        tree = Self.tree(json)
    }

    static func byUUID(_ list: Any?) -> [String: [String: Any]] {
        Dictionary((list as? [[String: Any]] ?? []).compactMap { item in (item["uuid"] as? String).map { ($0, item) } }) { first, _ in first }
    }

    mutating func object(_ source: [String: Any], parent: ObjectID?, ids: inout IDFactory) -> ObjectID? {
        let type = source["type"] as? String ?? "Object3D"
        let uuid = source["uuid"] as? String ?? UUID().uuidString
        let children = source["children"] as? [[String: Any]] ?? []
        if lightTargets.contains(uuid), children.isEmpty { return nil }
        guard let kind = kind(type, source: source) else { return nil }
        let id: ObjectID = ids.next()
        let threeName = source["name"] as? String ?? ""
        let maquette = (source["userData"] as? [String: Any])?["maquette"] as? [String: Any]
        let name = maquette?["name"] as? String ?? (threeName.isEmpty ? type : threeName)
        var transform = GLTFReader.decompose(GLTFReader.numbers(source["matrix"]) ?? ThreeMatrix.identity)
        if source["target"] == nil, ["DirectionalLight", "SpotLight"].contains(type) {
            // Without a target, three.js lights aim at the origin; ours shine down their −Z.
            transform.rotation = Quat.rotation(from: Vec3(0, 0, -1), to: (-transform.position).normalized)
        }
        var object = SceneObject(id: id, name: name, kind: kind, parent: parent, transform: transform)
        dress(&object, type: type, source: source)
        if type == "SkinnedMesh", !skin(&object, source: source) {
            notes.insert("Skinned meshes: brought in at their bind pose; their skeleton wasn't in the file.")
        }
        objectOf[uuid] = id
        if !threeName.isEmpty { named[threeName] = id }
        let slot = objects.count
        objects.append(object)
        var childIDs = instances(source, kind: kind, parent: id, ids: &ids)
        for child in children {
            if let childID = self.object(child, parent: id, ids: &ids) { childIDs.append(childID) }
        }
        objects[slot].children = childIDs
        return id
    }

    /// What a three.js object becomes; nil (with a note) for what has no place here.
    mutating func kind(_ type: String, source: [String: Any]) -> ObjectKind? {
        switch type {
        case "Bone":
            return nil
        case "Mesh", "SkinnedMesh":
            return mesh(source["geometry"] as? String).map { .mesh($0) } ?? .group
        case "InstancedMesh":
            return .group
        case "PerspectiveCamera", "OrthographicCamera":
            if type == "OrthographicCamera" { notes.insert("Orthographic cameras: brought in as ordinary cameras.") }
            return .camera
        case "DirectionalLight": return .light(.directional)
        case "PointLight": return .light(.point)
        case "SpotLight": return .light(.spot)
        case "RectAreaLight": return .light(.area)
        case "AmbientLight", "HemisphereLight", "LightProbe":
            notes.insert("\(type): left out; the Look's own sky light does its job.")
            return nil
        case "Points", "Line", "LineSegments", "LineLoop", "Sprite":
            notes.insert("\(type): left out; it isn't a surface (bring the project folder in to keep it playing as a web object).")
            return nil
        default:
            return .group
        }
    }

    mutating func dress(_ object: inout SceneObject, type: String, source: [String: Any]) {
        switch object.kind {
        case .camera:
            object[.fieldOfView] = .float(source["fov"] as? Double ?? 50)
        case let .light(lightType):
            object[.lightColor] = .color(.rgba(Self.colour(source["color"] as? Int ?? 0xFFFFFF)))
            object[.lightIntensity] = .float(source["intensity"] as? Double ?? 1)
            if let distance = source["distance"] as? Double, distance > 0 { object[.lightRange] = .float(distance) }
            if lightType == .spot { object[.spotAngle] = .float((source["angle"] as? Double ?? .pi / 3) * 360 / .pi) }
            if lightType == .area {
                object[.lightWidth] = .float(source["width"] as? Double ?? 1)
                object[.lightHeight] = .float(source["height"] as? Double ?? 1)
            }
        case .mesh:
            let reference = source["material"]
            let uuid = (reference as? String) ?? (reference as? [String])?.first
            if let uuid, let material = materials[uuid] {
                apply(material, to: &object)
                pictures[object.id] = pictures(material, geometry: source["geometry"] as? String)
                if pictures[object.id] == nil, ["map", "normalMap", "roughnessMap", "emissiveMap"].contains(where: { material[$0] != nil }) {
                    notes.insert("Pictures on surfaces: only pictures the file carries on its own triangles come in; the others kept their colours.")
                }
            }
        default:
            break
        }
    }

    /// An instanced mesh as one thing under the group, cloned where the instances stand (the `placed` layout: each copy's
    /// place, turn and size against the first's), so the copies stay one thing to edit.
    mutating func instances(_ source: [String: Any], kind: ObjectKind, parent: ObjectID, ids: inout IDFactory) -> [ObjectID] {
        let before = triangles
        guard source["type"] as? String == "InstancedMesh", let shape = mesh(source["geometry"] as? String),
              let matrices = GLTFReader.numbers((source["instanceMatrix"] as? [String: Any])?["array"]) else { return [] }
        let count = min(source["count"] as? Int ?? matrices.count / 16, matrices.count / 16, ObjectClones.maximumCount)
        guard count > 0 else { return [] }
        triangles += (triangles - before) * max(count - 1, 0)
        let places = (0 ..< count).map { GLTFReader.decompose(Array(matrices[$0 * 16 ..< $0 * 16 + 16])) }
        let first = places[0]
        let name = source["name"] as? String ?? "Copy"
        var thing = SceneObject(id: ids.next(), name: name.isEmpty ? "Copy" : name, kind: .mesh(shape), parent: parent, transform: first)
        let material = ((source["material"] as? String) ?? (source["material"] as? [String])?.first).flatMap { materials[$0] }
        if let material { apply(material, to: &thing) }
        if count > 1 {
            let back = first.rotation.inverse
            let relative = places.map { place in
                Transform(position: back.act(place.position - first.position), rotation: (back * place.rotation).normalized,
                          scale: Vec3(place.scale.x / Self.nonZero(first.scale.x), place.scale.y / Self.nonZero(first.scale.y),
                                      place.scale.z / Self.nonZero(first.scale.z)))
            }
            thing.motionDesign = MotionDesign(clones: ObjectClones(layout: .placed(relative)))
        }
        if (source["count"] as? Int ?? 0) > ObjectClones.maximumCount {
            notes.insert("Instanced meshes: the first \(ObjectClones.maximumCount) copies came in as clones.")
        }
        objects.append(thing)
        return [thing.id]
    }

    static func nonZero(_ value: Double) -> Double {
        abs(value) < 1e-9 ? 1e-9 : value
    }

    /// An sRGB hex number as a colour.
    static func colour(_ hex: Int) -> RGBA {
        RGBA(Double(hex >> 16 & 0xFF) / 255, Double(hex >> 8 & 0xFF) / 255, Double(hex & 0xFF) / 255)
    }
}
