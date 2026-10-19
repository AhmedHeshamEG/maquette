import Foundation
import HmmDocuments
import LoweyCore

/// Home's arrangement (L2: stacks are real folders, one level deep, so the Files app shows the same stacks): stacking,
/// moving in and out, renaming, each stack's own sort, and acting on several projects at once. Every change moves
/// files, then Home reads the folders again.
extension AppModel {
    /// The projects as the gallery sees them.
    var galleryItems: [GalleryItem] {
        projects.map { GalleryItem(id: $0.id.raw, name: $0.info.name, created: $0.info.created, modified: $0.info.modified) }
    }

    func project(_ id: String) -> ProjectSummary? {
        projects.first { $0.id.raw == id }
    }

    /// The order of the top level (nil) or inside a stack.
    func setGallerySort(_ sort: GallerySort, in stack: String? = nil) {
        guard gallery.sort(in: stack) != sort else { return }
        gallery.setSort(sort, in: stack)
        saveGallery()
    }

    /// Stacks projects together in a new folder and returns its name (the stack's id).
    @discardableResult
    func stackProjects(_ ids: [String], named name: String? = nil) -> String? {
        guard !ids.isEmpty else { return nil }
        let title = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let folder = try projectStore.folders.createFolder(named: title?.isEmpty == false ? title ?? "" : String(localized: "Stack"))
            moveProjects(ids, to: folder.name)
            return folder.name
        } catch {
            show("Couldn't make the stack: \(error.localizedDescription)", kind: .error)
            return nil
        }
    }

    /// Drops one project onto another (a new stack of the two) or onto a stack (it joins).
    func drop(_ project: String, onto target: GalleryEntry) {
        switch target {
        case let .item(item):
            guard item.id != project else { return }
            stackProjects([item.id, project])
        case let .stack(stack, _):
            moveProjects([project], to: stack.id)
        }
    }

    func addToStack(_ ids: [String], stack: String) {
        moveProjects(ids, to: stack)
    }

    func moveOutOfStacks(_ ids: [String]) {
        moveProjects(ids, to: nil)
    }

    /// Moves projects into a stack's folder (nil: the top level).
    func moveProjects(_ ids: [String], to folder: String?) {
        let moving = ids.compactMap(project)
        do {
            for summary in moving where summary.folder != folder {
                try projectStore.folders.move(summary.url, to: folder)
            }
        } catch {
            show("Couldn't move it: \(error.localizedDescription)", kind: .error)
        }
        refreshProjects()
    }

    /// Takes a stack apart: its projects go back to the top level and the folder goes.
    func unstack(_ stack: String) {
        do {
            try projectStore.folders.dissolve(stack)
        } catch {
            show("Couldn't unstack it: \(error.localizedDescription)", kind: .error)
        }
        refreshProjects()
    }

    /// Renames a stack (its folder); returns its new id.
    @discardableResult
    func renameStack(_ stack: String, to name: String) -> String {
        do {
            let renamed = try projectStore.folders.rename(stack, to: name)
            if let sort = gallery.sorts[stack] {
                gallery.sorts[stack] = nil
                gallery.sorts[renamed] = sort
                saveGallery()
            }
            refreshProjects()
            return renamed
        } catch {
            show("Couldn't rename it: \(error.localizedDescription)", kind: .error)
            return stack
        }
    }

    /// Reads the projects and their folders; 0.23's stacks (kept by id in `gallery.json`) become folders once.
    func refreshGallery() {
        var arrangement = GalleryArrangement.load(from: projectStore.root)
        if !arrangement.usesFolders, !arrangement.stacks.isEmpty {
            let urls = Dictionary(projects.map { ($0.id.raw, $0.url) }, uniquingKeysWith: { first, _ in first })
            if let migrated = try? projectStore.folders.migrate(arrangement, url: { urls[$0] }) {
                arrangement = migrated
                projects = projectStore.listProjects()
            }
        }
        var members: [String: [String]] = [:]
        for summary in projects {
            if let folder = summary.folder { members[folder, default: []].append(summary.id.raw) }
        }
        let before = arrangement
        arrangement.adopt(projectStore.folders.folders(), members: members)
        gallery = arrangement
        if arrangement.usesFolders != before.usesFolders || arrangement.sorts != before.sorts { saveGallery() }
    }

    // MARK: Several at once

    func duplicate(_ ids: [String]) {
        for id in ids {
            if let summary = project(id) { duplicate(summary) }
        }
    }

    func archive(_ ids: [String]) {
        let chosen = ids.compactMap(project)
        for summary in chosen {
            _ = try? projectStore.archiveProject(at: summary.url)
        }
        refreshProjects()
        refreshArchived()
        if !chosen.isEmpty { show(chosen.count == 1 ? "Archived. Find it in Home ▸ Archive" : "Archived \(chosen.count) projects") }
    }

    func delete(_ ids: [String]) {
        for summary in ids.compactMap(project) {
            delete(summary)
        }
    }
}
