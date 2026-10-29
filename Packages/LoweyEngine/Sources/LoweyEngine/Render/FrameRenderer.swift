import CoreGraphics
import CoreVideo
import Foundation
import Metal

/// Renders frames away from the screen: snapshots, library thumbnails, tests, and every exported frame (straight
/// into the encoder's IOSurface-backed pixel buffers, no copy). The stage and this share `LoweyRenderer`, so the
/// preview is the export.
@MainActor
public final class FrameRenderer {
    public let device: RenderDevice
    public let renderer: LoweyRenderer
    private var textureCache: CVMetalTextureCache?
    private var output: MTLTexture?
    /// The shared output is being drawn into and not read back yet.
    private var outputInUse = false

    /// `quality` is `.full` for everything that leaves the app; the tier tests render a lighter preview with it.
    public init(device: RenderDevice, models: ModelLibrary = .shared, quality: PreviewQuality = .full) throws {
        self.device = device
        renderer = try LoweyRenderer(device: device, models: models, quality: quality)
        CVMetalTextureCacheCreate(nil, nil, device.device, nil, &textureCache)
    }

    /// A readable output texture of `width` × `height`.
    func outputTexture(width: Int, height: Int) throws -> MTLTexture {
        if let output, output.width == width, output.height == height { return output }
        let texture = try device.makeTexture(RenderDevice.outputFormat, width: width, height: height,
                                             usage: [.shaderWrite, .shaderRead, .renderTarget], storage: .shared, label: "offscreen output")
        output = texture
        return texture
    }

    /// Encodes, commits and waits (without blocking the main thread).
    func run(_ request: FrameRequest, into texture: MTLTexture) async throws -> FrameReport {
        guard let commandBuffer = device.queue.makeCommandBuffer() else { throw RenderError.noMetal }
        commandBuffer.label = "Offscreen frame"
        let report = try renderer.encode(request, to: texture, commandBuffer: commandBuffer)
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            commandBuffer.addCompletedHandler { _ in continuation.resume() }
            commandBuffer.commit()
        }
        if let error = commandBuffer.error { throw error }
        return report
    }

    /// BGRA bytes of a frame, top row first.
    public func bytes(_ request: FrameRequest, width: Int, height: Int) async throws -> [UInt8] {
        // A frame asked for while another is still in flight (the Library's tiles coming on screen together) gets a
        // texture of its own: sharing one, each was read back after the next had drawn over it.
        let shared = !outputInUse
        let texture = shared ? try outputTexture(width: width, height: height)
            : try device.makeTexture(RenderDevice.outputFormat, width: width, height: height,
                                     usage: [.shaderWrite, .shaderRead, .renderTarget], storage: .shared, label: "offscreen output")
        if shared { outputInUse = true }
        defer { if shared { outputInUse = false } }
        _ = try await run(request, into: texture)
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        texture.getBytes(&bytes, bytesPerRow: width * 4, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        return bytes
    }

    /// Renders a frame without reading it back (benchmarks).
    @discardableResult
    public func render(_ request: FrameRequest, width: Int, height: Int) async throws -> FrameReport {
        try await run(request, into: outputTexture(width: width, height: height))
    }

    public func image(_ request: FrameRequest, width: Int, height: Int) async throws -> CGImage {
        let bytes = try await bytes(request, width: width, height: height)
        return try Self.image(bgra: bytes, width: width, height: height, transparent: request.transparent)
    }

    /// Renders straight into a pixel buffer (the encoder's, for export).
    public func render(_ request: FrameRequest, into buffer: CVPixelBuffer) async throws -> FrameReport {
        let texture = try texture(for: buffer)
        return try await run(request, into: texture)
    }

    /// A Metal texture over a pixel buffer's IOSurface.
    public func texture(for buffer: CVPixelBuffer) throws -> MTLTexture {
        guard let textureCache else { throw RenderError.texture }
        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        var cvTexture: CVMetalTexture?
        let usage: MTLTextureUsage = [.shaderRead, .shaderWrite, .renderTarget]
        let attributes = [kCVMetalTextureUsage as String: usage.rawValue] as CFDictionary
        // An HDR encoder's buffers are half floats; every other one is BGRA.
        let format: MTLPixelFormat = CVPixelBufferGetPixelFormatType(buffer) == kCVPixelFormatType_64RGBAHalf ? .rgba16Float : RenderDevice.outputFormat
        CVMetalTextureCacheCreateTextureFromImage(nil, textureCache, buffer, attributes, format, width, height, 0, &cvTexture)
        guard let cvTexture, let texture = CVMetalTextureGetTexture(cvTexture) else { throw RenderError.texture }
        return texture
    }

    /// A frame in Display P3 with 16 bits a channel (F1's wide-colour stills): drawn into half floats, read back, tagged.
    public func wideImage(_ request: FrameRequest, width: Int, height: Int) async throws -> CGImage {
        var wide = request
        wide.encoding = .displayP3
        let texture = try device.makeTexture(.rgba16Float, width: width, height: height, usage: [.shaderWrite, .shaderRead], storage: .shared,
                                             label: "wide colour output")
        _ = try await run(wide, into: texture)
        var halves = [Float16](repeating: 0, count: width * height * 4)
        texture.getBytes(&halves, bytesPerRow: width * 8, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        let words = halves.map { UInt16((min(max(Float($0), 0), 1) * 65535).rounded()) }
        let alpha: CGImageAlphaInfo = request.transparent ? .premultipliedLast : .noneSkipLast
        guard let provider = CGDataProvider(data: words.withUnsafeBufferPointer { Data(buffer: $0) } as CFData),
              let space = CGColorSpace(name: CGColorSpace.displayP3),
              let image = CGImage(width: width, height: height, bitsPerComponent: 16, bitsPerPixel: 64, bytesPerRow: width * 8, space: space,
                                  bitmapInfo: CGBitmapInfo(rawValue: CGBitmapInfo.byteOrder16Little.rawValue | alpha.rawValue),
                                  provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
        else { throw RenderError.readback }
        return image
    }

    public static func image(bgra bytes: [UInt8], width: Int, height: Int, transparent: Bool) throws -> CGImage {
        let alpha: CGImageAlphaInfo = transparent ? .premultipliedFirst : .noneSkipFirst
        guard let provider = CGDataProvider(data: Data(bytes) as CFData),
              let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGBitmapInfo(rawValue: CGBitmapInfo.byteOrder32Little.rawValue | alpha.rawValue),
                                  provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
        else { throw RenderError.readback }
        return image
    }
}
