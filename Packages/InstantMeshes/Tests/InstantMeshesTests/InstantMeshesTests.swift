import InstantMeshesCpp
import XCTest

final class InstantMeshesTests: XCTestCase {
    /// A lumpy ball: `rings` rows of `rings` corners, two triangles per square.
    private func ball(rings: Int) -> (positions: [Float], triangles: [UInt32]) {
        var positions: [Float] = []
        var triangles: [UInt32] = []
        for row in 0 ... rings {
            let v = Double.pi * Double(row) / Double(rings)
            for column in 0 ..< rings {
                let u = 2 * Double.pi * Double(column) / Double(rings)
                let radius = 1 + 0.08 * sin(5 * u) * sin(4 * v)
                positions += [Float(radius * sin(v) * cos(u)), Float(radius * cos(v)), Float(radius * sin(v) * sin(u))]
            }
        }
        for row in 0 ..< rings {
            for column in 0 ..< rings {
                let a = UInt32(row * rings + column), b = UInt32(row * rings + (column + 1) % rings)
                let c = a + UInt32(rings), d = b + UInt32(rings)
                if row > 0 { triangles += [a, b, c] }
                if row < rings - 1 { triangles += [b, d, c] }
            }
        }
        return (positions, triangles)
    }

    private func remesh(_ input: (positions: [Float], triangles: [UInt32]), faces: UInt32, pureQuads: Bool = false) -> (Int32, IMSurface) {
        var out = IMSurface()
        let options = IMOptions(targetFaces: faces, creaseDegrees: 0, pureQuads: pureQuads ? 1 : 0, alignToBoundaries: 0, smoothIterations: 0)
        let code = input.positions.withUnsafeBufferPointer { p in
            input.triangles.withUnsafeBufferPointer { t in
                IMRemesh(p.baseAddress, UInt32(input.positions.count / 3), t.baseAddress, UInt32(input.triangles.count / 3), options, &out)
            }
        }
        return (code, out)
    }

    func testABallBecomesMostlyQuadsNearTheAskedCount() throws {
        var (code, out) = remesh(ball(rings: 40), faces: 300)
        defer { IMFree(&out) }
        XCTAssertEqual(code, 0)
        let faces = Int(out.faceCount)
        XCTAssertGreaterThan(faces, 200)
        XCTAssertLessThan(faces, 450)
        let indices = UnsafeBufferPointer(start: out.indices, count: faces * 4)
        let quads = (0 ..< faces).filter { indices[$0 * 4 + 2] != indices[$0 * 4 + 3] }.count
        XCTAssertGreaterThan(Double(quads) / Double(faces), 0.7)
        // Every corner stays on the ball (radius 0.92…1.08).
        let positions = UnsafeBufferPointer(start: out.positions, count: Int(out.vertexCount) * 3)
        for vertex in 0 ..< Int(out.vertexCount) {
            let x = positions[vertex * 3], y = positions[vertex * 3 + 1], z = positions[vertex * 3 + 2]
            let radius = (x * x + y * y + z * z).squareRoot()
            XCTAssertEqual(radius, 1, accuracy: 0.12)
        }
    }

    func testPureQuadsHaveNoTriangles() {
        var (code, out) = remesh(ball(rings: 30), faces: 200, pureQuads: true)
        defer { IMFree(&out) }
        XCTAssertEqual(code, 0)
        let indices = UnsafeBufferPointer(start: out.indices, count: Int(out.faceCount) * 4)
        XCTAssertTrue((0 ..< Int(out.faceCount)).allSatisfy { indices[$0 * 4 + 2] != indices[$0 * 4 + 3] })
    }

    func testTheSameInputGivesTheSameQuads() {
        var (_, first) = remesh(ball(rings: 24), faces: 120)
        var (_, second) = remesh(ball(rings: 24), faces: 120)
        defer {
            IMFree(&first)
            IMFree(&second)
        }
        XCTAssertEqual(first.faceCount, second.faceCount)
        XCTAssertEqual(Array(UnsafeBufferPointer(start: first.indices, count: Int(first.faceCount) * 4)),
                       Array(UnsafeBufferPointer(start: second.indices, count: Int(second.faceCount) * 4)))
    }

    func testBadInputIsRefused() {
        var out = IMSurface()
        let positions: [Float] = [0, 0, 0, 1, 0, 0, 0, 1, 0]
        let triangles: [UInt32] = [0, 1, 7]
        let options = IMOptions(targetFaces: 100, creaseDegrees: 0, pureQuads: 0, alignToBoundaries: 0, smoothIterations: 0)
        XCTAssertNotEqual(IMRemesh(positions, 3, triangles, 1, options, &out), 0)
    }
}
