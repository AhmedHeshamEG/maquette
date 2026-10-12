import Foundation
@testable import LoweyCore
import XCTest

/// Out to game engines (U4 step 7): a rigged, animated thing leaves as a skin with its bones and their keys, so Godot
/// and Unity play it. CI opens the file this writes in Godot (`ACCEPTANCE_DIR/rigged/tail.glb`).
final class SkinExportTests: XCTestCase {
    /// The creature with its tail pinned, the tip pulled up over a second, as a scene and its skin.
    static func animatedTail() throws -> (scene: Scene, skin: GLTFScene.SkinnedExport) {
        let (document, mesh, rig, weights) = try RigMarksTests.pinnedTail()
        var scene = document.scene
        let tip = try XCTUnwrap(IKHandles.handles(of: "creature", in: scene).first)
        let up = IKHandles.solve(tip, to: Vec3(RigSamples.tailEnd - 0.4, RigSamples.tailHeight + 0.7, 0), in: scene, rest: scene)
        scene.timeline.tracks = up.enumerated().map { index, change in
            Track(id: TrackID(raw: "t\(index)"), target: "creature", property: change.key,
                  keyframes: [Keyframe(time: 0, value: .quat(.identity)), Keyframe(time: 1, value: change.value ?? .quat(.identity))])
        }
        let part = GLTFScene.LocalPart(name: "Creature", mesh: mesh, material: ExportMaterial(color: RGBA(0.85, 0.55, 0.3)))
        return (scene, GLTFScene.SkinnedExport(rig: rig, parts: [part], weights: [weights]))
    }

    func testARiggedThingLeavesAsASkinWithItsJointsKeyed() throws {
        let (scene, skin) = try Self.animatedTail()
        let glb = GLTFScene.glb(nil, in: scene, look: Look(), skinned: { $0.rig == nil ? nil : skin })
        // Read back as any reader would: the skeleton with the same joints, the surface skinned, the keys on the joints.
        let rig = try XCTUnwrap(GLTFReader.rig(data: glb))
        XCTAssertEqual(Set(rig.skeleton.names), Set(skin.rig.skeleton.names))
        for (name, position) in zip(skin.rig.skeleton.names, skin.rig.restPositions) {
            let index = try XCTUnwrap(rig.skeleton.index(of: name))
            XCTAssertLessThan(rig.skeleton.modelRest[index].position.distance(to: position), 1e-5, name)
        }
        let model = try GLTFMeshReader.model(data: glb)
        XCTAssertTrue(model.parts.allSatisfy(\.isSkinned))
        XCTAssertEqual(model.skin?.joints.count, skin.rig.skeleton.joints.count)
        let clip = try XCTUnwrap(rig.clips.values.first)
        XCTAssertGreaterThanOrEqual(clip.duration, 1 - 1e-6)
        XCTAssertTrue(clip.channels.contains { $0.joint == "j2~0" && $0.path == .rotation })
        // The pose a second in turns the tip joint where the scene had it.
        let posed = clip.pose(at: 1, skeleton: rig.skeleton)
        let tipJoint = try XCTUnwrap(rig.skeleton.index(of: "j2"))
        let tipNow = rig.skeleton.modelSpace(posed)[tipJoint].position
        XCTAssertGreaterThan(tipNow.y, RigSamples.tailHeight + 0.4, "the tip is up")
        if let directory = ProcessInfo.processInfo.environment["ACCEPTANCE_DIR"] {
            let folder = URL(fileURLWithPath: directory).appendingPathComponent("rigged")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try glb.write(to: folder.appendingPathComponent("tail.glb"))
        }
    }

    func testRepeatsArePlayedOutAndAStillPoseStandsInTheJoints() throws {
        var (scene, skin) = try Self.animatedTail()
        for index in scene.timeline.tracks.indices {
            scene.timeline.tracks[index].cycle = TrackCycle(start: 0, end: 1, repeats: 2)
        }
        let glb = GLTFScene.glb(nil, in: scene, look: Look(), skinned: { $0.rig == nil ? nil : skin })
        let clip = try XCTUnwrap(GLTFReader.rig(data: glb)?.clips.values.first)
        XCTAssertEqual(clip.duration, 3, accuracy: 1e-6, "three plays")
        // No keys: the hand-set pose is what the joints hold.
        scene.timeline.tracks = []
        let turn = Quat(angle: 0.5, axis: .unitZ)
        var pose = skin.rig.skeleton.restPose
        let bent = try XCTUnwrap(skin.rig.skeleton.index(of: "j2~1"))
        pose[bent].rotation = turn
        skin.pose = pose
        let still = try XCTUnwrap(GLTFReader.rig(data: GLTFScene.glb(nil, in: scene, look: Look(), skinned: { $0.rig == nil ? nil : skin })))
        let index = try XCTUnwrap(still.skeleton.index(of: "j2~1"))
        XCTAssertTrue(still.skeleton.joints[index].rest.rotation.isApproximately(turn, tolerance: 1e-6))
    }
}
