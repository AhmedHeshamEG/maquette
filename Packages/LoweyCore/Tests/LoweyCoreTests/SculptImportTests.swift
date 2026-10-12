import Foundation
@testable import LoweyCore
import XCTest

/// Bring your sculpt (U4 step 6): vertex colours in from glTF and OBJ, a heavy sculpt lightened as it comes in with its
/// paint carried across, and the lighter file kept with its colours. The real Nomad export joins these as a fixture
/// when Hesham sends it; until then the sculpt is made here the way Nomad writes one (one mesh, colours on its corners,
/// no texture).
final class SculptImportTests: XCTestCase {
    func testGLTFVertexColoursComeInAsSRGBAndGoOutAsLinear() throws {
        let (mesh, colors) = MeshSimplifyTests.sculpt(levels: 3)
        let painted = colors.map { $0.x > 0.5 ? SIMD4<Float>(0.8, 0.4, 0.2, 1) : SIMD4<Float>(0.2, 0.5, 0.9, 1) }
        let model = ImportedModel(parts: [ImportedPart(name: "Sculpt", mesh: mesh, material: 0, colors: painted)],
                                  materials: [ImportedMaterial(name: "Sculpt", baseColor: RGBA(1, 1, 1))])
        let back = try GLTFMeshReader.model(data: SculptImport.glb(model, name: "Sculpt"))
        XCTAssertTrue(back.hasVertexColors)
        let part = try XCTUnwrap(back.parts.first)
        for (a, b) in zip(part.colors, painted) {
            XCTAssertEqual(a.x, b.x, accuracy: 1e-4)
            XCTAssertEqual(a.y, b.y, accuracy: 1e-4)
            XCTAssertEqual(a.z, b.z, accuracy: 1e-4)
        }
        XCTAssertEqual(ColorSpace.srgb(fromLinear: ColorSpace.linear(fromSRGB: 0.37)), 0.37, accuracy: 1e-12)
    }

    func testOBJColoursAfterEachCornerAreRead() throws {
        let obj = """
        # Nomad-style: colours after each corner, no normals
        v 0 0 0 1 0 0
        v 1 0 0 0 1 0
        v 0 1 0 0 0 1
        v 1 1 0 1 1 1
        f 1 2 3
        f 2 4 3
        """
        let model = try OBJParser.model(Data(obj.utf8), name: "Sculpt")
        let part = try XCTUnwrap(model.parts.first)
        XCTAssertEqual(part.mesh.triangleCount, 2)
        XCTAssertEqual(part.colors.count, part.mesh.positions.count)
        XCTAssertEqual(part.colors.first, SIMD4<Float>(1, 0, 0, 1))
        XCTAssertEqual(part.mesh.normals.count, part.mesh.positions.count, "smooth normals made")
        // Colours written as 0…255, faces as v/vt/vn with negative indices, and exponents.
        let wide = "v 0 0 0 255 128 0\nv 1e0 0 0 255 128 0\nv 0 1.0E+0 0 255 128 0\nvt 0 0\nvn 0 0 1\nf -3/1/1 -2/1/1 -1/1/1\n"
        let other = try OBJParser.model(Data(wide.utf8), name: "Wide")
        XCTAssertEqual(other.parts[0].colors.first?.y ?? 0, 128.0 / 255, accuracy: 1e-6)
        XCTAssertEqual(other.parts[0].mesh.positions[1], SIMD3<Float>(1, 0, 0))
        XCTAssertEqual(other.parts[0].mesh.positions[2], SIMD3<Float>(0, 1, 0))
        // A file without colours has none.
        XCTAssertFalse(try OBJParser.model(Data("v 0 0 0\nv 1 0 0\nv 0 1 0\nf 1 2 3\n".utf8), name: "Plain").hasVertexColors)
    }

    func testAHeavySculptIsLightenedToTheTiersBudgetWithItsPaint() throws {
        let (mesh, colors) = MeshSimplifyTests.sculpt(levels: 6)
        let model = ImportedModel(parts: [ImportedPart(name: "Sculpt", mesh: mesh, material: 0, colors: colors)], materials: [])
        XCTAssertEqual(SculptImport.budget(tier: "b"), 200_000)
        XCTAssertNil(SculptImport.lightened(model, target: 200_000), "light enough already")
        let target = SculptImport.target(budget: 40000, detail: 1)
        let light = try XCTUnwrap(SculptImport.lightened(model, target: target))
        XCTAssertLessThanOrEqual(light.triangleCount, target)
        XCTAssertGreaterThan(light.triangleCount, target * 8 / 10)
        XCTAssertTrue(light.hasVertexColors, "the paint came along")
        // More detail asks for more triangles, within the slider's range.
        XCTAssertEqual(SculptImport.target(budget: 40000, detail: 9), 80000)
        XCTAssertEqual(SculptImport.target(budget: 40000, detail: 0.5), 20000)
        // A model with a picture wrapped on it isn't lightened (its picture would lose its place).
        var textured = model
        textured.materials[0].baseColorTexture = 0
        XCTAssertNil(SculptImport.lightened(textured, target: target))
    }
}
