import Foundation
@testable import LoweyCore
import XCTest

/// A1: a motion drawn with the Pencil, picking up and handing off, looking at things, and what 3D files keep of them.
final class AnimateTests: XCTestCase {
    /// A stroke as the Pencil gives it (240 samples a second): `place` at each moment of `duration` seconds.
    private func stroke(duration: Double, rate: Double = 240, _ place: (Double) -> Vec3) -> [DrawnMotion.Sample] {
        let count = Int(duration * rate)
        return (0 ... count).map { index in
            let time = Double(index) / rate
            return DrawnMotion.Sample(point: place(time), time: time)
        }
    }

    private func drawn(_ samples: [DrawnMotion.Sample], on id: ObjectID = "c", from start: Double = 1,
                       options: DrawnMotion.Options = DrawnMotion.Options(), document: Document = makeDocument()) throws -> Document {
        var ids = IDFactory.sequential("draw")
        let command = try XCTUnwrap(DrawnMotion.keys(samples, object: id, in: document, from: start, options: options, ids: &ids))
        return try assertReverts(command, on: document)
    }

    private func world(_ id: ObjectID, in document: Document, at time: Double) -> Transform {
        Animator.evaluate(document, at: time).scene.worldTransform(of: id)
    }

    // MARK: Drawing a motion

    func testADrawnPathPlaysWithTheDrawingsTiming() throws {
        // A wavy line drawn slowly, then faster and faster: 1.7 s of drawing.
        let place = { (time: Double) in Vec3(time * time * 2, 0, sin(time * 4) * 0.8) }
        let samples = stroke(duration: 1.7, place)
        let document = try drawn(samples)
        let track = try XCTUnwrap(document.scene.timeline.track(for: "c", .position))
        XCTAssertEqual(track.keyframes.first?.time ?? 0, 1, accuracy: 1e-9, "it starts at the playhead")
        XCTAssertEqual(track.keyframes.last?.time ?? 0, 2.7, accuracy: 1e-9, "it lasts as long as the drawing did")
        XCTAssertLessThan(track.keyframes.count, samples.count / 4, "the keys are only the ones the line needs")
        let fps = Double(document.scene.timeline.fps)
        // The keys keep to the line within 0.2 % of its size (6 m here: 12 mm).
        let tolerance = DrawnMotion.bounds(samples.map(\.point)) * 0.002 + 0.001
        for sample in samples where Int(sample.time * 240) % 7 == 0 {
            // Wherever the Pencil was at a moment, the thing is there within a frame of that moment.
            let moments = stride(from: -1.0, through: 1.0, by: 0.125).map { 1 + sample.time + $0 / fps }
            let nearest = moments.map { world("c", in: document, at: $0).position.distance(to: sample.point) }.min() ?? .infinity
            XCTAssertLessThan(nearest, tolerance, "at \(sample.time) s")
            XCTAssertLessThan(world("c", in: document, at: 1 + sample.time).position.distance(to: sample.point), 0.03)
        }
    }

    func testItFacesTheWayItGoesAndLeansIntoTurns() throws {
        // A circle of 2 m at 4 m/s, counter-clockwise seen from above, on the ground.
        let radius = 2.0
        let speed = 4.0
        let samples = stroke(duration: 2) { time in
            let angle = time * speed / radius
            return Vec3(radius * cos(angle), 0, -radius * sin(angle))
        }
        let document = try drawn(samples, from: 0)
        let expectedBank = atan(speed * speed / radius / DrawnMotion.gravity)
        for time in [0.5, 1.0, 1.5] {
            let turn = world("c", in: document, at: time).rotation
            let angle = time * speed / radius
            let way = Vec3(-sin(angle), 0, -cos(angle))
            let forward = turn.act(.unitZ)
            XCTAssertGreaterThan(forward.dot(way), 0.98, "its front points along the way at \(time) s")
            let up = turn.act(.unitY)
            let inward = Vec3(-cos(angle), 0, sin(angle))
            XCTAssertGreaterThan(up.dot(inward), 0, "its top leans into the turn")
            XCTAssertEqual(asin(up.dot(inward)), min(expectedBank, DrawnMotion.maxBank * .pi / 180), accuracy: 0.06)
        }
        // A character runs the same circle upright, leaning only a little.
        let upright = try drawn(samples, from: 0, options: DrawnMotion.Options(upright: true))
        let lean = asin(world("c", in: upright, at: 1).rotation.act(.unitY).dot(Vec3(-cos(2), 0, sin(2))))
        XCTAssertLessThan(lean, expectedBank * 0.45)
        XCTAssertGreaterThan(lean, 0)
    }

    func testOnASlopeAThingTiltsAndACharacterStaysLevel() throws {
        let samples = stroke(duration: 1) { time in Vec3(0, time, time * 2) }
        let thing = try drawn(samples, from: 0, options: DrawnMotion.Options(banks: false))
        let nose = world("c", in: thing, at: 0.5).rotation.act(.unitZ)
        XCTAssertEqual(nose.y, 1 / 5.0.squareRoot(), accuracy: 0.02, "a thing climbs nose up")
        let person = try drawn(samples, from: 0, options: DrawnMotion.Options(banks: false, upright: true))
        XCTAssertEqual(world("c", in: person, at: 0.5).rotation.act(.unitZ).y, 0, accuracy: 1e-6, "a character stays level")
        let still = try drawn(samples, from: 0, options: DrawnMotion.Options(facesTheWay: false))
        XCTAssertNil(still.scene.timeline.track(for: "c", .rotation), "not facing the way leaves its turn alone")
    }

    func testAStrokeTooShortMakesNothingAndKeysOutsideStay() throws {
        var ids = IDFactory.sequential("draw")
        let tap = stroke(duration: 0.03) { _ in Vec3(1, 0, 0) }
        XCTAssertNil(DrawnMotion.keys(tap, object: "c", in: makeDocument(), from: 0, ids: &ids))
        var document = makeDocument()
        document.scene.timeline.tracks = [Track(id: "t", target: "c", property: .position, keyframes: [
            Keyframe(time: 0, value: .vec3(Vec3(-2, 0, 1))), Keyframe(time: 1.5, value: .vec3(Vec3(0, 0, 0))),
            Keyframe(time: 8, value: .vec3(Vec3(5, 0, 5)))
        ])]
        let samples = stroke(duration: 1) { time in Vec3(time, 0, 0) }
        let result = try drawn(samples, from: 1, document: document)
        let keys = try XCTUnwrap(result.scene.timeline.track(for: "c", .position)).keyframes
        XCTAssertTrue(keys.contains { $0.time == 0 }, "a key before the stretch stays")
        XCTAssertTrue(keys.contains { $0.time == 8 }, "a key after it stays")
        XCTAssertFalse(keys.contains { abs($0.time - 1.5) < 1e-9 && $0.value == .vec3(Vec3(0, 0, 0)) }, "the one inside it goes")
    }

    func testTheTimelineGrowsToHoldTheMotionAndChildrenDrawInWorldSpace() throws {
        let samples = stroke(duration: 3) { time in Vec3(time, 1, 0) }
        let longer = try drawn(samples, on: "b", from: 9)
        XCTAssertEqual(longer.scene.timeline.duration, 13, "10 s grow to hold 9 + 3 s")
        // b sits under a (at x 1, half size): its keys are in a's space, its world place is the drawing.
        XCTAssertEqual(world("b", in: longer, at: 10.5).position.x, 1.5, accuracy: 0.01)
        XCTAssertEqual(world("b", in: longer, at: 10.5).position.y, 1, accuracy: 0.01)
    }

    func testEvenSpeedRetimingAndTurningTheFront() throws {
        // Slow for the first half of the way, fast for the rest.
        let samples = stroke(duration: 2) { time in Vec3(time < 1.5 ? time : 1.5 + (time - 1.5) * 6, 0, 0) }
        let document = try drawn(samples, from: 0)
        let even = try assertReverts(XCTUnwrap(DrawnMotion.evenSpeed("c", in: document.scene.timeline)), on: document)
        let start = world("c", in: even, at: 0).position.x
        let end = world("c", in: even, at: 2).position.x
        for time in [0.5, 1.0, 1.5] {
            XCTAssertEqual(world("c", in: even, at: time).position.x, start + (end - start) * time / 2, accuracy: 0.03)
        }
        let slower = try assertReverts(XCTUnwrap(DrawnMotion.retiming("c", to: 4, in: document.scene.timeline)), on: document)
        XCTAssertEqual(DrawnMotion.span(of: "c", in: slower.scene.timeline)?.end ?? 0, 4, accuracy: 1e-9)
        XCTAssertEqual(world("c", in: slower, at: 2).position.x, world("c", in: document, at: 1).position.x, accuracy: 0.01)
        let turned = try assertReverts(XCTUnwrap(DrawnMotion.turningFront("c", quarterTurns: 1, in: document.scene.timeline)), on: document)
        let side = world("c", in: turned, at: 0.5).rotation.act(.unitX)
        XCTAssertGreaterThan(side.dot(Vec3(-1, 0, 0)), 0.98, "a quarter turn puts its right side where its front was")
    }
}

// MARK: Holding

extension AnimateTests {
    /// "a" (the hand) moves from x 0 to 4 over 4 s; "c" (the cup) stands at (-2, 0, 1).
    private func handScene() -> Document {
        var document = makeDocument()
        document.scene.timeline.tracks = [Track(id: "hand", target: "a", property: .position, keyframes: [
            Keyframe(time: 0, value: .vec3(Vec3(0, 0, 0)), easing: .linear), Keyframe(time: 4, value: .vec3(Vec3(4, 0, 0)))
        ])]
        return document
    }

    private func pickUp(_ target: ObjectID, by holder: ObjectID, joint: String? = nil, at time: Double, in document: Document) throws -> Document {
        var ids = IDFactory.sequential("hold")
        let command = try XCTUnwrap(HoldOperations.pickUp(target, by: holder, joint: joint, at: time, shown: Animator.evaluate(document, at: time),
                                                          timeline: document.scene.timeline, ids: &ids))
        return try assertReverts(command, on: document)
    }

    func testAPickedUpThingRidesItsHolderAndStaysWhereItIsPutDown() throws {
        let held = try pickUp("c", by: "a", at: 1, in: handScene())
        XCTAssertEqual(world("c", in: held, at: 0.5).position, Vec3(-2, 0, 1), "before the pick-up it stands where it was")
        XCTAssertEqual(world("c", in: held, at: 1).position.x, -2, accuracy: 1e-9, "it doesn't jump when picked up")
        XCTAssertEqual(world("c", in: held, at: 3).position.x, 0, accuracy: 1e-9, "it rides the hand: 2 m further")
        var ids = IDFactory.sequential("down")
        let down = try assertReverts(XCTUnwrap(HoldOperations.putDown("c", at: 2.5, timeline: held.scene.timeline, ids: &ids)), on: held)
        XCTAssertEqual(world("c", in: down, at: 3.5).position.x, -0.5, accuracy: 1e-9, "put down where the hand had it at 2.5 s")
        XCTAssertEqual(world("c", in: down, at: 2.5).position.x, -0.5, accuracy: 1e-9)
        XCTAssertNil(HoldOperations.putDown("c", at: 3, timeline: down.scene.timeline, ids: &ids), "it isn't held then")
        XCTAssertEqual(HoldOperations.holder(of: "c", at: 2, in: down.scene.timeline)?.holder, "a")
        XCTAssertNil(HoldOperations.holder(of: "c", at: 3, in: down.scene.timeline))
    }

    func testAHandOffPassesItOnAndNothingHoldsItself() throws {
        var document = try pickUp("c", by: "a", at: 1, in: handScene())
        // "b" is a's child; give c to a thing of its own that stays: a new sphere "d" at the origin.
        var d = SceneObject(id: "d", name: "D", kind: .primitive(.sphere), transform: Transform(position: Vec3(0, 2, 0)))
        d.children = []
        document.scene.objects["d"] = d
        document.scene.roots.append("d")
        let handed = try pickUp("c", by: "d", at: 2, in: document)
        let atHandOff = world("c", in: handed, at: 2).position
        XCTAssertEqual(world("c", in: handed, at: 3.5).position.x, atHandOff.x, accuracy: 1e-9, "after the hand-off it stays with d")
        XCTAssertEqual(handed.scene.timeline.holds.count, 2)
        var ids = IDFactory.sequential("loop")
        let shown = Animator.evaluate(handed, at: 3)
        XCTAssertNil(HoldOperations.pickUp("d", by: "c", at: 3, shown: shown, timeline: handed.scene.timeline, ids: &ids),
                     "d can't be held by the cup it holds")
        XCTAssertNil(HoldOperations.pickUp("a", by: "b", at: 3, shown: shown, timeline: handed.scene.timeline, ids: &ids),
                     "a can't be held by its own child")
        // Deleting the holder takes its holds with it.
        let deleted = try assertReverts(XCTUnwrap(Operations().delete(["d"], in: handed.scene)), on: handed)
        XCTAssertEqual(deleted.scene.timeline.holds.map(\.holder), ["a"])
    }

    func testAJointHoldsWhatItPicksUp() throws {
        var document = makeDocument()
        var arm = SceneObject(id: "arm", name: "Arm", kind: .primitive(.cube))
        arm.rig = ObjectRig(names: ["shoulder", "hand"], parents: [nil, 0], positions: [.zero, Vec3(1, 0, 0)])
        document.scene.objects["arm"] = arm
        document.scene.roots.append("arm")
        // The cup sits on the hand, a little above it.
        document.scene.objects["c"]?.transform.position = Vec3(1, 0.1, 0)
        let held = try pickUp("c", by: "arm", joint: "hand", at: 0, in: document)
        // Turning the shoulder a quarter turn about y swings the hand from +x to −z.
        var turned = held
        turned.scene.objects["arm"]?[.boneTurn("shoulder")] = .quat(Quat(angle: .pi / 2, axis: .unitY))
        let place = world("c", in: turned, at: 0.5).position
        XCTAssertEqual(place.x, 0, accuracy: 1e-6)
        XCTAssertEqual(place.z, -1, accuracy: 1e-6)
        XCTAssertEqual(place.y, 0.1, accuracy: 1e-6)
        let shown = Animator.evaluate(document, at: 0)
        XCTAssertEqual(HoldOperations.nearestJoint(to: Vec3(0.9, 0, 0), of: "arm", in: shown), "hand")
    }

    func testHoldsSurviveTheProjectFile() throws {
        let held = try pickUp("c", by: "a", at: 1, in: handScene())
        let data = try LoweyJSON.encode(held.scene.timeline)
        XCTAssertEqual(try LoweyJSON.decode(Timeline.self, from: data), held.scene.timeline)
        XCTAssertTrue(held.scene.timeline.animatedObjects.contains("c"))
        let empty = try LoweyJSON.encode(Timeline())
        XCTAssertFalse(String(decoding: empty, as: UTF8.self).contains("holds"), "no holds, no key")
    }
}

// MARK: Looking

extension AnimateTests {
    func testAThingTurnsToWhatItLooksAtAndAKeyedSwitchTurnsOverAQuarterSecond() throws {
        var ids = IDFactory.sequential("look")
        let document = makeDocument()
        let looking = try assertReverts(XCTUnwrap(LookAtOperations.look("c", at: "a", at: 0, in: document.scene, ids: &ids)), on: document)
        let forward = world("c", in: looking, at: 0).rotation.act(.unitZ)
        let toA = (Vec3(1, 0, 0) - Vec3(-2, 0, 1)).normalized
        XCTAssertGreaterThan(forward.dot(toA), 0.999)
        // From 2 s on it watches b (at 1, 1, 0): halfway through the turn it looks between them.
        let switched = try assertReverts(XCTUnwrap(LookAtOperations.switchLook("c", to: "b", at: 2, in: looking.scene, ids: &ids)), on: looking)
        let toB = (Vec3(1, 1, 0) - Vec3(-2, 0, 1)).normalized
        XCTAssertGreaterThan(world("c", in: switched, at: 1.9).rotation.act(.unitZ).dot(toA), 0.999)
        XCTAssertGreaterThan(world("c", in: switched, at: 2.3).rotation.act(.unitZ).dot(toB), 0.999)
        let middle = world("c", in: switched, at: 2.125).rotation.act(.unitZ)
        XCTAssertLessThan(middle.dot(toB), 0.9999)
        XCTAssertGreaterThan(middle.dot(toB), middle.dot(toA) - 0.2)
    }

    func testAPersonTurnsTheirHeadNotTheirBody() throws {
        var ids = IDFactory.sequential("p")
        let fragment = CharacterMaker.start(.person, name: "Pat", at: .zero, ids: &ids)
        var document = try assertReverts(.insert(fragment, parent: nil, index: nil), on: makeDocument())
        let root = fragment.roots[0]
        let anatomy = try XCTUnwrap(CharacterAnatomy(root, in: document.scene))
        let rig = CharacterAutoRig.rig(CharacterAutoRig.marks(anatomy))
        var commands: [EditCommand] = [.setRig(root, rig)]
        let binding = RigidParts.binding(root, rig: rig, in: document.scene)
        if !binding.isEmpty { commands.append(.setProperties(binding)) }
        document = try assertReverts(.batch("Rig", commands), on: document)
        let head = try XCTUnwrap(document.scene.subtree(of: root).first { document.scene.objects[$0]?.part?.job == .head })
        let headBefore = world(head, in: document, at: 0).rotation
        // The person faces +z; the target stands off to their left (+x is their left when facing +z? it's to the side).
        document.scene.objects["c"]?.transform.position = Vec3(3, 1.5, 1)
        let looking = try assertReverts(XCTUnwrap(LookAtOperations.look(root, at: "c", at: 0, in: document.scene, ids: &ids)), on: document)
        XCTAssertEqual(world(root, in: looking, at: 0).rotation, world(root, in: document, at: 0).rotation, "the body stays")
        let headAfter = world(head, in: looking, at: 0).rotation
        XCTAssertGreaterThan(DrawnMotion.angle(between: headBefore, and: headAfter), 0.3, "the head turned")
        XCTAssertGreaterThan(headAfter.act(.unitZ).x, headBefore.act(.unitZ).x, "toward the target's side")
    }
}

// MARK: What 3D files keep

extension AnimateTests {
    func testHoldsBehavioursAndLooksBecomeKeysForFiles() throws {
        var document = try pickUp("c", by: "a", at: 1, in: handScene())
        document.scene.timeline.duration = 4
        document.scene.timeline.behaviors = [Behavior(id: "spin", target: "b", kind: .spin(degreesPerSecond: 90, axis: .y), start: 0, end: nil)]
        let baked = MotionBake.baked(document)
        XCTAssertTrue(baked.scene.timeline.holds.isEmpty)
        XCTAssertTrue(baked.scene.timeline.behaviors.isEmpty)
        XCTAssertNotNil(baked.scene.timeline.track(for: "c", .position))
        XCTAssertNotNil(baked.scene.timeline.track(for: "b", .rotation))
        for time in [0.5, 1.5, 2.25, 3.9] {
            XCTAssertLessThan(world("c", in: baked, at: time).position.distance(to: world("c", in: document, at: time).position), 0.002)
            XCTAssertLessThan(DrawnMotion.angle(between: world("b", in: baked, at: time).rotation, and: world("b", in: document, at: time).rotation),
                              0.01)
        }
        XCTAssertEqual(MotionBake.baked(makeDocument()), makeDocument(), "nothing to bake, nothing changes")
    }
}

// MARK: The bridge

extension AnimateTests {
    private func script(_ json: String, on document: Document = makeDocument()) throws -> ScriptResult {
        let script = try LoweyJSON.decode(SceneScript.self, from: Data(json.utf8))
        return try ScriptCompiler.compile(ScriptMigration.upgraded(script), document: document, context: ScriptContext(ids: .sequential("m")))
    }

    func testTheBridgeDrawsPathsHoldsAndLooks() throws {
        let result = try script("""
        {"version": 3, "title": "Motion", "actions": [
          {"do": "motion", "op": "path", "target": "C", "points": [[0, 0, 0], [3, 0, 0], [3, 0, 3]], "times": [0, 1, 3], "at": 1},
          {"do": "motion", "op": "pickUp", "target": "A", "by": "C", "at": 2},
          {"do": "motion", "op": "putDown", "target": "A", "at": 3},
          {"do": "motion", "op": "lookAt", "target": "B", "at": "C"},
          {"do": "motion", "op": "timing", "target": "C", "duration": 6}
        ]}
        """)
        let document = result.document
        XCTAssertNotNil(result.command, "one undo step")
        XCTAssertEqual(DrawnMotion.span(of: "c", in: document.scene.timeline)?.end ?? 0, 7, accuracy: 1e-9, "the motion lasts 6 s from 1 s")
        XCTAssertEqual(document.scene.timeline.holds.count, 2)
        XCTAssertEqual(document.scene.objects["b"]?[.lookAt], .string("c"))
        XCTAssertThrowsError(try script("""
        {"version": 3, "title": "Bad", "actions": [{"do": "motion", "op": "pickUp", "target": "A", "by": "B", "at": 0}]}
        """), "a can't be held by its own child")
        XCTAssertThrowsError(try script("""
        {"version": 3, "title": "Bad", "actions": [{"do": "motion", "op": "path", "target": "C", "points": [[0, 0, 0]]}]}
        """))
    }
}
