@testable import LoweyCore
import XCTest

/// Q2 step 3: a model made a character, its own mouth and eyes named as regions, bending its own geometry.
final class CharacterRegionTests: XCTestCase {
    /// A ball made a character (a sphere of radius 0.5 about (0, 0.5, 0) in its own space).
    private func ball() throws -> (Document, ObjectID) {
        var ids = IDFactory.sequential("r")
        let ball = SceneObject(id: ids.next(), name: "Ball", kind: .primitive(.sphere))
        var document = try assertReverts(.insert(SceneFragment(object: ball), parent: nil, index: nil), on: makeDocument())
        document = try assertReverts(XCTUnwrap(CharacterMaker.adopt(ball.id, in: document.scene)), on: document)
        return (document, ball.id)
    }

    /// The mouth: the front of the ball, a little below its middle.
    private let mouthArea = [Vec3(-0.15, 0.35, 0.45), Vec3(0.15, 0.35, 0.45), Vec3(0, 0.28, 0.42), Vec3(0, 0.4, 0.48)]

    func testARegionIsABoxAroundTheCircledAreaWithRoomToFade() throws {
        let region = try XCTUnwrap(CharacterRegion.around(mouthArea, job: .mouth, side: .middle))
        XCTAssertEqual(region.weight(Vec3(0, 0.35, 0.45)), 1, "the middle of the area bends fully")
        for point in mouthArea {
            XCTAssertGreaterThan(region.weight(point), 0.5, "the circled area bends")
        }
        XCTAssertEqual(region.weight(Vec3(0, 0.35, -0.45)), 0, "the back of the ball doesn't")
        XCTAssertEqual(region.weight(Vec3(0, 0.9, 0.3)), 0, "nor the top")
        XCTAssertNil(CharacterRegion.around(Array(mouthArea.prefix(2)), job: .mouth, side: .middle), "two points aren't an area")
    }

    func testTheMouthTalksWithItsOwnGeometry() throws {
        let (document, ball) = try ball()
        let region = try XCTUnwrap(CharacterRegion.around(mouthArea, job: .mouth, side: .middle))
        let named = try assertReverts(XCTUnwrap(CharacterMaker.nameRegion(region, on: ball, in: document.scene)), on: document)
        XCTAssertEqual(named.scene.objects[ball]?.part?.regions, [region])
        XCTAssertEqual(named.scene.objects[ball]?.part?.job, .body, "it stays its own body")
        XCTAssertTrue(CharacterMaker.faceJobs(of: ball, in: named.scene).contains(.mouth), "the panel sees a mouth")
        XCTAssertEqual(CharacterMaker.labels(of: ball, in: named.scene).map(\.job), [.mouth], "one label: the mouth (the ball itself wears none)")

        var scene = named.scene
        XCTAssertTrue(FaceRegions.bends(in: scene).isEmpty, "at rest nothing bends")
        scene.objects[ball]?[.mouthShape] = .enumeration(MouthShape.ah.rawValue)
        let bends = try XCTUnwrap(FaceRegions.bends(in: scene)[ball])
        XCTAssertEqual(bends.count, 1)
        let mesh = PrimitiveMesh.make(.sphere, shading: .smooth)
        let bent = FaceRegions.bend(mesh, bends)
        XCTAssertEqual(bent.positions.count, mesh.positions.count, "the same corners: the model stays whole")
        var moved = 0
        for (before, after) in zip(mesh.positions, bent.positions) {
            let delta = after - before
            let distance = (delta.x * delta.x + delta.y * delta.y + delta.z * delta.z).squareRoot()
            if before.z < 0 { XCTAssertEqual(distance, 0, accuracy: 1e-6, "the back of the ball stays put") }
            if distance > 1e-4 { moved += 1 }
        }
        XCTAssertGreaterThan(moved, 0, "the mouth opens")
        XCTAssertLessThan(moved, mesh.positions.count / 4, "only around the mouth")
    }

    func testANamedEyeBlinksAndNamingItAgainMovesIt() throws {
        let (document, ball) = try ball()
        let eye = try XCTUnwrap(CharacterRegion.around([Vec3(0.1, 0.65, 0.4), Vec3(0.2, 0.65, 0.38), Vec3(0.15, 0.72, 0.38), Vec3(0.15, 0.58, 0.4)],
                                                       job: .eye, side: .left))
        let named = try assertReverts(XCTUnwrap(CharacterMaker.nameRegion(eye, on: ball, in: document.scene)), on: document)
        var scene = named.scene
        XCTAssertEqual(scene.objects[ball]?[.autoBlink], .bool(true), "a character made from a model blinks by itself")
        scene.objects[ball]?[.blinkLeft] = .float(1)
        XCTAssertEqual(FaceRegions.bends(in: scene)[ball]?.first?.bend.squash, 1, "the left eye closes")
        scene.objects[ball]?[.blinkLeft] = .float(0)
        scene.objects[ball]?[.blinkRight] = .float(1)
        XCTAssertNil(FaceRegions.bends(in: scene)[ball], "the right blink doesn't close the left eye")

        var moved = eye
        moved.bounds = Bounds(min: eye.bounds.min + Vec3(0, 0.05, 0), max: eye.bounds.max + Vec3(0, 0.05, 0))
        let again = try assertReverts(XCTUnwrap(CharacterMaker.nameRegion(moved, on: ball, in: named.scene)), on: named)
        XCTAssertEqual(again.scene.objects[ball]?.part?.regions, [moved], "the left eye named again replaces it")
        let removed = try assertReverts(XCTUnwrap(CharacterMaker.removeRegion(.eye, side: .left, on: ball, in: again.scene)), on: again)
        XCTAssertEqual(removed.scene.objects[ball]?.part?.regions, [])
    }

    func testRegionsAreSavedAndANoseIsNotARegion() throws {
        let region = CharacterRegion(job: .brow, side: .right, bounds: Bounds(min: Vec3(-0.2, 0.2, 0.3), max: Vec3(-0.05, 0.3, 0.5)),
                                     states: ["up": FaceBend(lift: 0.6)])
        let part = CharacterPart(job: .body, style: CharacterMaker.ownBodyStyle, regions: [region])
        XCTAssertEqual(try LoweyJSON.decode(CharacterPart.self, from: LoweyJSON.encode(part)), part)
        let old = try LoweyJSON.decode(CharacterPart.self, from: Data(#"{"job":"body","style":"own"}"#.utf8))
        XCTAssertEqual(old.regions, [], "a part saved before 0.30 has none")
        let (document, ball) = try ball()
        XCTAssertNil(CharacterMaker.nameRegion(CharacterRegion(job: .nose, bounds: region.bounds), on: ball, in: document.scene))
    }

    func testTheBridgeNamesARegion() throws {
        let (document, ball) = try ball()
        var context = ScriptContext(ids: .sequential("b"))
        context.mesh = { _ in nil }
        let actions = """
        {"do": "character", "op": "region", "target": "Ball", "part": "mouth", "min": [-0.3, 0.15, 0.2], "max": [0.3, 0.55, 0.6]}
        """
        let script = try LoweyJSON.decode(SceneScript.self, from: Data("{\"version\": 3, \"title\": \"T\", \"actions\": [\(actions)]}".utf8))
        let result = try ScriptCompiler.compile(script, document: document, context: context)
        let applied = try assertReverts(XCTUnwrap(result.command), on: document)
        XCTAssertEqual(applied.scene.objects[ball]?.part?.regions.first?.job, .mouth)
    }
}
