import CoreGraphics
import LoweyCore
@testable import LoweyEngine
import Metal
import XCTest

/// U7 on the GPU: painted maps change the light (metal, roughness, glow, bumps), a mask hides its layer, a mirrored
/// stroke lands on both sides, fur grows, and a light sphere with normals baked from a detailed one shades like it.
@MainActor
final class TextureRenderTests: XCTestCase {
    private var device: RenderDevice!

    override func setUp() async throws {
        device = try RenderDevice.sharedDevice()
    }

    /// A grey cube with one layer whose maps `paint` fills, in front of the camera; its files.
    private func cube(_ edit: (inout ObjectPaint, inout [String: Data], MeshData) throws -> Void = { _, _, _ in }) throws -> (Document, [String: Data]) {
        var cube = SceneObject(id: "cube", name: "Cube", kind: .primitive(.cube))
        cube[.color] = .color(.rgba(RGBA(0.6, 0.6, 0.6)))
        let source = try XCTUnwrap(PaintSource.mesh(of: cube))
        var (paint, unwrap, files) = try PaintOperations.prepare(mesh: source, keepOwnUVs: false, size: 512)
        try edit(&paint, &files, XCTUnwrap(unwrap.mesh(over: source)))
        cube.paint = paint
        let document = TestDocuments.document("texture", objects: [cube], camera: Vec3(0, 0.5, 3.2), look: Look(presetID: LookPreset.clay.id))
        return (document, files)
    }

    /// A whole layer map filled with one value.
    private static func fill(_ map: PaintMap, _ color: RGBA, layer: Int = 0, paint: inout ObjectPaint, files: inout [String: Data]) {
        let filled = PaintOperations.fill(color, layer: paint.layers[layer], surface: paint.surface, object: "cube")
        files.merge(filled.files) { _, new in new }
        guard case let .paintTiles(_, changes) = filled.command else { return }
        for change in changes {
            paint.layers[layer][map, PaintTileIndex(key: change.tile) ?? .init(column: 0, row: 0)] = change.file
        }
    }

    private func render(_ document: Document, files: [String: Data]) async throws -> CGImage {
        let builder = ShotBuilder(document: document, catalog: .empty, models: ModelLibrary())
        builder.paintFile = { files[$0] }
        let request = builder.request(at: 0, framing: .landscape, size: CGSize(width: 640, height: 360), frameIndex: 0)
        return try await FrameRenderer(device: device, models: ModelLibrary()).image(request, width: 640, height: 360)
    }

    func testPaintedMapsChangeTheLight() async throws {
        let (plain, plainFiles) = try cube()
        let (shiny, shinyFiles) = try cube { paint, files, _ in
            Self.fill(.metal, .white, paint: &paint, files: &files)
            Self.fill(.roughness, RGBA(0.1, 0.1, 0.1), paint: &paint, files: &files)
        }
        let (glowing, glowFiles) = try cube { paint, files, _ in Self.fill(.glow, RGBA(1, 0.4, 0), paint: &paint, files: &files) }
        let plainImage = try await render(plain, files: plainFiles)
        let shinyImage = try await render(shiny, files: shinyFiles)
        let glowImage = try await render(glowing, files: glowFiles)
        GoldenImage().attach(shinyImage, name: "texture-metal")
        GoldenImage().attach(glowImage, name: "texture-glow")
        XCTAssertGreaterThan(ImageChecks.difference(plainImage, shinyImage), 0.01, "smooth metal looks different from grey paint")
        let lit = ImageChecks.rgb(glowImage, x: 0.5, y: 0.55)
        XCTAssertGreaterThan(lit.r, lit.b + 0.25, "it glows orange")
    }

    func testBumpsAndAMaskShowOnTheSurface() async throws {
        let brick = try XCTUnwrap(BuiltInMaterials.material("brick"))
        let (bricks, files) = try cube { paint, files, mesh in
            let made = try XCTUnwrap(PaintOperations.addFill(.material(brick), to: paint, above: nil, object: "cube",
                                                             images: PaintFills.images(.material(brick), paintMesh: mesh, size: 512)))
            files.merge(made.files) { a, _ in a }
            guard case let .setPaint(_, filled?) = made.command else { throw CommandError.empty }
            paint = filled
        }
        var hidden = bricks
        hidden.scene.objects["cube"]?.paint?.layers[1].maps[PaintMap.mask.rawValue] = [:]
        let shown = try await render(bricks, files: files)
        let masked = try await render(hidden, files: files)
        GoldenImage().attach(shown, name: "texture-bricks")
        XCTAssertGreaterThan(ImageChecks.difference(shown, masked), 0.02, "an empty mask hides the bricks")
        let face = ImageChecks.rgb(masked, x: 0.5, y: 0.55)
        XCTAssertLessThan(abs(face.r - face.b), 0.08, "behind the mask, the cube's own grey")
    }

    func testAMirroredStrokeLandsOnBothSides() async throws {
        let (document, files) = try cube()
        let builder = ShotBuilder(document: document, catalog: .empty, models: ModelLibrary())
        builder.paintFile = { files[$0] }
        var request = builder.request(at: 0, framing: .landscape, size: CGSize(width: 640, height: 360), frameIndex: 0)
        let brush = BuiltInBrushes.inkPen
        // A short stroke on the cube's left half only.
        let points = (0 ... 10).map { Vec2(270 + Double($0) * 2, 200) }
        let path = BrushPath(points: points, widths: Array(repeating: 16, count: points.count), alphas: Array(repeating: 1, count: points.count))
        request.livePaint = LivePaint(object: "cube", layer: "l1", stroke: 1, source: .stamps(BrushStroker.dabs(path, brush: brush, seed: 1), brush: brush),
                                      color: RGBA(0.1, 0.2, 0.95, 1), erases: false, pixelsPerPoint: 1, mirror: PaintMirror.x.scale)
        let frames = try FrameRenderer(device: device, models: ModelLibrary())
        let image = try await frames.image(request, width: 640, height: 360)
        GoldenImage().attach(image, name: "texture-mirror")
        let left = ImageChecks.rgb(image, x: 280.0 / 640, y: 200.0 / 360)
        let right = ImageChecks.rgb(image, x: 360.0 / 640, y: 200.0 / 360)
        XCTAssertGreaterThan(left.b, left.r + 0.2, "where it was drawn")
        XCTAssertGreaterThan(right.b, right.r + 0.2, "and mirrored across the cube's middle")
    }

    func testFurGrowsShellsAndCards() async throws {
        var (document, files) = try cube()
        document.scene.objects["cube"]?[.furLength] = .float(0.08)
        let shells = try await render(document, files: files)
        GoldenImage().attach(shells, name: "texture-fur")
        let (bare, bareFiles) = try cube()
        let plain = try await render(bare, files: bareFiles)
        XCTAssertGreaterThan(ImageChecks.difference(plain, shells), 0.005, "fur changes the outline")
        document.scene.objects["cube"]?[.furStyle] = .enumeration("cards")
        let frames = try FrameRenderer(device: device, models: ModelLibrary())
        let builder = ShotBuilder(document: document, catalog: .empty, models: ModelLibrary())
        builder.paintFile = { files[$0] }
        _ = try await frames.image(builder.request(at: 0, framing: .landscape, size: CGSize(width: 640, height: 360), frameIndex: 0), width: 640,
                                   height: 360)
        XCTAssertTrue(frames.renderer.lastScene?.items.contains { $0.furCards } == true, "cards drawn as their own items")
    }

    /// Acceptance (U7): a light sphere with normals baked from a detailed one shades like the detailed one (the Nomad
    /// fixture waits for Hesham's export, D-275; a dense sphere stands in).
    func testBakedNormalsMakeTheLightVersionLookLikeTheSculpt() async throws {
        let dense = PrimitiveMesh.sphere(segments: 96, rings: 64).shaded(.smooth)
        let light = MeshSimplify.simplified(PrimitiveMesh.make(.sphere), target: 90).mesh.shaded(.flat)
        func object(_ id: ObjectID, _ mesh: MeshData) -> SceneObject {
            var object = SceneObject(id: id, name: id.raw, kind: .mesh(MeshBuilder.mesh(from: mesh)))
            object[.color] = .color(.rgba(RGBA(0.8, 0.8, 0.8)))
            return object
        }
        let sculpt = object("sculpt", dense)
        var copy = object("copy", light)
        let source = try XCTUnwrap(PaintSource.mesh(of: copy))
        var (paint, unwrap, files) = try PaintOperations.prepare(mesh: source, keepOwnUVs: false, size: 1024)
        let high = try XCTUnwrap(PaintSource.mesh(of: sculpt))
        let png = try PNGCodec.encode(NormalBake.bake(low: XCTUnwrap(unwrap.mesh(over: source)), high: high, size: 1024))
        let name = PaintFiles.tileName(for: png)
        files[name] = png
        paint.normalMap = name
        let flat = copy
        copy.paint = paint
        let look = Look(presetID: LookPreset.clay.id)
        let reference = try await render(TestDocuments.document("sculpt", objects: [sculpt], camera: Vec3(0, 0.5, 2.4), look: look), files: [:])
        let baked = try await render(TestDocuments.document("baked", objects: [copy], camera: Vec3(0, 0.5, 2.4), look: look), files: files)
        let facets = try await render(TestDocuments.document("flat", objects: [flat], camera: Vec3(0, 0.5, 2.4), look: look), files: [:])
        GoldenImage().attach(baked, name: "texture-baked-normals")
        let bakedDifference = ImageChecks.difference(reference, baked)
        let facetDifference = ImageChecks.difference(reference, facets)
        XCTAssertLessThan(bakedDifference, facetDifference * 0.7, "baked \(bakedDifference) against the facets' \(facetDifference)")
    }
}
