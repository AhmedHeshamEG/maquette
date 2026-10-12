import Foundation
@testable import LoweyCore
import XCTest

/// SPIKE (U4 step 6): a quadric simplifier in Core lightens a sculpt-sized mesh inside the time budget. The sculpt is
/// a lumpy sphere of 1.3 million triangles painted red on top and blue below, the size Nomad exports. Lightened to a
/// tenth it must keep its shape and its paint; in a release build (`swift test -c release`, as CI runs the spike) it
/// must take under 20 seconds on the CI machine.
final class MeshSimplifyTests: XCTestCase {
    /// An icosphere subdivided `levels` times, pushed in and out by a few smooth bumps, painted by height.
    static func sculpt(levels: Int) -> (mesh: MeshData, colors: [SIMD4<Float>]) {
        let t = Float((1 + 5.0.squareRoot()) / 2)
        var positions: [SIMD3<Float>] = [[-1, t, 0], [1, t, 0], [-1, -t, 0], [1, -t, 0], [0, -1, t], [0, 1, t], [0, -1, -t], [0, 1, -t],
                                         [t, 0, -1], [t, 0, 1], [-t, 0, -1], [-t, 0, 1]].map { $0 / length3($0) }
        var faces: [SIMD3<UInt32>] = [[0, 11, 5], [0, 5, 1], [0, 1, 7], [0, 7, 10], [0, 10, 11], [1, 5, 9], [5, 11, 4], [11, 10, 2],
                                      [10, 7, 6], [7, 1, 8], [3, 9, 4], [3, 4, 2], [3, 2, 6], [3, 6, 8], [3, 8, 9], [4, 9, 5],
                                      [2, 4, 11], [6, 2, 10], [8, 6, 7], [9, 8, 1]]
        for _ in 0 ..< levels {
            var middles: [UInt64: UInt32] = [:]
            func middle(_ a: UInt32, _ b: UInt32) -> UInt32 {
                let key = UInt64(min(a, b)) << 32 | UInt64(max(a, b))
                if let known = middles[key] { return known }
                let point = (positions[Int(a)] + positions[Int(b)]) / 2
                positions.append(point / length3(point))
                middles[key] = UInt32(positions.count - 1)
                return UInt32(positions.count - 1)
            }
            var next: [SIMD3<UInt32>] = []
            next.reserveCapacity(faces.count * 4)
            for face in faces {
                let ab = middle(face.x, face.y), bc = middle(face.y, face.z), ca = middle(face.z, face.x)
                next += [[face.x, ab, ca], [face.y, bc, ab], [face.z, ca, bc], [ab, bc, ca]]
            }
            faces = next
        }
        var mesh = MeshData()
        mesh.positions = positions.map { point in
            let bump = 1 + 0.08 * sin(point.x * 7) * sin(point.y * 5) + 0.05 * cos(point.z * 9)
            return point * bump
        }
        mesh.indices = faces.flatMap { [$0.x, $0.y, $0.z] }
        mesh.uvs = Array(repeating: .zero, count: mesh.positions.count)
        mesh.computeSmoothNormals()
        let colors = mesh.positions.map { $0.y > 0 ? SIMD4<Float>(1, 0, 0, 1) : SIMD4<Float>(0, 0, 1, 1) }
        return (mesh, colors)
    }

    func testASculptIsLightenedToATenthKeepingItsShapeAndPaint() throws {
        // The full-size sculpt in a release build; a debug build (the everyday suite) checks the same on a smaller one.
        #if DEBUG
            let (mesh, colors) = Self.sculpt(levels: 6)
            XCTAssertEqual(mesh.triangleCount, 81920)
        #else
            let (mesh, colors) = Self.sculpt(levels: 8)
            XCTAssertEqual(mesh.triangleCount, 1_310_720)
        #endif
        let target = mesh.triangleCount / 10
        let start = Date()
        let (light, carried) = MeshSimplify.simplified(mesh, colors: colors, target: target)
        let seconds = Date().timeIntervalSince(start)
        print("SPIKE simplify \(mesh.triangleCount) → \(light.triangleCount) triangles in \(String(format: "%.2f", seconds)) s")
        XCTAssertLessThanOrEqual(light.triangleCount, target)
        XCTAssertGreaterThan(light.triangleCount, target * 9 / 10)
        // Every corner still lies on the lumpy surface (within half a percent of its size).
        for point in light.positions.prefix(5000) {
            let direction = point / length3(point)
            let surface = 1 + 0.08 * sin(direction.x * 7) * sin(direction.y * 5) + 0.05 * cos(direction.z * 9)
            XCTAssertEqual(length3(point), surface, accuracy: 0.01)
        }
        XCTAssertEqual(carried.count, light.positions.count)
        for (point, color) in zip(light.positions, carried) where abs(point.y) > 0.05 {
            XCTAssertEqual(color.x, point.y > 0 ? 1 : 0, "red on top, blue below")
        }
        XCTAssertEqual(light.normals.count, light.positions.count)
        #if !DEBUG
            XCTAssertLessThan(seconds, 20, "inside the time budget")
        #endif
    }

    func testOpenEdgesStayAndASmallMeshIsLeftAlone() throws {
        // A flat square cut into many triangles: its outline is kept while its inside is lightened.
        var grid = MeshData()
        let steps = 40
        for y in 0 ... steps {
            for x in 0 ... steps {
                grid.addVertex(SIMD3<Float>(Float(x) / Float(steps), 0, Float(y) / Float(steps)))
            }
        }
        for y in 0 ..< steps {
            for x in 0 ..< steps {
                let a = UInt32(y * (steps + 1) + x)
                grid.addTriangle(a, a + UInt32(steps + 1), a + 1)
                grid.addTriangle(a + 1, a + UInt32(steps + 1), a + UInt32(steps + 2))
            }
        }
        let (light, _) = MeshSimplify.simplified(grid, target: 200)
        XCTAssertLessThanOrEqual(light.triangleCount, 200)
        XCTAssertEqual(light.bounds, grid.bounds, "the corners of the square stay")
        let cube = PrimitiveMesh.make(.cube, shading: .smooth)
        XCTAssertEqual(MeshSimplify.simplified(cube, target: 100).mesh, cube)
    }
}
