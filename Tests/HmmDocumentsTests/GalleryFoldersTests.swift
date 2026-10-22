@testable import HmmDocuments
import XCTest

final class GalleryFoldersTests: XCTestCase {
    private var root = FileManager.default.temporaryDirectory

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("folders-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
    }

    private var folders: GalleryFolders {
        GalleryFolders(root: root, reserved: ["Archive"]) { $0.pathExtension == "doc" }
    }

    @discardableResult
    private func document(_ name: String, in folder: String? = nil) throws -> URL {
        let place = folder.map { root.appendingPathComponent($0) } ?? root
        let url = place.appendingPathComponent("\(name).doc", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: url.appendingPathComponent("project.json"))
        return url
    }

    func testFoldersAreStacksAndDocumentsAreNot() throws {
        try document("Robot")
        try document("Room", in: "Rooms")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Archive"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent(".hidden"), withIntermediateDirectories: true)
        XCTAssertEqual(folders.folders().map(\.name), ["Rooms"], "the archive, hidden folders and documents aren't stacks")
        XCTAssertEqual(folders.documents(in: nil).map(\.lastPathComponent), ["Robot.doc"])
        XCTAssertEqual(folders.allDocuments().map { "\($0.folder ?? "-")/\($0.url.lastPathComponent)" }.sorted(), ["-/Robot.doc", "Rooms/Room.doc"])
    }

    func testMovingKeepsNamesUniqueAndDissolvingEmptiesTheFolder() throws {
        let robot = try document("Robot")
        try document("Robot", in: "Toys")
        let moved = try folders.move(robot, to: "Toys")
        XCTAssertEqual(moved.lastPathComponent, "Robot 2.doc", "a name taken in the folder gets a number")
        XCTAssertEqual(try folders.move(moved, to: "Toys"), moved, "moving to where it is changes nothing")
        let back = try folders.dissolve("Toys")
        XCTAssertEqual(back.map(\.lastPathComponent).sorted(), ["Robot 2.doc", "Robot.doc"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("Toys").path), "the empty folder goes")
    }

    func testDissolvingLeavesAFolderWithOtherThings() throws {
        try document("Plan", in: "Work")
        try Data("notes".utf8).write(to: root.appendingPathComponent("Work/notes.txt"))
        try folders.dissolve("Work")
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("Work/notes.txt").path))
        XCTAssertEqual(folders.documents(in: nil).map(\.lastPathComponent), ["Plan.doc"])
    }

    func testCreatingAndRenamingMakeSafeUniqueNames() throws {
        XCTAssertEqual(try folders.createFolder(named: "  Rooms/2 ").name, "Rooms-2")
        XCTAssertEqual(try folders.createFolder(named: "Rooms-2").name, "Rooms-2 2")
        XCTAssertEqual(try folders.createFolder(named: "...").name, "Stack")
        XCTAssertEqual(try folders.rename("Stack", to: "Rooms-2"), "Rooms-2 3")
        XCTAssertEqual(try folders.rename("Rooms-2 3", to: "Rooms-2 3"), "Rooms-2 3")
        XCTAssertEqual(folders.folders().map(\.name), ["Rooms-2", "Rooms-2 2", "Rooms-2 3"])
    }

    func testStacksFromTheOldArrangementMoveIntoFolders() throws {
        let a = try document("A")
        let b = try document("B")
        try document("C")
        var old = GalleryArrangement(sort: .name)
        old.stack(["a", "b", "gone"], name: "Pair", id: "s1")
        let urls = ["a": a, "b": b]
        let left = try folders.migrate(old) { urls[$0] }
        XCTAssertTrue(left.stacks.isEmpty)
        XCTAssertTrue(left.usesFolders)
        XCTAssertEqual(left.sort, .name, "the sort stays")
        XCTAssertEqual(folders.documents(in: "Pair").map(\.lastPathComponent).sorted(), ["A.doc", "B.doc"])
        XCTAssertEqual(folders.documents(in: nil).map(\.lastPathComponent), ["C.doc"])
    }

    func testAnArrangementAdoptsTheFoldersAndKeepsEachStacksSort() throws {
        try document("Room", in: "Rooms")
        var arrangement = GalleryArrangement()
        arrangement.setSort(.name, in: "Rooms")
        arrangement.setSort(.created, in: "Gone")
        arrangement.adopt(folders.folders(), members: ["Rooms": ["r1", "r2"]])
        XCTAssertEqual(arrangement.stacks.map(\.id), ["Rooms"])
        XCTAssertEqual(arrangement.sort(in: "Rooms"), .name)
        XCTAssertEqual(arrangement.sort(in: nil), .recent)
        XCTAssertNil(arrangement.sorts["Gone"], "a folder that went takes its sort with it")
        let items = [GalleryItem(id: "r1", name: "Zed", created: Date(timeIntervalSince1970: 1), modified: Date(timeIntervalSince1970: 9)),
                     GalleryItem(id: "r2", name: "Ant", created: Date(timeIntervalSince1970: 2), modified: Date(timeIntervalSince1970: 1))]
        XCTAssertEqual(arrangement.entries(items, in: "Rooms").map(\.id), ["item-r2", "item-r1"], "inside, the stack's own order")
        XCTAssertEqual(arrangement.entries(items).map(\.id), ["stack-Rooms"])
    }

    func testAFolderArrangementSavesItsSortsButNotTheListing() throws {
        var arrangement = GalleryArrangement(sort: .created)
        arrangement.adopt([GalleryFolders.Folder(name: "Rooms", url: root, created: Date(timeIntervalSince1970: 1))], members: ["Rooms": ["a"]])
        arrangement.setSort(.name, in: "Rooms")
        try arrangement.save(to: root)
        let loaded = GalleryArrangement.load(from: root)
        XCTAssertTrue(loaded.usesFolders)
        XCTAssertTrue(loaded.stacks.isEmpty, "the folders are read from disk")
        XCTAssertEqual(loaded.sorts, ["Rooms": .name])
        XCTAssertEqual(loaded.sort, .created)
    }
}

final class PackManifestTests: XCTestCase {
    private func manifest(_ items: [HmmPackManifest.Item]) -> HmmPackManifest {
        HmmPackManifest(app: "maquette", name: "Autumn", author: "Lina", licence: .credit, created: Date(timeIntervalSince1970: 1_000_000),
                        items: items)
    }

    func testRoundTripsWithItsAuthorAndLicence() throws {
        let pack = manifest([.init(kind: "brush", id: "b1", name: "Leaf", file: "items/b1.json", files: ["pictures/leaf.png"])])
        let read = try HmmPackManifest.decode(pack.encoded())
        XCTAssertEqual(read, pack)
        XCTAssertEqual(read.files, ["items/b1.json", "pictures/leaf.png"])
        XCTAssertNoThrow(try read.validate(app: "maquette"))
        XCTAssertTrue(read.licenceText.contains("name Lina where it's shown"))
    }

    func testRefusesWhatItShouldnt() {
        let item = HmmPackManifest.Item(kind: "look", id: "l", name: "L", file: "items/l.json")
        XCTAssertThrowsError(try manifest([item]).validate(app: "cutaway")) { XCTAssertEqual($0 as? HmmPackManifest.Problem, .otherApp("maquette")) }
        XCTAssertThrowsError(try manifest([]).validate(app: "maquette")) { XCTAssertEqual($0 as? HmmPackManifest.Problem, .empty) }
        var escaping = item
        escaping.files = ["../outside.png"]
        XCTAssertThrowsError(try manifest([escaping]).validate(app: "maquette")) {
            XCTAssertEqual($0 as? HmmPackManifest.Problem, .unsafePath("../outside.png"))
        }
        var newer = manifest([item])
        newer.format = HmmPackManifest.formatVersion + 1
        XCTAssertThrowsError(try newer.validate(app: "maquette"))
        XCTAssertFalse(HmmPackManifest.isSafe("/etc/passwd"))
        XCTAssertFalse(HmmPackManifest.isSafe("C:evil"))
        XCTAssertTrue(HmmPackManifest.isSafe("items/a b.json"))
    }

    func testAnItemFromSomeoneElseKeepsItsAuthor() {
        let own = HmmPackManifest.Item(kind: "brush", id: "a", name: "Mine", file: "items/a.json")
        let passedOn = HmmPackManifest.Item(kind: "brush", id: "b", name: "Hers", file: "items/b.json", author: "Sara", licence: .personal)
        let pack = manifest([own, passedOn])
        XCTAssertEqual(pack.origin(of: own).author, "Lina")
        XCTAssertEqual(pack.origin(of: own).licence, .credit)
        XCTAssertEqual(pack.origin(of: passedOn).author, "Sara")
        XCTAssertEqual(pack.origin(of: passedOn).licence, .personal)
        XCTAssertEqual(pack.origin(of: passedOn).pack, "Autumn")
    }

    func testLicencesInWords() throws {
        XCTAssertEqual(HmmLicence.anything.sentence(author: ""), "Made by the author. Use it in anything you make, commercial work included.")
        XCTAssertEqual(HmmLicence.own("  Ask me first. ").sentence(author: "Sara"), "Made by Sara. Ask me first.")
        XCTAssertEqual(HmmLicence.own(" ").sentence(author: "Sara"), "Made by Sara.")
        for licence in [HmmLicence.anything, .credit, .personal, .own("Mine")] {
            let data = try JSONEncoder().encode(licence)
            XCTAssertEqual(try JSONDecoder().decode(HmmLicence.self, from: data), licence)
        }
        XCTAssertEqual(try JSONDecoder().decode(HmmLicence.self, from: Data(#"{"kind":"future"}"#.utf8)), .anything)
        XCTAssertTrue(HmmLicence.own("a").sameKind(as: .own("b")))
        XCTAssertEqual(HmmLicence.choices.map(\.title), ["Use in anything", "Credit me", "Personal use only", "My own words"])
    }
}
