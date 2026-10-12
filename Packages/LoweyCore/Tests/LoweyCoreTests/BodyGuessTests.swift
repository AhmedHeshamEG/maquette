import Foundation
@testable import LoweyCore
import XCTest

/// SPIKE (U4 step 3): can the body shortcuts guess where the joints are from the shape alone? A person is checked on
/// the Kit's astronaut; four legs and wings on made animals, turned both ways. A guess passes when every dot lands within
/// a tenth of the body's size of where it belongs. Where a guess can't see the body it says so, and the standard layout
/// stands in.
final class BodyGuessTests: XCTestCase {
    static func box(_ centre: Vec3, _ size: Vec3) -> MeshData {
        RigSamples.box(centre: centre, size: size, steps: 4)
    }

    /// A dog-like animal along `axis` (x or z), its head at the + end unless `headBack`: a body, four legs, a raised
    /// head, a tail behind.
    static func animal(along axis: Vec3, headBack: Bool = false) -> (mesh: MeshData, joints: [String: Vec3]) {
        let ahead = headBack ? -1.0 : 1.0
        // The animal's right, as it faces.
        let across = (axis * ahead).cross(.unitY)
        func at(_ forward: Double, _ side: Double, _ up: Double) -> Vec3 { axis * (forward * ahead) + across * side + Vec3(0, up, 0) }
        func sized(_ forward: Double, _ side: Double, _ up: Double) -> Vec3 { axis.absolute * forward + across.absolute * side + Vec3(0, up, 0) }
        var mesh = box(at(0, 0, 0.75), sized(1.2, 0.45, 0.4))
        var joints: [String: Vec3] = [:]
        for (end, forward) in [("front", 0.45), ("back", -0.45)] {
            for (side, offset) in [("Right", 0.15), ("Left", -0.15)] {
                mesh.append(box(at(forward, offset, 0.3), sized(0.12, 0.12, 0.6)))
                joints["\(end)\(side)Foot"] = at(forward, offset, 0.02)
            }
        }
        mesh.append(box(at(0.75, 0, 1.05), sized(0.35, 0.25, 0.3)))
        joints["head"] = at(0.7, 0, 1.0)
        mesh.append(box(at(-0.85, 0, 0.85), sized(0.5, 0.06, 0.06)))
        joints["tailTip"] = at(-1.1, 0, 0.85)
        return (mesh, joints)
    }

    /// A bird facing +z: a body, two thin wings spread across x, a head in front.
    static func bird() -> (mesh: MeshData, joints: [String: Vec3]) {
        var mesh = box(Vec3(0, 0.5, 0), Vec3(0.3, 0.3, 0.6))
        mesh.append(box(Vec3(0.65, 0.55, 0), Vec3(1.0, 0.03, 0.3)))
        mesh.append(box(Vec3(-0.65, 0.55, 0), Vec3(1.0, 0.03, 0.3)))
        mesh.append(box(Vec3(0, 0.6, 0.4), Vec3(0.15, 0.15, 0.2)))
        return (mesh, ["leftWingTip": Vec3(1.15, 0.55, 0), "rightWingTip": Vec3(-1.15, 0.55, 0), "leftWing": Vec3(0.17, 0.55, 0),
                       "head": Vec3(0, 0.6, 0.4)])
    }

    func assertNear(_ marks: [RigMark], _ joints: [String: Vec3], within: Double, file: StaticString = #filePath, line: UInt = #line) {
        for (name, point) in joints {
            guard let mark = marks.first(where: { $0.name == name }) else {
                XCTFail("no \(name)", file: file, line: line)
                continue
            }
            XCTAssertLessThan(mark.position.distance(to: point), within, "\(name) at \(mark.position), not \(point)", file: file, line: line)
        }
    }

    func testFourLegsAreFoundAlongEitherSideAndTheHeadIsTheHigherEnd() throws {
        for (axis, headBack) in [(Vec3.unitX, false), (.unitZ, false), (.unitX, true)] {
            let (mesh, joints) = Self.animal(along: axis, headBack: headBack)
            let bounds = try XCTUnwrap(mesh.bounds)
            let marks = try XCTUnwrap(BodyGuess.fourLegs(BodyGuess.points(of: mesh), bounds: bounds), "four legs along \(axis)")
            assertNear(marks, joints, within: bounds.size.length * 0.1)
            XCTAssertEqual(marks.first?.name, "hips")
            let rig = RigMarks.rig(marks, surface: BodyGuess.points(of: mesh))
            XCTAssertNotNil(rig.skeleton.index(of: "frontLeftKnee"))
            XCTAssertNotNil(rig.skeleton.index(of: "tailTip~1"), "the tail bends softly")
        }
    }

    func testWingsAreFoundWhereTheBodyThinsOut() throws {
        let (mesh, joints) = Self.bird()
        let bounds = try XCTUnwrap(mesh.bounds)
        let marks = try XCTUnwrap(BodyGuess.wings(BodyGuess.points(of: mesh), bounds: bounds))
        assertNear(marks, joints, within: bounds.size.length * 0.1)
        let elbow = try XCTUnwrap(marks.first { $0.name == "leftWingElbow" })
        XCTAssertEqual(elbow.position.x, 0.66, accuracy: 0.2, "halfway along the wing")
    }

    func testAPersonIsGuessedOnTheKitAstronaut() throws {
        let (mesh, parts) = try RiggingTests.astronaut()
        let expected = try RiggingTests.astronautDots(parts)
        let bounds = try XCTUnwrap(mesh.bounds)
        let dots = try XCTUnwrap(BodyGuess.person(BodyGuess.points(of: mesh), bounds: bounds))
        XCTAssertEqual(Set(dots.keys), Set(HumanRig.Dot.allCases))
        let height = bounds.size.y
        for dot in HumanRig.Dot.allCases {
            let guess = try XCTUnwrap(dots[dot]), truth = try XCTUnwrap(expected[dot])
            // The front view decides x and y; depth is found afterwards by looking through the limb.
            let flat = Vec3(guess.x - truth.x, guess.y - truth.y, 0).length
            XCTAssertLessThan(flat, height * 0.1, "\(dot): \(guess) vs \(truth)")
        }
        XCTAssertNotNil(HumanRig.rig(from: dots, bounds: bounds))
    }

    /// The Kit's rigged people carry their real skeletons: the guess is checked against those joints.
    func testAPersonIsGuessedOnTheKitsRiggedPeopleNearTheirRealJoints() throws {
        let kit = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("App/Resources/Kit/Characters")
        let joints: [(HumanRig.Dot, String)] = [(.leftShoulder, "leftUpperArm"), (.leftElbow, "leftLowerArm"), (.leftWrist, "leftHand"),
                                                (.leftHip, "leftUpperLeg"), (.leftKnee, "leftLowerLeg"), (.leftAnkle, "leftFoot"),
                                                (.rightElbow, "rightLowerArm"), (.rightKnee, "rightLowerLeg")]
        // (The UAL model passes too; reading its hundred clips takes half a minute, so it stays out of the suite.)
        for name in ["characters-superhero-male-fullbody", "characters-superhero-female-fullbody"] {
            let url = kit.appendingPathComponent("\(name).loweyasset/model.glb")
            var mesh = MeshData()
            for part in try GLTFMeshReader.model(contentsOf: url).parts {
                mesh.append(part.mesh)
            }
            let rig = try XCTUnwrap(GLTFReader.rig(contentsOf: url))
            let rest = rig.skeleton.modelRest
            let bounds = try XCTUnwrap(mesh.bounds)
            let dots = try XCTUnwrap(BodyGuess.person(BodyGuess.points(of: mesh), bounds: bounds), name)
            for (dot, bone) in joints {
                let joint = try XCTUnwrap(rig.skeleton.index(of: rig.boneMap[bone] ?? bone), "\(name) \(bone)")
                let guess = try XCTUnwrap(dots[dot])
                let flat = Vec3(guess.x - rest[joint].position.x, guess.y - rest[joint].position.y, 0).length
                XCTAssertLessThan(flat, bounds.size.y * 0.1, "\(name) \(dot): \(guess) vs \(rest[joint].position)")
            }
        }
    }

    func testWhatCantBeSeenFallsBackToTheStandardLayout() throws {
        // A plain box has no legs and no wings.
        let mesh = Self.box(Vec3(0, 0.5, 0), Vec3(1, 1, 0.5))
        let bounds = try XCTUnwrap(mesh.bounds)
        let points = BodyGuess.points(of: mesh)
        XCTAssertNil(BodyGuess.fourLegs(points, bounds: bounds))
        XCTAssertNil(BodyGuess.wings(points, bounds: bounds))
        XCTAssertNil(BodyGuess.person(points, bounds: bounds))
        for body in [BodyGuess.Body.fourLegs, .wings] {
            let (marks, guessed) = BodyGuess.marks(body, vertices: points, bounds: bounds)
            XCTAssertFalse(guessed)
            XCTAssertGreaterThan(marks.count, 8)
            for mark in marks {
                XCTAssertTrue(bounds.contains(mark.position, tolerance: 1e-6), "\(mark.name) inside the box")
            }
            XCTAssertEqual(Set(marks.map(\.name)).count, marks.count)
        }
    }
}
