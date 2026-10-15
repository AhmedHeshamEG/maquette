import Foundation
@testable import LoweyCore
import XCTest

/// P1's exports: a run always leaves as baked motion, and real things carry their collision shapes in the glTF physics
/// form Godot reads (`OMI_physics_body`, `OMI_physics_shape`). CI opens the file in Godot 4.3.
final class PhysicsExportTests: XCTestCase {
    func testADroppedCubeLeavesWithBakedMotionAndColliders() throws {
        var floor = SceneObject(id: "floor", name: "Floor", kind: .primitive(.cube), transform: Transform(position: Vec3(0, -0.2, 0), scale: Vec3(4, 0.2, 4)))
        floor.physics = ObjectPhysics(material: .concrete, motion: .stays)
        let document = PhysicsTests.document([PhysicsTests.cube("wood", at: Vec3(0, 2, 0)), floor], duration: 2)
        let frames = try PhysicsTests.run(document)
        let baked = PhysicsKeep.baked(frames, into: document)
        XCTAssertTrue(baked.scene.timeline.tracks.contains { $0.target == "wood" && $0.property == .position })
        let glb = GLTFScene.glb(nil, in: baked.scene, look: baked.effectiveLook)
        let json = try Self.glbJSON(glb)
        XCTAssertEqual(Set(json["extensionsUsed"] as? [String] ?? []), ["OMI_physics_body", "OMI_physics_shape"])
        let shapes = try XCTUnwrap((json["extensions"] as? [String: Any])?["OMI_physics_shape"] as? [String: Any])["shapes"] as? [[String: Any]]
        XCTAssertEqual(shapes?.map { $0["type"] as? String }, ["convex", "trimesh"])
        let nodes = try XCTUnwrap(json["nodes"] as? [[String: Any]])
        let wood = try XCTUnwrap(nodes.first { $0["name"] as? String == "wood" })
        let body = try XCTUnwrap((wood["extensions"] as? [String: Any])?["OMI_physics_body"] as? [String: Any])
        let motion = try XCTUnwrap(body["motion"] as? [String: Any])
        XCTAssertEqual(motion["type"] as? String, "dynamic")
        XCTAssertEqual(motion["mass"] as? Double ?? 0, 700, accuracy: 10)
        XCTAssertNotNil(body["collider"])
        XCTAssertFalse((json["animations"] as? [[String: Any]] ?? []).isEmpty, "the run is baked")
        if let directory = ProcessInfo.processInfo.environment["ACCEPTANCE_DIR"] {
            let folder = URL(fileURLWithPath: directory).appendingPathComponent("physics")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try glb.write(to: folder.appendingPathComponent("drop.glb"))
        }
    }

    func testTheBridgeMakesThingsRealJoinsThemAndKeepsTheRun() throws {
        var document = PhysicsTests.document([PhysicsTests.cube("box", at: Vec3(0, 1, 0))], physics: nil)
        document.scene.objects["box"]?.physics = nil
        var context = ScriptContext(ids: .sequential("s"))
        context.mesh = { _ in nil }
        let actions = """
        {"do": "physics", "op": "real", "target": "box", "material": "steel"},
         {"do": "physics", "op": "scene", "gravity": "moon", "wind": {"speed": 4, "heading": 90}},
         {"do": "physics", "op": "joint", "kind": "rope", "first": "box", "anchor": [0, 1.5, 0], "to": [0, 2.5, 0], "length": 1, "id": "rope"},
         {"do": "physics", "op": "force", "kind": "fan", "at": [2, 1, 0], "aim": [-1, 0, 0]},
         {"do": "physics", "op": "sun", "place": "Cairo", "date": "2026-12-21", "hour": 9, "study": [7, 17]},
         {"do": "physics", "op": "stand", "target": "box"},
         {"do": "physics", "op": "keep"}
        """
        let script = try LoweyJSON.decode(SceneScript.self, from: Data("{\"version\": 3, \"title\": \"T\", \"actions\": [\(actions)]}".utf8))
        let result = try ScriptCompiler.compile(script, document: document, context: context)
        var applied = document
        _ = try XCTUnwrap(result.command).apply(to: &applied)
        XCTAssertEqual(applied.scene.objects["box"]?.physics?.material, .steel)
        XCTAssertEqual(applied.scene.objects["box"]?.physics?.motion, .follows, "kept")
        XCTAssertEqual(applied.scene.physics?.gravity, .moon)
        XCTAssertEqual(applied.scene.physics?.joints.first?.kind, .rope)
        XCTAssertTrue(applied.scene.objects.values.contains {
            if case .force = $0.kind {
                true
            } else {
                false
            }
        })
        XCTAssertEqual(applied.project.look.lighting.realSun?.place, "Cairo")
        XCTAssertTrue(result.report.contains { $0.hasPrefix("It stands") || $0.hasPrefix("It tips") })
        XCTAssertTrue(applied.scene.timeline.tracks.contains { $0.target == "box" })
    }

    static func glbJSON(_ glb: Data) throws -> [String: Any] {
        let bytes = [UInt8](glb)
        let length = Int(UInt32(bytes[12]) | UInt32(bytes[13]) << 8 | UInt32(bytes[14]) << 16 | UInt32(bytes[15]) << 24)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(bytes[20 ..< 20 + length])) as? [String: Any])
    }
}
