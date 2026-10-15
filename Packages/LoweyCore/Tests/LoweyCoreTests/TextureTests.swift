import Foundation
@testable import LoweyCore
import XCTest

/// U7: paint as maps (colour, roughness, metal, glow, bumps, fur) with masks and fill layers; materials, wear,
/// decals, faces, smudge, seams, texture size, normal bakes, fur and every map leaving in glTF and USDZ.
final class TextureTests: XCTestCase {
    /// A painted cube at a small size (fast), its paint mesh and the files so far.
    private func cube(size: Int = 256) throws -> (object: SceneObject, paint: ObjectPaint, mesh: MeshData, files: [String: Data]) {
        var cube = SceneObject(id: "cube", name: "Crate", kind: .primitive(.cube))
        cube[.color] = .color(.rgba(RGBA(1, 1, 1)))
        let source = try XCTUnwrap(PaintSource.mesh(of: cube))
        let prepared = try PaintOperations.prepare(mesh: source, keepOwnUVs: false, size: size)
        let mesh = try XCTUnwrap(prepared.unwrap.mesh(over: source))
        cube.paint = prepared.paint
        return (cube, prepared.paint, mesh, prepared.files)
    }

    // MARK: Maps, masks and the document

    func testMapTilesRevertAndSurviveJSON() throws {
        var document = makeDocument()
        var (_, paint, _, _) = try cube()
        paint.layers[0].maps[PaintMap.mask.rawValue] = [:]
        _ = try EditCommand.setPaint("a", paint).apply(to: &document)
        let tile = PaintTileIndex(column: 0, row: 0)
        let applied = try assertReverts(.paintTiles("a", [PaintTileChange(layer: "l1", tile: tile, file: "paint/r.png", map: .roughness),
                                                          PaintTileChange(layer: "l1", tile: tile, file: "paint/m.png", map: .mask)]),
                                        on: document)
        let layer = try XCTUnwrap(applied.scene.objects["a"]?.paint?.layers.first)
        XCTAssertEqual(layer[.roughness, tile], "paint/r.png")
        XCTAssertEqual(layer[.mask, tile], "paint/m.png")
        XCTAssertNil(layer[tile], "colour untouched")
        XCTAssertEqual(layer.paintedMaps, [.roughness])
        XCTAssertTrue(layer.hasMask)
        var working = document
        XCTAssertThrowsError(try EditCommand.paintTiles("a", [PaintTileChange(layer: "l1", tile: "0,0", file: nil, mapName: "sparkle")])
            .apply(to: &working), "a map this app doesn't know")
        var unmasked = document
        unmasked.scene.objects["a"]?.paint?.layers[0].maps = [:]
        XCTAssertThrowsError(try EditCommand.paintTiles("a", [PaintTileChange(layer: "l1", tile: tile, file: "paint/m.png", map: .mask)])
            .apply(to: &unmasked), "no mask to paint")
        // Round trip, and a 0.17 layer (no maps, no fill) still reads.
        let data = try LoweyJSON.encode(layer)
        XCTAssertEqual(try LoweyJSON.decode(PaintLayer.self, from: data), layer)
        let old = try LoweyJSON.decode(
            PaintLayer.self,
            from: Data(#"{"id":"l1","name":"Layer 1","opacity":1,"blend":"normal","visible":true,"tiles":{}}"#.utf8)
        )
        XCTAssertTrue(old.maps.isEmpty)
        XCTAssertNil(old.fill)
        XCTAssertFalse(try String(decoding: LoweyJSON.encode(old), as: UTF8.self).contains("maps"), "no maps, no key")
        let fill = try PaintLayer(id: "f", name: "Oak", fill: .material(XCTUnwrap(BuiltInMaterials.material("oak"))))
        XCTAssertEqual(try LoweyJSON.decode(PaintLayer.self, from: LoweyJSON.encode(fill)), fill)
        XCTAssertEqual(try LoweyJSON.decode(PaintFill.self, from: LoweyJSON.encode(PaintFill.wear(PaintWear(kind: .edges)))),
                       .wear(PaintWear(kind: .edges)))
    }

    func testAMaskHidesItsLayerWhereItsClear() throws {
        let surface = PaintSurface(size: 256, unwrap: "u", mesh: "m")
        let red = RGBAImage(width: 256, height: 256, color: RGBA(1, 0, 0, 1))
        var half = RGBAImage.clear(width: 256, height: 256)
        for y in 0 ..< 256 {
            for x in 0 ..< 128 {
                half.setPixel(x, y, .white)
            }
        }
        var layer = PaintLayer(id: "l1", name: "Red")
        layer.tiles["0,0"] = "red"
        layer[.mask, PaintTileIndex(column: 0, row: 0)] = "half"
        let pictures = ["red": red, "half": half]
        let composite = PaintComposer.composite(ObjectPaint(surface: surface, layers: [layer])) { layer, map in
            PaintComposer.layerImage(layer, map: map, surface: surface) { pictures[$0] }
        }
        XCTAssertEqual(composite.pixel(10, 10), RGBA(1, 0, 0, 1), "shown where the mask is white")
        XCTAssertEqual(composite.pixel(200, 10).a, 0, "hidden where it's clear")
        // A mask with no tiles hides everything; switching one on shows everything.
        var empty = layer
        empty.maps[PaintMap.mask.rawValue] = [:]
        XCTAssertTrue(empty.hasMask)
        let paint = ObjectPaint(surface: surface, layers: [PaintLayer(id: "l1", name: "L")])
        let made = try XCTUnwrap(PaintOperations.setMask(true, layer: "l1", in: paint, object: "a"))
        guard case let .setPaint(_, masked?) = made.command else { return XCTFail("a paint change") }
        XCTAssertEqual(masked.layers[0].tiles(of: .mask).count, 1, "every tile of a 256 surface, opaque")
        XCTAssertNil(PaintOperations.setMask(true, layer: "l1", in: masked, object: "a"), "already masked")
    }

    func testNewBlendModes() {
        XCTAssertEqual(PaintBlend.darken.mix(0.3, 0.6), 0.3)
        XCTAssertEqual(PaintBlend.lighten.mix(0.3, 0.6), 0.6)
        XCTAssertEqual(PaintBlend.softLight.mix(0.5, 0.5), 0.5, accuracy: 1e-9, "a mid source leaves it")
        XCTAssertLessThan(PaintBlend.softLight.mix(0.5, 0.2), 0.5)
        XCTAssertEqual(PaintBlend.allCases.map(\.shaderIndex), Array(0 ..< PaintBlend.allCases.count), "the shader's numbers")
        XCTAssertEqual(PaintBlend.normal.shaderIndex, 0)
        XCTAssertEqual(PaintBlend.add.shaderIndex, 4, "the 0.17 modes keep their numbers")
    }

    // MARK: Materials

    func testMaterialsAreDeterministicAndInRange() throws {
        XCTAssertGreaterThanOrEqual(BuiltInMaterials.all.count, 20)
        XCTAssertEqual(Set(BuiltInMaterials.all.map(\.id)).count, BuiltInMaterials.all.count, "ids are unique")
        for material in BuiltInMaterials.all {
            for point in [SIMD3<Float>(0.1, 0.2, 0.3), SIMD3<Float>(-1.7, 0.4, 2.2)] {
                let a = material.sample(at: point, normal: SIMD3<Float>(0, 1, 0))
                XCTAssertEqual(a, material.sample(at: point, normal: SIMD3<Float>(0, 1, 0)), "\(material.name) is the same twice")
                XCTAssertTrue((0 ... 1).contains(a.roughness) && (0 ... 1).contains(a.metal) && (0 ... 1).contains(a.height), material.name)
            }
        }
        let gold = try XCTUnwrap(BuiltInMaterials.material("gold"))
        XCTAssertEqual(gold.maps, [.color, .roughness, .metal, .bumps])
        XCTAssertEqual(try XCTUnwrap(BuiltInMaterials.material("plastic")).maps, [.color, .roughness, .metal], "no relief, no glow")
        XCTAssertTrue(try XCTUnwrap(BuiltInMaterials.material("neon")).maps.contains(.glow))
        // Wood varies across its rings; plain plastic doesn't.
        let oak = try XCTUnwrap(BuiltInMaterials.material("oak"))
        let tones = Set((0 ..< 40).map { Int(oak.sample(at: SIMD3<Float>(Float($0) * 0.01, 0, 0), normal: SIMD3<Float>(0, 1, 0)).color.x * 100) })
        XCTAssertGreaterThan(tones.count, 5)
    }

    func testAMaterialFillWritesEveryMapItHas() throws {
        let (_, paint, mesh, _) = try cube()
        let brick = try XCTUnwrap(BuiltInMaterials.material("brick"))
        let images = PaintFills.images(.material(brick), paintMesh: mesh, size: 256)
        XCTAssertEqual(Set(images.keys), [.color, .roughness, .metal, .bumps])
        let made = try XCTUnwrap(PaintOperations.addFill(.material(brick), to: paint, above: nil, object: "cube", images: images))
        guard case let .setPaint(_, filled?) = made.command else { return XCTFail("a paint change") }
        let layer = try XCTUnwrap(filled.layers.last)
        XCTAssertEqual(layer.name, "Brick")
        XCTAssertEqual(layer.fill, .material(brick))
        XCTAssertEqual(Set(layer.paintedMaps), [.color, .roughness, .metal, .bumps])
        XCTAssertTrue(layer.files.isSubset(of: Set(made.files.keys)))
        // Mortar and brick differ in colour and height.
        let colours = Set(stride(from: 0, to: 256 * 256, by: 97).map { images[.color]?.pixels[$0 * 4] ?? 0 })
        XCTAssertGreaterThan(colours.count, 3)
        // A plain colour is one tile repeated.
        let plain = PaintFills.images(.color(RGBA(0.2, 0.4, 0.6)), paintMesh: mesh, size: 256)
        let one = PaintOperations.filled(PaintLayer(id: "c", name: "C"), with: plain, surface: PaintSurface(size: 512, unwrap: "u", mesh: "m"))
        XCTAssertEqual(one.files.count, 1)
    }

    func testTheMaterialLibraryKeepsYoursAndSurvivesDisk() throws {
        var library = MaterialLibrary()
        let copy = try XCTUnwrap(library.duplicate("oak", as: "mine"))
        XCTAssertEqual(copy.name, "Oak copy")
        XCTAssertEqual(library.all.first?.id, "mine", "yours first")
        library.rename("mine", to: "Barn wood")
        var edited = try XCTUnwrap(BuiltInMaterials.material("steel"))
        edited.roughness = 0.9
        library.update(edited)
        XCTAssertEqual(library.material("steel")?.roughness, 0.9)
        library.delete("steel")
        XCTAssertEqual(library.material("steel"), BuiltInMaterials.material("steel"), "a built-in goes back")
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("materials-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = MaterialLibraryStore(root: root)
        try store.save(library)
        XCTAssertEqual(store.load(), library)
        let key = try store.store(image: Data([1, 2, 3]))
        XCTAssertTrue(key.hasPrefix("materials/"))
    }

    func testABrushLibraryFromAnOlderVersionStillLoads() throws {
        // D-339: the brush library had no migrations, so a schema bump lost it.
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("brushes-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var library = BrushLibrary()
        library.addSet(id: "mine", name: "Mine")
        let current = try SchemaCoder.shared.encode(library, kind: .brushes)
        let older = String(decoding: current, as: UTF8.self).replacingOccurrences(of: "\"schemaVersion\":\(LoweySchema.currentVersion)",
                                                                                  with: "\"schemaVersion\":16")
        try Data(older.utf8).write(to: root.appendingPathComponent(BrushLibraryStore.file))
        XCTAssertNotNil(BrushLibraryStore(root: root).load().set("mine"))
    }

    func testPBRSetsAreSortedByName() {
        let names = ["Oak_Floor_basecolor.png", "Oak_Floor_Roughness.jpg", "Oak_Floor_normal_gl.png", "Oak_Floor_Height.png",
                     "Oak_Floor_AO.png", "Oak_Floor_Metallic.png", "readme.txt"]
        let roles = PBRSetImport.classify(names)
        XCTAssertEqual(roles[.color], "Oak_Floor_basecolor.png")
        XCTAssertEqual(roles[.roughness], "Oak_Floor_Roughness.jpg")
        XCTAssertEqual(roles[.normal], "Oak_Floor_normal_gl.png")
        XCTAssertEqual(roles[.height], "Oak_Floor_Height.png")
        XCTAssertEqual(roles[.occlusion], "Oak_Floor_AO.png")
        XCTAssertEqual(roles[.metal], "Oak_Floor_Metallic.png")
        XCTAssertNil(PBRSetImport.role(of: "readme.txt"))
        XCTAssertEqual(PBRSetImport.role(of: "bricks_diff_4k.jpg"), .color)
        XCTAssertEqual(PBRSetImport.role(of: "Metal_Plate_Displacement.png"), .height)
        XCTAssertTrue(PBRSetImport.isDirectXNormal("rock_nor_dx_2k.png"))
        XCTAssertEqual(PBRSetImport.setName(names.dropLast().map(\.self)), "Oak Floor")
    }

    func testTheMaterialPreviewIsABall() throws {
        let gold = try XCTUnwrap(BuiltInMaterials.material("gold"))
        let picture = MaterialPreview.render(gold, size: 48)
        XCTAssertEqual(picture.pixel(0, 0).a, 0, "clear around the ball")
        XCTAssertEqual(picture.pixel(24, 24).a, 1)
        XCTAssertGreaterThan(picture.pixel(24, 24).r, picture.pixel(24, 24).b, "gold is warm")
        XCTAssertEqual(MaterialPreview.render(gold, size: 48), picture, "the same every time")
    }

    // MARK: Wear

    func testWearGathersOnEdgesAndInCreases() throws {
        let (_, _, mesh, _) = try cube()
        let bake = WearBake.make(mesh, size: 64, rays: 8)
        // The middle of a face is far from every edge; somewhere on the surface is right on one.
        XCTAssertGreaterThan(bake.convex.max() ?? 0, 0.8)
        XCTAssertEqual(bake.concave.max() ?? 1, 0, "a cube has no creases")
        XCTAssertGreaterThan(bake.occlusion.min() ?? 0, 0.9, "nothing on a cube shades itself")
        let edges = PaintFills.images(.wear(PaintWear(kind: .edges, amount: 0.8)), paintMesh: mesh, size: 128, inputs: .init(wear: bake))
        let covered = stride(from: 3, to: 128 * 128 * 4, by: 4).filter { (edges[.color]?.pixels[$0] ?? 0) > 0 }.count
        XCTAssertGreaterThan(covered, 50)
        XCTAssertLessThan(covered, 128 * 128 / 2, "only near the edges")
        let none = PaintFills.images(.wear(PaintWear(kind: .edges, amount: 0)), paintMesh: mesh, size: 64, inputs: .init(wear: bake))
        XCTAssertTrue(none[.color]?.isClear ?? false, "no amount, no wear")
        // An L of two boxes has a crease where they meet.
        var crease = MeshData()
        crease.append(PrimitiveMesh.make(.cube, shading: .flat))
        var second = PrimitiveMesh.make(.cube, shading: .flat)
        second.positions = second.positions.map { $0 + SIMD3<Float>(1, 0, 0) - SIMD3<Float>(0, 0.5, 0) }
        crease.append(second)
        let unwrap = try PaintUnwrap.unwrap(crease)
        let creaseBake = try WearBake.make(XCTUnwrap(unwrap.mesh(over: crease)), size: 64, rays: 8)
        XCTAssertLessThan(creaseBake.occlusion.min() ?? 1, 0.9, "the inside corner is shaded")
    }

    // MARK: Decals, faces, smudge, size

    func testADecalLandsOnTheFaceItIsPressedOn() throws {
        let (_, _, mesh, _) = try cube()
        let picture = RGBAImage(width: 8, height: 8, color: RGBA(0, 0, 1, 1))
        let decal = PaintDecal(center: SIMD3<Float>(0, 0.5, 0.5), normal: SIMD3<Float>(0, 0, 1), size: 0.5)
        let image = decal.image(picture, on: mesh, textureSize: 128)
        let blue = stride(from: 0, to: 128 * 128, by: 1).filter { image.pixels[$0 * 4 + 3] > 0 }.count
        XCTAssertGreaterThan(blue, 100)
        // The front face is about a sixth of the cube; a quarter of it takes the decal.
        let front = 128 * 128 / 6
        XCTAssertLessThan(blue, front)
    }

    func testTheFacesBrushFillsAWholeFlatFace() throws {
        let (_, paint, mesh, _) = try cube()
        let pick = PaintSurfacePick(paintMesh: mesh)
        let hit = try XCTUnwrap(pick.hit(origin: SIMD3<Float>(0.1, 3, 0.1), direction: SIMD3<Float>(0, -1, 0), size: 256))
        XCTAssertEqual(hit.normal.y, 1, accuracy: 1e-4, "the top")
        let face = pick.face(of: hit.triangle)
        XCTAssertEqual(face.count, 2, "a cube's side is two triangles")
        let made = PaintOperations.fillFaces(face, color: RGBA(0, 1, 0, 1), layer: paint.layers[0], surface: paint.surface, paintMesh: mesh,
                                             image: .clear(width: 256, height: 256))
        XCTAssertFalse(made.changes.isEmpty)
        XCTAssertEqual(Set(made.changes.map(\.layer)), ["l1"])
        XCTAssertGreaterThan(hit.density, 0)
    }

    func testSmudgeCarriesPaintAlongTheStroke() {
        var image = RGBAImage.clear(width: 64, height: 64)
        for y in 28 ..< 36 {
            for x in 4 ..< 12 {
                image.setPixel(x, y, RGBA(1, 0, 0, 1))
            }
        }
        let dabs = stride(from: 8, through: 40, by: 2).map { PaintSmudge.Dab(center: SIMD2<Float>(Float($0), 32), radius: 6, strength: 0.8) }
        let changed = PaintSmudge.apply(dabs, to: &image, tileSize: 32)
        XCTAssertGreaterThan(image.pixel(20, 32).a, 0.1, "red dragged to the right")
        XCTAssertEqual(image.pixel(20, 10).a, 0, "nothing off the stroke")
        XCTAssertTrue(changed.contains(PaintTileIndex(column: 0, row: 1)))
        XCTAssertTrue(PaintSmudge.apply(Array(dabs.prefix(1)), to: &image).isEmpty, "one dab moves nothing")
    }

    func testTextureSizeResamplesEveryMap() throws {
        let (_, paint, _, _) = try cube()
        var layer = paint.layers[0]
        layer.tiles["0,0"] = "red"
        layer[.roughness, PaintTileIndex(column: 0, row: 0)] = "grey"
        var painted = paint
        painted.layers[0] = layer
        painted.normalMap = "paint/n.png"
        let pictures = PaintPictures(painted, images: ["l1": RGBAImage(width: 256, height: 256, color: RGBA(1, 0, 0, 1)),
                                                       "l1#roughness": RGBAImage(width: 256, height: 256, color: RGBA(0.5, 0.5, 0.5, 1))])
        let made = try XCTUnwrap(PaintOperations.resized(painted, to: 512, pictures: pictures))
        XCTAssertEqual(made.paint.surface.size, 512)
        XCTAssertEqual(made.paint.layers[0].tiles.count, 4)
        XCTAssertEqual(made.paint.layers[0].tiles(of: .roughness).count, 4)
        XCTAssertNil(made.paint.normalMap, "baked normals are baked again")
        XCTAssertNil(PaintOperations.resized(made.paint, to: 512, pictures: pictures), "already that size")
    }

    // MARK: Seams

    func testSeamsCloseOffAreasForTheUnwrap() throws {
        let mesh = PrimitiveMesh.make(.cube, shading: .flat)
        // The four edges round the top face (a cube stands on y = 0).
        let top: [PaintSeam] = [(-0.5, -0.5, 0.5, -0.5), (0.5, -0.5, 0.5, 0.5), (0.5, 0.5, -0.5, 0.5), (-0.5, 0.5, -0.5, -0.5)].map {
            PaintSeam(Vec3($0.0, 1, $0.1), Vec3($0.2, 1, $0.3))
        }
        let groups = SeamGroups.groups(mesh, seams: top)
        XCTAssertEqual(Set(groups).count, 2, "the top face cut off from the rest")
        XCTAssertEqual(Set(SeamGroups.groups(mesh, seams: Array(top.prefix(2)))).count, 1, "an open seam cuts nothing off")
        let unwrap = try PaintUnwrap.unwrap(mesh, seams: top)
        XCTAssertEqual(unwrap.triangleCount, mesh.triangleCount)
        XCTAssertEqual(PaintSeam(Vec3(1, 0, 0), Vec3(0, 0, 0)), PaintSeam(Vec3(0, 0, 0), Vec3(1, 0, 0)), "one edge either way")
    }

    // MARK: Normals

    /// A light sphere baked from a detailed one: its normal map turns its few facets back into the round shape.
    func testANormalMapMakesTheLightVersionLookLikeTheDetailedOne() throws {
        let high = PrimitiveMesh.sphere(segments: 64, rings: 40).shaded(.smooth)
        let low = MeshSimplify.simplified(PrimitiveMesh.make(.sphere), target: 120).mesh
        let centre = SIMD3<Float>(0, 0.5, 0)
        let flatLow = low.shaded(.flat)
        let unwrap = try PaintUnwrap.unwrap(flatLow)
        let paintMesh = try XCTUnwrap(unwrap.mesh(over: flatLow))
        let size = 128
        let map = NormalBake.bake(low: paintMesh, high: high, size: size)
        let frames = NormalBake.triangleFrames(paintMesh)
        var bakedError: Float = 0, flatError: Float = 0, count: Float = 0
        SurfaceTexels.visit(paintMesh, size: size) { x, y, position, normal in
            let index = (y * size + x) * 4
            let local = SIMD3<Float>(Float(map.pixels[index]), Float(map.pixels[index + 1]), Float(map.pixels[index + 2])) / 255 * 2 - 1
            // The triangle under the texel (the frame is per triangle; any of the low's is close enough here).
            let truth = normalize3(position - centre, fallback: normal)
            guard let face = (0 ..< paintMesh.triangleCount).first(where: { face in
                let p = (0 ..< 3).map { paintMesh.positions[Int(paintMesh.indices[face * 3 + $0])] }
                return abs(dot3(normalize3(cross3(p[1] - p[0], p[2] - p[0]), fallback: .zero), normal) - 1) < 1e-3
                    && length3((p[0] + p[1] + p[2]) / 3 - position) < 0.3
            }) else { return }
            let (t, b) = NormalBake.orthonormal(frames[face], normal: normal)
            let world = normalize3(t * local.x + b * local.y + normal * local.z, fallback: normal)
            bakedError += acos(min(max(dot3(world, truth), -1), 1))
            flatError += acos(min(max(dot3(normal, truth), -1), 1))
            count += 1
        }
        XCTAssertGreaterThan(count, 500)
        let baked = bakedError / count * 180 / .pi, flat = flatError / count * 180 / .pi
        XCTAssertLessThan(baked, flat * 0.5, "baked \(baked)° against the facets' \(flat)°")
        XCTAssertLessThan(baked, 4)
    }

    func testBumpsBecomeANormalMapThatTiltsWithTheSlope() {
        var heights = RGBAImage.clear(width: 16, height: 16)
        for y in 0 ..< 16 {
            for x in 0 ..< 16 {
                let h = Double(x) / 15
                heights.setPixel(x, y, RGBA(h, h, h, 1))
            }
        }
        let normals = NormalBake.fromBumps(heights, baked: nil, coverage: nil, size: 16, strength: 4)
        let middle = normals.pixel(8, 8)
        XCTAssertLessThan(middle.r, 0.5, "rising to the right leans the normal left")
        XCTAssertEqual(middle.g, 0.5, accuracy: 0.01)
        let flat = NormalBake.fromBumps(nil, baked: nil, coverage: nil, size: 4)
        XCTAssertEqual(flat.pixel(1, 1).b, 1, accuracy: 0.01)
    }

    // MARK: Fur

    func testFurIsPropertiesAndMakesCardsAndShells() throws {
        var object = SceneObject(id: "f", name: "Fluffy", kind: .primitive(.sphere))
        XCTAssertNil(FurSettings(object))
        object[.furLength] = .float(0.05)
        object[.furStyle] = .enumeration("cards")
        let fur = try XCTUnwrap(FurSettings(object))
        XCTAssertEqual(fur.style, .cards)
        XCTAssertEqual(PropertyKey.furLength.spec?.animatable, true)
        let mesh = PrimitiveMesh.make(.sphere, shading: .smooth)
        let cards = FurGeometry.cards(on: mesh, fur: fur, limit: 300)
        XCTAssertGreaterThan(cards.triangleCount, 100)
        XCTAssertEqual(cards, FurGeometry.cards(on: mesh, fur: fur, limit: 300), "the same tufts every time")
        let bare = FurGeometry.cards(on: mesh, fur: fur, limit: 300) { _ in 0 }
        XCTAssertTrue(bare.isEmpty, "a black fur map grows nothing")
        let shells = FurGeometry.shells(of: mesh, fur: fur, count: 6)
        XCTAssertEqual(shells.count, 6)
        let lastRadius = shells.last.map { length3($0.positions[0]) } ?? 0
        XCTAssertGreaterThan(lastRadius, length3(mesh.positions[0]) + 0.03)
        XCTAssertGreaterThan(FurGeometry.strandPicture(size: 32, cards: false).pixels.count, 0)
        XCTAssertEqual(FurSettings.shells(forTier: 0), 24)
    }

    // MARK: Hatching

    func testHatchingIsAPartOfTheLook() throws {
        var comic = ComicParams()
        XCTAssertEqual(comic.hatching, 0)
        XCTAssertFalse(try String(decoding: LoweyJSON.encode(comic), as: UTF8.self).contains("hatching"))
        comic.hatching = 0.7
        XCTAssertEqual(try LoweyJSON.decode(ComicParams.self, from: LoweyJSON.encode(comic)), comic)
        let old = try LoweyJSON.decode(ComicParams.self, from: Data(#"{"halftone":0.5,"halftoneScale":7,"objectSpaceDots":false,"misregistration":true}"#.utf8))
        XCTAssertEqual(old.hatching, 0)
        XCTAssertTrue(old.misregistration)
    }
}

extension PaintTileChange {
    /// A change naming any map, known or not (for testing what an older app does with a newer map).
    init(layer: String, tile: String, file: String?, mapName: String) {
        self.init(layer: layer, tile: PaintTileIndex(key: tile) ?? PaintTileIndex(column: 0, row: 0), file: file)
        map = mapName
    }
}
