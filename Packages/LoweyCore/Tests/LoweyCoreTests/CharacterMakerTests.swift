@testable import LoweyCore
import XCTest

/// K1: characters made from parts, rigged by themselves, with face states and proportions by hand.
final class CharacterMakerTests: XCTestCase {
    private func started(_ start: CharacterStart) throws -> (Document, ObjectID) {
        var ids = IDFactory.sequential("c")
        let fragment = CharacterMaker.start(start, name: start.title, at: Vec3(1, 0, 0), ids: &ids)
        let document = try assertReverts(.insert(fragment, parent: nil, index: nil), on: makeDocument())
        return (document, fragment.roots[0])
    }

    /// Every piece's world bounds, lowest point first.
    private func lowest(_ root: ObjectID, in scene: Scene) -> Double {
        let anatomy = CharacterAnatomy(root, in: scene)
        let world = scene.worldTransform(of: root)
        return anatomy?.pieces.compactMap(\.rootBounds).map { world.apply(to: $0.min).y }.min() ?? .infinity
    }

    private func rigged(_ document: Document, _ root: ObjectID) throws -> (Document, ObjectRig) {
        let anatomy = try XCTUnwrap(CharacterAnatomy(root, in: document.scene))
        let rig = CharacterAutoRig.rig(CharacterAutoRig.marks(anatomy))
        var commands: [EditCommand] = [.setRig(root, rig)]
        let binding = RigidParts.binding(root, rig: rig, in: document.scene)
        if !binding.isEmpty { commands.append(.setProperties(binding)) }
        return try (assertReverts(.batch("Rig", commands), on: document), rig)
    }

    private func piece(_ scene: Scene, _ root: ObjectID, _ job: CharacterPart.Job, side: CharacterPart.Side = .middle, segment: Int = 0,
                       limb: String = "") -> ObjectID? {
        scene.subtree(of: root).first { id in
            guard let part = scene.objects[id]?.part else { return false }
            return part.job == job && part.side == side && part.segment == segment && part.limb == limb
        }
    }

    func testAPersonStandsOnTheGroundAndRigsAsAHumanoid() throws {
        let (document, root) = try started(.person)
        let scene = document.scene
        XCTAssertEqual(scene.objects[root]?[.characterStart], .enumeration("person"))
        XCTAssertEqual(lowest(root, in: scene), 0, accuracy: 0.02, "the feet stand on the ground")
        let (rigged, rig) = try rigged(document, root)
        XCTAssertEqual(rig.standard, .humanoid, "a person's joints are the humanoid standard")
        XCTAssertTrue(CharacterAutoRig.humanoidJoints.isSubset(of: Set(rig.skeleton.names)))
        // Each piece rides the joint of its bone.
        let ride = { (id: ObjectID?) in id.flatMap { rigged.scene.objects[$0]?[.attachBone]?.stringValue } }
        XCTAssertEqual(ride(piece(rigged.scene, root, .arm, side: .left, segment: 0)), "leftUpperArm")
        XCTAssertEqual(ride(piece(rigged.scene, root, .arm, side: .left, segment: 1)), "leftLowerArm")
        XCTAssertEqual(ride(piece(rigged.scene, root, .arm, side: .right, segment: 2)), "rightHand")
        XCTAssertEqual(ride(piece(rigged.scene, root, .leg, side: .left, segment: 1)), "leftLowerLeg")
        XCTAssertEqual(ride(piece(rigged.scene, root, .leg, side: .right, segment: 2)), "rightFoot")
        XCTAssertEqual(ride(piece(rigged.scene, root, .head)), "head")
        // The face sits on the head and the eyes blink through the face rig.
        let head = try XCTUnwrap(piece(scene, root, .head))
        let eye = try XCTUnwrap(piece(scene, root, .eye, side: .left))
        XCTAssertEqual(scene.objects[eye]?.parent, head)
        XCTAssertEqual(scene.objects[eye]?[.faceRole], .string("eye.L"))
        XCTAssertTrue(scene.objects[eye]?.children.contains { scene.objects[$0]?[.faceRole] == .string("pupil.L") } ?? false)
        // A humanoid clip plays on it.
        var animated = rigged
        let walk = ClipSegment(id: "walk", clip: ClipRef(asset: BuiltinClips.assetID, name: "Walk"), start: 0, duration: 2)
        animated.scene.timeline.clipTracks.append(ClipTrack(id: "clips", target: root, segments: [walk]))
        let pose = Animator.evaluate(animated, at: 0.5).poses[root]
        XCTAssertNotNil(pose, "the walk poses the made person")
    }

    func testFourLegsRigLikeAnAnimal() throws {
        let (document, root) = try started(.fourLegs)
        XCTAssertEqual(lowest(root, in: document.scene), 0, accuracy: 0.02)
        let anatomy = try XCTUnwrap(CharacterAnatomy(root, in: document.scene))
        XCTAssertTrue(anatomy.walksOnFour)
        XCTAssertEqual(anatomy.limbs(.leg).count, 4)
        let (rigged, rig) = try rigged(document, root)
        let names = Set(rig.skeleton.names)
        for name in ["hips", "shoulders", "neck", "head", "frontLeftLeg", "frontRightKnee", "backLeftFoot", "tail", "tailTip"] {
            XCTAssertTrue(names.contains(name), name)
        }
        XCTAssertEqual(rig.standard, .custom)
        let ride = piece(rigged.scene, root, .leg, side: .right, segment: 0, limb: "back").flatMap { rigged.scene.objects[$0]?[.attachBone]?.stringValue }
        XCTAssertEqual(ride, "backRightLeg")
    }

    func testABodylessEyeCreatureHasOneJointAndTalks() throws {
        let (document, root) = try started(.nothing)
        var ids = IDFactory.sequential("p")
        let eye = try XCTUnwrap(CharacterMaker.add(.eye, to: root, in: document.scene, ids: &ids))
        var working = try assertReverts(eye.command, on: document)
        XCTAssertEqual(eye.made.count, 1, "a bodyless creature's first eye is one big eye")
        XCTAssertEqual(working.scene.objects[eye.made[0]]?.part?.style, "big")
        let mouth = try XCTUnwrap(CharacterMaker.add(.mouth, to: root, in: working.scene, ids: &ids))
        working = try assertReverts(mouth.command, on: working)
        let eyeY = working.scene.worldTransform(of: eye.made[0]).position.y
        XCTAssertLessThan(working.scene.worldTransform(of: mouth.made[0]).position.y, eyeY, "the mouth goes under the eye")
        let (rigged, rig) = try rigged(working, root)
        XCTAssertEqual(rig.skeleton.names, [RigMarks.rootName])
        // A typed line lip-syncs it: the 14 shapes are keyed and the mouth bends.
        let line = try XCTUnwrap(LipSync.line("Hello there, wonderful world.", character: root, from: 0.2, language: "en-US",
                                              timeline: rigged.scene.timeline, ids: &ids))
        let talking = try assertReverts(line, on: rigged)
        let shapes = try XCTUnwrap(talking.scene.timeline.track(for: root, .mouthShape))
        XCTAssertGreaterThan(Set(shapes.keyframes.map(\.value)).count, 4, "several of the 14 shapes")
        let open = shapes.keyframes.first { $0.value != .enumeration("neutral") && $0.value != .enumeration("m") }
        let evaluated = try Animator.evaluate(talking, at: XCTUnwrap(open).time + 0.01)
        XCTAssertNotNil(evaluated.simulated.meshes[mouth.made[0]], "the mouth shows its state, bent")
        let end = try XCTUnwrap(shapes.keyframes.last).time
        XCTAssertNil(Animator.evaluate(talking, at: end + 0.5).simulated.meshes[mouth.made[0]], "at rest the mouth is as made")
    }

    func testPartsAttachToAnyThing() throws {
        var document = makeDocument()
        var ids = IDFactory.sequential("t")
        let cube = SceneObject(id: ids.next(), name: "Teapot", kind: .primitive(.cube), transform: Transform(position: Vec3(2, 0, 0)))
        document = try assertReverts(.insert(SceneFragment(object: cube), parent: nil, index: nil), on: document)
        let arms = try XCTUnwrap(CharacterMaker.add(.arm, to: cube.id, in: document.scene, ids: &ids))
        let after = try assertReverts(arms.command, on: document)
        XCTAssertNotEqual(arms.root, cube.id)
        XCTAssertEqual(after.scene.objects[cube.id]?.parent, arms.root, "the thing became the body of a new character")
        XCTAssertEqual(after.scene.objects[cube.id]?.part?.job, .body)
        XCTAssertEqual(after.scene.worldTransform(of: cube.id).position.x, 2, accuracy: 1e-9, "it stays where it was")
        XCTAssertEqual(arms.made.count, 6, "a pair of arms, three pieces each")
        let left = try XCTUnwrap(piece(after.scene, arms.root, .arm, side: .left))
        XCTAssertGreaterThan(after.scene.worldTransform(of: left).position.x, 2.3, "on the thing's left side")
        // Eyes go on its front, since it has no head.
        let eyes = try XCTUnwrap(CharacterMaker.add(.eye, to: arms.root, in: after.scene, ids: &ids))
        let seeing = try assertReverts(eyes.command, on: after)
        XCTAssertEqual(seeing.scene.objects[eyes.made[0]]?.parent, cube.id)
    }

    func testAPartAddedAgainIsAnotherOne() throws {
        let (document, root) = try started(.person)
        var ids = IDFactory.sequential("r")
        let arms = try XCTUnwrap(CharacterMaker.add(.arm, to: root, in: document.scene, ids: &ids))
        let after = try assertReverts(arms.command, on: document)
        XCTAssertEqual(CharacterAnatomy(root, in: after.scene)?.limbs(.arm).count, 4)
        XCTAssertNotNil(piece(after.scene, root, .arm, side: .left, limb: "2"))
        let (_, rig) = try rigged(after, root)
        XCTAssertTrue(rig.skeleton.names.contains("leftUpperArm2"))
    }

    func testLongerLegsKeepTheFeetOnTheGround() throws {
        let (document, root) = try started(.person)
        let anatomy = try XCTUnwrap(CharacterAnatomy(root, in: document.scene))
        let before = CharacterProportions.measure(anatomy)
        let command = try XCTUnwrap(CharacterProportions.change(.legs, by: 1.5, anatomy: anatomy, scene: document.scene))
        let after = try assertReverts(command, on: document)
        let measured = try CharacterProportions.measure(XCTUnwrap(CharacterAnatomy(root, in: after.scene)))
        XCTAssertEqual(lowest(root, in: after.scene), 0, accuracy: 0.02, "the feet stay on the ground")
        XCTAssertGreaterThan(try XCTUnwrap(measured[.legs]), try XCTUnwrap(before[.legs]) * 1.3)
        XCTAssertGreaterThan(try XCTUnwrap(measured[.height]), try XCTUnwrap(before[.height]))
        let head = try XCTUnwrap(CharacterProportions.change(.head, by: 1.25, anatomy: anatomy, scene: document.scene))
        let bigger = try assertReverts(head, on: document)
        XCTAssertEqual(try CharacterProportions.measure(XCTUnwrap(CharacterAnatomy(root, in: bigger.scene)))[.head] ?? 0,
                       (before[.head] ?? 0) * 1.25, accuracy: 1e-6)
    }

    func testFaceStatesBendThePart() throws {
        let mouth = PartSet.mesh(.mouth, style: "oval")
        let bounds = try XCTUnwrap(mouth.bounds)
        let oh = try XCTUnwrap(FaceStates.defaultBend(.mouth, "oh").bend(mouth, bounds: bounds, side: 0).bounds)
        XCTAssertGreaterThan(oh.size.y, bounds.size.y * 1.5, "Oh opens")
        XCTAssertLessThan(oh.size.x, bounds.size.x, "and rounds")
        let brow = PartSet.mesh(.brow, style: "line")
        let browBounds = try XCTUnwrap(brow.bounds)
        let angry = FaceStates.defaultBend(.brow, "angry")
        // The left brow's inner end (toward the middle, −x) drops.
        let inner = angry.bend(Vec3(browBounds.min.x, browBounds.center.y, 0), bounds: browBounds, side: 1)
        let outer = angry.bend(Vec3(browBounds.max.x, browBounds.center.y, 0), bounds: browBounds, side: 1)
        XCTAssertLessThan(inner.y, outer.y)
        XCTAssertEqual(FaceStates.names(for: .mouth).count, 14)
        XCTAssertEqual(MouthShape.reading(jaw: 0.9, wide: 0, smile: 0, brows: 0.8), .surprised)
        XCTAssertEqual(Phonemizer.shared.shapes(for: "hello", language: "en-US").map(\.0), [.uh, .uh, .l, .oh])
        XCTAssertEqual(Phonemizer.shared.shapes(for: "shoe", language: "en-US").map(\.0), [.s, .wOo])
    }

    func testAChangedStateAndADrawnStateShow() throws {
        let (document, root) = try started(.person)
        let mouth = try XCTUnwrap(piece(document.scene, root, .mouth))
        let wide = FaceBend(open: 0.2, wide: 0.9)
        let command = try XCTUnwrap(CharacterMaker.setState("ee", of: mouth, to: wide, mirrored: true, in: document.scene))
        var working = try assertReverts(command, on: document)
        XCTAssertEqual(working.scene.objects[mouth]?.part?.states["ee"], wide)
        // A drawn Oh: shown only while the mouth says Oh, in the mouth's place.
        var ids = IDFactory.sequential("d")
        let drawing = SceneObject(id: ids.next(), name: "Oh", kind: .primitive(.sphere))
        working = try assertReverts(.insert(SceneFragment(object: drawing), parent: nil, index: nil), on: working)
        let assign = try XCTUnwrap(CharacterMaker.assign(drawing.id, as: .mouth, shows: "oh", character: root, in: working.scene))
        working = try assertReverts(assign, on: working)
        working.scene.objects[root]?[.mouthShape] = .enumeration("oh")
        let saying = Animator.evaluate(working, at: 0).scene
        XCTAssertEqual(saying.objects[drawing.id]?.isVisible, true)
        XCTAssertEqual(saying.objects[mouth]?.isVisible, false)
        working.scene.objects[root]?[.mouthShape] = .enumeration("ah")
        let other = Animator.evaluate(working, at: 0).scene
        XCTAssertEqual(other.objects[drawing.id]?.isVisible, false)
        XCTAssertEqual(other.objects[mouth]?.isVisible, true)
    }

    func testRestyleAndRemove() throws {
        let (document, root) = try started(.person)
        var ids = IDFactory.sequential("s")
        let leg = try XCTUnwrap(piece(document.scene, root, .leg, side: .left))
        let restyle = try XCTUnwrap(CharacterMaker.restyle(leg, to: "stubby", mirrored: true, in: document.scene, ids: &ids))
        let stubby = try assertReverts(restyle, on: document)
        let pieces = CharacterMaker.partPieces(of: leg, in: stubby.scene, mirrored: true)
        XCTAssertEqual(pieces.count, 6)
        XCTAssertTrue(pieces.allSatisfy { stubby.scene.objects[$0]?.part?.style == "stubby" })
        let eye = try XCTUnwrap(piece(document.scene, root, .eye, side: .right))
        let removed = try assertReverts(CharacterMaker.remove(eye, mirrored: true, in: document.scene), on: document)
        XCTAssertTrue(CharacterAnatomy(root, in: removed.scene)?.pieces(.eye).isEmpty ?? false)
    }

    func testActingOutPointsTheBones() throws {
        let (document, root) = try started(.person)
        let (rigged, rig) = try rigged(document, root)
        // Standing, the left arm straight out to the side.
        var joints: [ActOut.BodyJoint: Vec3] = [
            .root: Vec3(0, 1, 0), .spine: Vec3(0, 1.2, 0), .centerShoulder: Vec3(0, 1.45, 0), .centerHead: Vec3(0, 1.6, 0),
            .topHead: Vec3(0, 1.75, 0), .leftShoulder: Vec3(0.18, 1.45, 0), .leftElbow: Vec3(0.45, 1.45, 0), .leftWrist: Vec3(0.7, 1.45, 0),
            .rightShoulder: Vec3(-0.18, 1.45, 0), .rightElbow: Vec3(-0.2, 1.18, 0), .rightWrist: Vec3(-0.21, 0.92, 0),
            .leftHip: Vec3(0.1, 1, 0), .rightHip: Vec3(-0.1, 1, 0), .leftKnee: Vec3(0.1, 0.55, 0), .rightKnee: Vec3(-0.1, 0.55, 0),
            .leftAnkle: Vec3(0.1, 0.1, 0), .rightAnkle: Vec3(-0.1, 0.1, 0)
        ]
        let turns = ActOut.pose(ActOut.Frame(time: 0, joints: joints), rig: rig)
        var local = rig.skeleton.restPose
        for (index, joint) in rig.skeleton.joints.enumerated() {
            if let turn = turns[joint.name] { local[index].rotation = turn }
        }
        let model = rig.skeleton.modelSpace(local)
        let upper = try XCTUnwrap(rig.skeleton.index(of: "leftUpperArm")), lower = try XCTUnwrap(rig.skeleton.index(of: "leftLowerArm"))
        let direction = (model[lower].position - model[upper].position).normalized
        XCTAssertGreaterThan(direction.x, 0.95, "the upper arm points out to the side")
        // Frames over time become keys, and the character travels with the hips.
        var frames: [ActOut.Frame] = []
        for step in 0 ..< 10 {
            joints[.root] = Vec3(0, 1, Double(step) * 0.05)
            frames.append(ActOut.Frame(time: Double(step) / 10, joints: joints))
        }
        var ids = IDFactory.sequential("a")
        let object = try XCTUnwrap(rigged.scene.objects[root])
        let keys = try XCTUnwrap(ActOut.keys(frames, rig: rig, character: object, from: 1, mirrored: false, timeline: rigged.scene.timeline, ids: &ids))
        let acted = try assertReverts(keys, on: rigged)
        XCTAssertEqual(acted.scene.timeline.track(for: root, .boneTurn("leftUpperArm"))?.keyframes.count, 10)
        XCTAssertNotNil(acted.scene.timeline.track(for: root, .position))
    }

    func testTheBridgeMakesACharacter() throws {
        var context = ScriptContext(ids: .sequential("b"))
        context.mesh = { _ in nil }
        let actions = """
        {"do": "character", "op": "new", "start": "nothing", "name": "Peeper"},
         {"do": "character", "op": "add", "target": "Peeper", "part": "eye"},
         {"do": "character", "op": "add", "target": "Peeper", "part": "mouth", "style": "grin"},
         {"do": "character", "op": "say", "target": "Peeper", "line": "Look at me!", "at": 0.5},
         {"do": "character", "op": "new", "start": "fourLegs", "name": "Biscuit", "at": [2, 0, 0]},
         {"do": "character", "op": "proportion", "target": "Biscuit", "measure": "legs", "by": 1.2},
         {"do": "character", "op": "state", "target": "Mouth", "state": "oh", "bend": {"open": 1.4}}
        """
        let script = try LoweyJSON.decode(SceneScript.self, from: Data("{\"version\": 3, \"title\": \"T\", \"actions\": [\(actions)]}".utf8))
        let result = try ScriptCompiler.compile(script, document: makeDocument(), context: context)
        let applied = try assertReverts(XCTUnwrap(result.command), on: makeDocument())
        let peeper = try XCTUnwrap(applied.scene.objects.values.first { $0.name == "Peeper" })
        XCTAssertEqual(peeper.rig?.skeleton.names, [RigMarks.rootName], "rigged by itself")
        XCTAssertNotNil(applied.scene.timeline.track(for: peeper.id, .mouthShape))
        let biscuit = try XCTUnwrap(applied.scene.objects.values.first { $0.name == "Biscuit" })
        XCTAssertTrue(biscuit.rig?.skeleton.names.contains("frontLeftLeg") ?? false)
        XCTAssertEqual(lowest(biscuit.id, in: applied.scene), 0, accuracy: 0.02)
        XCTAssertEqual(applied.scene.objects.values.first { $0.part?.job == .mouth && $0.part?.style == "grin" }?.part?.states["oh"]?.open, 1.4)
    }
}
