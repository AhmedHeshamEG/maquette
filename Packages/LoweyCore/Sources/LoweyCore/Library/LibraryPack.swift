import Foundation
import HmmDocuments

/// Library things shared as one `.maquettepack` file (L2, law 12, D-485): brushes, Looks, materials, effects, parts,
/// motions and things, with who made them and what others may do with them. The same extension carries a whole
/// project; what's inside decides (`pack.json` here, `project.json` there). Packs are data only: every item is read
/// as the kind it says it is, and anything else is counted and left out.
///
///     pack.json            the manifest (HmmPackManifest: name, author, licence, items)
///     LICENCE.txt          the licence in words
///     items/<n>.json       one item each, in a versioned envelope
///     files/<key>          the pictures and models the items name, by the key they're kept under
public enum LibraryPack {
    public static let app = "maquette"
    public static let itemsFolder = "items"
    public static let filesFolder = "files"

    /// One thing in a pack.
    public enum Item: Sendable {
        case brush(Brush)
        case look(LookPreset)
        case material(PaintMaterial)
        case effect(SavedEffect)
        case part(SavedPart)
        case motion(MotionItem)
        /// A saved thing and the imported models it places (the Kit's travel by name: every iPad has them).
        case thing(Prefab, assets: [LibraryAsset])

        public var kind: LibraryKind {
            switch self {
            case .brush: .brush
            case .look: .look
            case .material: .material
            case .effect: .effect
            case .part: .part
            case .motion: .motion
            case .thing: .thing
            }
        }

        public var id: String {
            switch self {
            case let .brush(brush): brush.id
            case let .look(look): look.id
            case let .material(material): material.id
            case let .effect(effect): effect.id
            case let .part(part): part.id
            case let .motion(motion): motion.id
            case let .thing(prefab, _): prefab.id.raw
            }
        }

        public var name: String {
            switch self {
            case let .brush(brush): brush.name
            case let .look(look): look.name
            case let .material(material): material.name
            case let .effect(effect): effect.name
            case let .part(part): part.name
            case let .motion(motion): motion.name
            case let .thing(prefab, _): prefab.name
            }
        }
    }

    /// The item envelopes' payloads (one shape per kind, so a reader decodes only what the kind says).
    struct ThingPayload: Codable, Sendable {
        var prefab: Prefab
        var assets: [LibraryAsset]
    }

    // MARK: Writing

    /// A pack of `items`, made by `author` under `licence`. `file` returns a file an item names, by its key (brush and
    /// material pictures by their key, a model as `assets/<id>/<name>`); `assetFiles` lists a model's files. Things
    /// that came from someone else's pack keep their author and licence (`origins`).
    public static func archive(_ items: [Item], name: String, author: String, licence: HmmLicence, origins: [String: HmmPackOrigin] = [:],
                               created: Date = Date(), assetFiles: (LibraryAsset) -> [String] = { _ in [] },
                               file: (String) -> Data?) throws -> Data {
        var entries: [(name: String, data: Data)] = []
        var manifestItems: [HmmPackManifest.Item] = []
        var written: Set<String> = []
        for (index, item) in items.enumerated() {
            let path = "\(itemsFolder)/\(index + 1).json"
            try entries.append((path, payload(item)))
            var keys: [String] = []
            for key in fileKeys(item, assetFiles: assetFiles) where HmmPackManifest.isSafe(key) {
                guard let data = file(key) else { continue }
                keys.append("\(filesFolder)/\(key)")
                if written.insert(key).inserted { entries.append(("\(filesFolder)/\(key)", data)) }
            }
            let origin = origins[item.kind.key(item.id)]
            manifestItems.append(HmmPackManifest.Item(kind: item.kind.rawValue, id: item.id, name: item.name, file: path, files: keys,
                                                      author: origin?.author, licence: origin?.licence))
        }
        let manifest = HmmPackManifest(app: app, name: name, author: author, licence: licence, created: created, items: manifestItems)
        try entries.insert((HmmPackManifest.fileName, manifest.encoded()), at: 0)
        entries.insert((HmmPackManifest.licenceFileName, Data(manifest.licenceText.utf8)), at: 1)
        return ZipWriter.storedArchive(entries)
    }

    static func payload(_ item: Item) throws -> Data {
        switch item {
        case let .brush(brush): try SchemaCoder.shared.encode(brush, kind: .brushes)
        case let .look(look): try SchemaCoder.shared.encode(look, kind: .library)
        case let .material(material): try SchemaCoder.shared.encode(material, kind: .materials)
        case let .effect(effect): try SchemaCoder.shared.encode(effect, kind: .library)
        case let .part(part): try SchemaCoder.shared.encode(part, kind: .library)
        case let .motion(motion): try SchemaCoder.shared.encode(motion, kind: .library)
        case let .thing(prefab, assets): try SchemaCoder.shared.encode(ThingPayload(prefab: prefab, assets: assets), kind: .library)
        }
    }

    /// The files an item names (by the key it's kept under).
    static func fileKeys(_ item: Item, assetFiles: (LibraryAsset) -> [String]) -> [String] {
        switch item {
        case let .brush(brush): brush.imageKeys
        case let .material(material): material.pictures?.files.sorted() ?? []
        case let .thing(_, assets): assets.filter { $0.kit == nil }.flatMap(assetFiles)
        default: []
        }
    }

    // MARK: Reading

    public struct Entry: Sendable {
        public var item: Item
        public var origin: HmmPackOrigin
    }

    public struct Contents: Sendable {
        public var manifest: HmmPackManifest
        public var entries: [Entry]
        /// The files the items name, by key.
        public var files: [String: Data]
        /// Items of kinds this version doesn't know, or that couldn't be read, left out.
        public var leftOut: Int
    }

    /// Whether a `.maquettepack` holds library things (not a project).
    public static func isLibraryPack(_ data: Data) -> Bool {
        (try? ZipReader.entries(data) { $0 == HmmPackManifest.fileName })?.isEmpty == false
    }

    public static func read(_ data: Data, now: Date = Date()) throws -> Contents {
        let entries = try Dictionary(ZipReader.entries(data).map { ($0.name, $0.data) }, uniquingKeysWith: { first, _ in first })
        guard let manifestData = entries[HmmPackManifest.fileName] else { throw HmmPackManifest.Problem.empty }
        let manifest = try HmmPackManifest.decode(manifestData)
        try manifest.validate(app: app)
        var contents = Contents(manifest: manifest, entries: [], files: [:], leftOut: 0)
        for item in manifest.items {
            guard let kind = LibraryKind(rawValue: item.kind), let json = entries[item.file], let read = try? decode(kind, json) else {
                contents.leftOut += 1
                continue
            }
            contents.entries.append(Entry(item: read, origin: manifest.origin(of: item, imported: now)))
            for path in item.files where path.hasPrefix(filesFolder + "/") {
                if let file = entries[path] { contents.files[String(path.dropFirst(filesFolder.count + 1))] = file }
            }
        }
        return contents
    }

    static func decode(_ kind: LibraryKind, _ data: Data) throws -> Item {
        let coder = SchemaCoder.shared
        switch kind {
        case .brush: return try .brush(coder.decode(Brush.self, kind: .brushes, from: data).clamped)
        case .look: return try .look(coder.decode(LookPreset.self, kind: .library, from: data))
        case .material: return try .material(coder.decode(PaintMaterial.self, kind: .materials, from: data))
        case .effect: return try .effect(coder.decode(SavedEffect.self, kind: .library, from: data))
        case .part: return try .part(coder.decode(SavedPart.self, kind: .library, from: data))
        case .motion: return try .motion(coder.decode(MotionItem.self, kind: .library, from: data))
        case .thing:
            let thing = try coder.decode(ThingPayload.self, kind: .library, from: data)
            return .thing(thing.prefab, assets: thing.assets)
        }
    }
}
