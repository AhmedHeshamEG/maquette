import Foundation
import HmmDocuments
@testable import LoweyCore
import XCTest

/// Home's stacks are real folders (L2): projects are found in them, and renaming or duplicating one keeps it there.
final class ProjectFoldersTests: XCTestCase {
    func testProjectsInFoldersAreListedWithTheirFolder() throws {
        let store = try ProjectStore(root: temporaryDirectory())
        let (loose, _) = try store.createProject(name: "Loose")
        let (tower, _) = try store.createProject(name: "Tower")
        let moved = try store.folders.move(tower, to: store.folders.createFolder(named: "Towers").name)
        _ = try store.archiveProject(at: loose)
        let listed = store.listProjects()
        XCTAssertEqual(listed.map(\.info.name), ["Tower"], "the archive isn't a stack")
        XCTAssertEqual(listed.first?.folder, "Towers")
        XCTAssertEqual(listed.first?.url.standardizedFileURL.path, moved.standardizedFileURL.path)
        XCTAssertEqual(store.folders.folders().map(\.name), ["Towers"])
    }

    func testRenamingAndDuplicatingStayInTheFolder() throws {
        let store = try ProjectStore(root: temporaryDirectory())
        let (url, _) = try store.createProject(name: "Draft")
        let inside = try store.folders.move(url, to: store.folders.createFolder(named: "Work").name)
        let renamed = try store.renameProject(at: inside, to: "Final")
        XCTAssertEqual(renamed.deletingLastPathComponent().lastPathComponent, "Work")
        let copy = try store.duplicateProject(at: renamed)
        XCTAssertEqual(copy.deletingLastPathComponent().lastPathComponent, "Work")
        XCTAssertEqual(Set(store.listProjects().map(\.folder)), ["Work"])
    }
}
