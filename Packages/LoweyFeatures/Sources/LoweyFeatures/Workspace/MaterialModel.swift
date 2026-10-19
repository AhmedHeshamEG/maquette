import CoreGraphics
import Foundation
import LoweyCore
import LoweyEngine
import Observation
import os
import UIKit

/// The materials on this iPad (U7, D-343): the built-ins (with any edits), the person's own and imported PBR sets,
/// their pictures, and the ball each one is shown as. A project keeps a frozen copy of each material a fill uses.
@Observable
@MainActor
final class MaterialModel {
    private(set) var library = MaterialLibrary.standard
    @ObservationIgnored let store: MaterialLibraryStore
    /// Bumped whenever a material's look changes, so previews redraw.
    private(set) var revision = 0
    @ObservationIgnored private var previews: [String: CGImage] = [:]
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private let logger = Logger(subsystem: AppIdentity.subsystem, category: "materials")

    init(root: URL) {
        store = MaterialLibraryStore(root: root)
    }

    func load() {
        library = store.load()
    }

    var all: [PaintMaterial] { library.all }

    func material(_ id: String) -> PaintMaterial? { library.material(id) }

    // MARK: Changing

    /// A Material Studio edit (saved a moment later, so dragging a slider writes once).
    func update(_ material: PaintMaterial) {
        library.update(material)
        changed(material.id)
    }

    @discardableResult
    func duplicate(_ id: String) -> String? {
        let newID = "material-" + UUID().uuidString.prefix(8).lowercased()
        guard library.duplicate(id, as: newID) != nil else { return nil }
        changed(newID)
        return newID
    }

    func delete(_ id: String) {
        library.delete(id)
        changed(id)
    }

    func rename(_ id: String, to name: String) {
        library.rename(id, to: name)
        changed(id)
    }

    /// A new material of the person's own, from a plain grey to change in the studio.
    func makeNew() -> String {
        let id = "material-" + UUID().uuidString.prefix(8).lowercased()
        library.update(PaintMaterial(id: id, name: "My material", color: RGBA(0.7, 0.7, 0.7), roughness: 0.6, pattern: .noise, variation: 0.2))
        changed(id)
        return id
    }

    /// A pack's materials taken in (L2): the library with them added, and their pictures filed under their keys.
    func adopt(_ adopted: MaterialLibrary, pictures: [String: Data]) {
        for (_, png) in pictures {
            _ = try? store.store(image: png)
        }
        let added = adopted.own.map(\.id).filter { library.materials[$0] == nil }
        library = adopted
        changed(added.first ?? "")
    }

    private func changed(_ id: String) {
        previews[id] = nil
        revision += 1
        saveTask?.cancel()
        let library = library
        let store = store
        saveTask = Task { [logger] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            do {
                try await Task.detached { try store.save(library) }.value
            } catch {
                logger.error("Saving the materials failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    // MARK: Pictures

    /// An imported picture's bytes (from the library's folder).
    nonisolated func pictureData(_ key: String) -> Data? {
        try? Data(contentsOf: store.imageURL(key))
    }

    /// The ball a material is shown as (drawn off the main thread once, then kept).
    func preview(_ material: PaintMaterial, size: Int = 96) async -> CGImage? {
        if let known = previews[material.id] { return known }
        let pictures = material.pictures?.files ?? []
        let store = store
        let image = await Task.detached(priority: .userInitiated) { () -> CGImage? in
            var images: [String: RGBAImage] = [:]
            for key in pictures {
                images[key] = (try? Data(contentsOf: store.imageURL(key))).flatMap(PaintPixels.decode)
            }
            let ball = MaterialPreview.render(material, size: size, pictures: images.isEmpty ? nil : MaterialPictureSource(images: images))
            return Self.cgImage(ball)
        }.value
        previews[material.id] = image
        return image
    }

    nonisolated static func cgImage(_ image: RGBAImage) -> CGImage? {
        guard let provider = CGDataProvider(data: Data(image.pixels) as CFData), let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        return CGImage(width: image.width, height: image.height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: image.width * 4, space: space,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue), provider: provider, decode: nil, shouldInterpolate: true,
                       intent: .defaultIntent)
    }

    // MARK: Importing PBR sets

    /// A PBR set from picture files (any of PNG, JPEG, TIFF…): each sorted into its map by its name, stored as PNG in the
    /// library (a gloss map turned into roughness, a DirectX normal map's green flipped), one new material. Nil when no
    /// file is a picture of a map.
    func importSet(_ urls: [URL]) async -> PaintMaterial? {
        let names = urls.map(\.lastPathComponent)
        let roles = PBRSetImport.classify(names)
        guard !roles.isEmpty else { return nil }
        let store = store
        let keys = await Task.detached(priority: .userInitiated) { () -> [PBRSetImport.Role: String] in
            var keys: [PBRSetImport.Role: String] = [:]
            for (role, name) in roles {
                guard let url = urls.first(where: { $0.lastPathComponent == name }) else { continue }
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                guard let data = try? Data(contentsOf: url), var image = PaintPixels.decode(data) else { continue }
                if role == .gloss { image = Self.inverted(image) }
                if role == .normal, PBRSetImport.isDirectXNormal(name) { image = Self.flippedGreen(image) }
                keys[role == .gloss ? .roughness : role] = try? store.store(image: PaintPixels.png(image))
            }
            if keys[.roughness] == nil, let gloss = keys[.gloss] { keys[.roughness] = gloss }
            return keys
        }.value
        guard !keys.isEmpty else { return nil }
        let id = "material-" + UUID().uuidString.prefix(8).lowercased()
        let material = PBRSetImport.material(named: PBRSetImport.setName(names), id: id, keys: keys)
        library.update(material)
        changed(id)
        return material
    }

    nonisolated static func inverted(_ image: RGBAImage) -> RGBAImage {
        var result = image
        for index in stride(from: 0, to: result.pixels.count, by: 4) {
            for channel in 0 ..< 3 {
                result.pixels[index + channel] = 255 - result.pixels[index + channel]
            }
        }
        return result
    }

    nonisolated static func flippedGreen(_ image: RGBAImage) -> RGBAImage {
        var result = image
        for index in stride(from: 1, to: result.pixels.count, by: 4) {
            result.pixels[index] = 255 - result.pixels[index]
        }
        return result
    }
}

extension EditorModel {
    /// The material frozen into the project when a fill uses it: its pictures copied into the project's assets.
    func freezing(_ material: PaintMaterial) async -> PaintMaterial {
        let files = material.pictures?.files ?? []
        guard !files.isEmpty else { return material }
        let library = app.materials
        var copies: PaintOperations.Files = [:]
        for key in files {
            if let data = library.pictureData(key) { copies[key] = data }
        }
        try? await Self.write(copies, to: assetsFolder)
        return material
    }
}
