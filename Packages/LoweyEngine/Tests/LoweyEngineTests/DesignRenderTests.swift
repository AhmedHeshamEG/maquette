import CoreText
import HmmMedia
import HmmVector
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

    /// The phase's acceptance (D1): a logo extruded, cloned and rippling to a music track, the loop closed, looks the same
    /// at its end as at its start, and exports as a ProRes 4444 loop with alpha (where the simulator writes ProRes).
    func testARipplingLogoLoopsSeamlesslyAndExports() async throws {
        let svg = "<svg viewBox='0 0 200 80'><rect width='200' height='80' fill='#d81e2c'/><circle cx='100' cy='40' r='25' fill='#ffffff'/></svg>"
        var ids = IDFactory.sequential("logo")
        let made = try XCTUnwrap(try LogoImport.objects(SVG.read(Data(svg.utf8)), name: "Brand", width: 0.6, depth: 0.06) { ids.next() })
        var document = TestDocuments.document("Brand loop", objects: made.objects, camera: Vec3(0, 1.6, 6))
        var design = MotionDesign(clones: ObjectClones(layout: .grid(columns: 3, rows: 3, layers: 1, spacing: Vec3(0.9, 0.9, 0.9))))
        design.clones?.effects = [CloneEffect.starting(.push, id: "ripple", size: 0.6), CloneEffect(id: "d", kind: .delay, delay: 0.1)]
        document.scene.objects[made.root]?.motionDesign = design
        document.scene.objects[made.root]?[PropertyKey.effectStrength] = PropertyValue.float(0)
        var music = AudioClip(id: "music", role: .music, name: "Music", file: "music.m4a", duration: 4)
        music.levels = SoundLevels(loudness: Array(repeating: 200, count: 240), bass: Array(repeating: 200, count: 240),
                                   beats: stride(from: 0.0, to: 4, by: 0.5).map(\.self), tempo: 120)
        document.scene.timeline.duration = 2
        document.scene.timeline.audio = [music]
        document.scene.timeline.links = [MotionLink(id: "l", target: made.root, channel: .effect, driver: .sound(clip: "music", feature: .beat))]
        document.scene.timeline.behaviors = [Behavior(id: "spin", target: made.root, kind: .spin(degreesPerSecond: 70, axis: .y))]
        let range = TimeRange(start: 0, end: 2)
        var closed = document
        _ = try XCTUnwrap(LoopClose.command(document, range: range)).apply(to: &closed)
        XCTAssertEqual(LoopCheck.seams(closed, range: range), [])
        let first = try await image(closed, at: 0)
        let last = try await image(closed, at: 2)
        let middle = try await image(closed, at: 1.1)
        GoldenImage().attach(middle, name: "brand-loop")
        XCTAssertLessThan(ImageChecks.difference(first, last), 0.002, "the end meets the start")
        XCTAssertGreaterThan(ImageChecks.difference(first, middle), 0.002, "and it moves in between")
        let writes = await VideoEncoder.canEncode(.prores4444)
        let session = try TestDocuments.session(closed)
        let settings = ExportSettings(framing: .landscape, longSide: 320, fps: 10, codec: writes ? .prores4444 : .hevcAlpha, range: range,
                                      transparent: true)
        let url = try await session.video(settings, audio: nil, to: ImageChecks.temporaryFolder("brand-loop").appendingPathComponent("loop.mov")) { _ in }
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }
}
