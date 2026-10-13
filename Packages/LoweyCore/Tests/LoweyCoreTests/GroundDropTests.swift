@testable import LoweyCore
import XCTest

/// U5 (device note: "To the ground" left things hovering): a thing lands by its lowest real points, on the highest
/// surface under them or on the ground.
final class GroundDropTests: XCTestCase {
    /// A square table top at `height`, 2 m across, facing up.
    private func tableTop(_ height: Float) -> MeshData {
        MeshData(positions: [SIMD3(-1, height, -1), SIMD3(1, height, -1), SIMD3(1, height, 1), SIMD3(-1, height, 1)],
                 normals: Array(repeating: SIMD3(0, 1, 0), count: 4), uvs: Array(repeating: .zero, count: 4), indices: [0, 2, 1, 0, 3, 2])
    }

    func testAThingLandsOnTheSurfaceUnderItsLowestPoint() {
        let lowest = GroundDrop.lowest(of: MeshData(positions: [SIMD3(0.1, 1.3, 0), SIMD3(0.2, 1.3, 0), SIMD3(0.1, 1.8, 0)]))
        XCTAssertEqual(lowest.count, 2, "only the lowest corners")
        XCTAssertEqual(GroundDrop.rise(lowest: lowest, top: 1.8, surfaces: [tableTop(1)]), -0.3, accuracy: 1e-6, "down onto the table")
        XCTAssertEqual(GroundDrop.rise(lowest: lowest, top: 1.8, surfaces: []), -1.3, accuracy: 1e-6, "nothing under: the ground")
    }

    func testASunkThingComesUpAndOneBesideTheTableGoesToTheGround() {
        let sunk = [Vec3(0, 0.9, 0)]
        XCTAssertEqual(GroundDrop.rise(lowest: sunk, top: 1.2, surfaces: [tableTop(1)]), 0.1, accuracy: 1e-6)
        let beside = [Vec3(3, 0.5, 0)]
        XCTAssertEqual(GroundDrop.rise(lowest: beside, top: 1, surfaces: [tableTop(1)]), -0.5, accuracy: 1e-6)
        XCTAssertEqual(GroundDrop.rise(lowest: [], top: 1, surfaces: []), 0)
    }
}

/// U5: a closed shape shows one arrow to pull it into a solid.
final class PullArrowTests: XCTestCase {
    func testTheArrowRisesFromTheMiddleOfTheRegion() throws {
        var mesh = MeshData()
        ModelOverlay.arrow(from: Vec3(1, 0, 1), direction: .unitY, length: 0.5, width: 0.01, into: &mesh)
        let bounds = try XCTUnwrap(mesh.bounds)
        XCTAssertEqual(bounds.max.y, 0.5, accuracy: 0.01)
        XCTAssertEqual(bounds.min.y, 0, accuracy: 0.01)
        XCTAssertEqual(mesh.triangleCount, 8 * 5, "a shaft and four barbs")
        var none = MeshData()
        ModelOverlay.arrow(from: .zero, direction: .zero, length: 1, width: 0.01, into: &none)
        XCTAssertTrue(none.isEmpty)
        let region = SketchRegion(outline: [Vec2(0, 0), Vec2(2, 0), Vec2(2, 2), Vec2(0, 2)], holes: [])
        XCTAssertEqual(ModelOverlay.middle(of: region), Vec2(1, 1))
    }
}
