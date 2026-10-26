import Foundation
@testable import LoweyCore
import XCTest

/// Export ▸ For the web (X1): the folder, its two scene files saying the same thing, and the three.js it carries.
final class ThreeProjectTests: XCTestCase {
    /// three.js as the app carries it (HmmWeb's copy).
    static let libraryFolder = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent("HmmKit/Sources/HmmWeb/Web/lib/three")

    static func library(_ path: String) -> Data? {
        try? Data(contentsOf: libraryFolder.appendingPathComponent(path))
    }

    /// A table (a group with a top and a leg) sliding, the keyed lantern, a spot, two cameras and a cut between them.
    static func webScene() -> Scene {
        var scene = GLTFPointerTests.keyedScene()
        var table = SceneObject(id: "table", name: "Coffee table", kind: .group, children: ["top", "leg"],
                                transform: Transform(position: Vec3(1, 0, -2), rotation: Quat(angle: 0.3, axis: .unitY)))
        table[.visible] = .bool(true)
        var top = SceneObject(id: "top", name: "Top", kind: .mesh(.box(min: Vec3(-0.6, 0.72, -0.4), max: Vec3(0.6, 0.76, 0.4))), parent: "table")
        top[.color] = .color(.rgba(RGBA(0.8, 0.3, 0.1)))
        var leg = SceneObject(id: "leg", name: "Top", kind: .primitive(.cylinder), parent: "table",
                              transform: Transform(position: Vec3(0, 0.36, 0), scale: Vec3(0.1, 0.72, 0.1)))
        leg[.color] = .color(.rgba(RGBA(0.2, 0.2, 0.25)))
        var wide = SceneObject(id: "wide", name: "Wide", kind: .camera, transform: Transform(position: Vec3(4, 3, 6)))
        wide.transform.rotation = Quat(angle: 0.5, axis: .unitY) * Quat(angle: -0.3, axis: .unitX)
        wide[.fieldOfView] = .float(40)
        for object in [table, top, leg, wide] {
            scene.objects[object.id] = object
        }
        scene.roots += ["table", "wide"]
        scene.activeCamera = "cam"
        scene.timeline.tracks.append(Track(id: TrackID(raw: "slide"), target: "table", property: .position, keyframes: [
            Keyframe(time: 0, value: .vec3(Vec3(1, 0, -2)), easing: .linear), Keyframe(time: 2, value: .vec3(Vec3(2, 0, -1)), easing: .linear)
        ]))
        scene.timeline.cuts = [CameraCut(time: 0, camera: "cam"), CameraCut(time: 1.5, camera: "wide")]
        return scene
    }

    static func folder() throws -> [(name: String, data: Data)] {
        let scene = webScene()
        let glb = GLTFScene.glb(nil, in: scene, look: Look())
        return try ThreeProject.files(ThreeProject.Input(scene: scene, look: Look(), preset: .ink, glb: glb, name: "Night room", library: library))
    }

    func testTheCarriedThreeResolvesEveryImport() throws {
        let carried = Set(ThreeProject.libraryFiles)
        for path in ThreeProject.libraryFiles where path.hasSuffix(".js") {
            let source = try XCTUnwrap(Self.library(path).map { String(decoding: $0, as: UTF8.self) }, path)
            let folder = (path as NSString).deletingLastPathComponent
            for specifier in Self.imports(source) where specifier.hasPrefix(".") {
                let resolved = URL(fileURLWithPath: "/" + folder).appendingPathComponent(specifier).standardized.path.dropFirst()
                XCTAssertTrue(carried.contains(String(resolved)), "\(path) imports \(specifier), which the folder doesn't carry")
            }
        }
        // The folder's own modules only ask for what's carried.
        for script in [ThreeProjectScripts.mainJS, ThreeProjectScripts.lookJS, ThreeProjectScripts.pointerJS] {
            for specifier in Self.imports(script) where specifier.hasPrefix("three/addons/") {
                XCTAssertTrue(carried.contains("addons/" + specifier.dropFirst("three/addons/".count)), specifier)
            }
        }
    }

    /// `import … from '…'` specifiers (comments with example URLs aside).
    static func imports(_ source: String) -> [String] {
        let pattern = try? NSRegularExpression(pattern: #"^\s*import\s[^'"]*from\s*['"]([^'"]+)['"]"#, options: [.anchorsMatchLines])
        let range = NSRange(source.startIndex..., in: source)
        return pattern?.matches(in: source, range: range).compactMap { Range($0.range(at: 1), in: source).map { String(source[$0]) } } ?? []
    }

    func testTheFolderHoldsEverythingNamedOnce() throws {
        let files = try Self.folder()
        let names = Set(files.map(\.name))
        for expected in ["index.html", "main.js", "scene.glb", "scene.json", "Scene.jsx", "AGENTS.md", "LICENSE.txt", "maquette/scene.js",
                         "maquette/look.js", "maquette/pointer.js", "lib/three/three.module.js"] {
            XCTAssertTrue(names.contains(expected), expected)
        }
        let glb = try XCTUnwrap(files.first { $0.name == "scene.glb" }?.data)
        let nodes = try GLTFReader.parse(glb, baseURL: nil).array("nodes").compactMap { $0["name"] as? String }
        // Two things called "Top" and a name with a space: clean and unique, as three.js keeps them.
        XCTAssertEqual(Set(nodes).count, nodes.count)
        XCTAssertTrue(nodes.contains("Coffee_table"))
        XCTAssertTrue(nodes.contains("Top") && nodes.contains("Top_1"))
        let agents = try String(decoding: XCTUnwrap(files.first { $0.name == "AGENTS.md" }?.data), as: UTF8.self)
        XCTAssertTrue(agents.contains("| `Coffee_table` | Coffee table | group"))
        let component = try String(decoding: XCTUnwrap(files.first { $0.name == "Scene.jsx" }?.data), as: UTF8.self)
        XCTAssertTrue(component.contains("'Coffee_table': { role: 'group'"))
        let info = try String(decoding: XCTUnwrap(files.first { $0.name == "maquette/scene.js" }?.data), as: UTF8.self)
        XCTAssertTrue(info.contains("\"camera\" : \"Wide\""), info)
    }

    func testSceneJSONIsTheGLBInThreesOwnFormat() throws {
        let files = try Self.folder()
        let data = try XCTUnwrap(files.first { $0.name == "scene.json" }?.data)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual((json["metadata"] as? [String: Any])?["type"] as? String, "Object")
        var names: [String: String] = [:]
        func walk(_ object: [String: Any]) {
            if let name = object["name"] as? String { names[name] = object["type"] as? String }
            (object["children"] as? [[String: Any]] ?? []).forEach(walk)
        }
        try walk(XCTUnwrap(json["object"] as? [String: Any]))
        XCTAssertEqual(names["Lantern"], "Mesh")
        XCTAssertEqual(names["Spot"], "SpotLight")
        XCTAssertEqual(names["Shot"], "PerspectiveCamera")
        XCTAssertEqual(names["Coffee_table"], "Object3D")
        let tracks = Set(((json["animations"] as? [[String: Any]])?.first?["tracks"] as? [[String: Any]] ?? []).compactMap { $0["name"] as? String })
        for expected in ["Coffee_table.position", "Lantern.material.color", "Lantern.material.opacity", "Lantern.material.roughness",
                         "Lantern.material.emissiveIntensity", "Spot.intensity", "Spot.angle", "Shot.fov"] {
            XCTAssertTrue(tracks.contains(expected), expected)
        }
        // A fading material is drawn see-through.
        let lantern = (json["materials"] as? [[String: Any]])?.first { ($0["name"] as? String)?.hasPrefix("Lantern") == true }
        XCTAssertEqual(lantern?["transparent"] as? Bool, true)
    }

    /// Writes the folder and what the node and browser checks compare it with (`Tools/check_threejs.mjs`).
    func testWritesTheFolderForTheThreeJSCheck() throws {
        guard let directory = ProcessInfo.processInfo.environment["ACCEPTANCE_DIR"] else { throw XCTSkip("ACCEPTANCE_DIR not set") }
        let root = URL(fileURLWithPath: directory).appendingPathComponent("threejs/night-room")
        for file in try Self.folder() {
            let url = root.appendingPathComponent(file.name)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try file.data.write(to: url)
        }
        let scene = Self.webScene()
        let worlds: [String: [Double]] = ["Lantern": scene.worldTransform(of: "lantern"), "Top": scene.worldTransform(of: "top"),
                                          "Shot": scene.worldTransform(of: "cam")].mapValues { [$0.position.x, $0.position.y, $0.position.z] }
        // Maquette's own picture of the moment the browser draws (the camera, its lens and the places as keyed).
        let (width, height, moment) = (480, 270, 0.5)
        let mask = ThreeSilhouette.mask(scene, at: moment, camera: "cam", width: width, height: height)
        try ThreeSilhouette.pgm(mask, width: width, height: height).write(to: root.appendingPathComponent("expected-mask.pgm"))
        XCTAssertGreaterThan(mask.filter { $0 > 0 }.count, width * height / 50, "the golden shows the scene")
        let manifest: [String: Any] = ["meshes": ["Lantern", "Top", "Top_1"], "cameras": ["Shot", "Wide"], "lights": ["Spot"],
                                       "worldAtZero": worlds, "clips": ["Night"], "renderAt": moment, "camera": "Shot",
                                       "width": width, "height": height]
        try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys]).write(to: root.appendingPathComponent("expected.json"))
    }
}
