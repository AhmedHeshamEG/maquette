import CoreText
import LoweyCore
@testable import LoweyEngine
import UIKit
import XCTest

/// D1 on the GPU: letters that fly in and rest exactly as the still text, a font brought in from a file, a cube on its
/// way into a ball, and a cloner's copies drawn and picked as their thing.
@MainActor
final class DesignRenderTests: XCTestCase {
    private func text(_ recipe: TextRecipe, letters: TextAnimator? = nil) -> Document {
        var object = SceneObject(id: "title", name: "Title", kind: .text(recipe), transform: Transform(position: Vec3(0, 0.2, 0)))
        object[.color] = .color(.rgba(RGBA(0.95, 0.5, 0.1)))
        object.motionDesign = letters.map { MotionDesign(letters: $0) }
        return TestDocuments.document("Letters", objects: [object], camera: Vec3(0, 0.7, 4))
    }

    private func image(_ document: Document, at time: Double = 0, files: [String: Data] = [:]) async throws -> CGImage {
        let session = try TestDocuments.session(document)
        session.paintFile = { files[$0] }
        return try await session.image(at: time, framing: .landscape, longSide: 320)
    }

    func testLettersFlyInAndRestAsTheStillText() async throws {
        let recipe = TextRecipe(text: "HELLO", style: .bold, size: 0.6)
        let flying = text(recipe, letters: TextAnimator(preset: .flyIn, start: 0.5, stagger: 0.1, length: 0.5))
        let still = try await image(text(recipe))
        let before = try await image(flying, at: 0)
        let during = try await image(flying, at: 0.8)
        let after = try await image(flying, at: 2)
        GoldenImage().attach(during, name: "letters-flying")
        XCTAssertGreaterThan(ImageChecks.difference(still, before), 0.02, "nothing shows before they start")
        XCTAssertGreaterThan(ImageChecks.difference(still, during), 0.005, "on their way")
        XCTAssertLessThan(ImageChecks.difference(still, after), 0.002, "arrived, they are the still text")
    }

    func testBlockyLettersWaveToo() async throws {
        let recipe = TextRecipe(text: "WAVE", style: .blocky, size: 0.5)
        let wave = text(recipe, letters: TextAnimator(preset: .wave, start: 0, stagger: 0.1, length: 1))
        let a = try await image(wave, at: 0.25)
        let b = try await image(wave, at: 0.75)
        XCTAssertGreaterThan(ImageChecks.difference(a, b), 0.003)
    }

    /// A font file read from the simulator's own fonts stands in for one a person brings in.
    func testAFontBroughtInIsUsed() async throws {
        let courier = CTFontCreateWithName("Courier" as CFString, 12, nil)
        let url = try XCTUnwrap(CTFontCopyAttribute(courier, kCTFontURLAttribute) as? URL)
        let data = try Data(contentsOf: url)
        XCTAssertNotNil(FontFileInfo.name(of: data))
        XCTAssertNil(FontFileInfo.name(of: Data("not a font".utf8)))
        let plain = TextRecipe(text: "Fonts", style: .bold, size: 0.6)
        var custom = plain
        custom.font = "fonts/brand.ttf"
        let system = try await image(text(plain))
        let brought = try await image(text(custom), files: ["fonts/brand.ttf": data])
        let missing = try await image(text(custom))
        XCTAssertGreaterThan(ImageChecks.difference(system, brought), 0.005, "the font's own letters")
        XCTAssertLessThan(ImageChecks.difference(system, missing), 0.001, "a font that can't be read falls back to the style")
    }

    func testACubeOnItsWayIntoABall() async throws {
        var cube = SceneObject(id: "cube", name: "Cube", kind: .primitive(.cube))
        cube[.color] = .color(.rgba(RGBA(0.9, 0.2, 0.2)))
        cube.motionDesign = MotionDesign(morph: ObjectMorph(target: "ball"))
        var ball = SceneObject(id: "ball", name: "Ball", kind: .primitive(.sphere), transform: Transform(position: Vec3(3, 0, 0)))
        ball[.color] = .color(.rgba(RGBA(0.2, 0.3, 0.9)))
        ball[.visible] = .bool(false)
        func at(_ amount: Double) -> Document {
            var morphing = cube
            morphing[.morph] = .float(amount)
            return TestDocuments.document("Morph", objects: [morphing, ball], camera: Vec3(0, 0.8, 3.5))
        }
        let start = try await image(at(0))
        let halfway = try await image(at(0.5))
        let end = try await image(at(1))
        var shown = ball
        shown[.visible] = .bool(true)
        shown.transform.position = .zero
        let real = try await image(TestDocuments.document("Ball", objects: [shown], camera: Vec3(0, 0.8, 3.5)))
        GoldenImage().attach(halfway, name: "morph-halfway")
        XCTAssertGreaterThan(ImageChecks.difference(start, halfway), 0.01)
        XCTAssertGreaterThan(ImageChecks.difference(halfway, end), 0.01)
        XCTAssertLessThan(ImageChecks.difference(end, real), 0.01, "at the end it is the ball, in the ball's colour")
    }

    func testCopiesDrawAndPickAsTheirThing() async throws {
        var cube = SceneObject(id: "cube", name: "Cube", kind: .primitive(.cube), transform: Transform(scale: Vec3(0.5, 0.5, 0.5)))
        cube[.color] = .color(.rgba(RGBA(0.95, 0.95, 0.95)))
        cube.motionDesign = MotionDesign(clones: ObjectClones(layout: .line(count: 3, step: Vec3(1.2, 0, 0))))
        let document = TestDocuments.document("Clones", objects: [cube], camera: Vec3(1.2, 0.8, 4))
        let frame = try await image(document)
        GoldenImage().attach(frame, name: "clones-line")
        let shown = Animator.evaluate(document, at: 0)
        let input = RenderInput(document: Document(project: document.project, scene: shown.scene), time: 0, poses: [:], selection: ["cube"])
        let renderer = try LoweyRenderer(device: RenderDevice.sharedDevice())
        let compiled = renderer.compiler.compile(input, cameraPosition: SIMD3<Float>(1.2, 0.8, 4))
        let picked = Set(compiled.items.map(\.uniforms.ids.x))
        XCTAssertEqual(picked.count, 1, "all three copies pick as the cube")
        XCTAssertEqual(compiled.items.count, 3)
        XCTAssertTrue(compiled.items.allSatisfy { ($0.uniforms.ids.z & ObjectFlags.selected.rawValue) != 0 }, "and are selected with it")
    }
}
