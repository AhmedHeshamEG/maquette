import Foundation
@testable import LoweyCore
import XCTest

final class SketchAssistTests: XCTestCase {
    func testALineTellsItsLengthAndAngle() {
        let guess = SketchAssist.guess(from: Vec2(0, 0), to: Vec2(3, 4), edges: [], reach: 0.01, snapping: false)
        XCTAssertEqual(guess.length, 5, accuracy: 1e-12)
        XCTAssertEqual(guess.angle, atan2(4, 3) * 180 / .pi, accuracy: 1e-9)
        XCTAssertNil(guess.snap)
    }

    func testANearlyRoundAngleSnapsAndIsNamed() {
        let guess = SketchAssist.guess(from: Vec2(0, 0), to: Vec2(1, 1.03), edges: [], reach: 0.01)
        XCTAssertEqual(guess.snap, .angle(45))
        XCTAssertEqual(guess.snap?.label, "45°")
        XCTAssertEqual(guess.angle, 45, accuracy: 1e-9)
        XCTAssertEqual(guess.length, Vec2(1, 1.03).length, accuracy: 1e-9, "the length the Pencil drew is kept")
        XCTAssertEqual(guess.ghost.count, 2)
        let down = SketchAssist.guess(from: Vec2(0, 0), to: Vec2(0.01, -2), edges: [], reach: 0.01)
        XCTAssertEqual(down.snap, .angle(270))
        XCTAssertEqual(down.point.x, 0, accuracy: 1e-9)
    }

    func testCornersAndMiddlesWinOverAngles() {
        let edges = [(Vec2(2, 0), Vec2(2, 2))]
        XCTAssertEqual(SketchAssist.guess(from: .zero, to: Vec2(2.005, 2.004), edges: edges, reach: 0.02).snap, .corner)
        let middle = SketchAssist.guess(from: .zero, to: Vec2(1.99, 1.01), edges: edges, reach: 0.02)
        XCTAssertEqual(middle.snap, .midpoint)
        XCTAssertEqual(middle.point, Vec2(2, 1))
    }

    func testParallelAndPerpendicularToAnEdgeAlreadyThere() {
        // An edge at 20°, which is not a round angle.
        let radians = 20 * Double.pi / 180
        let edge = (Vec2(5, 5), Vec2(5 + cos(radians), 5 + sin(radians)))
        let parallel = SketchAssist.guess(from: .zero, to: Vec2(cos(radians + 0.02), sin(radians + 0.02)) * 2, edges: [edge], reach: 0.01)
        XCTAssertEqual(parallel.snap, .parallel)
        XCTAssertEqual(parallel.angle, 20, accuracy: 1e-9)
        XCTAssertEqual(parallel.ghost, [edge.0, edge.1], "the ghost shows the edge it lines up with")
        let across = radians + .pi / 2 - 0.02
        let perpendicular = SketchAssist.guess(from: .zero, to: Vec2(cos(across), sin(across)) * 2, edges: [edge], reach: 0.01)
        XCTAssertEqual(perpendicular.snap, .perpendicular)
        XCTAssertEqual(perpendicular.angle, 110, accuracy: 1e-9)
        let reversed = SketchAssist.guess(from: .zero, to: Vec2(-cos(radians), -sin(radians + 0.01)) * 2, edges: [edge], reach: 0.01)
        XCTAssertEqual(reversed.snap, .parallel, "a line drawn the other way is parallel too")
    }

    func testClipsRetimeByTheirEdges() {
        let clip = ClipSegment(id: "c", clip: ClipRef(asset: "kit", name: "walk"), start: 1, duration: 2, speed: 1)
        let longer = clip.retimed(end: true, to: 5)
        XCTAssertEqual(longer.duration, 4)
        XCTAssertEqual(longer.speed, 0.5, "the same motion, slower")
        XCTAssertEqual(longer.start, 1)
        let earlier = clip.retimed(end: false, to: 2)
        XCTAssertEqual(earlier.start, 2)
        XCTAssertEqual(earlier.end, 3, accuracy: 1e-12, "the other edge stays")
        XCTAssertEqual(earlier.speed, 2)
        XCTAssertGreaterThan(clip.retimed(end: true, to: 0).duration, 0, "never shorter than a frame")
    }
}
