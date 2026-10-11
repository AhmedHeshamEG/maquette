import LoweyCore
import LoweyEngine
@testable import LoweyFeatures
import UIKit
import XCTest

/// The Kit's pictures, baked by the app's own renderer in the Ink Look (the same picture the Library used to render on
/// the iPad the first time a tile appeared). `Tools/bake-kit-pictures.sh` runs this with `KIT_PICTURES_OUTPUT` naming a
/// folder; the pictures land there in the Kit's own layout and are committed beside each model.
@MainActor
final class KitPicturesTests: XCTestCase {
    /// The repository's Kit (the simulator reads the Mac's files).
    private var kitRoot: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("App/Resources/Kit")
    }

    private func catalog(_ kit: KitIndex) -> AssetCatalog {
        var manifest = LibraryManifest()
        manifest.kit = kit.assets
        let root = kitRoot
        return AssetCatalog(manifest: manifest) { root.appendingPathComponent($0.file) }
    }

    private func picture(of asset: LibraryAsset, catalog: AssetCatalog, thumbnailer: Thumbnailer, models: ModelLibrary) async throws -> CGImage {
        let object = SceneObject(id: .make(), name: asset.name, kind: .asset(asset.id))
        return try await thumbnailer.portrait(of: SceneFragment(objects: [object], roots: [object.id]), catalog: catalog, models: models,
                                              width: Self.size, height: Self.size)
    }

    static let size = 256

    /// A picture shows the model: a placed Kit model is waited for, never drawn while still loading (the grey tiles).
    func testAPictureShowsTheModel() async throws {
        let kit = try KitIndex.load(from: kitRoot)
        let desk = try XCTUnwrap(kit.assets.first { $0.kit?.clipsOnly != true })
        let image = try await picture(of: desk, catalog: catalog(kit), thumbnailer: Thumbnailer(), models: ModelLibrary())
        XCTAssertGreaterThan(Self.inkCoverage(image), 0.02, "\(desk.name)'s picture is empty")
    }

    func testBakeTheKitsPictures() async throws {
        guard let output = ProcessInfo.processInfo.environment["KIT_PICTURES_OUTPUT"], !output.isEmpty else {
            throw XCTSkip("Bakes only with KIT_PICTURES_OUTPUT (Tools/bake-kit-pictures.sh).")
        }
        let kit = try KitIndex.load(from: kitRoot)
        let catalog = catalog(kit)
        let thumbnailer = Thumbnailer()
        let models = ModelLibrary()
        var empty: [String] = []
        for asset in kit.assets where asset.kit?.clipsOnly != true {
            let picturePath = try XCTUnwrap(asset.kitPicture)
            let image = try await picture(of: asset, catalog: catalog, thumbnailer: thumbnailer, models: models)
            if Self.inkCoverage(image) < 0.02 { empty.append(asset.name) }
            let url = URL(fileURLWithPath: output).appendingPathComponent(picturePath)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try XCTUnwrap(UIImage(cgImage: image).pngData()).write(to: url)
            models.evict(asset.id)
        }
        XCTAssertTrue(empty.isEmpty, "empty pictures: \(empty)")
    }

    /// The share of pixels that aren't the background (the top-left corner's colour).
    static func inkCoverage(_ image: CGImage) -> Double {
        let width = image.width
        let height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = pixels.withUnsafeMutableBytes { raw -> Bool in
            guard let context = CGContext(data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                          space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn, width > 0, height > 0 else { return 0 }
        let background = Array(pixels[0 ..< 4])
        var different = 0
        for index in stride(from: 0, to: pixels.count, by: 4) {
            let distance = (0 ..< 3).reduce(0) { $0 + abs(Int(pixels[index + $1]) - Int(background[$1])) }
            if distance > 24 { different += 1 }
        }
        return Double(different) / Double(width * height)
    }
}
