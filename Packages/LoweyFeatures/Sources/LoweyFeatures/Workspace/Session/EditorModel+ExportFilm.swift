import Foundation
import LoweyCore
import LoweyEngine
import UIKit

/// F1's exports from the sheet: the animatic, spatial and 360° video (one file per shot when asked), spatial photos and
/// panoramas of the playhead, and the storyboard.
extension EditorModel {
    func exportFilmMoving(_ job: ExportJob, document: Document, isOpen: Bool, id: String,
                          progress: @escaping (Double) -> Void) async throws -> [URL] {
        let ranges = ranges(for: job, in: document, isOpen: isOpen)
        var urls: [URL] = []
        for (index, range) in ranges.enumerated() {
            var settings = job.settings
            settings.range = range
            let session = try makeExportSession(document, final: false)
            session.onWaiting = { [weak self] waiting in
                self?.exportWaiting = waiting
                self?.app.exportReporter?.exportProgressed(id: id, fraction: self?.exportProgress ?? 0, waiting: waiting)
            }
            let step: (Double) -> Void = { progress((Double(index) + $0) / Double(ranges.count)) }
            let base = rendersFolder.appendingPathComponent(exportName(document, settings, shot: ranges.count > 1 ? index + 1 : nil))
            let audio = await mixdown(range, of: document.scene.timeline)
            switch job.preset.kind {
            case .spatialVideo:
                try await urls.append(session.spatialVideo(settings, audio: audio, to: base.appendingPathExtension("mov"), progress: step))
            case .video360:
                try await urls.append(session.panoramaVideo(settings, audio: audio, to: base.appendingPathExtension(settings.codec.fileExtension),
                                                            progress: step))
            default:
                try await urls.append(session.animatic(settings, audio: audio, to: base.appendingPathExtension(settings.codec.fileExtension),
                                                       progress: step))
            }
        }
        return urls
    }

    func exportFilmPicture(_ job: ExportJob, document: Document, at time: Double, progress: @escaping (Double) -> Void) async throws -> URL {
        let session = try makeExportSession(document, final: false)
        var settings = job.settings
        settings.range = TimeRange(start: time, end: time + 1 / Double(max(settings.fps, 1)))
        let name = exportName(document, settings, shot: nil)
        let url: URL
        if job.preset.kind == .spatialPhoto {
            url = rendersFolder.appendingPathComponent(name).appendingPathExtension("heic")
            try await session.spatialPhoto(at: time, settings: settings).write(to: url, options: .atomic)
        } else {
            url = rendersFolder.appendingPathComponent(name + " 360").appendingPathExtension("jpg")
            try await session.panorama(at: time, settings: settings).write(to: url, options: .atomic)
        }
        progress(1)
        return url
    }

    /// Every shot's key frame on landscape sheets, with its camera, lens, length and the words said over it.
    func exportStoryboard(_ job: ExportJob, document: Document, isOpen: Bool, progress: @escaping (Double) -> Void) async throws -> URL {
        guard let paper = job.preset.paper else { throw ExportError.nothingToExport }
        let session = try makeExportSession(document, final: job.settings.final)
        let timeline = document.scene.timeline
        let range = isOpen ? job.settings.range : TimeRange(start: 0, end: timeline.duration)
        let panels = Storyboard.panels(document, range: range)
        var pictures: [PDFWriter.Picture] = []
        for (index, panel) in panels.enumerated() {
            try Task.checkCancellation()
            let image = try await session.image(at: panel.shot.keyMoment, framing: timeline.frameShape, longSide: 960)
            guard let jpeg = UIImage(cgImage: image).jpegData(compressionQuality: 0.85) else { throw ExportError.nothingToExport }
            pictures.append(PDFWriter.Picture(jpeg: jpeg, width: image.width, height: image.height))
            progress(Double(index + 1) / Double(max(panels.count, 1)))
        }
        let title = document.project.sceneNames[document.scene.id] ?? document.scene.name
        let data = Storyboard.pdf(panels, pictures: pictures, paper: paper.size, title: title)
        let url = rendersFolder.appendingPathComponent(exportName(document, job.settings, shot: nil) + " storyboard").appendingPathExtension("pdf")
        try data.write(to: url, options: .atomic)
        return url
    }
}
