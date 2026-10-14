import Foundation
@testable import LoweyCore
import XCTest

/// SPIKE (U6 step 5): clean topology through Instant Meshes, vendored, inside the time budget on a 500 000 triangle
/// sculpt. In a release build (`swift test -c release`, as CI runs the spike) it must take under 30 seconds on the CI
/// machine; the iPad's own time is a device check. Also the cage's cost on a 50 000 triangle model (U1's gates).
final class QuadRemeshTests: XCTestCase {
    /// A lumpy ball of `rings` rows of `rings` corners: 2 · rings² triangles.
    static func ball(rings: Int) -> MeshData {
        var mesh = MeshData()
        for row in 0 ... rings {
            let v = Double.pi * Double(row) / Double(rings)
            for column in 0 ..< rings {
                let u = 2 * Double.pi * Double(column) / Double(rings)
                let radius = 1 + 0.08 * sin(5 * u) * sin(4 * v) + 0.03 * sin(17 * u + 3 * v)
                mesh.addVertex(SIMD3<Float>(Float(radius * sin(v) * cos(u)), Float(radius * cos(v)), Float(radius * sin(v) * sin(u))))
            }
        }
        for row in 0 ..< rings {
            for column in 0 ..< rings {
                let a = UInt32(row * rings + column), b = UInt32(row * rings + (column + 1) % rings)
                let c = a + UInt32(rings), d = b + UInt32(rings)
                // Wound so the faces point out.
                if row > 0 { mesh.addTriangle(a, b, c) }
                if row < rings - 1 { mesh.addTriangle(b, d, c) }
            }
        }
        return mesh
    }

    func testASculptBecomesCleanQuadsInsideTheBudget() throws {
        // The full-size sculpt in a release build; a debug build (the everyday suite, Eigen unoptimised) checks the same
        // on a smaller one.
        #if DEBUG
            let sculpt = Self.ball(rings: 40)
            let faces = 250
        #else
            let sculpt = Self.ball(rings: 500)
            XCTAssertGreaterThan(sculpt.triangleCount, 495_000)
            let faces = 2000
        #endif
        let start = Date()
        let cleaned = try QuadRemesh.remesh(sculpt, options: QuadRemesh.Options(faces: faces))
        let seconds = Date().timeIntervalSince(start)
        let quads = cleaned.faces.filter { $0.outline.count == 4 }.count
        print("SPIKE clean topology \(sculpt.triangleCount) triangles → \(cleaned.faces.count) faces (\(quads) quads) in \(String(format: "%.2f", seconds)) s")
        XCTAssertGreaterThan(cleaned.faces.count, faces * 6 / 10)
        XCTAssertLessThan(cleaned.faces.count, faces * 16 / 10)
        XCTAssertGreaterThan(Double(quads) / Double(cleaned.faces.count), 0.6)
        XCTAssertGreaterThan(cleaned.volume, 0, "faces point out like the sculpt's")
        // Every corner still lies on the lumpy surface.
        for vertex in cleaned.vertices.prefix(2000) {
            XCTAssertEqual(vertex.length, 1, accuracy: 0.15)
        }
        #if !DEBUG
            XCTAssertLessThan(seconds, 30, "inside the time budget")
        #endif
    }

    func testACageMovesFiftyThousandTrianglesQuickly() throws {
        let model = Self.ball(rings: 160)
        XCTAssertGreaterThan(model.triangleCount, 50000)
        var cage = try DeformCage.around(XCTUnwrap(model.bounds), counts: [4, 4, 4])
        cage.offsets[cage.index(3, 3, 3)] = Vec3(0.4, 0.2, 0)
        let start = Date()
        let moved = CageDeform.apply(cage, to: model.positions)
        let seconds = Date().timeIntervalSince(start)
        print("SPIKE cage on \(model.triangleCount) triangles in \(String(format: "%.1f", seconds * 1000)) ms")
        XCTAssertEqual(moved.count, model.positions.count)
        #if !DEBUG
            XCTAssertLessThan(seconds, 0.25, "fast enough to follow a dragged point")
        #endif
    }
}
