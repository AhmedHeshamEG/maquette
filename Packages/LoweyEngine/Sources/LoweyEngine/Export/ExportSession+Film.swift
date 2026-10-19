import CoreGraphics
import Foundation
import HmmMedia
import LoweyCore
import Metal
import simd

/// F1's exports: the animatic, spatial video and photos for Vision Pro, 360° video and panoramas, and wide-colour stills.
/// Every one draws through the same renderer and `ShotBuilder` as the stage and the other exports.
public extension ExportSession {
    /// Each shot held on its key moment for as long as it lasts, with the whole soundtrack.
    func animatic(_ settings: ExportSettings, audio: [Float]?, to url: URL, progress: @escaping (Double) -> Void) async throws -> URL {
        let shots = builder.timeline.shots(in: settings.range)
        return try await video(settings, audio: audio, to: url, shown: { time in
            shots.last { $0.start <= time + 1e-9 }?.keyMoment ?? time
        }, progress: progress)
    }

    // MARK: Stereo

    /// The two eyes of a request: parallel cameras a person's width apart (times `depth`), no transition between shots.
    internal func eyes(_ request: FrameRequest, depth: Double) -> (left: FrameRequest, right: FrameRequest) {
        let camera = CoreTransform(position: Vec3(request.camera.position), rotation: Quat(request.camera.orientation))
        let (leftEye, rightEye) = StereoRig.eyes(camera, baseline: StereoRig.humanBaseline * min(max(depth, 0.3), 3))
        var left = request
        left.camera.position = leftEye.position.float3
        left.transition = nil
        var right = left
        right.camera.position = rightEye.position.float3
        return (left, right)
    }

    /// Each eye's horizontal field of view (degrees) for the settings' frame.
    internal func horizontalFieldOfView(_ request: FrameRequest, settings: ExportSettings) -> Double {
        let size = settings.size
        let aspect = Double(size.width) / Double(max(size.height, 1))
        return 2 * atan(tan(Double(request.camera.fieldOfView) * .pi / 360) * aspect) * 180 / .pi
    }

    /// Spatial video (MV-HEVC): both eyes every frame, the sound once. Verified like every video.
    func spatialVideo(_ settings: ExportSettings, audio: [Float]?, to url: URL, progress: @escaping (Double) -> Void) async throws -> URL {
        await loadModels()
        let size = settings.size
        var encode = settings.encodeSettings
        encode.codec = .hevc
        let first = try await frameRequest(at: settings.range.start, settings: settings)
        let stereo = SpatialVideoEncoder.Stereo(baseline: StereoRig.humanBaseline * settings.stereoDepth,
                                                horizontalFieldOfView: horizontalFieldOfView(first, settings: settings))
        let encoder = try SpatialVideoEncoder(url: url, settings: encode, stereo: stereo, audio: audio)
        do {
            for frame in 0 ..< settings.frameCount {
                try Task.checkCancellation()
                try await waitUntilRenderable()
                let time = settings.range.start + Double(frame) / Double(settings.fps)
                let (left, right) = try await eyes(frameRequest(at: time, settings: settings), depth: settings.stereoDepth)
                let leftBuffer = try encoder.makePixelBuffer()
                let rightBuffer = try encoder.makePixelBuffer()
                _ = try await frames.render(left, into: leftBuffer)
                _ = try await frames.render(right, into: rightBuffer)
                try await encoder.append(left: leftBuffer, right: rightBuffer, frame: frame)
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
        try await verifyVideo(url, settings: settings, size: size, audio: audio)
        return url
    }

    /// A spatial photo (HEIC stereo pair) of the moment.
    func spatialPhoto(at time: Double, settings: ExportSettings) async throws -> Data {
        await loadModels()
        let size = settings.size
        let request = try await frameRequest(at: time, settings: settings)
        let (left, right) = eyes(request, depth: settings.stereoDepth)
        let leftImage = try await frames.image(left, width: size.width, height: size.height)
        let rightImage = try await frames.image(right, width: size.width, height: size.height)
        return try ImageWriters.spatialPhoto(left: leftImage, right: rightImage, baseline: StereoRig.humanBaseline * settings.stereoDepth,
                                             horizontalFieldOfView: horizontalFieldOfView(request, settings: settings))
    }

    // MARK: 360°

    /// The six views around the shot camera at `time`, laid flat into `output` (2:1). Titles and flipbooks stay out: they
    /// belong to a flat frame, not to the world around you.
    internal func panoramaFrame(at time: Double, into output: MTLTexture) async throws {
        let face = max(output.width / 4 - (output.width / 4) % 2, 16)
        let size = CGSize(width: face, height: face)
        await prepareMedia(at: time, size: size, framing: .square)
        let base = builder.request(at: time, framing: .square, size: size, frameIndex: builder.timeline.frame(for: time), transparent: false)
        let heading = Panorama.heading(of: CoreTransform(position: Vec3(base.camera.position), rotation: Quat(base.camera.orientation)))
        let device = frames.device
        let faces = try device.makeTexture(RenderDevice.outputFormat, width: face, height: face, usage: [.shaderRead], label: "360 faces",
                                           arrayLength: 6)
        for side in Panorama.Face.allCases {
            var request = base
            request.camera = RenderCamera(position: base.camera.position, orientation: Panorama.rotation(side, heading: heading).simd,
                                          fieldOfView: 90, near: base.camera.near, far: base.camera.far)
            request.lens = nil
            request.transition = nil
            request.overlay = nil
            request.flipbooks = []
            request.guides = nil
            let view = try frames.outputTexture(width: face, height: face)
            _ = try await frames.run(request, into: view)
            try await copy(view, into: faces, slice: side.rawValue)
        }
        guard let commandBuffer = device.queue.makeCommandBuffer(), let encoder = commandBuffer.makeComputeCommandEncoder() else {
            throw RenderError.noMetal
        }
        encoder.setComputePipelineState(device.pipelines.equirect)
        encoder.setTexture(faces, index: 0)
        encoder.setTexture(output, index: 1)
        encoder.dispatchThreadgroups(MTLSize(width: (output.width + 7) / 8, height: (output.height + 7) / 8, depth: 1),
                                     threadsPerThreadgroup: MTLSize(width: 8, height: 8, depth: 1))
        encoder.endEncoding()
        try await finish(commandBuffer)
    }

    private func copy(_ view: MTLTexture, into faces: MTLTexture, slice: Int) async throws {
        guard let commandBuffer = frames.device.queue.makeCommandBuffer(), let blit = commandBuffer.makeBlitCommandEncoder() else {
            throw RenderError.noMetal
        }
        blit.copy(from: view, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                  sourceSize: MTLSize(width: view.width, height: view.height, depth: 1), to: faces, destinationSlice: slice, destinationLevel: 0,
                  destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0))
        blit.endEncoding()
        try await finish(commandBuffer)
    }

    private func finish(_ commandBuffer: MTLCommandBuffer) async throws {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            commandBuffer.addCompletedHandler { _ in continuation.resume() }
            commandBuffer.commit()
        }
        if let error = commandBuffer.error { throw error }
    }

    /// A 360° panorama of the moment (JPEG with Photo Sphere tags).
    func panorama(at time: Double, settings: ExportSettings) async throws -> Data {
        try await ImageWriters.panorama(panoramaImage(at: time, settings: settings))
    }

    /// The flat 360° picture of the moment.
    func panoramaImage(at time: Double, settings: ExportSettings) async throws -> CGImage {
        await loadModels()
        let size = settings.size
        let output = try frames.device.makeTexture(RenderDevice.outputFormat, width: size.width, height: size.height,
                                                   usage: [.shaderWrite, .shaderRead], storage: .shared, label: "360 still")
        try await panoramaFrame(at: time, into: output)
        var bytes = [UInt8](repeating: 0, count: size.width * size.height * 4)
        output.getBytes(&bytes, bytesPerRow: size.width * 4, from: MTLRegionMake2D(0, 0, size.width, size.height), mipmapLevel: 0)
        return try FrameRenderer.image(bgra: bytes, width: size.width, height: size.height, transparent: false)
    }

    /// 360° video, marked for YouTube and headsets (the Spherical Video box), verified like every video.
    func panoramaVideo(_ settings: ExportSettings, audio: [Float]?, to url: URL, progress: @escaping (Double) -> Void) async throws -> URL {
        await loadModels()
        let size = settings.size
        let encoder = try VideoEncoder(url: url, settings: settings.encodeSettings, audio: audio)
        do {
            for frame in 0 ..< settings.frameCount {
                try Task.checkCancellation()
                try await waitUntilRenderable()
                let buffer = try encoder.makePixelBuffer()
                try await panoramaFrame(at: settings.range.start + Double(frame) / Double(settings.fps), into: frames.texture(for: buffer))
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
        try SphericalVideo.injectFile(url)
        try await verifyVideo(url, settings: settings, size: size, audio: audio)
        return url
    }

    private func verifyVideo(_ url: URL, settings: ExportSettings, size: (width: Int, height: Int), audio: [Float]?) async throws {
        let expected = ExportExpectation(duration: Double(settings.frameCount) / Double(settings.fps), frameCount: settings.frameCount,
                                         width: size.width, height: size.height, audio: !(audio ?? []).isEmpty)
        let problems = try await MediaInspector.verify(url, expected: expected)
        guard problems.isEmpty else { throw ExportError.verification(problems) }
    }

    // MARK: Wide colour

    /// The moment in Display P3, 16 bits a channel.
    func wideImage(at time: Double, settings: ExportSettings) async throws -> CGImage {
        await loadModels()
        let size = settings.size
        return try await frames.wideImage(frameRequest(at: time, settings: settings), width: size.width, height: size.height)
    }

    /// The moment as a 16-bit Display P3 PNG.
    func widePNG(at time: Double, settings: ExportSettings) async throws -> Data {
        try await ImageWriters.png(wideImage(at: time, settings: settings))
    }
}
