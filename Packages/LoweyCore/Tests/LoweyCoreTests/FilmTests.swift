import Foundation
@testable import LoweyCore
import XCTest

/// F1's film tools: the body and its millimetres, the frame's shape, rigs, focus that follows, light setups, the air,
/// HDRIs, storyboards, stereo and 360 geometry, the rotoscope's clock, and the bridge's `film`.
final class FilmTests: XCTestCase {
    private func document(camera position: Vec3 = Vec3(0, 1.5, 6), objects: [SceneObject] = []) -> Document {
        var scene = Scene(id: "s", name: "Film")
        var camera = SceneObject(id: "cam", name: "Shot", kind: .camera, transform: Transform(position: position))
        camera[.fieldOfView] = .float(40)
        camera[.focusDistance] = .float(6)
        let hero = SceneObject(id: "hero", name: "Hero", kind: .primitive(.cube), transform: Transform(position: Vec3(0, 0, 0)))
        for object in [camera, hero] + objects {
            scene.objects[object.id] = object
            scene.roots.append(object.id)
        }
        scene.activeCamera = "cam"
        return Document(project: ProjectInfo(id: "p", name: "P"), scene: scene)
    }

    private func run(_ actions: String, on document: Document? = nil, now: Double = 0) throws -> ScriptResult {
        let script = try LoweyJSON.decode(SceneScript.self, from: Data("{\"version\": 3, \"title\": \"T\", \"actions\": [\(actions)]}".utf8))
        return try ScriptCompiler.compile(script, document: document ?? self.document(), context: ScriptContext(now: now, ids: .sequential("f")))
    }

    // MARK: Lens and frame

    func testABodyChangesTheMillimetresNotThePicture() {
        let lens = CameraLens(fieldOfView: CameraLens.fieldOfView(focalLength: 50))
        XCTAssertEqual(lens.focalLength(on: .fullFrame), 50, accuracy: 1e-9)
        XCTAssertEqual(lens.focalLength(on: .super35), 50 / CameraSensor.super35.cropFactor, accuracy: 1e-9)
        XCTAssertEqual(CameraLens.fieldOfView(focalLength: 35, on: .super35), CameraLens.fieldOfView(focalLength: 35 * 43.27 / 31.11), accuracy: 1e-9)
        XCTAssertEqual(lens.focalLength(on: .phone), 50 * 6.86 / 24, accuracy: 1e-9, "a phone's 24 mm look is 6.86 mm")
    }

    func testCinemaKeepsTheWidthAndLosesHeight() {
        let lens = CameraLens(fieldOfView: 40)
        let wide = lens.framing(aspect: 16.0 / 9.0)
        let cinema = lens.framing(aspect: 2.39)
        let halfWidth = { (fov: Double, aspect: Double) in tan(fov * .pi / 360) * aspect }
        XCTAssertEqual(halfWidth(cinema.fieldOfView, 2.39), halfWidth(wide.fieldOfView, 16.0 / 9.0), accuracy: 1e-9)
        XCTAssertLessThan(cinema.fieldOfView, wide.fieldOfView)
        XCTAssertEqual(lens.framing(aspect: 0.8).fieldOfView, lens.framing(aspect: 9.0 / 16.0).fieldOfView, "4:5 is tall: portrait zoom")
    }

    func testFrameShapesAndTheTimelineKeepsOne() throws {
        XCTAssertEqual(FrameShape.cinema.pixelSize(longSide: 1920).width, 1920)
        XCTAssertEqual(FrameShape.cinema.pixelSize(longSide: 1920).height, 802)
        XCTAssertEqual(FrameShape.vertical.pixelSize(longSide: 1350).width, 1080)
        XCTAssertEqual(FrameShape.landscape.pixelSize(longSide: 1920).height, 1080)
        var timeline = Timeline()
        XCTAssertEqual(timeline.frameShape, .landscape)
        timeline.frame = .cinema
        let back = try LoweyJSON.decode(Timeline.self, from: LoweyJSON.encode(timeline))
        XCTAssertEqual(back.frame, .cinema)
        let result = try run(#"{"do": "film", "op": "frame", "shape": "4:5"}"#)
        XCTAssertEqual(result.document.scene.timeline.frame, .vertical)
    }

    // MARK: Rigs and focus

    private func cameraWorld(_ document: Document, at time: Double) -> Transform {
        let animated = Animator.evaluate(document, at: time)
        return animated.scene.worldTransform(of: "cam")
    }

    func testADollyTravelsTheWayTheCameraFaces() {
        var document = document()
        document.scene.objects["cam"]?[.rig] = .enumeration(CameraRig.dolly.rawValue)
        document.scene.objects["cam"]?[.rigTravel] = .float(2)
        let world = cameraWorld(document, at: 0)
        XCTAssertEqual(world.position.z, 4, accuracy: 1e-9, "two metres in")
        XCTAssertEqual(world.position.y, 1.5, accuracy: 1e-9)
    }

    func testACraneRisesAndKeepsItsSubjectAhead() {
        var document = document()
        document.scene.objects["cam"]?[.rig] = .enumeration(CameraRig.crane.rawValue)
        document.scene.objects["cam"]?[.rigLift] = .float(3)
        let world = cameraWorld(document, at: 0)
        XCTAssertEqual(world.position.y, 4.5, accuracy: 1e-9)
        let forward = world.rotation.act(Vec3(0, 0, -1))
        let toAim = (Vec3(0, 1.5, 0) - world.position).normalized
        XCTAssertGreaterThan(forward.dot(toAim), 0.999, "it looks down at what it framed")
    }

    func testAnOrbitCirclesWhatItWatches() {
        var document = document()
        document.scene.objects["cam"]?[.rig] = .enumeration(CameraRig.orbit.rawValue)
        document.scene.objects["cam"]?[.rigSwing] = .float(90)
        document.scene.objects["cam"]?[.lookAt] = .string("hero")
        let world = cameraWorld(document, at: 0)
        XCTAssertEqual(Vec3(world.position.x, 0, world.position.z).length, 6, accuracy: 1e-6, "the same distance around")
        XCTAssertEqual(world.position.x, 6, accuracy: 1e-6, "a quarter turn left from the front is +x")
    }

    func testHandheldShakesALittleTheSameEveryTimeAfterTheLook() {
        var document = document()
        document.scene.objects["cam"]?[.rig] = .enumeration(CameraRig.handheld.rawValue)
        document.scene.objects["cam"]?[.lookAt] = .string("hero")
        let first = cameraWorld(document, at: 1.3)
        XCTAssertEqual(first, cameraWorld(document, at: 1.3), "deterministic")
        XCTAssertLessThan(first.position.distance(to: Vec3(0, 1.5, 6)), 0.02)
        var still = document
        still.scene.objects["cam"]?[.rig] = nil
        let steady = cameraWorld(still, at: 1.3)
        let angle = acos(min(abs(first.rotation.normalized.dot(steady.rotation.normalized)), 1)) * 2 * 180 / .pi
        XCTAssertGreaterThan(angle, 0.01, "the shake survives the camera turning to look")
        XCTAssertLessThan(angle, 3)
    }

    func testFocusFollowsItsSubjectAndPullsToTheNext() throws {
        var document = document(objects: [SceneObject(id: "far", name: "Far", kind: .primitive(.cube), transform: Transform(position: Vec3(0, 0, -10)))])
        var ids = IDFactory.sequential("k")
        var move = Track(id: ids.next(), target: "hero", property: .position)
        move.setKey(Keyframe(time: 0, value: .vec3(.zero)))
        move.setKey(Keyframe(time: 2, value: .vec3(Vec3(0, 0, 3))))
        document.scene.timeline.tracks.append(move)
        document.scene.timeline.duration = 6
        let on = try XCTUnwrap(FocusOperations.focus("cam", on: "hero", at: 0, in: document.scene, ids: &ids))
        _ = try on.apply(to: &document)
        let focus = { (time: Double) in Animator.evaluate(document, at: time).scene.objects["cam"]?[.focusDistance]?.floatValue ?? 0 }
        XCTAssertEqual(focus(0), Vec3(0, 1.5, 6).distance(to: .zero), accuracy: 1e-6)
        XCTAssertEqual(focus(2), Vec3(0, 1.5, 6).distance(to: Vec3(0, 0, 3)), accuracy: 1e-6, "it follows the thing")
        let pull = try XCTUnwrap(FocusOperations.focus("cam", on: "far", at: 4, in: document.scene, ids: &ids))
        _ = try pull.apply(to: &document)
        let near = Vec3(0, 1.5, 6).distance(to: Vec3(0, 0, 3))
        let far = Vec3(0, 1.5, 6).distance(to: Vec3(0, 0, -10))
        XCTAssertEqual(focus(4 + FocusPull.duration / 2), (near + far) / 2, accuracy: 1e-6, "halfway through the pull")
        XCTAssertEqual(focus(5), far, accuracy: 1e-6)
    }

    // MARK: Light

    func testThreePointPutsAKeyAFillAndARimAimedAtTheSubject() throws {
        let result = try run(#"{"do": "lighting", "recipe": "three-point", "subject": "Hero"}"#)
        let lamps = result.document.scene.objects.values.filter {
            if case .light = $0.kind {
                true
            } else {
                false
            }
        }
        XCTAssertEqual(Set(lamps.map(\.name)), ["Key light", "Fill light", "Rim light"])
        XCTAssertEqual(lamps.filter { $0.kind == .light(.area) }.count, 2, "the key and fill are soft panels")
        for lamp in lamps where lamp.kind != .light(.point) {
            let forward = lamp.transform.rotation.act(Vec3(0, 0, -1))
            XCTAssertGreaterThan(forward.dot((Vec3(0, 0.5, 0) - lamp.transform.position).normalized), 0.95, lamp.name)
        }
        let again = try run(#"{"do": "lighting", "recipe": "neon", "subject": "Hero"}"#, on: result.document)
        let relit = again.document.scene.objects.values.filter {
            if case .light = $0.kind {
                true
            } else {
                false
            }
        }
        XCTAssertEqual(relit.count, 2, "re-lighting replaces the last setup's lamps")
        XCTAssertEqual(again.document.effectiveLook.lightingPreset, .night)
        XCTAssertEqual(again.document.effectiveLook.atmosphere?.haze ?? 0, 0.3, accuracy: 1e-9)
    }

    func testGoldenHourBringsItsMoodAndAir() throws {
        let result = try run(#"{"do": "lighting", "recipe": "golden-hour"}"#)
        let look = result.document.effectiveLook
        XCTAssertEqual(look.lightingPreset, .goldenHour)
        XCTAssertLessThan(look.lighting.sunElevation, 15, "a low sun")
        XCTAssertGreaterThan(look.atmosphere?.godRays ?? 0, 0)
    }

    func testASoftPanelFromAScriptAndThroughGLTF() throws {
        let result = try run(#"{"do": "light", "type": "panel", "name": "Window", "at": [2, 2, 2], "size": [1.2, 0.8], "aim": "Hero"}"#)
        let window = try XCTUnwrap(result.document.scene.objects.values.first { $0.name == "Window" })
        XCTAssertEqual(window.kind, .light(.area))
        XCTAssertEqual(window[.lightWidth], .float(1.2))
        let glb = GLTFScene.glb(nil, in: result.document.scene, look: Look())
        var ids = IDFactory.sequential("in")
        let read = try GLTFSceneReader.read(glb, ids: &ids)
        let back = try XCTUnwrap(read.fragment.objects.first { $0.name == "Window" })
        XCTAssertEqual(back.kind, .light(.area), "a panel goes out as a spot and comes back a panel")
        XCTAssertEqual(back[.lightHeight]?.floatValue ?? 0, 0.8, accuracy: 1e-9)
    }

    func testTheAirIsTheLooks() throws {
        let hazy = try run(#"{"do": "film", "op": "air", "haze": 0.5, "godRays": 0.7}"#)
        XCTAssertEqual(hazy.document.effectiveLook.atmosphere, Atmosphere(haze: 0.5, godRays: 0.7))
        let clear = try run(#"{"do": "film", "op": "air", "haze": 0, "godRays": 0}"#, on: hazy.document)
        XCTAssertNil(clear.document.effectiveLook.atmosphere)
        let old = try LoweyJSON.decode(Look.self, from: LoweyJSON.encode(Look.default))
        XCTAssertNil(old.atmosphere, "a Look from before F1 reads as clear air")
    }

    // MARK: HDRI

    /// A sky map with a bright sun at the given direction.
    private func sky(width: Int = 64, sun toward: Vec3) -> RadianceHDR {
        let empty = RadianceHDR(width: width, height: width / 2, pixels: [])
        var pixels = [Float](repeating: 0, count: width * width / 2 * 3)
        for row in 0 ..< width / 2 {
            for column in 0 ..< width {
                let direction = empty.direction(column: column, row: row)
                let index = (row * width + column) * 3
                let sun: Float = direction.dot(toward.normalized) > 0.995 ? 400 : 0
                let up = Float(max(direction.y, 0))
                pixels[index] = 0.3 + up * 0.2 + sun
                pixels[index + 1] = 0.4 + up * 0.3 + sun * 0.9
                pixels[index + 2] = 0.6 + up * 0.5 + sun * 0.7
            }
        }
        return RadianceHDR(width: width, height: width / 2, pixels: pixels)
    }

    func testRadianceReadsWhatItWrites() throws {
        let map = sky(sun: Vec3(1, 1, 0))
        let read = try RadianceHDR.read(RadianceHDR.write(width: map.width, height: map.height, pixels: map.pixels))
        XCTAssertEqual(read.width, 64)
        for (a, b) in zip(read.pixels, map.pixels) {
            XCTAssertEqual(a, b, accuracy: max(b * 0.01, 0.01), "RGBE keeps 8 bits a channel under a shared exponent")
        }
        let shrunk = try RadianceHDR.read(RadianceHDR.write(width: map.width, height: map.height, pixels: map.pixels), maxWidth: 16)
        XCTAssertEqual(shrunk.width, 16)
        XCTAssertEqual(shrunk.height, 8)
        XCTAssertThrowsError(try RadianceHDR.read(Data("P6 1 1 255\n".utf8)))
    }

    func testRunLengthScanlines() throws {
        // Width 8, one row: R runs of 8 × 128, G literal 0…7, B one run, E one run (exponent 129 → ×1/128).
        var data = Data("#?RADIANCE\nFORMAT=32-bit_rle_rgbe\n\n-Y 1 +X 8\n".utf8)
        data.append(contentsOf: [2, 2, 0, 8])
        data.append(contentsOf: [UInt8(136), 128])
        data.append(contentsOf: [8, 0, 1, 2, 3, 4, 5, 6, 7])
        data.append(contentsOf: [UInt8(136), 64])
        data.append(contentsOf: [UInt8(136), 129])
        let read = try RadianceHDR.read(data)
        XCTAssertEqual(read.pixels[0], 128.5 / 128, accuracy: 1e-6, "(128 + ½) × 2^(129−136)")
        XCTAssertEqual(read.pixels[7 * 3 + 1], 7.5 / 128, accuracy: 1e-6)
        XCTAssertEqual(read.pixels[2], 64.5 / 128, accuracy: 1e-6)
    }

    func testAnHDRIFindsItsSunAndSky() {
        let toSun = Vec3(1, 1, 0).normalized
        let light = EnvironmentLight.analyse(sky(width: 256, sun: toSun))
        let lighting = Lighting(sunElevation: light.sunElevation, sunAzimuth: light.sunAzimuth)
        XCTAssertGreaterThan((-lighting.sunDirection).dot(toSun), 0.99, "the sun comes from where it is in the picture")
        XCTAssertGreaterThan(light.sunIntensity, 0.15)
        XCTAssertGreaterThan(light.sky.top.b, light.sky.top.r, "a blue sky")
        let turned = EnvironmentLight.analyse(sky(width: 256, sun: toSun), turn: 90)
        XCTAssertEqual((turned.sunAzimuth - light.sunAzimuth + 360).truncatingRemainder(dividingBy: 360), 90, accuracy: 2)
        let look = light.applied(to: Look.default, environment: "assets/sky.hdr", turn: 0)
        XCTAssertEqual(look.sky.environment, "assets/sky.hdr")
        XCTAssertNil(look.lightingPreset)
        let back = try? LoweyJSON.decode(Look.self, from: LoweyJSON.encode(look))
        XCTAssertEqual(back?.sky.environment, "assets/sky.hdr")
    }

    // MARK: Shots, storyboards, stereo, 360, the rotoscope

    func testShotsAndTheStoryboard() throws {
        var document = document()
        document.scene.timeline.duration = 9
        document.scene.timeline.cuts = [CameraCut(time: 0, camera: "cam"), CameraCut(time: 3, camera: "cam"), CameraCut(time: 6, camera: "cam")]
        document.scene.timeline.audio = [AudioClip(id: "vo", role: .voiceover, name: "VO", file: "audio/vo.m4a", duration: 9)]
        document.scene.timeline.transcripts = [Transcript(clip: "vo", language: "en-US", words: [
            TranscriptWord(text: "Once", start: 0.5, end: 0.8), TranscriptWord(text: "upon", start: 3.5, end: 3.8),
            TranscriptWord(text: "a", start: 3.9, end: 4), TranscriptWord(text: "time", start: 6.2, end: 6.6)
        ])]
        let shots = document.scene.timeline.shots()
        XCTAssertEqual(shots.map(\.start), [0, 3, 6])
        XCTAssertEqual(shots[1].keyMoment, 4, accuracy: 1e-9)
        let panels = Storyboard.panels(document)
        XCTAssertEqual(panels.map(\.words), ["Once", "upon a", "time"])
        XCTAssertTrue(panels[0].heading.hasPrefix("Shot 1  ·  Shot"))
        XCTAssertTrue(panels[0].detail.contains("3.0 s") && panels[0].detail.contains("mm"), panels[0].detail)
        let picture = PDFWriter.Picture(jpeg: Data([0xFF, 0xD8, 0xFF, 0xD9]), width: 16, height: 9)
        let pdf = Storyboard.pdf(panels, pictures: Array(repeating: picture, count: 3), paper: .a4, title: "Film")
        XCTAssertTrue(String(decoding: pdf.prefix(5), as: UTF8.self).hasPrefix("%PDF"))
        XCTAssertEqual(Storyboard.wrap(String(repeating: "word ", count: 60), width: 100, size: 8).count, 2)
    }

    func testStereoEyesAreParallelAndApart() {
        let camera = Transform(position: Vec3(0, 1, 0), rotation: Quat(angle: .pi / 2, axis: .unitY))
        let eyes = StereoRig.eyes(camera)
        XCTAssertEqual(eyes.left.position.distance(to: eyes.right.position), 0.063, accuracy: 1e-12)
        XCTAssertEqual(eyes.left.rotation, eyes.right.rotation)
        XCTAssertEqual((eyes.right.position - eyes.left.position).normalized.dot(camera.rotation.act(.unitX)), 1, accuracy: 1e-9)
    }

    func testThePanoramaCubeAndTheFlatPictureAgree() {
        for face in Panorama.Face.allCases {
            let rotation = Panorama.rotation(face, heading: .identity)
            let forward = rotation.act(Vec3(0, 0, -1))
            XCTAssertGreaterThan(forward.dot(face.axes.forward), 0.999, "\(face)")
            XCTAssertGreaterThan(rotation.act(.unitY).dot(face.axes.up), 0.999, "\(face) up")
        }
        XCTAssertGreaterThan(Panorama.direction(u: 0.5, v: 0.5).dot(Vec3(0, 0, -1)), 0.999, "the middle is straight ahead")
        for (u, v) in [(0.1, 0.3), (0.62, 0.8), (0.9, 0.45), (0.5, 0.05)] {
            let direction = Panorama.direction(u: u, v: v)
            let (face, s, t) = Panorama.faceCoordinate(direction)
            XCTAssertTrue((0 ... 1).contains(s) && (0 ... 1).contains(t))
            // The pixel at (s, t) of that face looks back along the same direction.
            let rotation = Panorama.rotation(face, heading: .identity)
            let local = Vec3(s * 2 - 1, 1 - t * 2, -1)
            XCTAssertGreaterThan(rotation.act(local).normalized.dot(direction), 0.9999)
        }
    }

    func testTheRotoscopeFollowsThePlayheadByWholeFrames() {
        let roto = Rotoscope(video: "assets/run.mov", start: 1)
        XCTAssertNil(roto.frameTime(at: 0.5, fps: 24), "before it starts")
        XCTAssertEqual(roto.frameTime(at: 2.03, fps: 24) ?? -1, 1, accuracy: 1e-9)
        XCTAssertEqual(roto.frameTime(at: 2.05, fps: 24) ?? -1, 1 + 1.0 / 24, accuracy: 1e-9)
        XCTAssertNil(roto.frameTime(at: 9, fps: 24, length: 5), "after it ends")
        var workspace = ProjectWorkspace()
        workspace.rotoscope = Rotoscope(video: "assets/run.mov", opacity: 4)
        let back = try? LoweyJSON.decode(ProjectWorkspace.self, from: LoweyJSON.encode(workspace))
        XCTAssertEqual(back?.rotoscope?.opacity, 1, "kept in range")
    }

    // MARK: The bridge

    func testTheFilmVerb() throws {
        let result = try run(#"""
        {"do": "film", "op": "lens", "camera": "Shot", "mm": 32, "sensor": "super35", "aperture": 2},
        {"do": "film", "op": "rig", "kind": "crane", "arm": 4, "keys": {"lift": [[0, 0], [3, 2]]}},
        {"do": "film", "op": "focus", "on": "Hero"},
        {"do": "film", "op": "shots"}
        """#)
        let camera = try XCTUnwrap(result.document.scene.objects["cam"])
        XCTAssertEqual(CameraLens(camera).focalLength(on: .super35), 32, accuracy: 1e-6)
        XCTAssertEqual(camera[.sensor], .enumeration("super35"))
        XCTAssertEqual(CameraRig.of(camera), .crane)
        XCTAssertEqual(result.document.scene.timeline.track(for: "cam", .rigLift)?.keyframes.count, 2)
        XCTAssertEqual(camera[.focusOn], .string("hero"))
        XCTAssertTrue(result.report.contains { $0.hasPrefix("Shot 1") }, "\(result.report)")
        XCTAssertThrowsError(try run(#"{"do": "film", "op": "lens", "sensor": "vhs"}"#))
        XCTAssertThrowsError(try run(#"{"do": "film", "op": "environment", "turn": 30}"#), "no HDRI yet")
        XCTAssertTrue(ScriptReference.text.contains(#""do":"film""#))
    }
}
