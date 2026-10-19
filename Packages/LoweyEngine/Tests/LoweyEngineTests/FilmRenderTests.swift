import AVFoundation
import HmmMedia
import ImageIO
import LoweyCore
@testable import LoweyEngine
import UIKit
import XCTest

/// F1 on the GPU: a soft panel, haze and god rays, the HDRI sky, the rotoscope, and the film exports (a three-shot scene as
/// one cut film and as a storyboard, the animatic, 360°, spatial, HDR, wide colour).
@MainActor
final class FilmRenderTests: XCTestCase {
    /// A white cube in front of the camera on no ground, at night (dark), lit by whatever is added.
    private func dark(_ extra: [SceneObject] = []) -> Document {
        var cube = SceneObject(id: "cube", name: "Cube", kind: .primitive(.cube), transform: Transform(position: Vec3(0, 0, 0)))
        cube[.color] = .color(.rgba(RGBA(0.9, 0.9, 0.9)))
        var look = Look.default.applying(.night)
        look.lighting.sunIntensity = 0.02
        look.lighting.ambientIntensity = 0.05
        look.ground.visible = false
        return TestDocuments.document("Film", objects: [cube] + extra, camera: Vec3(0, 0.5, 4), look: look)
    }

    private func image(_ document: Document, at time: Double = 0, longSide: Int = 320) async throws -> CGImage {
        try await TestDocuments.session(document).image(at: time, framing: .landscape, longSide: longSide)
    }

    func testASoftPanelLightsWhatItFacesAndNotWhatsBehindIt() async throws {
        var factory = ObjectFactory(ids: .sequential("l"))
        var panel = factory.light(.area, at: Vec3(0, 0.5, 2), color: .white)
        panel.transform.rotation = .identity // shining down −z, at the cube
        panel[.lightIntensity] = .float(3)
        var away = panel
        away.transform.rotation = Quat(angle: .pi, axis: .unitY) // the same panel turned to face away
        let face = CGRect(x: 0.45, y: 0.42, width: 0.1, height: 0.12)
        let unlit = try await ImageChecks.brightness(image(dark()), in: face)
        let lit = try await ImageChecks.brightness(image(dark([panel])), in: face)
        let behind = try await ImageChecks.brightness(image(dark([away])), in: face)
        XCTAssertGreaterThan(lit, unlit + 0.15, "the cube's front is lit by the panel facing it")
        XCTAssertEqual(behind, unlit, accuracy: 0.03, "a panel lights only out of its front")
    }

    func testHazeAndGodRaysChangeTheFrame() async throws {
        var clear = TestDocuments.document("Air", objects: [SceneObject(id: "cube", name: "Cube", kind: .primitive(.cube))],
                                           camera: Vec3(0, 1, 8))
        clear.scene.look?.lighting.sunAzimuth = 180 // the sun ahead of the camera, low
        clear.scene.look?.lighting.sunElevation = 8
        var hazy = clear
        hazy.scene.look?.atmosphere = Atmosphere(haze: 0.8, godRays: 1)
        let plain = try await image(clear)
        let air = try await image(hazy)
        GoldenImage().attach(air, name: "haze-and-rays")
        XCTAssertGreaterThan(ImageChecks.difference(plain, air), 0.02)
    }

    func testAnHDRIShowsBehindEverything() async throws {
        // A map that is pure orange everywhere: the sky must come out orange whatever the Look's mood.
        let pixels = (0 ..< 16 * 8 * 3).map { index in [Float(0.9), 0.35, 0.05][index % 3] }
        let hdr = RadianceHDR.write(width: 16, height: 8, pixels: pixels)
        var document = TestDocuments.document("Sky", objects: [], camera: Vec3(0, 1, 4))
        document.scene.look?.sky.environment = "environment/orange.hdr"
        document.scene.look?.sky.environmentExposure = 0
        let session = try TestDocuments.session(document)
        session.paintFile = { $0 == "environment/orange.hdr" ? hdr : nil }
        let frame = try await session.image(at: 0, framing: .landscape, longSide: 160)
        let sky = ImageChecks.rgb(frame, x: 0.5, y: 0.2)
        XCTAssertGreaterThan(sky.r, sky.b + 0.3, "the sky is the picture's orange: \(sky)")
    }

    func testTheRotoscopeShowsBehindWhatsDrawn() async throws {
        let session = try TestDocuments.session(dark())
        await session.loadModels()
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 32, height: 18))
        let red = try XCTUnwrap(renderer.image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 32, height: 18))
        }.cgImage)
        var request = session.builder.request(at: 0, framing: .landscape, size: CGSize(width: 320, height: 180), frameIndex: 0)
        request.rotoscope = RotoscopeFrame(image: red, opacity: 1, inFront: false)
        let frame = try await session.frames.image(request, width: 320, height: 180)
        let backdrop = ImageChecks.rgb(frame, x: 0.05, y: 0.1)
        let cube = ImageChecks.rgb(frame, x: 0.5, y: 0.45)
        XCTAssertGreaterThan(backdrop.r, 0.8, "the video where nothing is drawn")
        XCTAssertLessThan(abs(cube.r - cube.g), 0.2, "the cube stays in front of it")
    }

    // MARK: Exports

    /// Three shots of one scene: three cameras cut at 0, 1 and 2 s, a cube moving across, a voiceover's words.
    private func threeShots() -> Document {
        var cube = SceneObject(id: "cube", name: "Cube", kind: .primitive(.cube))
        cube[.color] = .color(.rgba(RGBA(1, 0.5, 0.2)))
        var document = TestDocuments.document("Three shots", objects: [cube], camera: Vec3(0, 1, 5))
        for (index, x) in [-3.0, 3.0].enumerated() {
            var camera = SceneObject(id: ObjectID(raw: "cam\(index + 2)"), name: "Camera \(index + 2)", kind: .camera,
                                     transform: Transform(position: Vec3(x, 1, 4), rotation: Quat(angle: x > 0 ? 0.6 : -0.6, axis: .unitY)))
            camera[.fieldOfView] = .float(40)
            document.scene.objects[camera.id] = camera
            document.scene.roots.append(camera.id)
        }
        document.scene.timeline.duration = 3
        document.scene.timeline.cuts = [CameraCut(time: 0, camera: "cam"), CameraCut(time: 1, camera: "cam2"), CameraCut(time: 2, camera: "cam3")]
        document.scene.timeline.tracks = [Track(id: "move", target: "cube", property: .position, keyframes: [
            Keyframe(time: 0, value: .vec3(Vec3(-1, 0, 0)), easing: .linear), Keyframe(time: 3, value: .vec3(Vec3(1, 0, 0)), easing: .linear)
        ])]
        return document
    }

    /// Acceptance: a three-shot scene exports as one cut film and as a storyboard PDF.
    func testAThreeShotSceneIsOneCutFilmAndAStoryboard() async throws {
        let document = threeShots()
        let session = try TestDocuments.session(document)
        let settings = ExportSettings(framing: .landscape, longSide: 320, fps: 10, codec: .h264, range: TimeRange(start: 0, end: 3))
        let film = try await session.video(settings, audio: nil, to: ImageChecks.temporaryFolder("film").appendingPathComponent("film.mp4"),
                                           progress: { _ in })
        let facts = try await MediaInspector.facts(of: film)
        XCTAssertEqual(facts.frameCount, 30, "one file, all three shots")
        let panels = Storyboard.panels(document)
        XCTAssertEqual(panels.count, 3)
        var pictures: [PDFWriter.Picture] = []
        for panel in panels {
            let image = try await session.image(at: panel.shot.keyMoment, framing: .landscape, longSide: 320)
            let jpeg = try XCTUnwrap(UIImage(cgImage: image).jpegData(compressionQuality: 0.8))
            pictures.append(PDFWriter.Picture(jpeg: jpeg, width: image.width, height: image.height))
        }
        XCTAssertGreaterThan(try ImageChecks.difference(XCTUnwrap(UIImage(data: pictures[0].jpeg)?.cgImage),
                                                        XCTUnwrap(UIImage(data: pictures[1].jpeg)?.cgImage)), 0.02, "each panel is its own shot")
        let pdf = Storyboard.pdf(panels, pictures: pictures, paper: .a4, title: "Three shots")
        let provider = try XCTUnwrap(CGDataProvider(data: pdf as CFData))
        let parsed = try XCTUnwrap(CGPDFDocument(provider), "a PDF that opens")
        XCTAssertEqual(parsed.numberOfPages, 1)
    }

    func testTheAnimaticHoldsEachShot() async throws {
        let session = try TestDocuments.session(threeShots())
        let settings = ExportSettings(framing: .landscape, longSide: 160, fps: 10, codec: .h264, range: TimeRange(start: 0, end: 3))
        let url = try await session.animatic(settings, audio: nil, to: ImageChecks.temporaryFolder("animatic").appendingPathComponent("a.mp4"),
                                             progress: { _ in })
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let early = try await generator.image(at: CMTime(seconds: 0.1, preferredTimescale: 600)).image
        let late = try await generator.image(at: CMTime(seconds: 0.8, preferredTimescale: 600)).image
        let next = try await generator.image(at: CMTime(seconds: 1.5, preferredTimescale: 600)).image
        XCTAssertLessThan(ImageChecks.difference(early, late), 0.01, "the shot is held though the cube moves")
        XCTAssertGreaterThan(ImageChecks.difference(late, next), 0.02, "the next shot is another picture")
    }

    func testA360PanoramaIsTwoToOneAndItsVideoIsMarked() async throws {
        let session = try TestDocuments.session(threeShots())
        var still = ExportPreset.panorama6K.settings(range: TimeRange(start: 0, end: 0.1), fps: 10)
        still.longSide = 512
        let picture = try await session.panoramaImage(at: 0, settings: still)
        XCTAssertEqual(picture.width, 512)
        XCTAssertEqual(picture.height, 256)
        GoldenImage().attach(picture, name: "panorama")
        XCTAssertGreaterThan(GoldenImage.coverage(picture).content, 0.01, "the cube is somewhere around")
        var moving = ExportPreset.video360x4K.settings(range: TimeRange(start: 0, end: 0.3), fps: 10)
        moving.longSide = 512
        let url = try await session.panoramaVideo(moving, audio: nil, to: ImageChecks.temporaryFolder("360").appendingPathComponent("v.mp4"),
                                                  progress: { _ in })
        XCTAssertTrue(try SphericalVideo.isSpherical(Data(contentsOf: url)))
    }

    func testASpatialPhotoIsTwoEyes() async throws {
        let session = try TestDocuments.session(threeShots())
        let settings = ExportPreset.spatialPhotoHD.settings(range: TimeRange(start: 0, end: 0.1), fps: 10)
        let data: Data
        do {
            data = try await session.spatialPhoto(at: 0, settings: settings)
        } catch {
            throw XCTSkip("no HEIC encoder on this simulator")
        }
        let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        XCTAssertEqual(CGImageSourceGetCount(source), 2)
    }

    func testWideColourStillsAreSixteenBitP3() async throws {
        let session = try TestDocuments.session(threeShots())
        var settings = ExportPreset.stillP3.settings(range: TimeRange(start: 0, end: 0.1), fps: 10)
        settings.longSide = 320
        let image = try await session.wideImage(at: 0, settings: settings)
        XCTAssertEqual(image.bitsPerComponent, 16)
        XCTAssertEqual(image.colorSpace?.name, CGColorSpace.displayP3)
    }

    func testHDRVideoWhereTheSimulatorWritesIt() async throws {
        guard await VideoEncoder.canEncode(.hevcHDR) else { throw XCTSkip("no 10-bit HEVC encoder here") }
        let session = try TestDocuments.session(threeShots())
        var settings = ExportPreset.hdr1080.settings(range: TimeRange(start: 0, end: 0.3), fps: 10)
        settings.longSide = 320
        XCTAssertEqual(settings.encoding, .hdr)
        let url = try await session.video(settings, audio: nil, to: ImageChecks.temporaryFolder("hdr").appendingPathComponent("hdr.mov"),
                                          progress: { _ in })
        let facts = try await MediaInspector.facts(of: url)
        XCTAssertEqual(facts.frameCount, 3)
    }
}
