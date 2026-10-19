import CoreGraphics
import Foundation
import HmmMedia
import LoweyCore
import os

public enum ExportError: Error, Equatable, CustomStringConvertible {
    case cancelled
    case nothingToExport
    case gpuStopped
    case verification([String])

    public var description: String {
        switch self {
        case .cancelled: "Export cancelled."
        case .nothingToExport: "There's nothing to export."
        case .gpuStopped: "The renderer stopped responding. Keep Maquette in front while it exports."
        case let .verification(problems): "The exported file isn't right: " + problems.joined(separator: " ")
        }
    }
}

/// Renders a document frame by frame at a fixed timestep (never real time) into video, GIF, PNG stills, a PNG
/// sequence or render passes. Same renderer, same `ShotBuilder` as the stage: the preview is the export. Every video
/// is verified (duration, frame count, sound, size) before it counts as done. A Final session (A1) draws with the best
/// shadows and the finest water, and each frame with motion blur and anti-aliasing (`FinalFrames`).
@MainActor
public final class ExportSession {
    public let builder: ShotBuilder
    let frames: FrameRenderer
    /// Final: motion blur, supersampling, the best shadows and the finest water.
    public let final: Bool
    private let videoFrames = VideoFrames(exact: true)
    private let logger = Logger(subsystem: "studio.h.maquette", category: "export")
    /// Where a project media file lives (videos on cards and overlays, Manim renders).
    public var mediaURL: (String) -> URL? = { _ in nil }
    /// Stills in the project's assets.
    public var stillImage: (String) -> CGImage? = { _ in nil }
    /// Painted objects' files in the project's assets.
    public var paintFile: @Sendable (String) -> Data? {
        get { builder.paintFile }
        set { builder.paintFile = newValue }
    }

    /// Whether the GPU may be used now (iOS suspends GPU work in the background: the export waits instead).
    public var canRender: () -> Bool = { true }
    public var onWaiting: (Bool) -> Void = { _ in }

    public init(document: Document, catalog: AssetCatalog, device: RenderDevice, models: ModelLibrary = .shared, final: Bool = false) throws {
        builder = ShotBuilder(document: document, catalog: catalog, models: models)
        frames = try FrameRenderer(device: device, models: models, quality: final ? .final : .full)
        self.final = final
    }

    /// Loads every model the document uses (exports never show placeholders), then the whole physics run.
    public func loadModels() async {
        for object in builder.document.scene.objects.values {
            guard let id = object.kind.assetID, let asset = builder.catalog.manifest.asset(id) else { continue }
            _ = await builder.models.load(asset, catalog: builder.catalog)
        }
        await builder.models.waitUntilLoaded()
        await preparePhysics(reusing: builder.physics, detail: final ? 2 : 1)
    }

    /// Loads the exact pictures and video frames shown at `time` (never "the nearest one").
    func prepareMedia(at time: Double, size: CGSize, framing: Framing) async {
        var images: [String: CGImage] = [:]
        let scene = builder.document.scene
        var keys: [String] = scene.objects.values.compactMap { object in
            guard case let .card(recipe) = object.kind else { return nil }
            return recipe.frameKey(at: time)
        }
        let placements = OverlayLayout.placements(in: builder.evaluate(at: time).scene, palette: builder.document.palette,
                                                  width: Double(size.width), height: Double(size.height), time: time)
        keys += placements.compactMap(\.recipe.image)
        for key in Set(keys) {
            if let (file, _) = VideoFrameKey.parse(key) {
                if let url = mediaURL(file), let image = await videoFrames.frame(key, url: url) { images[key] = image }
            } else if let image = stillImage(key) {
                images[key] = image
            }
        }
        let stills = stillImage
        builder.mediaImage = { images[$0] ?? stills($0) }
    }

    /// One frame as an image (snapshots, stills, tests).
    public func image(at time: Double, framing: Framing, longSide: Int, transparent: Bool = false) async throws -> CGImage {
        await loadModels()
        var settings = ExportSettings(framing: framing, longSide: longSide, fps: builder.timeline.fps, codec: .h264,
                                      range: TimeRange(start: time, end: time), transparent: transparent)
        settings.final = final
        return try await frameImage(at: time, settings: settings)
    }

    /// A video: H.264 / HEVC .mp4, or HEVC with alpha / ProRes 4444 / HDR .mov. Verified before it returns. `shown` picks
    /// the moment drawn for each frame's time (an animatic holds each shot's key moment; the sound runs on).
    public func video(_ settings: ExportSettings, audio: [Float]?, to url: URL, shown: ((Double) -> Double)? = nil,
                      progress: @escaping (Double) -> Void) async throws -> URL {
        await loadModels()
        let size = settings.size
        let encoder = try VideoEncoder(url: url, settings: settings.encodeSettings, audio: audio)
        do {
            for frame in 0 ..< settings.frameCount {
                try Task.checkCancellation()
                try await waitUntilRenderable()
                let clock = settings.range.start + Double(frame) / Double(settings.fps)
                let time = shown?(clock) ?? clock
                let buffer = try encoder.makePixelBuffer()
                // Final averages 8-bit frames, so an HDR file draws each frame once (its highlights are the point).
                if settings.final, settings.encoding != .hdr {
                    try await FinalFrames.copy(frameBytes(at: time, settings: settings), width: size.width, height: size.height, into: buffer)
                } else {
                    var request = try await frameRequest(at: time, settings: settings)
                    request.encoding = settings.encoding
                    _ = try await frames.render(request, into: buffer)
                }
                try await encoder.append(buffer, frame: frame)
                progress(Double(frame + 1) / Double(settings.frameCount))
                await Task.yield()
            }
            try await encoder.finish()
        } catch is CancellationError {
            encoder.cancel()
            throw ExportError.cancelled
        } catch {
            encoder.cancel()
            throw error
        }
        // ProRes 4444 always carries an alpha channel (opaque when the background is drawn).
        let expected = ExportExpectation(duration: Double(settings.frameCount) / Double(settings.fps), frameCount: settings.frameCount,
                                         width: size.width, height: size.height, audio: !(audio ?? []).isEmpty,
                                         alpha: settings.transparent || settings.codec == .prores4444)
        let problems = try await MediaInspector.verify(url, expected: expected)
        guard problems.isEmpty else { throw ExportError.verification(problems) }
        return url
    }

    /// A short looping GIF.
    public func gif(_ settings: ExportSettings, to url: URL, progress: @escaping (Double) -> Void) async throws -> URL {
        await loadModels()
        let writer = try GIFWriter(url: url, frameCount: settings.frameCount, fps: settings.fps)
        for frame in 0 ..< settings.frameCount {
            try Task.checkCancellation()
            try await waitUntilRenderable()
            let time = settings.range.start + Double(frame) / Double(settings.fps)
            try await writer.append(frameImage(at: time, settings: settings))
            progress(Double(frame + 1) / Double(settings.frameCount))
        }
        try writer.finish()
        return url
    }

    /// One PNG per frame in a folder (plus the soundtrack as WAV).
    public func pngSequence(_ settings: ExportSettings, audio: [Float]?, to folder: URL, progress: @escaping (Double) -> Void) async throws -> URL {
        await loadModels()
        try? FileManager.default.removeItem(at: folder)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        if let audio, !audio.isEmpty {
            try WAV.data(audio, channels: 2, sampleRate: 48000).write(to: folder.appendingPathComponent("soundtrack.wav"))
        }
        for frame in 0 ..< settings.frameCount {
            try Task.checkCancellation()
            try await waitUntilRenderable()
            let time = settings.range.start + Double(frame) / Double(settings.fps)
            let image = try await frameImage(at: time, settings: settings)
            try ImageWriters.writePNG(image, to: folder.appendingPathComponent(String(format: "frame_%05d.png", frame + 1)))
            progress(Double(frame + 1) / Double(settings.frameCount))
        }
        return folder
    }

    // MARK: Frames

    /// The frame at `time` as BGRA bytes of the settings' size (top row first): one draw, or Final's moments, each
    /// drawn larger and brought down, averaged.
    func frameBytes(at time: Double, settings: ExportSettings) async throws -> [UInt8] {
        let size = settings.size
        guard settings.final else {
            return try await frames.bytes(frameRequest(at: time, settings: settings), width: size.width, height: size.height)
        }
        let scale = FinalFrames.supersample(longSide: settings.longSide)
        var large = settings
        large.longSide = settings.longSide * scale
        let largeSize = large.size
        var sum = [Float](repeating: 0, count: size.width * size.height * 4)
        let moments = FinalFrames.moments(at: time, fps: settings.fps)
        for moment in moments {
            try Task.checkCancellation()
            let request = try await frameRequest(at: max(moment, 0), settings: large, frameIndex: builder.timeline.frame(for: time))
            let bytes = try await frames.bytes(request, width: largeSize.width, height: largeSize.height)
            FinalFrames.accumulate(FinalFrames.downsampled(bytes, width: largeSize.width, height: largeSize.height, to: size.width, size.height),
                                   into: &sum)
        }
        return FinalFrames.average(sum, count: moments.count)
    }

    func frameImage(at time: Double, settings: ExportSettings) async throws -> CGImage {
        let size = settings.size
        return try await FrameRenderer.image(bgra: frameBytes(at: time, settings: settings), width: size.width, height: size.height,
                                             transparent: settings.transparent)
    }

    /// The request for `time` (`frameIndex` keeps a Final frame's moments on one frame of stepping and boil).
    func frameRequest(at time: Double, settings: ExportSettings, frameIndex: Int? = nil) async throws -> FrameRequest {
        let size = CGSize(width: settings.size.width, height: settings.size.height)
        await prepareMedia(at: time, size: size, framing: settings.framing)
        return builder.request(at: time, framing: settings.framing, size: size, frameIndex: frameIndex ?? builder.timeline.frame(for: time),
                               transparent: settings.transparent)
    }

    /// Holds the export while the app can't use the GPU (it resumes by itself when the app is back in front).
    func waitUntilRenderable() async throws {
        guard !canRender() else { return }
        logger.notice("Export waiting: the app is not in front")
        onWaiting(true)
        defer { onWaiting(false) }
        while !canRender() {
            try await Task.sleep(for: .milliseconds(250))
        }
    }
}
