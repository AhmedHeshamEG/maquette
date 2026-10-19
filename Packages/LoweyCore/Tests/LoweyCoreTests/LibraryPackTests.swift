import Foundation
import HmmDocuments
@testable import LoweyCore
import XCTest

/// `.maquettepack` files of library things (L2's acceptance: a pack made on one iPad imports on another with its author).
final class LibraryPackTests: XCTestCase {
    private let tip = PNGCodec.encode(RGBAImage(width: 4, height: 4, color: RGBA(1, 1, 1, 0.5)))
    private let albedo = PNGCodec.encode(RGBAImage(width: 2, height: 2, color: RGBA(0.6, 0.3, 0.1)))
    private let model = Data("glTF model bytes".utf8)

    private var items: [LibraryPack.Item] {
        var brush = BuiltInBrushes.inkPen
        brush.id = "leaf"
        brush.name = "Leaf"
        brush.shape.source = .image(BrushKey.imageKey(for: tip))
        let material = PaintMaterial(id: "bark", name: "Bark", color: .hex("#6B4428"), pictures: MaterialPictures(color: "materials/bark.png"))
        let asset = LibraryAsset(id: AssetID(raw: "a-lamp"), name: "Lamp", format: .glb, file: "lamp.glb")
        var kitAsset = LibraryAsset(id: AssetID(raw: "kit-chair"), name: "Chair", format: .glb, file: "chair.glb")
        kitAsset.kit = KitInfo(set: "Kenney", category: "furniture", realSize: Vec3(0.5, 1, 0.5), front: .unitZ, surfaces: [], clipsOnly: false)
        let lamp = SceneObject(id: "o1", name: "Lamp", kind: .asset(asset.id))
        let prefab = Prefab(id: PrefabID(raw: "corner"), name: "Reading corner", fragment: SceneFragment(object: lamp))
        let wave = MotionItem(id: "wave", name: "Wave", kind: .loop, standard: .humanoid, joints: ["spine": [Keyframe(time: 0, value: .float(0))]],
                              duration: 1)
        return [.brush(brush), .look(LookPreset.watercolour.duplicated(id: "autumn", name: "Autumn wash")), .material(material),
                .effect(SavedEffect(id: "leaves", name: "Falling leaves", recipe: .preset(.confetti))),
                .part(SavedPart(id: "antlers", name: "Antlers", job: .extra, fragment: SceneFragment(objects: [], roots: []))), .motion(wave),
                .thing(prefab, assets: [asset, kitAsset])]
    }

    private func pack(origins: [String: HmmPackOrigin] = [:]) throws -> Data {
        try LibraryPack.archive(items, name: "Autumn", author: "Lina", licence: .credit, origins: origins,
                                created: Date(timeIntervalSince1970: 1_000_000), assetFiles: { ["assets/\($0.id.raw)/\($0.file)"] }) { key in
            [BrushKey.imageKey(for: tip): tip, "materials/bark.png": albedo, "assets/a-lamp/lamp.glb": model][key]
        }
    }

    func testAPackMadeOnOneIPadImportsOnAnotherWithItsAuthor() throws {
        let data = try pack()
        XCTAssertTrue(LibraryPack.isLibraryPack(data))
        let contents = try LibraryPack.read(data, now: Date(timeIntervalSince1970: 2_000_000))
        XCTAssertEqual(contents.manifest.author, "Lina")
        XCTAssertEqual(contents.entries.map(\.item.kind), [.brush, .look, .material, .effect, .part, .motion, .thing])
        XCTAssertEqual(contents.leftOut, 0)
        XCTAssertNotNil(contents.files["assets/a-lamp/lamp.glb"], "an imported model travels with its thing")
        XCTAssertNil(contents.files["assets/kit-chair/chair.glb"], "the Kit's models are on every iPad")
        // Another iPad: empty libraries.
        var library = LibraryManifest()
        var brushes = BrushLibrary()
        var materials = MaterialLibrary()
        var next = 0
        let adopted = LibraryPack.adopt(contents, into: &library, brushes: &brushes, materials: &materials) {
            next += 1
            return "new\(next)"
        }
        XCTAssertEqual(adopted.total, 7)
        XCTAssertEqual(adopted.brushSet?.name, "Autumn", "brushes arrive as a set named after the pack")
        XCTAssertEqual(brushes.brush("leaf")?.name, "Leaf")
        XCTAssertEqual(materials.material("bark")?.name, "Bark")
        XCTAssertEqual(library.style("autumn")?.paint, LookPreset.watercolour.paint)
        XCTAssertEqual(library.effect("leaves")?.recipe, .preset(.confetti))
        XCTAssertEqual(library.part("antlers")?.job, .extra)
        XCTAssertEqual(library.motions.first?.id, "wave")
        XCTAssertEqual(library.prefab(PrefabID(raw: "corner"))?.name, "Reading corner")
        XCTAssertEqual(library.assets.map(\.id.raw), ["a-lamp"])
        XCTAssertEqual(adopted.assetFiles["assets/a-lamp/lamp.glb"], model)
        XCTAssertNotNil(adopted.brushPictures[BrushKey.imageKey(for: tip)])
        let filedAlbedo = MaterialLibraryStore.imageKey(for: albedo)
        XCTAssertEqual(materials.material("bark")?.pictures?.color, filedAlbedo, "a picture is filed under what it is")
        XCTAssertEqual(adopted.materialPictures[filedAlbedo], albedo)
        for kind in LibraryKind.allCases {
            let id = ["brush": "leaf", "look": "autumn", "material": "bark", "effect": "leaves", "part": "antlers", "motion": "wave",
                      "thing": "corner"][kind.rawValue] ?? ""
            let origin = library.origin(kind, id)
            XCTAssertEqual(origin?.author, "Lina", "\(kind) remembers who made it")
            XCTAssertEqual(origin?.licence, .credit)
            XCTAssertEqual(origin?.pack, "Autumn")
        }
        // The same pack again: everything comes in beside what's there, under fresh ids.
        let again = LibraryPack.adopt(contents, into: &library, brushes: &brushes, materials: &materials) {
            next += 1
            return "new\(next)"
        }
        XCTAssertEqual(again.total, 7)
        XCTAssertEqual(library.styles.count, 2)
        XCTAssertEqual(library.prefabs.count, 2)
        XCTAssertEqual(library.assets.count, 1, "a model already here isn't copied twice")
        XCTAssertEqual(Set(library.styles.map(\.id)).count, 2)
    }

    func testPassingAThingOnKeepsItsMakersName() throws {
        let origins = [LibraryKind.look.key("autumn"): HmmPackOrigin(author: "Sara", licence: .personal, pack: "Sara's washes")]
        let contents = try LibraryPack.read(pack(origins: origins))
        let look = try XCTUnwrap(contents.entries.first { $0.item.kind == .look })
        XCTAssertEqual(look.origin.author, "Sara")
        XCTAssertEqual(look.origin.licence, .personal)
        XCTAssertEqual(contents.entries.first { $0.item.kind == .brush }?.origin.author, "Lina")
        let licence = try XCTUnwrap(ZipReader.entries(pack()).first { $0.name == HmmPackManifest.licenceFileName })
        XCTAssertTrue(String(decoding: licence.data, as: UTF8.self).contains("Made by Lina"))
    }

    func testOnlyDataComesIn() throws {
        // A pack naming a kind this version doesn't know, and one whose item file is damaged: both left out.
        var entries = try ZipReader.entries(pack())
        let manifestIndex = try XCTUnwrap(entries.firstIndex { $0.name == HmmPackManifest.fileName })
        var manifest = try HmmPackManifest.decode(entries[manifestIndex].data)
        manifest.items[0].kind = "script"
        manifest.items[1].file = "items/missing.json"
        entries[manifestIndex].data = try manifest.encoded()
        let contents = try LibraryPack.read(ZipWriter.storedArchive(entries))
        XCTAssertEqual(contents.leftOut, 2)
        XCTAssertEqual(contents.entries.count, 5)
        // A project package is not a library pack; another app's pack is refused.
        XCTAssertFalse(LibraryPack.isLibraryPack(ZipWriter.storedArchive([("project.json", Data("{}".utf8))])))
        manifest.app = "cutaway"
        entries[manifestIndex].data = try manifest.encoded()
        XCTAssertThrowsError(try LibraryPack.read(ZipWriter.storedArchive(entries)))
    }
}
