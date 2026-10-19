import Foundation
import HmmDocuments
import LoweyCore

/// One thing chosen to go in a pack (L2, law 12), by where it lives on this iPad.
enum PackChoice: Hashable, Sendable {
    case brush(String)
    case look(String)
    case material(String)
    case effect(String)
    case part(String)
    case motion(String)
    case thing(PrefabID)
}

/// Packs (L2, D-485): things from Yours shared as one `.maquettepack` file with who made them and what others may do
/// with them; a pack someone sends lands in Yours with its author. The author and licence chosen are remembered.
extension AppModel {
    static let packAuthorKey = "pack.author"
    static let packLicenceKey = "pack.licence"

    var packAuthor: String {
        get { UserDefaults.standard.string(forKey: Self.packAuthorKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: Self.packAuthorKey) }
    }

    var packLicence: HmmLicence {
        get {
            guard let data = UserDefaults.standard.data(forKey: Self.packLicenceKey),
                  let licence = try? JSONDecoder().decode(HmmLicence.self, from: data) else { return .anything }
            return licence
        }
        set { UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: Self.packLicenceKey) }
    }

    /// The pack items for what was chosen (`looks`: the open project's own Looks, which can go too).
    func packItems(_ choices: [PackChoice], looks: [LookPreset] = []) -> [LibraryPack.Item] {
        let manifest = library.manifest
        return choices.compactMap { choice -> LibraryPack.Item? in
            switch choice {
            case let .brush(id): brushes.library.brush(id).map(LibraryPack.Item.brush)
            case let .look(id): (manifest.style(id) ?? looks.first { $0.id == id }).map(LibraryPack.Item.look)
            case let .material(id): materials.material(id).map(LibraryPack.Item.material)
            case let .effect(id): manifest.effect(id).map(LibraryPack.Item.effect)
            case let .part(id): manifest.part(id).map(LibraryPack.Item.part)
            case let .motion(id): manifest.motions.first { $0.id == id }.map(LibraryPack.Item.motion)
            case let .thing(id):
                manifest.prefab(id).map { prefab in
                    let used = Set(prefab.fragment.objects.compactMap(\.kind.assetID))
                    return .thing(prefab, assets: used.compactMap(manifest.asset).sorted { $0.id.raw < $1.id.raw })
                }
            }
        }
    }

    /// Writes the pack to a temporary file to share (nil when nothing could be packed).
    func writePack(_ choices: [PackChoice], name: String, author: String, licence: HmmLicence, looks: [LookPreset] = []) -> URL? {
        let items = packItems(choices, looks: looks)
        guard !items.isEmpty else { return nil }
        let title = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? String(localized: "My pack") : name
        let brushStore = brushes.store, materialStore = materials.store, libraryRoot = library.store.root
        do {
            let data = try LibraryPack.archive(items, name: title, author: author, licence: licence, origins: library.manifest.origins,
                                               assetFiles: { Self.files(of: $0, in: libraryRoot) }) { key in
                if key.hasPrefix(BrushLibraryStore.imagesFolder + "/") { return try? Data(contentsOf: brushStore.imageURL(key)) }
                if key.hasPrefix(MaterialLibraryStore.imagesFolder + "/") { return try? Data(contentsOf: materialStore.imageURL(key)) }
                return try? Data(contentsOf: libraryRoot.appendingPathComponent(key))
            }
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(ProjectStore.sanitize(title))
                .appendingPathExtension(ProjectPackage.fileExtension)
            try data.write(to: url, options: .atomic)
            packAuthor = author
            packLicence = licence
            return url
        } catch {
            show("Couldn't make the pack: \(error.localizedDescription)", kind: .error)
            return nil
        }
    }

    /// A model's files, by their place in the library (`assets/<id>/<file>`).
    nonisolated static func files(of asset: LibraryAsset, in root: URL) -> [String] {
        let folder = root.appendingPathComponent(LibraryStore.assetsFolder).appendingPathComponent(asset.id.raw)
        guard let walker = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.isDirectoryKey]) else { return [] }
        let base = folder.standardizedFileURL.path
        var files: [String] = []
        for case let url as URL in walker where (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) != true {
            let relative = String(url.standardizedFileURL.path.dropFirst(base.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            files.append("\(LibraryStore.assetsFolder)/\(asset.id.raw)/\(relative)")
        }
        return files.sorted()
    }

    /// A pack someone sent lands in Yours: brushes as a set named after it, the rest beside your own, each keeping who
    /// made it.
    func importLibraryPack(_ data: Data) async {
        let read = await Task.detached(priority: .userInitiated) { Result { try LibraryPack.read(data) } }.value
        let contents: LibraryPack.Contents
        switch read {
        case let .success(found):
            contents = found
        case let .failure(error):
            let reason = (error as? HmmPackManifest.Problem)?.description ?? error.localizedDescription
            show(String.LocalizationValue(reason), kind: .error)
            return
        }
        var manifest = library.manifest
        var brushLibrary = brushes.library
        var materialLibrary = materials.library
        let adopted = LibraryPack.adopt(contents, into: &manifest, brushes: &brushLibrary, materials: &materialLibrary) {
            UUID().uuidString.prefix(8).lowercased()
        }
        brushes.adopt(brushLibrary, pictures: adopted.brushPictures)
        materials.adopt(materialLibrary, pictures: adopted.materialPictures)
        library.adopt(manifest, assetFiles: adopted.assetFiles)
        let manifestInfo = contents.manifest
        show("Added \(adopted.total) things from “\(manifestInfo.name)” by \(manifestInfo.author) to Yours")
        if let editor { editor.libraryPage = .yours }
    }
}
