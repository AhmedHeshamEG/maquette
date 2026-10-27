import Foundation
import LoweyCore
import LoweyEngine
import UIKit

/// Making, copying and moving projects (Theater actions), the samples, and files coming in from elsewhere.
extension AppModel {
    /// A new project from a starter template, in a Mood and a Look (the template suggests both). Made inside a stack,
    /// it joins the stack.
    func createProject(named name: String, template: StarterTemplate = .blank, mood: LightingPreset, look presetID: String,
                       inStack stack: String? = nil) {
        do {
            var look = Look.default.applying(mood)
            look.presetID = presetID
            let title = name.isEmpty ? String(localized: "Untitled") : name
            var (url, _) = try projectStore.createProject(name: title, template: template, look: look)
            // Made inside a stack, it's made in the stack's folder.
            if let stack { url = try projectStore.folders.move(url, to: stack) }
            refreshProjects()
            open(url: url)
        } catch {
            show("Couldn't create the project: \(error.localizedDescription)", kind: .error)
        }
    }

    /// The + on Home (and the quiet set-up row): a new project straight away, in its set-up's world (Blank: the dark
    /// studio), named by itself. It can be renamed from its card any time.
    /// With no set-up named, the + makes your defaults (Settings ▸ New projects, U8): your set-up, Look, units and brush.
    func startProject(_ kind: StarterTemplate.Kind? = nil, inStack stack: String? = nil) {
        let template = kind.map(StarterTemplate.template) ?? YourSettings.template()
        createProject(named: newProjectName(), template: template, mood: template.mood, look: template.lookPresetID, inStack: stack)
        if kind == nil, let brush = UserDefaults.standard.string(forKey: YourSettings.defaultBrush), brushes.library.brush(brush) != nil {
            brushes.select(brush, for: .ink)
        }
    }

    /// "Untitled", then "Untitled 2", "Untitled 3"… so a fresh project never shares a name.
    func newProjectName() -> String {
        let base = String(localized: "Untitled")
        let names = Set(projects.map(\.info.name))
        guard names.contains(base) else { return base }
        var number = 2
        while names.contains("\(base) \(number)") {
            number += 1
        }
        return "\(base) \(number)"
    }

    func duplicate(_ project: ProjectSummary) {
        perform("duplicate") { _ = try projectStore.duplicateProject(at: project.url) }
    }

    func rename(_ project: ProjectSummary, to name: String) {
        guard !name.isEmpty else { return }
        perform("rename") { _ = try projectStore.renameProject(at: project.url, to: name) }
    }

    func delete(_ project: ProjectSummary) {
        perform("delete") {
            try projectStore.deleteProject(at: project.url)
            cardImages.remove(project.id)
        }
    }

    func archive(_ project: ProjectSummary) {
        perform("archive") { _ = try projectStore.archiveProject(at: project.url) }
        show("Archived. Find it in Home ▸ Archive")
    }

    func unarchive(_ project: ProjectSummary) {
        perform("restore") { _ = try projectStore.unarchiveProject(at: project.url) }
    }

    /// The project with its library assets copied in, as a folder (Files, AirDrop).
    func exportFolder(_ project: ProjectSummary) -> URL? {
        do {
            let info = try projectStore.loadProjectInfo(at: project.url).info
            let scenes = info.sceneOrder.compactMap { try? projectStore.loadScene($0, in: project.url).scene }
            _ = try ProjectAssets.embed(scenes: scenes, library: library.manifest, libraryStore: library.store, into: project.url)
            return project.url
        } catch {
            show("Couldn't prepare the project: \(error.localizedDescription)", kind: .error)
            return nil
        }
    }

    /// One `.maquettepack` file to share or back up (library assets included).
    func package(_ project: ProjectSummary) -> URL? {
        guard exportFolder(project) != nil else { return nil }
        do {
            let data = try ProjectPackage.archive(project.url)
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(ProjectStore.sanitize(project.info.name))
                .appendingPathExtension(ProjectPackage.fileExtension)
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            show("Couldn't package the project: \(error.localizedDescription)", kind: .error)
            return nil
        }
    }

    func importPackage(_ url: URL) {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            let destination = try ProjectPackage.unpack(Data(contentsOf: url), into: projectStore)
            adoptAssets(of: destination)
        } catch {
            show("Couldn't import: \(String(describing: error))", kind: .error)
        }
    }

    /// Copies a scene of the open project into another project.
    func copyScene(_ scene: SceneID, from source: URL, to project: ProjectSummary) {
        do {
            let copied = try projectStore.copyScene(scene, from: source, to: project.url)
            show("“\(copied.name)” copied to \(project.info.name)")
        } catch {
            show("Couldn't copy the scene: \(error.localizedDescription)", kind: .error)
        }
    }

    // MARK: Samples

    func createIslandSample(open shouldOpen: Bool) {
        do {
            let (info, scenes) = try Showcase.island(kit: library.manifest.kit, ids: .random)
            var fresh = info
            fresh.id = .make()
            let url = try projectStore.writeProject(info: fresh, scenes: scenes)
            refreshProjects()
            drawSampleCard(url)
            if shouldOpen { open(url: url) }
        } catch {
            show("Couldn't add the island: \(error.localizedDescription)", kind: .error)
        }
    }

    /// The Enigma sets (Ink, Comic, Sketch) and the narrated story (a placeholder narrator speaks each sentence at its time).
    func createEnigmaSample(open shouldOpen: Bool) {
        do {
            let (info, scenes) = try Showcase.enigma(kit: library.manifest.kit, ids: .random)
            var fresh = info
            fresh.id = .make()
            fresh.created = Date()
            fresh.modified = Date()
            let url = try projectStore.writeProject(info: fresh, scenes: scenes)
            refreshProjects()
            drawSampleCard(url)
            let voice = url.appendingPathComponent(ProjectLayout.audioFolder).appendingPathComponent(EnigmaSample.voiceoverFile)
            Task {
                try? await PlaceholderVoice.render(EnigmaSample.narration.map { ($0.sentence, $0.start) }, duration: 12.6, to: voice)
                if shouldOpen { open(url: url) }
            }
        } catch {
            show("Couldn't add the sample: \(error.localizedDescription)", kind: .error)
        }
    }

    /// A new sample's card is drawn right away, so Home is alive from the first launch.
    private func drawSampleCard(_ url: URL) {
        guard !AppIdentity.isUITesting || AppIdentity.isTakingScreenshots, let document = try? projectStore.openDocument(at: url) else { return }
        Task { await drawCard(EditorModel.CardJob(document: document, viewpoint: document.scene.viewpoint, projectURL: url)) }
    }

    /// The 60-second tour happens on the welcome island (added if it isn't there).
    func startTour() {
        if let island = projects.first(where: { $0.info.name == Showcase.islandName }) {
            open(url: island.url)
        } else {
            createIslandSample(open: true)
        }
        showTour = true
    }

    // MARK: Incoming files (share sheet, Open in…, drag and drop)

    public func handleOpenedFile(_ url: URL) {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case _ where ProjectLayout.isProject(url):
            importProjectFolder(url)
        case _ where ext == ProjectPackage.fileExtension || ProjectPackage.legacyExtensions.contains(ext):
            openPackage(url)
        case _ where LayeredImage.fileExtensions.contains(ext):
            landDrawing(url)
        case _ where BrushFileImport.fileExtensions.contains(ext):
            Task { await importBrushes(url) }
        case "json" where EditorModel.isThreeSceneFile(url), "zip", "html", "htm":
            landWeb(url)
        case _ where url.hasDirectoryPath && EditorModel.isWebProject(url):
            landWeb(url)
        case "json" where editor != nil:
            if let data = try? Data(contentsOf: url) { editor?.importScript(data, source: url.lastPathComponent) }
        default:
            landModels([url])
        }
    }

    /// three.js work from elsewhere (X1): a scene file or a project (a page, a folder, a zip) comes into the open
    /// project's scene, or a new one made for it.
    func landWeb(_ url: URL) {
        if editor == nil { startProject() }
        if EditorModel.isThreeJSON(url) {
            editor?.bringInThreeJSON(url)
        } else {
            editor?.bringInThreeProject(url)
        }
    }

    /// A `.maquettepack` holds a project or library things (L2): what's inside decides where it goes.
    func openPackage(_ url: URL) {
        let access = url.startAccessingSecurityScopedResource()
        let data = try? Data(contentsOf: url)
        if access { url.stopAccessingSecurityScopedResource() }
        if let data, LibraryPack.isLibraryPack(data) {
            Task { await importLibraryPack(data) }
        } else {
            importPackage(url)
        }
    }

    /// A layered drawing from elsewhere (L2) stands up as a diorama in the open project, or in a new one made for it.
    func landDrawing(_ url: URL) {
        if editor == nil { startProject() }
        Task { await editor?.importDrawing(url) }
    }

    /// Model files from elsewhere (Open in, the share sheet, a drop on Home, Home's import) land on the stage: in the
    /// open project, or a new one made for them. More than one: the first lands, the rest wait in the Library.
    func landModels(_ urls: [URL], at point: CGPoint? = nil) {
        Task {
            let assets = await library.importAssets(urls)
            guard let first = assets.first else {
                show("Nothing Maquette can open there (glTF, GLB, OBJ, USDZ, STL, 3MF)", kind: .error)
                return
            }
            if editor == nil { startProject() }
            editor?.land(first, at: point)
            if assets.count > 1 { show("The other \(assets.count - 1) are in your Library") }
        }
    }

    /// A brush file (Procreate, Photoshop or a shared set) joins the brush library as a new set.
    func importBrushes(_ url: URL) async {
        switch await brushes.importFile(url) {
        case let .added(set, count) where count == 1:
            show("Added “\(set)” to your brushes")
        case let .added(set, count):
            show("Added \(count) brushes in “\(set)”")
        case let .failed(file):
            show("“\(file)” isn't a brush file Maquette can open", kind: .error)
        }
    }

    private func importProjectFolder(_ url: URL) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        do {
            let destination = projectStore.uniqueURL(for: url.deletingPathExtension().lastPathComponent)
            try FileManager.default.copyItem(at: url, to: destination)
            adoptAssets(of: destination)
        } catch {
            show("Couldn't import the project: \(error.localizedDescription)", kind: .error)
        }
    }

    /// Library assets that came inside an imported project join the library.
    private func adoptAssets(of project: URL) {
        do {
            var manifest = library.manifest
            let added = try ProjectAssets.adopt(from: project, into: &manifest, libraryStore: library.store)
            library.replaceManifest(manifest)
            refreshProjects()
            show(added > 0 ? "Project imported with \(added) library items" : "Project imported")
        } catch {
            show("Imported, but its library items couldn't be read: \(error.localizedDescription)", kind: .error)
        }
    }

    private func perform(_ verb: String, _ body: () throws -> Void) {
        do {
            try body()
            refreshProjects()
            refreshArchived()
        } catch {
            show("Couldn't \(verb) it: \(error.localizedDescription)", kind: .error)
        }
    }
}
