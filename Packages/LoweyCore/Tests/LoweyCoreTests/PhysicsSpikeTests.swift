import Foundation
@testable import LoweyCore
import XCTest

/// P1's benchmark gates, run in a release build on CI (the numbers go to the run summary; the iPad's are the device
/// check): a 500-body stack through the whole Core path, and a glass filling with water, made once and then played from
/// the run, where a frame costs a lookup, not a simulation.
final class PhysicsSpikeTests: XCTestCase {
    func testFiveHundredBodiesThroughTheCorePath() throws {
        var objects: [SceneObject] = []
        for layer in 0 ..< 5 {
            for row in 0 ..< 10 {
                for column in 0 ..< 10 {
                    let id = ObjectID(raw: "b\(layer)-\(row)-\(column)")
                    objects.append(PhysicsTests.cube(id, at: Vec3(Double(column) * 0.51 - 2.5, Double(layer) * 0.5, Double(row) * 0.51 - 2.5), size: 0.5))
                }
            }
        }
        let document = PhysicsTests.document(objects, duration: 2, fps: 60)
        let input = try PhysicsTests.input(document)
        let start = Date()
        let frames = try XCTUnwrap(PhysicsSimulator.run(input))
        let perFrame = Date().timeIntervalSince(start) / Double(frames.frames.count) * 1000
        print("SPIKE (P1) 500 bodies through PhysicsSimulator: \(String(format: "%.2f", perFrame)) ms per 60 Hz frame")
        let top = Animator.evaluate(document, at: 2, physics: frames).scene.objects["b4-9-9"]?.transform.position.y ?? 0
        XCTAssertEqual(top, 2, accuracy: 0.05, "the tower stands")
    }

    func testAGlassFillsWithWaterAndPlaysFromTheRun() throws {
        let glass = PhysicsMoreTests.glass()
        let tap = SceneObject(id: "tap", name: "Tap", kind: .fluid(FluidRecipe(kind: .pour, box: Vec3(0.4, 0.4, 0.4), amount: 0.12, duration: 2)),
                              transform: Transform(position: Vec3(0, 0.22, 0)))
        let document = PhysicsTests.document([glass, tap], duration: 2.5, fps: 30)
        let started = Date()
        let frames = try PhysicsTests.run(document)
        let bake = Date().timeIntervalSince(started)
        let litres = frames.frames.last?.fluids.first?.amount ?? 0
        let playing = Date()
        var drawn = 0
        for frame in 0 ..< frames.frames.count {
            drawn += Animator.evaluate(document, at: Double(frame) / 30, physics: frames).simulated.fluids["tap"]?.surface?.triangleCount ?? 0
        }
        let perFrame = Date().timeIntervalSince(playing) / Double(frames.frames.count) * 1000
        print("SPIKE (P1) a glass fills with \(String(format: "%.2f", litres)) l of water: made in \(String(format: "%.1f", bake)) s "
            + "(\(String(format: "%.0f", bake / Double(frames.frames.count) * 1000)) ms a frame, in the background); "
            + "played at \(String(format: "%.2f", perFrame)) ms a frame from the run")
        XCTAssertGreaterThan(litres, 0.15)
        XCTAssertGreaterThan(drawn, 0)
        XCTAssertLessThan(perFrame, 4, "playing from the run fits a frame's budget")
    }
}
