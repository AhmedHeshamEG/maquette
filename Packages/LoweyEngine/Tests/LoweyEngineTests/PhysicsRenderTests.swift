import CoreGraphics
import LoweyCore
@testable import LoweyEngine
import XCTest

/// P1 on the GPU: the acceptance golden (a 1 m wood cube and a 1 m steel cube dropped side by side land the same on
/// the stage, whose run is played while it's being made, and in the export, which makes the whole run first), cloth
/// and water drawn from a run.
@MainActor
final class PhysicsRenderTests: XCTestCase {
    private var device: RenderDevice!

    override func setUp() async throws {
        device = try RenderDevice.sharedDevice()
    }

    private func drop() -> Document {
        var wood = SceneObject(id: "wood", name: "Wood", kind: .primitive(.cube), transform: Transform(position: Vec3(-0.8, 2.5, 0)))
        wood[.color] = .color(.rgba(RGBA.hex("#B07A45")))
        wood.physics = ObjectPhysics(material: .wood)
        var steel = SceneObject(id: "steel", name: "Steel", kind: .primitive(.cube), transform: Transform(position: Vec3(0.8, 2.5, 0)))
        steel[.color] = .color(.rgba(RGBA.hex("#9AA3AD")))
        steel.physics = ObjectPhysics(material: .steel)
        var document = TestDocuments.document("physics", objects: [wood, steel], camera: Vec3(0, 1.4, 6), look: Look(presetID: LookPreset.clay.id))
        document.scene.timeline = Timeline(fps: 30, duration: 2)
        document.scene.physics = ScenePhysics()
        return document
    }

    private func render(_ document: Document, physics: PhysicsFrames?, at time: Double) async throws -> CGImage {
        let builder = ShotBuilder(document: document, catalog: .empty, models: ModelLibrary())
        builder.physics = physics
        let request = builder.request(at: time, framing: .landscape, size: CGSize(width: 640, height: 360), frameIndex: builder.timeline.frame(for: time))
        return try await FrameRenderer(device: device, models: ModelLibrary()).image(request, width: 640, height: 360)
    }

    func testDroppedCubesLandTheSameOnTheStageAndInTheExport() async throws {
        let document = drop()
        // The stage: a run read while it's still being made.
        let input = try XCTUnwrap(PhysicsSources.gather(document, catalog: .empty, models: ModelLibrary()).input(document))
        let stage = try XCTUnwrap(PhysicsSimulator(input))
        while stage.frames.reach < 0.4, stage.step() {}
        let early = try await render(document, physics: stage.frames, at: 0.4)
        while stage.step() {}
        // The export: its own session makes the whole run before the first frame.
        let session = try TestDocuments.session(document)
        let exported = try await session.image(at: 1.5, framing: .landscape, longSide: 640)
        let exportedEarly = try await session.image(at: 0.4, framing: .landscape, longSide: 640)
        let shown = try await render(document, physics: stage.frames, at: 1.5)
        XCTAssertEqual(session.builder.physics?.key, stage.frames.key)
        XCTAssertLessThan(ImageChecks.difference(shown, exported), 0.002, "the stage and the export agree")
        XCTAssertLessThan(ImageChecks.difference(early, exportedEarly), 0.002, "even mid-fall, while the stage's run was being made")
        let unmoved = try await render(document, physics: nil, at: 1.5)
        XCTAssertGreaterThan(ImageChecks.difference(unmoved, shown), 0.005, "they fell")
        try GoldenImage().assertMatches(exported, named: "physics-drop")
    }

    func testClothAndWaterAreDrawnFromTheRun() async throws {
        executionTimeAllowance = 600 // the cloth and the water are simulated first; a slow runner passes five minutes
        var cloth = SceneObject(id: "cloth", name: "Cloth", kind: .primitive(.plane), transform: Transform(position: Vec3(0, 1.2, 0), scale: Vec3(1.4, 1, 1.4)))
        cloth[.color] = .color(.rgba(RGBA.hex("#C0392B")))
        cloth.physics = ObjectPhysics(material: .cloth)
        var ball = SceneObject(id: "ball", name: "Ball", kind: .primitive(.sphere), transform: Transform(position: .zero, scale: Vec3(0.9, 0.9, 0.9)))
        ball.physics = ObjectPhysics(material: .stone, motion: .stays)
        let splash = SceneObject(id: "splash", name: "Splash", kind: .fluid(FluidRecipe(kind: .splash, box: Vec3(1.2, 1, 1.2), amount: 0.3)),
                                 transform: Transform(position: Vec3(1.6, 0.4, 0)))
        var document = TestDocuments.document("drape", objects: [cloth, ball, splash], camera: Vec3(0.6, 1.6, 4.5), look: Look(presetID: LookPreset.clay.id))
        document.scene.timeline = Timeline(fps: 24, duration: 0.8)
        document.scene.physics = ScenePhysics()
        let session = try TestDocuments.session(document)
        let start = try await session.image(at: 0, framing: .landscape, longSide: 640)
        let draped = try await session.image(at: 0.8, framing: .landscape, longSide: 640)
        GoldenImage().attach(draped, name: "physics-drape")
        let frames = try XCTUnwrap(session.builder.physics)
        XCTAssertNotNil(frames.frames.last?.fluids.first?.surface, "the water has a surface")
        XCTAssertGreaterThan(ImageChecks.difference(start, draped), 0.005, "the cloth fell and the water spread")
    }
}
