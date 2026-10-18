import Foundation
@testable import LoweyCore
import XCTest

/// A1: what the named 3D presets change before a file is written.
final class ExportPrepTests: XCTestCase {
    func testEnginePresetsLeaveCamerasLightsAndColliders() throws {
        var document = makeDocument()
        document.scene.objects["cam"] = SceneObject(id: "cam", name: "Cam", kind: .camera)
        document.scene.objects["sun"] = SceneObject(id: "sun", name: "Sun", kind: .light(.directional))
        document.scene.roots += ["cam", "sun"]
        document.scene.objects["c"]?.physics = ObjectPhysics(material: .wood)
        let game = ExportPrep.withoutCamerasAndLights(document.scene)
        XCTAssertFalse(game.isEffectivelyVisible("cam"))
        XCTAssertFalse(game.isEffectivelyVisible("sun"))
        XCTAssertTrue(game.isEffectivelyVisible("c"))
        let glb = GLTFScene.glb(nil, in: game, look: Look())
        XCTAssertNil(try PhysicsExportTests.glbJSON(glb)["cameras"], "no camera in the file")
        let plain = ExportPrep.withoutPhysics(document.scene)
        XCTAssertNil(plain.objects["c"]?.physics)
        let only = ExportPrep.only(["b"], in: document.scene)
        XCTAssertTrue(only.isEffectivelyVisible("b"))
        XCTAssertFalse(only.isEffectivelyVisible("c"))
    }

    func testEngineNamesRenameJointsAndTheirKeys() throws {
        let rig = ObjectRig(names: ["hips", "leftUpperArm", "tail"], parents: [nil, 0, 0], positions: [.zero, Vec3(0.2, 1, 0), Vec3(0, 0.5, -0.3)])
        let skin = GLTFScene.SkinnedExport(rig: rig, parts: [], weights: [])
        let tracks = [Track(id: "t", target: "a", property: .boneTurn("leftUpperArm"), keyframes: [Keyframe(time: 0, value: .quat(.identity))]),
                      Track(id: "p", target: "a", property: .position)]
        let (unreal, keys) = ExportPrep.renamed(skin, tracks: tracks, for: .unreal)
        XCTAssertEqual(unreal.rig.skeleton.names, ["pelvis", "upperarm_l", "tail"])
        XCTAssertEqual(keys.map(\.property), [.boneTurn("upperarm_l"), .position])
        XCTAssertEqual(ExportPrep.renamed(skin, tracks: [], for: .unity).0.rig.skeleton.names, ["Hips", "LeftUpperArm", "Tail"])
    }
}
