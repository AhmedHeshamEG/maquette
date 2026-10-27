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

    /// X1: the skin comes back as a rigged thing: the same joints where they were, weights for every corner of the
    /// surface it draws, and the joints' keys as its `bone.` keys.
    func testASkinComesBackRigged() throws {
        let (scene, skin) = try Self.animatedTail()
        let glb = GLTFScene.glb(nil, in: scene, look: Look(), skinned: { $0.rig == nil ? nil : skin })
        var ids = IDFactory.sequential("r")
        let result = try GLTFSceneReader.read(glb, ids: &ids)
        let objects = Dictionary(uniqueKeysWithValues: result.fragment.objects.map { ($0.id, $0) })
        let rigged = try XCTUnwrap(result.fragment.objects.first { $0.rig != nil })
        let rig = try XCTUnwrap(rigged.rig)
        XCTAssertEqual(rig.skeleton.names.sorted(), skin.rig.skeleton.names.sorted())
        XCTAssertFalse(result.fragment.objects.contains { skin.rig.skeleton.names.contains($0.name) }, "joints aren't things")
        var world = rigged.transform
        var parent = rigged.parent
        while let id = parent, let above = objects[id] {
            world = above.transform * world
            parent = above.parent
        }
        let original = try XCTUnwrap(scene.objects["creature"]).transform
        for (name, position) in zip(skin.rig.skeleton.names, skin.rig.restPositions) {
            let index = try XCTUnwrap(rig.skeleton.index(of: name))
            XCTAssertLessThan(world.apply(to: rig.skeleton.modelRest[index].position).distance(to: original.apply(to: position)), 1e-4, name)
        }
        let file = try XCTUnwrap(rig.skin.flatMap { result.files[$0] })
        let weights = try SkinWeights(data: file)
        XCTAssertEqual(weights.count, PaintSource.unshaped(of: rigged)?.positions.count)
        XCTAssertEqual(rig.surface, PaintSource.unshaped(of: rigged).map(PaintMesh.fingerprint))
        // Every joint moves as much of the surface as it did: the weights came across, not a guess.
        let source = skin.weights[0]
        for (joint, name) in skin.rig.skeleton.names.enumerated() {
            let mine = try XCTUnwrap(rig.skeleton.index(of: name))
            let before = source.weights.indices.map { source.weight(of: joint, at: $0) }.max() ?? 0
            let after = weights.weights.indices.map { weights.weight(of: mine, at: $0) }.max() ?? 0
            XCTAssertEqual(after, before, accuracy: 0.1, name)
        }
        // The keys: every turned joint, the same turn a second in.
        let turns = result.tracks.filter { $0.target == rigged.id && $0.property.boneJoint != nil }
        XCTAssertEqual(Set(turns.map(\.property)), Set(scene.timeline.tracks.map(\.property)))
        for track in scene.timeline.tracks {
            let read = try XCTUnwrap(turns.first { $0.property == track.property })
            let want = try XCTUnwrap(track.keyframes.last?.value.quatValue), got = try XCTUnwrap(read.keyframes.last?.value.quatValue)
            XCTAssertGreaterThan(abs(want.x * got.x + want.y * got.y + want.z * got.z + want.w * got.w), 1 - 1e-4, track.property.rawValue)
        }
    }

    /// SPIKE (U4 step 7): our own FBX writer. CI opens this file in Godot (ufbx) and Blender.
    func testARiggedThingLeavesAsAnFBXOfItsOwn() throws {
        let (scene, skin) = try Self.animatedTail()
        let fbx = FBXSkin.file(skin, name: "Creature", tracks: scene.timeline.tracks, fps: 30)
        XCTAssertEqual(fbx.prefix(20), Data("Kaydara FBX Binary  ".utf8))
        XCTAssertEqual(fbx[23 ..< 27].withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }.littleEndian, 7400)
        XCTAssertGreaterThan(fbx.count, 10000)
        let angle = FBXSkin.euler(Quat(angle: .pi / 2, axis: .unitZ))
        XCTAssertEqual(angle.z, 90, accuracy: 1e-9)
        XCTAssertEqual(FBXSkin.Builder.unwrapped(Vec3(-179, 0, 0), near: Vec3(179, 0, 0)).x, 181, accuracy: 1e-9)
        if let directory = ProcessInfo.processInfo.environment["ACCEPTANCE_DIR"] {
            let folder = URL(fileURLWithPath: directory).appendingPathComponent("rigged")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try fbx.write(to: folder.appendingPathComponent("tail.fbx"))
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
