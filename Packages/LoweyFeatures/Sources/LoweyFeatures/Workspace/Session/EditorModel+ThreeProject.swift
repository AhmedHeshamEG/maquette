import Foundation
import HmmWeb
import LoweyCore
import LoweyEngine

/// A three.js project (a folder or a zip with its page and scripts) brought in (X1 step 3): it plays in the web sandbox
/// with no network, the recorder takes its scene and ten seconds of its motion, and they come in as editable things and
/// keys. A surface drawn by its own shader stays playing on a card in its place; a page with no three.js scene (an HTML
/// composition) plays over the frame instead. Nothing is asked first.
extension EditorModel {
    /// How much of the page's motion comes in, and how finely (keys a second, before the straight stretches are dropped).
    static let recordedSeconds = 10.0
    static let recordedRate = 30

    /// Whether a chosen file is a web project: a page, a zip, or a folder with a page in it.
    static func isWebProject(_ url: URL) -> Bool {
        if ["zip", "html", "htm"].contains(url.pathExtension.lowercased()) { return true }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        return webEntry(in: url) != nil
    }

    /// The page a folder opens with: `index.html`, else its only page; one folder deep when a zip wrapped it.
    static func webEntry(in folder: URL) -> String? {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        let pages = names.filter { $0.lowercased().hasSuffix(".html") }
        if pages.contains("index.html") { return "index.html" }
        if pages.count == 1 { return pages[0] }
        let folders = names.filter { !$0.hasPrefix(".") && !$0.hasPrefix("__MACOSX") }
        if pages.isEmpty, folders.count == 1, let inner = webEntry(in: folder.appendingPathComponent(folders[0])) {
            return folders[0] + "/" + inner
        }
        return nil
    }

    /// Brings a three.js project into the scene, as one step.
    func bringInThreeProject(_ url: URL) {
        Task { await bringInThreeProject(at: url) }
    }

    func bringInThreeProject(at url: URL) async {
        let copied: (name: String, entry: String)
        do {
            copied = try copyWebProject(url)
        } catch {
            app.show("Couldn't open \(url.lastPathComponent): \(error.localizedDescription)", kind: .error)
            return
        }
        let folder = assetsFolder.appendingPathComponent(copied.name)
        // A zip that wrapped its page in a folder: the stand-ins' pages sit beside the page, so its own paths still work.
        let inner = (copied.entry as NSString).deletingLastPathComponent
        let pieceFile = inner.isEmpty ? copied.name : copied.name + "/" + inner
        app.show("Playing \(url.deletingPathExtension().lastPathComponent) to bring it in…")
        let output = await Self.record(HmmWebPiece(kind: .html, source: .folder(folder, entry: copied.entry)))
        var ids = operations.ids
        defer { operations.ids = ids }
        let recording: ThreeRecording.Result
        do {
            recording = try ThreeRecording.read(output ?? #"{"error":"noScene"}"#, folder: pieceFile, ids: &ids)
        } catch ThreeRecording.Failure.noScene {
            // An HTML composition (HyperFrames and the like): it plays over the frame, on the timeline's clock.
            let piece = WebPiece(kind: .html, file: copied.name, entry: copied.entry, start: 0)
            if addWebPiece(piece, as: .overlay, named: url.deletingPathExtension().lastPathComponent) != nil {
                app.show("No three.js scene in it: it plays over the frame as a web piece")
            }
            return
        } catch {
            app.show(String.LocalizationValue(String(describing: error)), kind: .error)
            return
        }
        do {
            try writeSoloPages(recording, folder: folder.appendingPathComponent(inner), entry: (copied.entry as NSString).lastPathComponent)
        } catch {
            app.show("Couldn't save the page's copies: \(error.localizedDescription)", kind: .error)
            return
        }
        if recording.reader.scene.pictures.isEmpty, recording.reader.scene.files.isEmpty {
            guard perform(ModelingOperations.importScene(recording.reader.scene, in: baseScene)) else { return }
            broughtIn(recording.reader)
        } else {
            bringInPainted(recording.reader)
        }
    }

    /// The page played offscreen with the recorder: the scene's motion as JSON, or nil when it didn't play.
    private static func record(_ piece: HmmWebPiece) async -> String? {
        let player = HmmWebPlayer(piece: piece, scripts: [ThreeRecorder.hook])
        defer { player.unload() }
        // Its modules and models load on real time: wait until the scene stops growing (about four seconds at most).
        var last = -1
        for _ in 0 ..< 40 {
            let count = await (player.evaluate("return window.__maquetteThree ? window.__maquetteThree.count() : -1;", atFrame: 0) as? NSNumber)?.intValue ?? -1
            if count < 0 { return nil }
            if count > 0, count == last { break }
            last = count
            try? await Task.sleep(for: .milliseconds(100))
        }
        let body = ThreeRecorder.record(from: 0, seconds: recordedSeconds, rate: recordedRate)
        return await player.evaluate(body, atFrame: 0) as? String
    }

    /// The project copied into `assets/` (a zip unpacked there), so its stand-ins keep playing.
    private func copyWebProject(_ url: URL) throws -> (name: String, entry: String) {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        try FileManager.default.createDirectory(at: assetsFolder, withIntermediateDirectories: true)
        let name = uniqueMediaName(url.deletingPathExtension().lastPathComponent)
        let destination = assetsFolder.appendingPathComponent(name, isDirectory: true)
        if url.pathExtension.lowercased() == "zip" {
            let entries = try ZipReader.entries(Data(contentsOf: url)) { !$0.hasSuffix("/") && !$0.hasPrefix("__MACOSX/") }
            for entry in entries {
                let target = destination.appendingPathComponent(entry.name).standardizedFileURL
                // Nothing in a zip writes outside its own folder.
                guard target.path.hasPrefix(destination.standardizedFileURL.path + "/") else { continue }
                try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                try entry.data.write(to: target)
            }
        } else if url.hasDirectoryPath {
            try FileManager.default.copyItem(at: url, to: destination)
        } else {
            // One page on its own: a folder of its own.
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: url, to: destination.appendingPathComponent(url.lastPathComponent))
        }
        guard let entry = Self.webEntry(in: destination) else {
            try? FileManager.default.removeItem(at: destination)
            throw CocoaError(.fileReadCorruptFile, userInfo: [NSLocalizedDescriptionKey: "there's no page (.html) in it"])
        }
        return (name, entry)
    }

    /// Beside the page, a copy of it for each stand-in that shows only that surface.
    private func writeSoloPages(_ recording: ThreeRecording.Result, folder: URL, entry: String) throws {
        guard !recording.standIns.isEmpty else { return }
        let html = try String(contentsOf: folder.appendingPathComponent(entry), encoding: .utf8)
        for (index, standIn) in recording.standIns.map(\.standIn).enumerated() {
            try Data(ThreeRecording.soloPage(html, standIn: standIn).utf8).write(to: folder.appendingPathComponent(ThreeRecording.soloEntry(index)))
        }
    }
}
