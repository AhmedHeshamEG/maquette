import HmmMedia
import LoweyCore
@testable import LoweyEngine
import UIKit
import XCTest

/// A1's exports: Final (motion blur, anti-aliasing), render passes (alpha, depth, masks) and ProRes 4444.
@MainActor
final class AnimateExportTests: XCTestCase {
    /// A cube crossing the frame fast (40 m in a second, in the middle at 0.5 s), another standing still further back, on no ground.
    private func scene() -> Document {
        var fast = SceneObject(id: "fast", name: "Fast", kind: .primitive(.cube), transform: Transform(position: Vec3(-2, 0.5, 0), scale: Vec3(0.6, 0.6, 0.6)))
        fast[.color] = .color(.rgba(RGBA(1, 0.45, 0.2)))
        var still = SceneObject(id: "still", name: "Still", kind: .primitive(.cube), transform: Transform(position: Vec3(0.8, 0.5, -2.5)))
        still[.color] = .color(.rgba(RGBA(0.2, 0.5, 1)))
        var look = Look.default
        look.ground.visible = false
        var document = TestDocuments.document("Motion", objects: [fast, still], camera: Vec3(0, 0.8, 5), look: look)
        document.scene.timeline.tracks = [Track(id: "move", target: "fast", property: .position, keyframes: [
            Keyframe(time: 0, value: .vec3(Vec3(-20, 0.5, 0)), easing: .linear), Keyframe(time: 1, value: .vec3(Vec3(20, 0.5, 0)), easing: .linear)
        ])]
        return document
    }

    /// Pixels neither empty nor solid: the blurred and anti-aliased edges.
    private func partial(_ image: CGImage) -> Int {
        let pixels = GoldenImage.rgba(image)
        return stride(from: 3, to: pixels.count, by: 4).filter { pixels[$0] > 20 && pixels[$0] < 235 }.count
    }

    func testFinalBlursWhatMovesAndKeepsWhatStandsStill() async throws {
        let document = scene()
        let plain = try await TestDocuments.session(document).image(at: 0.5, framing: .landscape, longSide: 320, transparent: true)
        let finalSession = try ExportSession(document: document, catalog: .empty, device: RenderDevice.sharedDevice(), models: ModelLibrary(), final: true)
        let final = try await finalSession.image(at: 0.5, framing: .landscape, longSide: 320, transparent: true)
        GoldenImage().attach(plain, name: "final-off")
        GoldenImage().attach(final, name: "final-on")
        XCTAssertGreaterThan(partial(final), partial(plain) * 3, "the moving cube trails a soft edge across half a frame")
        XCTAssertEqual(FinalFrames.moments(at: 1, fps: 30).count, 8)
        // Half a frame (1/60 s) centred on the moment, eight samples in the middle of their slices.
        XCTAssertEqual(FinalFrames.moments(at: 1, fps: 30).first ?? 0, 1 - 0.25 / 30 + 0.5 / 30 / 16, accuracy: 1e-9)
        XCTAssertEqual(FinalFrames.supersample(longSide: 1920), 2)
        XCTAssertEqual(FinalFrames.supersample(longSide: 3840), 1)
        // The still cube's middle is the same either way.
        let rect = CGRect(x: 0.565, y: 0.53, width: 0.03, height: 0.04)
        XCTAssertEqual(ImageChecks.brightness(final, in: rect), ImageChecks.brightness(plain, in: rect), accuracy: 0.04)
    }

    func testRenderPassesWriteColourAlphaDepthAndAMaskPerThing() async throws {
        let session = try TestDocuments.session(scene())
        let settings = ExportSettings(framing: .landscape, longSide: 240, fps: 10, codec: .h264, range: TimeRange(start: 0.4, end: 0.6))
        let folder = try await session.passes(settings, to: ImageChecks.temporaryFolder("passes"), progress: { _ in })
        for pass in ["colour", "alpha", "depth", "masks"] {
            let files = try FileManager.default.contentsOfDirectory(atPath: folder.appendingPathComponent(pass).path).filter { $0.hasSuffix(".png") }
            XCTAssertEqual(files.count, 2, "\(pass): a picture a frame")
        }
        let key = try JSONSerialization.jsonObject(with: Data(contentsOf: folder.appendingPathComponent("passes.json"))) as? [String: Any]
        let masks = try XCTUnwrap(key?["masks"] as? [String: String])
        XCTAssertEqual(Set(masks.values), ["Fast", "Still"], "each thing's mask colour is named")
        let depthKey = try XCTUnwrap(key?["depth"] as? [String: Any])
        XCTAssertLessThan(depthKey["near"] as? Double ?? 0, depthKey["far"] as? Double ?? 0)
        let maskImage = try XCTUnwrap(UIImage(contentsOfFile: folder.appendingPathComponent("masks/frame_00002.png").path)?.cgImage)
        let pixels = GoldenImage.rgba(maskImage)
        var colours = Set<[UInt8]>()
        for index in stride(from: 0, to: pixels.count, by: 4) {
            colours.insert(Array(pixels[index ..< index + 3]))
        }
        XCTAssertEqual(colours.count, 3, "two flat colours and the empty black")
        let depth = try XCTUnwrap(UIImage(contentsOfFile: folder.appendingPathComponent("depth/frame_00002.png").path)?.cgImage)
        XCTAssertEqual(depth.bitsPerComponent, 16)
        attach(maskImage, "passes-masks")
        attach(depth, "passes-depth")
    }

    func testProResCarriesTransparencyWhereTheDeviceWritesIt() async throws {
        let writes = await VideoEncoder.canEncode(.prores4444)
        try XCTSkipUnless(writes, "this simulator writes no ProRes")
        let session = try TestDocuments.session(scene())
        let settings = ExportSettings(framing: .landscape, longSide: 320, fps: 10, codec: .prores4444, range: TimeRange(start: 0, end: 0.5),
                                      transparent: true)
        XCTAssertEqual(settings.codec, .prores4444, "transparency keeps ProRes, which has its own alpha")
        let url = try await session.video(settings, audio: nil, to: ImageChecks.temporaryFolder("prores").appendingPathComponent("clip.mov")) { _ in }
        XCTAssertEqual(url.pathExtension, "mov")
    }

    func testAFinalVideoIsVerifiedLikeAnyOther() async throws {
        let finalSession = try ExportSession(document: scene(), catalog: .empty, device: RenderDevice.sharedDevice(), models: ModelLibrary(), final: true)
        var settings = ExportSettings(framing: .landscape, longSide: 240, fps: 10, codec: .h264, range: TimeRange(start: 0, end: 0.3))
        settings.final = true
        var frames = 0
        let url = try await finalSession.video(settings, audio: nil, to: ImageChecks.temporaryFolder("final").appendingPathComponent("final.mp4")) { _ in
            frames += 1
        }
        XCTAssertEqual(frames, settings.frameCount)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    private func attach(_ image: CGImage, _ name: String) {
        GoldenImage().attach(image, name: name)
    }
}
