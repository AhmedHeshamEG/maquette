import CoreGraphics
import LoweyCore
@testable import LoweyEngine
import XCTest

/// L2 on the simulator's GPU: the painted Looks paint, the Finish works on any Look, Pixel draws in blocks, grounds are
/// made of something, the drawn effects ink the frame, and the Keeper's Tower renders. Every Look's golden pair is in
/// `RenderTests.testEveryLookInDayAndNight`; these frames are attached for the eye.
@MainActor
final class LooksL2RenderTests: XCTestCase {
    private func frame(_ document: Document, at time: Double = 0, longSide: Int = 640) async throws -> CGImage {
        try await TestDocuments.session(document).image(at: time, framing: .landscape, longSide: longSide)
    }

    private func attach(_ image: CGImage, _ name: String) {
        GoldenImage().attach(image, name: name)
    }

    /// The Look check in `look`, with its Look changed by `edit` (kept as the project's own Look).
    private func lookCheck(_ look: LookPreset, mood: LightingPreset = .day, edit: (inout LookPreset) -> Void = { _ in }) -> Document {
        var document = TestScenes.lookCheck(look: look.id, mood: mood)
        var mine = look.duplicated(id: "edited", name: "Edited")
        edit(&mine)
        document.project.customLooks = [mine]
        document.project.look.presetID = mine.id
        return document
    }

    func testThePaintedLooksPaint() async throws {
        for look in [LookPreset.painterly, .watercolour, .gouache] {
            let painted = try await frame(lookCheck(look))
            let unpainted = try await frame(lookCheck(look) { $0.paint = nil })
            attach(painted, "l2-\(look.id)")
            XCTAssertGreaterThan(ImageChecks.difference(painted, unpainted), 0.004, "\(look.id) lays paint over the picture")
            XCTAssertGreaterThan(GoldenImage.coverage(painted).content, 0.08)
        }
    }

    func testTheFinishWorksOnAnyLook() async throws {
        let plain = try await frame(TestScenes.lookCheck(look: LookPreset.ink.id, mood: .day))
        let finishes: [(String, PostSettings)] = [
            ("benday", PostSettings(benDay: 0.8)),
            ("newsprint", PostSettings(texture: .newsprint, textureStrength: 0.8)),
            ("riso", PostSettings(texture: .riso, textureStrength: 0.8)),
            ("canvas", PostSettings(texture: .canvas, textureStrength: 0.8)),
            ("boil", PostSettings(boil: 1))
        ]
        for (name, post) in finishes {
            var document = TestScenes.lookCheck(look: LookPreset.ink.id, mood: .day)
            document.project.look.post = post
            let image = try await frame(document, at: 0.1)
            attach(image, "l2-finish-\(name)")
            XCTAssertGreaterThan(ImageChecks.difference(image, plain), 0.002, "the \(name) finish changes the picture")
        }
    }

    func testPixelDrawsInBlocks() async throws {
        let image = try await frame(TestScenes.lookCheck(look: LookPreset.pixel.id, mood: .day), longSide: 1920)
        attach(image, "l2-pixel-1080")
        let bytes = GoldenImage.rgba(image)
        let block = PixelStyle(size: 4, colors: 8).blockPixels(height: image.height)
        XCTAssertEqual(block, 4)
        var uniform = 0, checked = 0
        for blockY in stride(from: 40, to: image.height / block - 40, by: 7) {
            for blockX in stride(from: 40, to: image.width / block - 40, by: 11) {
                let first = ((blockY * block) * image.width + blockX * block) * 4
                var same = true
                for dy in 0 ..< block {
                    for dx in 0 ..< block {
                        let index = ((blockY * block + dy) * image.width + blockX * block + dx) * 4
                        if abs(Int(bytes[index]) - Int(bytes[first])) > 2 || abs(Int(bytes[index + 1]) - Int(bytes[first + 1])) > 2 { same = false }
                    }
                }
                uniform += same ? 1 : 0
                checked += 1
            }
        }
        XCTAssertGreaterThan(Double(uniform) / Double(max(checked, 1)), 0.97, "every four by four block is one colour")
    }

    func testGroundsAreMadeOfSomething() async throws {
        var plainDocument = TestScenes.lookCheck(look: LookPreset.ink.id, mood: .day)
        plainDocument.project.look.ground = plainDocument.project.look.ground.made(of: nil)
        let plain = try await frame(plainDocument)
        let floor = CGRect(x: 0.05, y: 0.8, width: 0.9, height: 0.18)
        for surface in GroundSurface.allCases {
            var document = TestScenes.lookCheck(look: LookPreset.ink.id, mood: .day)
            document.project.look.ground = document.project.look.ground.made(of: surface)
            let image = try await frame(document, at: 0.5)
            attach(image, "l2-ground-\(surface.rawValue)")
            XCTAssertNotEqual(ImageChecks.brightness(image, in: floor), ImageChecks.brightness(plain, in: floor), "\(surface) shows on the floor")
            XCTAssertGreaterThan(ImageChecks.difference(image, plain), 0.003, "\(surface) is a ground of its own")
        }
    }

    func testTheDrawnEffectsInkTheFrame() async throws {
        let document = TestScenes.lookCheck(look: LookPreset.ink.id, mood: .day)
        let plain = try await frame(document, at: 0.5)
        let sphere = try XCTUnwrap(document.scene.objects.values.first { $0.name == "Sphere" }?.id)
        let effects = [ScreenEffect(id: "i", kind: .impact, start: 0.4, center: Vec2(0.5, 0.5)),
                       ScreenEffect(id: "f", kind: .focusLines, start: 0.2, duration: 1, target: sphere),
                       ScreenEffect(id: "k", kind: .kirbyDots, start: 0.2, duration: 1, target: sphere)]
        for effect in effects {
            var drawn = document
            drawn.scene.timeline.effects = [effect]
            let image = try await frame(drawn, at: 0.5)
            attach(image, "l2-effect-\(effect.kind.rawValue)")
            XCTAssertGreaterThan(ImageChecks.difference(image, plain), effect.kind == .impact ? 0.1 : 0.004, "\(effect.kind) inks the frame")
        }
        // Focus lines leave their target clear and ink the edges.
        var lines = document
        lines.scene.timeline.effects = [effects[1]]
        let lined = try await frame(lines, at: 0.5)
        let edges = CGRect(x: 0, y: 0, width: 0.06, height: 1)
        XCTAssertLessThan(ImageChecks.brightness(lined, in: edges), ImageChecks.brightness(plain, in: edges), "the frame's edge is inked")
    }

    func testTheKeepersTowerRenders() async throws {
        let (info, scenes) = try KeepersTowerSample.build()
        let document = try Document(project: info, scene: XCTUnwrap(scenes.first))
        for time in [0.0, 6.0] {
            let image = try await frame(document, at: time, longSide: 960)
            attach(image, "keepers-tower-\(Int(time))")
            XCTAssertGreaterThan(GoldenImage.coverage(image).content, 0.04, "the tower is drawn")
        }
    }
}
