import Foundation
import HmmDesign
import LoweyCore
import LoweyEngine
import Photos
import UIKit

/// Export (A1, formats first): video (verified), PNG frames, render passes, GIF loops, stills, 3D files, the Look as a
/// shader, Paper and captions, on the stage's renderer. It runs in the background (the stage stays usable), keeps going
/// when the app leaves the screen, and reports its progress to the Live Activity.
extension EditorModel {
    var isExporting: Bool { exportProgress != nil }

    /// Starts an export (one at a time).
    func startExport(_ job: ExportJob) {
        guard exportTask == nil else { return }
        pause()
        exportProgress = 0
        exportResults = []
        let id = UUID().uuidString
        let reporter = app.exportReporter
        let background = BackgroundExport()
        background.onExpired = { [weak self] in self?.cancelExport() }
        background.begin(title: "Exporting \(baseScene.name)", subtitle: job.title)
        reporter?.exportStarted(id: id, title: job.title)
        ScreenAwake.hold("export", true)
        exportTask = Task { [weak self] in
            guard let self else { return }
            let urls = await runExport(job, id: id, background: background)
            background.end(success: urls != nil)
            if let urls {
                exportResults = urls
                HmmHaptics.play(.commit)
                reporter?.exportFinished(id: id, title: job.title, files: urls)
            }
            exportProgress = nil
            exportWaiting = false
            exportTask = nil
            ScreenAwake.hold("export", false)
        }
    }

    private func runExport(_ job: ExportJob, id: String, background: BackgroundExport) async -> [URL]? {
        let progress: (Double) -> Void = { [weak self] fraction in
            self?.exportProgress = fraction
            background.progress(fraction)
            self?.app.exportReporter?.exportProgressed(id: id, fraction: fraction, waiting: false)
        }
        do {
            try FileManager.default.createDirectory(at: rendersFolder, withIntermediateDirectories: true)
            let documents = try exportDocuments(job)
            var urls: [URL] = []
            for (index, document) in documents.enumerated() {
                let share = 1 / Double(documents.count)
                let step: (Double) -> Void = { progress((Double(index) + $0) * share) }
                urls += try await exportFiles(job, document: document, isOpen: index == 0, id: id, progress: step)
            }
            guard !urls.isEmpty else { throw ExportError.nothingToExport }
            return urls
        } catch ExportError.cancelled {
            app.show("Export cancelled")
        } catch {
            app.show("Export failed: \(String(describing: error))", kind: .error)
            app.exportReporter?.exportFailed(id: id, title: baseScene.name, message: String(describing: error))
        }
        return nil
    }

    /// The open scene (with only the selection, when asked), then every other scene as last saved.
    private func exportDocuments(_ job: ExportJob) throws -> [Document] {
        var open = session.document
        if job.onlySelection, !selection.isEmpty {
            open.scene = ExportPrep.only(selection, in: open.scene)
        }
        guard job.everyScene, job.preset.kind != .model, job.preset.kind != .captions else { return [open] }
        let others = sceneList.map(\.id).filter { $0 != baseScene.id }.compactMap { id in
            try? store.loadScene(id, in: projectURL).scene
        }
        return [open] + others.map { Document(project: document.project, scene: $0) }
    }

    /// The files of one scene: per shot when asked, else the whole range (the sheet's for the open scene).
    private func exportFiles(_ job: ExportJob, document: Document, isOpen: Bool, id: String,
                             progress: @escaping (Double) -> Void) async throws -> [URL] {
        switch job.preset.kind {
        case .video, .gif, .frames, .passes:
            let ranges = ranges(for: job, in: document, isOpen: isOpen)
            var urls: [URL] = []
            for (index, range) in ranges.enumerated() {
                var settings = job.settings
                settings.range = range
                let name = exportName(document, settings, shot: ranges.count > 1 ? index + 1 : nil)
                let step: (Double) -> Void = { progress((Double(index) + $0) / Double(ranges.count)) }
                try await urls.append(exportMoving(job.preset.kind, settings: settings, document: document, name: name, id: id, progress: step))
            }
            return urls
        case .still, .stillPasses:
            return try await [exportPicture(job, document: document, at: isOpen ? time : min(time, document.scene.timeline.duration),
                                            progress: progress)]
        case .model, .lookShader:
            return try exportThreeD(job, document: document, progress: progress)
        case .paper:
            return try await [exportPaper(job, document: document, isOpen: isOpen, progress: progress)]
        case .captions:
            guard let url = exportSubtitles() else { throw ExportError.nothingToExport }
            progress(1)
            return [url]
        }
    }

    /// The stretches to export: each shot between camera cuts, or the sheet's range (the whole timeline for other scenes).
    func ranges(for job: ExportJob, in document: Document, isOpen: Bool) -> [TimeRange] {
        let timeline = document.scene.timeline
        let whole = isOpen ? job.settings.range : TimeRange(start: 0, end: timeline.duration)
        guard job.everyShot else { return [whole] }
        let starts = Array(Set(timeline.cuts.map(\.time).filter { $0 > whole.start + 1e-3 && $0 < whole.end - 1e-3 } + [whole.start])).sorted()
        return starts.enumerated().map { index, start in TimeRange(start: start, end: index + 1 < starts.count ? starts[index + 1] : whole.end) }
    }

    private func exportMoving(_ kind: ExportKind, settings: ExportSettings, document: Document, name: String, id: String,
                              progress: @escaping (Double) -> Void) async throws -> URL {
        let session = try makeExportSession(document, final: settings.final)
        session.onWaiting = { [weak self] waiting in
            self?.exportWaiting = waiting
            self?.app.exportReporter?.exportProgressed(id: id, fraction: self?.exportProgress ?? 0, waiting: waiting)
        }
        let base = rendersFolder.appendingPathComponent(name)
        switch kind {
        case .gif:
            return try await session.gif(settings, to: base.appendingPathExtension("gif"), progress: progress)
        case .frames:
            return try await session.pngSequence(settings, audio: mixdown(settings.range, of: document.scene.timeline),
                                                 to: rendersFolder.appendingPathComponent(name + " frames"), progress: progress)
        case .passes:
            return try await session.passes(settings, to: rendersFolder.appendingPathComponent(name + " passes"), progress: progress)
        default:
            let url = base.appendingPathExtension(settings.codec.fileExtension)
            try? FileManager.default.removeItem(at: url)
            return try await session.video(settings, audio: mixdown(settings.range, of: document.scene.timeline), to: url, progress: progress)
        }
    }

    /// A picture of the frame at `time` (PNG), or its passes.
    private func exportPicture(_ job: ExportJob, document: Document, at time: Double, progress: @escaping (Double) -> Void) async throws -> URL {
        let session = try makeExportSession(document, final: job.settings.final)
        var settings = job.settings
        settings.range = TimeRange(start: time, end: time + 1 / Double(max(settings.fps, 1)))
        let name = exportName(document, settings, shot: nil)
        if job.preset.kind == .stillPasses {
            return try await session.passes(settings, to: rendersFolder.appendingPathComponent(name + " passes"), progress: progress)
        }
        let image = try await session.image(at: time, framing: settings.framing, longSide: settings.longSide, transparent: settings.transparent)
        let url = rendersFolder.appendingPathComponent(name).appendingPathExtension("png")
        guard let png = UIImage(cgImage: image).pngData() else { throw ExportError.nothingToExport }
        try png.write(to: url, options: .atomic)
        progress(1)
        return url
    }

    func makeExportSession(_ document: Document? = nil, final: Bool = false) throws -> ExportSession {
        let exporter = try ExportSession(document: document ?? session.document, catalog: library.catalog, device: RenderDevice.sharedDevice(),
                                         models: library.models, final: final)
        let assets = assetsFolder
        exporter.mediaURL = { file in
            let url = assets.appendingPathComponent(file)
            return FileManager.default.fileExists(atPath: url.path) ? url : nil
        }
        exporter.stillImage = { name in UIImage(contentsOfFile: assets.appendingPathComponent(name).path)?.cgImage }
        exporter.paintFile = paintFiles
        // A finished run for this scene is reused; otherwise the export makes the same one before its first frame.
        if document == nil || document?.scene.id == baseScene.id { exporter.builder.physics = physicsRun.frames }
        let gpuInBackground = BackgroundExport.backgroundGPU
        exporter.canRender = { gpuInBackground || UIApplication.shared.applicationState != .background }
        return exporter
    }

    /// "Tower 16x9 2026-10-18 14.02.11", with the scene's name and the shot's number when there are several.
    func exportName(_ document: Document, _ settings: ExportSettings, shot: Int?) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        let shape = settings.framing.rawValue.replacingOccurrences(of: ":", with: "x")
        let name = document.project.sceneNames[document.scene.id] ?? document.scene.name
        return "\(ProjectStore.sanitize(name))\(shot.map { " shot \($0)" } ?? "") \(shape) \(formatter.string(from: Date()))"
    }

    /// The soundtrack mixed exactly as the preview plays it (same gains, fades and envelopes).
    func mixdown(_ range: TimeRange, of timeline: Timeline? = nil) async -> [Float]? {
        let clips = (timeline ?? self.timeline).audio
        guard !clips.isEmpty else { return nil }
        let folder = audioFolder
        return await Task.detached(priority: .userInitiated) {
            var sources: [String: PCMAudio] = [:]
            for file in Set(clips.map(\.file)) {
                sources[file] = try? AudioDecoder.decode(folder.appendingPathComponent(file))
            }
            return AudioMixer.mix(clips, sources: sources, range: range, sampleRate: AudioDecoder.sampleRate)
        }.value
    }

    /// A PNG of the shot at the playhead (or `time`), through the shot camera like the export (the bridge's snapshot).
    func snapshotPNG(framing: Framing, longSide: Int, at time: Double? = nil) async -> Data? {
        if let time { setTime(time) }
        guard let exporter = try? makeExportSession(),
              let image = try? await exporter.image(at: self.time, framing: framing, longSide: longSide) else { return nil }
        return UIImage(cgImage: image).pngData()
    }

    func cancelExport() {
        exportTask?.cancel()
    }

    func saveToPhotos(_ urls: [URL]) {
        let media = urls.filter { ["mp4", "mov", "png", "gif"].contains($0.pathExtension.lowercased()) }
        guard !media.isEmpty else { return }
        Task {
            let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            guard status == .authorized || status == .limited else {
                app.show("Allow \(AppIdentity.displayName) to add to Photos in Settings", kind: .error)
                return
            }
            do {
                try await PHPhotoLibrary.shared().performChanges {
                    for url in media {
                        let isVideo = ["mp4", "mov"].contains(url.pathExtension.lowercased())
                        PHAssetCreationRequest.forAsset().addResource(with: isVideo ? .video : .photo, fileURL: url, options: nil)
                    }
                }
                app.show("Saved to Photos", kind: .success)
            } catch {
                app.show("Couldn't save to Photos: \(error.localizedDescription)", kind: .error)
            }
        }
    }
}
