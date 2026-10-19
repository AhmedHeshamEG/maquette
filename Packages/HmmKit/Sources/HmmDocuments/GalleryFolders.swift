import Foundation

/// Stacks as real folders (Maquette 0.24): a stack on the gallery is a folder beside the documents, one level deep,
/// so the Files app shows the same arrangement and a folder made there is a stack in the app. The folder's name is the
/// stack's name and its id. Synchronous file work: call it off the main thread.
public struct GalleryFolders: Sendable {
    public struct Folder: Hashable, Sendable {
        public var name: String
        public var url: URL
        public var created: Date
    }

    public let root: URL
    /// Folders that are the app's own (an archive), never stacks.
    public let reserved: Set<String>
    private let isDocument: @Sendable (URL) -> Bool

    public init(root: URL, reserved: Set<String> = [], isDocument: @escaping @Sendable (URL) -> Bool) {
        self.root = root
        self.reserved = reserved
        self.isDocument = isDocument
    }

    // MARK: Reading

    /// The stacks: every visible folder that isn't a document or the app's own, by name.
    public func folders() -> [Folder] {
        let keys: [URLResourceKey] = [.isDirectoryKey, .creationDateKey]
        let entries = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])) ?? []
        return entries.compactMap { url -> Folder? in
            let values = try? url.resourceValues(forKeys: Set(keys))
            guard values?.isDirectory == true, !isDocument(url), !reserved.contains(url.lastPathComponent) else { return nil }
            return Folder(name: url.lastPathComponent, url: url, created: values?.creationDate ?? .distantPast)
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// The documents at the top level (`nil`) or in one folder.
    public func documents(in folder: String?) -> [URL] {
        let place = folder.map { root.appendingPathComponent($0, isDirectory: true) } ?? root
        let entries = (try? FileManager.default.contentsOfDirectory(at: place, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        return entries.filter(isDocument)
    }

    /// Every document with the folder it's in (nil at the top level).
    public func allDocuments() -> [(url: URL, folder: String?)] {
        documents(in: nil).map { ($0, nil) } + folders().flatMap { folder in documents(in: folder.name).map { ($0, folder.name) } }
    }

    // MARK: Changing

    /// A new folder, its name made unique ("Stack", "Stack 2"…).
    @discardableResult
    public func createFolder(named name: String) throws -> Folder {
        let url = unique(Self.sanitize(name), in: root, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        return Folder(name: url.lastPathComponent, url: url, created: Date())
    }

    /// Moves a document into a folder (nil: the top level), keeping its name unless one is taken there. Returns where it
    /// went.
    @discardableResult
    public func move(_ document: URL, to folder: String?) throws -> URL {
        let place = folder.map { root.appendingPathComponent($0, isDirectory: true) } ?? root
        guard place.standardizedFileURL.path != document.deletingLastPathComponent().standardizedFileURL.path else { return document }
        try FileManager.default.createDirectory(at: place, withIntermediateDirectories: true)
        let stem = document.deletingPathExtension().lastPathComponent
        let target = unique(stem, in: place, isDirectory: false, extension: document.pathExtension)
        try FileManager.default.moveItem(at: document, to: target)
        return target
    }

    /// Renames a folder; returns its new name (unique).
    @discardableResult
    public func rename(_ folder: String, to name: String) throws -> String {
        let cleaned = Self.sanitize(name)
        guard cleaned != folder else { return folder }
        let target = unique(cleaned, in: root, isDirectory: true)
        try FileManager.default.moveItem(at: root.appendingPathComponent(folder, isDirectory: true), to: target)
        return target.lastPathComponent
    }

    /// Takes a stack apart: its documents go to the top level and the folder goes, unless something that isn't a
    /// document is left in it (then it stays, as a folder the person made in Files). Returns the documents' new places.
    @discardableResult
    public func dissolve(_ folder: String) throws -> [URL] {
        let moved = try documents(in: folder).map { try move($0, to: nil) }
        let url = root.appendingPathComponent(folder, isDirectory: true)
        let left = (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        if left.isEmpty { try FileManager.default.removeItem(at: url) }
        return moved
    }

    /// Moves 0.23's stacks (members by id in `gallery.json`) into folders of their name. `url` finds a document by id.
    /// Returns the arrangement left (no stacks of its own any more; the sort kept).
    public func migrate(_ arrangement: GalleryArrangement, url: (String) -> URL?) throws -> GalleryArrangement {
        for stack in arrangement.stacks {
            let documents = stack.members.compactMap(url)
            guard !documents.isEmpty else { continue }
            let folder = try createFolder(named: stack.name)
            for document in documents {
                try move(document, to: folder.name)
            }
        }
        var left = arrangement
        left.stacks = []
        left.usesFolders = true
        return left
    }

    // MARK: Names

    /// A file-system-safe name: no slashes, colons or the like, trimmed, never empty, at most 80 characters.
    public static func sanitize(_ name: String) -> String {
        let forbidden = CharacterSet(charactersIn: "/\\:?%*|\"<>").union(.controlCharacters)
        let cleaned = String(String.UnicodeScalarView(name.unicodeScalars.map { forbidden.contains($0) ? "-" : $0 }))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let dotless = cleaned.hasPrefix(".") ? String(cleaned.drop { $0 == "." }) : cleaned
        return dotless.isEmpty ? "Stack" : String(dotless.prefix(80))
    }

    private func unique(_ stem: String, in folder: URL, isDirectory: Bool, extension ext: String = "") -> URL {
        func candidate(_ name: String) -> URL {
            let url = folder.appendingPathComponent(name, isDirectory: isDirectory)
            return ext.isEmpty ? url : url.appendingPathExtension(ext)
        }
        var url = candidate(stem)
        var counter = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = candidate("\(stem) \(counter)")
            counter += 1
        }
        return url
    }
}

public extension GalleryArrangement {
    /// The stacks as the folders say: each folder a stack holding the ids of the documents in it (`id` names a document
    /// by its place). Sorts of folders that went are forgotten.
    mutating func adopt(_ folders: [GalleryFolders.Folder], members: [String: [String]]) {
        stacks = folders.map { folder in
            GalleryStack(id: folder.name, name: folder.name, members: members[folder.name] ?? [], created: folder.created)
        }
        let names = Set(folders.map(\.name))
        sorts = sorts.filter { names.contains($0.key) }
        usesFolders = true
    }
}
