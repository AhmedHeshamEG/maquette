import Foundation

/// What someone who receives a pack may do with what's in it, in plain words (no legal code to look up).
public enum HmmLicence: Hashable, Sendable {
    /// Use it in anything, commercial work included.
    case anything
    /// Use it in anything, naming the author where the work is shown.
    case credit
    /// Use it for personal work only, nothing sold.
    case personal
    /// The author's own words.
    case own(String)

    /// The licences an author picks from, own words last.
    public static let choices: [HmmLicence] = [.anything, .credit, .personal, .own("")]

    /// A short name for a picker.
    public var title: String {
        switch self {
        case .anything: "Use in anything"
        case .credit: "Credit me"
        case .personal: "Personal use only"
        case .own: "My own words"
        }
    }

    /// The sentence shown beside the item and written into the licence file.
    public func sentence(author: String) -> String {
        let who = author.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "the author" : author
        switch self {
        case .anything: return "Made by \(who). Use it in anything you make, commercial work included."
        case .credit: return "Made by \(who). Use it in anything you make, commercial work included, and name \(who) where it's shown."
        case .personal: return "Made by \(who). Use it in your own personal work; don't sell what you make with it."
        case let .own(text):
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "Made by \(who)." : "Made by \(who). \(trimmed)"
        }
    }

    /// Whether two licences are the same kind (own words compare by kind only).
    public func sameKind(as other: HmmLicence) -> Bool {
        switch (self, other) {
        case (.anything, .anything), (.credit, .credit), (.personal, .personal), (.own, .own): true
        default: false
        }
    }
}

extension HmmLicence: Codable {
    private enum CodingKeys: String, CodingKey { case kind, text }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(String.self, forKey: .kind) {
        case "credit": self = .credit
        case "personal": self = .personal
        case "own": self = try .own(container.decodeIfPresent(String.self, forKey: .text) ?? "")
        default: self = .anything
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .anything: try container.encode("anything", forKey: .kind)
        case .credit: try container.encode("credit", forKey: .kind)
        case .personal: try container.encode("personal", forKey: .kind)
        case let .own(text):
            try container.encode("own", forKey: .kind)
            try container.encode(text, forKey: .text)
        }
    }
}

/// Where an imported library item came from: who made it, under what licence, in which pack. It stays on the item, so
/// the author's name travels with it wherever it goes next.
public struct HmmPackOrigin: Codable, Hashable, Sendable {
    public var author: String
    public var licence: HmmLicence
    public var pack: String
    public var imported: Date

    public init(author: String, licence: HmmLicence, pack: String, imported: Date = Date()) {
        self.author = author
        self.licence = licence
        self.pack = pack
        self.imported = imported
    }
}

/// `pack.json`, at the root of a pack file: library things someone made, shared as one file (Maquette's
/// `.maquettepack`, Cutaway's own), with who made them and what others may do with them. Packs are data only: an app
/// reads the kinds it knows and never runs anything a pack holds.
public struct HmmPackManifest: Codable, Hashable, Sendable {
    public static let fileName = "pack.json"
    public static let licenceFileName = "LICENCE.txt"
    public static let formatVersion = 1
    /// More than this many items, or files, and a pack is refused (a file this big wasn't made by hand).
    public static let maximumItems = 2000

    /// One thing in the pack: its kind (the app's word: `brush`, `look`, `material`…), its id when it was made, its
    /// name, the JSON file that holds it and the other files it needs (pictures), all relative to the pack's root. A
    /// thing that came from someone else's pack keeps its own author and licence, so sharing it on never loses them.
    public struct Item: Codable, Hashable, Sendable {
        public var kind: String
        public var id: String
        public var name: String
        public var file: String
        public var files: [String]
        public var author: String?
        public var licence: HmmLicence?

        public init(kind: String, id: String, name: String, file: String, files: [String] = [], author: String? = nil,
                    licence: HmmLicence? = nil) {
            self.kind = kind
            self.id = id
            self.name = name
            self.file = file
            self.files = files
            self.author = author
            self.licence = licence
        }
    }

    /// Where an item came from once it's imported: its own author and licence, else the pack's.
    public func origin(of item: Item, imported: Date = Date()) -> HmmPackOrigin {
        HmmPackOrigin(author: item.author ?? author, licence: item.licence ?? licence, pack: name, imported: imported)
    }

    public var format: Int
    /// The app that made it (`maquette`); another app's pack is refused by name.
    public var app: String
    public var name: String
    public var author: String
    public var licence: HmmLicence
    public var created: Date
    public var items: [Item]

    public init(app: String, name: String, author: String, licence: HmmLicence, created: Date = Date(), items: [Item]) {
        format = Self.formatVersion
        self.app = app
        self.name = name
        self.author = author
        self.licence = licence
        self.created = created
        self.items = items
    }

    /// The licence file written beside the manifest, so the terms are readable without the app.
    public var licenceText: String {
        "\(name)\n\n\(licence.sentence(author: author))\n"
    }

    /// Every file the manifest names (the items' files and what they need).
    public var files: Set<String> {
        Set(items.flatMap { [$0.file] + $0.files })
    }

    public enum Problem: Error, Equatable, CustomStringConvertible {
        case newer(Int)
        case otherApp(String)
        case tooMany
        case unsafePath(String)
        case empty

        public var description: String {
            switch self {
            case .newer: "This pack was made by a newer version of the app"
            case let .otherApp(app): "This pack was made for \(app)"
            case .tooMany: "This pack holds too many things"
            case let .unsafePath(path): "This pack names a file outside itself (\(path))"
            case .empty: "This pack is empty"
            }
        }
    }

    /// Checks the manifest before anything in the pack is read.
    public func validate(app expected: String) throws(Problem) {
        guard format <= Self.formatVersion else { throw .newer(format) }
        guard app == expected else { throw .otherApp(app) }
        guard !items.isEmpty else { throw .empty }
        guard items.count <= Self.maximumItems, files.count <= Self.maximumItems * 8 else { throw .tooMany }
        for path in files where !Self.isSafe(path) {
            throw .unsafePath(path)
        }
    }

    /// A relative path that stays inside the pack.
    public static func isSafe(_ path: String) -> Bool {
        !path.isEmpty && !path.hasPrefix("/") && !path.hasPrefix("\\") && !path.contains("..") && !path.contains(":")
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }

    public static func decode(_ data: Data) throws -> HmmPackManifest {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(HmmPackManifest.self, from: data)
    }
}
