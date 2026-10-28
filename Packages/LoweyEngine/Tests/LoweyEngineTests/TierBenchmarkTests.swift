import CoreGraphics
import HmmDiagnostics
import LoweyCore
@testable import LoweyEngine
import QuartzCore
import XCTest

/// Older iPads are simulated, not bought (CONTEXT §D.27): fifty things on the stage, previewed the way a Tier B iPad
/// previews them, hold 60 frames a second on CI. Each frame is built and drawn and waited for before the next, so CPU
/// and GPU never overlap: the stage, which overlaps them, is faster than this.
@MainActor
final class TierBenchmarkTests: XCTestCase {
    /// An 11-inch iPad's screen in pixels.
    private static let screen = (width: 2360, height: 1640)
    private static let budget = 1.0 / 60.0

    func testFiftyThingsHoldSixtyFramesASecondAtTierB() async throws {
        let quality = PreviewQuality(tier: .b)
        let scale = quality.renderScale.upperBound
        let width = Int(Float(Self.screen.width) * scale), height = Int(Float(Self.screen.height) * scale)
        let models = ModelLibrary()
        let frames = try FrameRenderer(device: RenderDevice.sharedDevice(), models: models, quality: quality)
        let document = Self.fiftyThings()
        XCTAssertEqual(document.scene.objects.values.filter { $0.kind != .camera }.count, 50)
        let builder = ShotBuilder(document: document, catalog: .empty, models: models)
        var times: [Double] = []
        for index in 0 ..< 150 {
            let start = CACurrentMediaTime()
            let request = builder.request(at: Double(index) / 60, framing: .landscape, size: CGSize(width: width, height: height),
                                          frameIndex: index, renderScale: scale)
            try await frames.render(request, width: width, height: height)
            // The first 30 frames warm the pipelines and caches up.
            if index >= 30 { times.append(CACurrentMediaTime() - start) }
        }
        times.sort()
        let p95 = times[Int(Double(times.count - 1) * 0.95)] * 1000
        let median = times[times.count / 2] * 1000
        print(String(format: "TIER-B: 50 things at %d × %d, median %.1f ms, p95 %.1f ms (budget %.1f ms)", width, height, median, p95,
                     Self.budget * 1000))
        XCTAssertLessThanOrEqual(p95, Self.budget * 1000, "fifty things at Tier B miss 60 fps")
    }

    /// Fifty bevelled shapes in four colours on a ten-by-five grid, in the Ink Look (its lines are the heaviest
    /// everyday pass), lit by the day.
    static func fiftyThings() -> Document {
        var ids = IDFactory.sequential("tierb")
        var look = MoodPresets.look(for: .day)
        look.presetID = LookPreset.ink.id
        let info = ProjectInfo(id: "tierb-project", name: "Tier B", look: look)
        var scene = Scene(id: "tierb-scene", name: "Tier B")
        var objects: [SceneObject] = []
        let shapes: [PrimitiveShape] = [.cube, .sphere, .cylinder, .cone, .torus]
        for index in 0 ..< 50 {
            let shape = shapes[index % shapes.count]
            let position = Vec3(Double(index % 10) * 1.2 - 5.4, 0, Double(index / 10) * 1.2 - 2.4)
            var object = SceneObject(id: ids.next(), name: "Thing \(index + 1)", kind: .primitive(shape),
                                     transform: Transform(position: position, scale: Vec3(0.8, 0.8, 0.8)))
            object[.color] = .color(.palette(index % 4))
            if BevelSpec.applies(to: shape) {
                object[.bevel] = .float(BevelSpec.standard.radius)
                object[.bevelSegments] = .int(BevelSpec.standard.segments)
            }
            objects.append(object)
        }
        let camera = TestScenes.camera(ids: &ids, view: Viewpoint(target: Vec3(0, 0.3, 0), yaw: 28, pitch: 24, distance: 13))
        objects.append(camera)
        for object in objects {
            scene.objects[object.id] = object
        }
        scene.roots = objects.map(\.id)
        scene.activeCamera = camera.id
        scene.timeline = Timeline(fps: 60, duration: 3)
        return Document(project: info, scene: scene)
    }
}
