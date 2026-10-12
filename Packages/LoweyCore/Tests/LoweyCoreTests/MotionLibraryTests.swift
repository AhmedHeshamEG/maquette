import Foundation
@testable import LoweyCore
import XCTest

/// Motion as library material (U4 step 5): poses, clips and loops saved and dropped on anything, and a motion
/// played again by dragging its end.
final class MotionLibraryTests: XCTestCase {
    static func rope(_ names: [String]) -> SceneObject {
        var marks: [RigMark] = []
        for (index, name) in names.enumerated() {
            marks.append(RigMark(name: name, kind: .dot, position: Vec3(Double(index), 0, 0), parent: index == 0 ? nil : names[index - 1]))
        }
        var object = SceneObject(id: ObjectID(raw: names.joined()), name: "Rope", kind: .group)
        object.rig = RigMarks.rig(marks, surface: [])
        return object
    }

    func testATrackPlaysAgainAfterItsEndARepeatCountOrForever() {
        let keys = [Keyframe(time: 1, value: .float(0), easing: .linear), Keyframe(time: 3, value: .float(10), easing: .linear)]
        var track = Track(id: "t", target: "a", property: "x", keyframes: keys)
        XCTAssertEqual(track.value(at: 4)?.floatValue, 10, "once: it holds")
        track.cycle = TrackCycle(start: 1, end: 3, repeats: 2)
        XCTAssertEqual(track.value(at: 4)?.floatValue ?? -1, 5, accuracy: 1e-9, "halfway through the second play")
        XCTAssertEqual(track.value(at: 6.5)?.floatValue ?? -1, 7.5, accuracy: 1e-9)
        XCTAssertEqual(track.value(at: 7.5)?.floatValue, 10, "after the last repeat it holds the end")
        XCTAssertEqual(track.value(at: 0.5)?.floatValue, 0, "before it starts, the first key")
        XCTAssertEqual(track.cycle?.finish, 7)
        track.cycle?.repeats = nil
        XCTAssertEqual(track.value(at: 101.5)?.floatValue ?? -1, 2.5, accuracy: 1e-9, "forever")
        XCTAssertEqual(try LoweyJSON.decode(Track.self, from: LoweyJSON.encode(track)), track)
    }

    func testAPoseSavedOnOneRigDropsOnAnotherWhereTheJointsMatch() throws {
        var scene = Scene(id: "s", name: "S")
        let source = Self.rope(["base", "mid", "tip"])
        let target = Self.rope(["base", "mid", "end"])
        scene.objects = [source.id: source, target.id: target]
        scene.roots = [source.id, target.id]
        let bent = Quat(angle: 0.6, axis: .unitZ)
        scene.objects[source.id]?[.boneTurn("mid")] = .quat(bent)
        let pose = try XCTUnwrap(MotionLibrary.pose(of: source.id, in: scene, id: "p", name: "Bent"))
        XCTAssertEqual(pose.kind, .pose)
        XCTAssertEqual(Set(pose.joints.keys), ["base", "mid", "tip"])
        let dropped = MotionLibrary.poseChanges(pose, to: target.id, in: scene)
        XCTAssertEqual(dropped.skipped, ["tip"], "says what didn't match")
        let mid = try XCTUnwrap(dropped.changes.first { $0.key == .boneTurn("mid") }?.value?.quatValue)
        XCTAssertTrue(mid.isApproximately(bent, tolerance: 1e-9))
    }

    func testAClipCarriesItsKeysAndTravelAndALoopCyclesWhereItsDropped() throws {
        var scene = Scene(id: "s", name: "S")
        var source = Self.rope(["base", "mid", "tip"])
        source.transform.position = Vec3(5, 0, 0)
        let target = Self.rope(["base", "mid"])
        scene.objects = [source.id: source, target.id: target]
        scene.roots = [source.id, target.id]
        var timeline = Timeline()
        timeline.tracks = [
            Track(id: "a", target: source.id, property: .boneTurn("mid"),
                  keyframes: [Keyframe(time: 2, value: .quat(.identity)), Keyframe(time: 3, value: .quat(Quat(angle: 1, axis: .unitZ)))]),
            Track(id: "b", target: source.id, property: .position,
                  keyframes: [Keyframe(time: 2, value: .vec3(Vec3(5, 0, 0))), Keyframe(time: 3, value: .vec3(Vec3(6, 0, 0)))])
        ]
        let clip = try XCTUnwrap(MotionLibrary.clip(of: source.id, in: scene, timeline: timeline, loops: true, id: "c", name: "Swing"))
        XCTAssertEqual(clip.kind, .loop)
        XCTAssertEqual(clip.duration, 1, accuracy: 1e-9)
        XCTAssertEqual(clip.joints["mid"]?.first?.time, 0, "times from 0")
        XCTAssertEqual(clip.travel[.position]?.last?.value, .vec3(Vec3(1, 0, 0)), "travel is relative")
        // Dropped at 10 s on a thing standing at the origin.
        var ids = 0
        let (edits, skipped) = MotionLibrary.applying(clip, to: target.id, at: 10, in: scene, timeline: Timeline()) {
            ids += 1
            return TrackID(raw: "n\(ids)")
        }
        XCTAssertEqual(skipped, [])
        XCTAssertEqual(edits.count, 2)
        let turn = try XCTUnwrap(edits.compactMap(\.track).first { $0.property == .boneTurn("mid") })
        XCTAssertEqual(turn.keyframes.map(\.time), [10, 11])
        XCTAssertEqual(turn.cycle, TrackCycle(start: 10, end: 11), "a loop loops forever")
        let move = try XCTUnwrap(edits.compactMap(\.track).first { $0.property == .position })
        XCTAssertEqual(move.keyframes.last?.value, .vec3(Vec3(1, 0, 0)), "from where it stands")
        // The library keeps it.
        let manifest = LibraryManifest(motions: [clip])
        XCTAssertEqual(try LoweyJSON.decode(LibraryManifest.self, from: LoweyJSON.encode(manifest)).motions, [clip])
    }

    func testARigChangedAfterAnimatingKeepsItsAnimation() throws {
        var object = Self.rope(["base", "mid", "tip"])
        var document = makeDocument()
        document.scene.objects = [object.id: object]
        document.scene.roots = [object.id]
        document.scene.timeline.tracks = [Track(id: "k", target: object.id, property: .boneTurn("mid"),
                                                keyframes: [Keyframe(time: 0, value: .quat(.identity)),
                                                            Keyframe(time: 1, value: .quat(Quat(angle: .pi / 2, axis: .unitZ)))])]
        func tip(_ document: Document) throws -> Vec3 {
            let frame = Animator.evaluate(document, at: 1)
            let rig = try XCTUnwrap(frame.scene.objects[object.id]?.rig)
            let pose = try XCTUnwrap(frame.poses[object.id])
            let index = try XCTUnwrap(rig.skeleton.index(of: "tip"))
            return rig.skeleton.modelSpace(pose)[index].position
        }
        XCTAssertEqual(try tip(document).y, 1, accuracy: 1e-6, "the tip swung up")
        // Move the middle dot and add one past the tip: the turn on "mid" still plays.
        let rig = try XCTUnwrap(object.rig)
        var marks = RigMarks.moving("mid", to: Vec3(0.5, 0, 0), in: rig.marks)
        marks = RigMarks.adding(.pin, at: Vec3(3, 0, 0), to: "tip", in: marks).marks
        object.rig = RigMarks.rig(marks, surface: [])
        document.scene.objects[object.id] = object
        let moved = try tip(document)
        XCTAssertEqual(moved.x, 0.5, accuracy: 1e-6)
        XCTAssertEqual(moved.y, 1.5, accuracy: 1e-6, "turned about the moved joint, the keys untouched")
        XCTAssertEqual(document.scene.timeline.tracks.count, 1)
    }
}
