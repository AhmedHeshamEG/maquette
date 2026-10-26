import Foundation
import LoweyCore
import LoweyEngine
import UIKit

/// 3D files, the Look as a shader and Paper (A1). Motion the timeline's keys don't hold (behaviours, holds, looks,
/// physics) is baked into keys for the formats that carry animation.
extension EditorModel {
    /// Whether the export holds a rigged solid FBX can carry (FBX is offered only then).
    var canExportFBX: Bool {
        let ids = selection.isEmpty ? baseScene.roots : selection
        return ids.flatMap { baseScene.subtree(of: $0) }.contains { id in
            guard let object = baseScene.objects[id], let rig = object.rig else { return false }
            return rig.skin != nil && object.paint == nil
        }
    }

    /// Whether anything in the scene is painted (Maps is offered only then).
    var hasPaintedThings: Bool {
        baseScene.objects.values.contains { $0.paint != nil }
    }

    func exportThreeD(_ job: ExportJob, document: Document, progress: (Double) -> Void) throws -> [URL] {
        let files: [(name: String, data: Data)] = if let engine = job.preset.shaderEngine {
            [LookShaderExport.archive(document.lookPreset, engine: engine)]
        } else if let format = job.preset.format.modelFormat {
            modelFiles(format, preset: job.preset.model ?? .apps, selectionOnly: job.onlySelection, colors: job.paintColors)
        } else {
            []
        }
        guard !files.isEmpty else { throw ExportError.nothingToExport }
        let urls = try files.map { file in
            let url = rendersFolder.appendingPathComponent(file.name)
            try file.data.write(to: url, options: .atomic)
            return url
        }
        progress(1)
        return urls
    }

    /// The scene (or the selection) as a 3D file, with its preset applied: glTF, a three.js folder, USDZ, OBJ (with its
    /// materials), STL, 3MF, a Blender package, every painted map, or one rigged thing as FBX.
    func modelFiles(_ format: ModelExportFormat, preset: ModelPreset, selectionOnly: Bool, colors: PaintColorOutput) -> [(name: String, data: Data)] {
        let ids = selectionOnly && !selection.isEmpty ? selection : nil
        let name = ProjectStore.sanitize(ids.flatMap { $0.count == 1 ? displayed.scene.objects[$0[0]]?.name : nil } ?? baseScene.name)
        // The scene as edited for the timeline's keys (glTF, Blender, FBX); as shown for the rest.
        let edited = format == .glb || format == .web || format == .blender || format == .fbx
        if edited, let frames = physicsRun.frames, !frames.isComplete {
            app.show("The physics run is still being worked out; export again in a moment")
            return []
        }
        var source = displayed.scene
        if edited {
            let physical = physicsRun.frames.map { PhysicsKeep.baked($0, into: session.document) } ?? session.document
            source = MotionBake.baked(physical, rigs: rigs()).scene
        }
        let files = ModelExport.files(format, ids: ids, scene: preset.prepared(source), look: look, preset: lookPreset, catalog: library.catalog,
                                      models: library.models, name: name, paintFile: paintFiles, poses: edited ? [:] : displayed.poses,
                                      colors: preset == .web ? .vertexColors : colors, engine: preset.engine)
        if files.isEmpty { app.show("Nothing to export") }
        return files
    }

    /// Paper: the frame at the playhead on a page, or frames across the shot on one sheet, as a PDF.
    func exportPaper(_ job: ExportJob, document: Document, isOpen: Bool, progress: @escaping (Double) -> Void) async throws -> URL {
        guard let paper = job.preset.paper else { throw ExportError.nothingToExport }
        let session = try makeExportSession(document, final: job.settings.final)
        let timeline = document.scene.timeline
        let range = isOpen ? job.settings.range : TimeRange(start: 0, end: timeline.duration)
        let title = document.project.sceneNames[document.scene.id] ?? document.scene.name
        let moments = paper.frames ? PaperLayout.moments(9, across: range) : [isOpen ? time : 0]
        var pictures: [(picture: PDFWriter.Picture, time: Double)] = []
        for (index, moment) in moments.enumerated() {
            try Task.checkCancellation()
            let image = try await session.image(at: moment, framing: job.settings.framing, longSide: paper.frames ? 1200 : 3000)
            guard let jpeg = UIImage(cgImage: image).jpegData(compressionQuality: 0.88) else { throw ExportError.nothingToExport }
            pictures.append((PDFWriter.Picture(jpeg: jpeg, width: image.width, height: image.height), moment))
            progress(Double(index + 1) / Double(moments.count))
        }
        let data = if paper.frames, !pictures.isEmpty {
            PaperLayout.frames(pictures, paper: paper.size, title: title)
        } else if let first = pictures.first {
            PaperLayout.frame(first.picture, paper: paper.size, title: title, caption: "At " + PaperLayout.timecode(first.time))
        } else {
            Data()
        }
        let url = rendersFolder.appendingPathComponent(exportName(document, job.settings, shot: nil)).appendingPathExtension("pdf")
        try data.write(to: url, options: .atomic)
        return url
    }
}
