#if canImport(AVFoundation) && canImport(VideoToolbox)
    import AVFoundation
    import CoreMedia
    import CoreVideo
    import Foundation
    import VideoToolbox

    /// Spatial video for Apple Vision Pro (and the iPhone's Spatial player): MV-HEVC, two views in one track, tagged as
    /// the left and right eye, with the cameras' baseline, field of view and the screen's depth, so the Photos app plays
    /// it in stereo. Frames are rendered straight into the pool's buffers, a pair at a time, with the same sound as a
    /// flat video. Confine an instance to one actor.
    public final class SpatialVideoEncoder {
        /// How the two eyes were filmed.
        public struct Stereo: Hashable, Sendable {
            /// The distance between the eyes in metres (a person's is about 63 mm).
            public var baseline: Double
            /// Each eye's horizontal field of view in degrees.
            public var horizontalFieldOfView: Double
            /// Where the screen sits: −1 (things come out of it) … 1 (everything behind it), 0 = at infinity.
            public var disparityAdjustment: Double

            public init(baseline: Double = 0.063, horizontalFieldOfView: Double, disparityAdjustment: Double = 0.02) {
                self.baseline = baseline
                self.horizontalFieldOfView = horizontalFieldOfView
                self.disparityAdjustment = disparityAdjustment
            }
        }

        public let settings: EncodeSettings
        public let url: URL
        private let writer: AVAssetWriter
        private let input: AVAssetWriterInput
        private let adaptor: AVAssetWriterInputTaggedPixelBufferGroupAdaptor
        private let sound: VideoEncoderSound?

        /// Whether this device encodes MV-HEVC (the iPad's media engine does on M-series and recent A-series chips).
        public static var isSupported: Bool { VTIsStereoMVHEVCEncodeSupported() }

        public init(url: URL, settings: EncodeSettings, stereo: Stereo, audio: [Float]? = nil) throws {
            guard settings.isValid else { throw EncodeError.invalidSettings }
            guard Self.isSupported else { throw EncodeError.writer("this device doesn't encode spatial video") }
            self.settings = settings
            self.url = url
            try? FileManager.default.removeItem(at: url)
            writer = try AVAssetWriter(outputURL: url, fileType: .mov)
            let compression: [CFString: Any] = [
                kVTCompressionPropertyKey_MVHEVCVideoLayerIDs: [0, 1],
                kVTCompressionPropertyKey_MVHEVCViewIDs: [0, 1],
                kVTCompressionPropertyKey_MVHEVCLeftAndRightViewIDs: [0, 1],
                kVTCompressionPropertyKey_HasLeftStereoEyeView: true,
                kVTCompressionPropertyKey_HasRightStereoEyeView: true,
                kVTCompressionPropertyKey_StereoCameraBaseline: UInt32((stereo.baseline * 1_000_000).rounded()),
                kVTCompressionPropertyKey_HorizontalFieldOfView: UInt32((stereo.horizontalFieldOfView * 1000).rounded()),
                kVTCompressionPropertyKey_HorizontalDisparityAdjustment: Int32((min(max(stereo.disparityAdjustment, -1), 1) * 10000).rounded()),
                kVTCompressionPropertyKey_AverageBitRate: settings.bitrate * 2,
                kVTCompressionPropertyKey_ExpectedFrameRate: settings.fps,
                kVTCompressionPropertyKey_MaxKeyFrameInterval: settings.keyframeInterval
            ]
            input = AVAssetWriterInput(mediaType: .video, outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.hevc, AVVideoWidthKey: settings.width, AVVideoHeightKey: settings.height,
                AVVideoCompressionPropertiesKey: compression
            ])
            input.expectsMediaDataInRealTime = false
            adaptor = AVAssetWriterInputTaggedPixelBufferGroupAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: settings.width,
                kCVPixelBufferHeightKey as String: settings.height,
                kCVPixelBufferMetalCompatibilityKey as String: true,
                kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any]()
            ])
            guard writer.canAdd(input) else { throw EncodeError.writer("can't add the spatial video track") }
            writer.add(input)
            sound = try audio.flatMap { $0.isEmpty ? nil : try VideoEncoderSound(writer: writer, audio: $0, sampleRate: settings.audioSampleRate) }
            guard writer.startWriting() else { throw EncodeError.writer(writer.error?.localizedDescription ?? "couldn't start") }
            writer.startSession(atSourceTime: .zero)
        }

        /// A buffer from the encoder's pool to render one eye into.
        public func makePixelBuffer() throws -> CVPixelBuffer {
            guard let pool = adaptor.pixelBufferPool else { throw EncodeError.writer(writer.error?.localizedDescription ?? "no buffer pool") }
            var buffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
            guard let buffer else { throw EncodeError.writer("no pixel buffer") }
            return buffer
        }

        /// Appends frame `frame` (0-based): the two eyes, and the sound up to its end.
        public func append(left: CVPixelBuffer, right: CVPixelBuffer, frame: Int) async throws {
            var waited = 0
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(for: .milliseconds(4))
                waited += 1
                if waited > 5000 { throw EncodeError.stalled }
            }
            let time = CMTime(value: CMTimeValue(frame), timescale: CMTimeScale(settings.fps))
            let eyes = [
                CMTaggedBuffer(tags: [.stereoView(.leftEye), .videoLayerID(0)], pixelBuffer: left),
                CMTaggedBuffer(tags: [.stereoView(.rightEye), .videoLayerID(1)], pixelBuffer: right)
            ]
            guard adaptor.appendTaggedBuffers(eyes, withPresentationTime: time) else {
                throw EncodeError.writer(writer.error?.localizedDescription ?? "couldn't append frame \(frame)")
            }
            try await sound?.append(upTo: Int((Double(frame + 1) / Double(settings.fps) * Double(settings.audioSampleRate)).rounded()))
        }

        public func finish() async throws {
            try await sound?.finish()
            input.markAsFinished()
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                writer.finishWriting { continuation.resume() }
            }
            guard writer.status == .completed else {
                throw EncodeError.writer(writer.error?.localizedDescription ?? "status \(writer.status.rawValue)")
            }
        }

        public func cancel() {
            writer.cancelWriting()
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// An AAC sound track fed from interleaved stereo Float32, as frames go in (shared by the flat and spatial encoders).
    final class VideoEncoderSound {
        private let input: AVAssetWriterInput
        private let format: CMAudioFormatDescription
        private let audio: [Float]
        private let sampleRate: Int
        private var written = 0

        init(writer: AVAssetWriter, audio: [Float], sampleRate: Int) throws {
            input = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: sampleRate, AVNumberOfChannelsKey: 2, AVEncoderBitRateKey: 192_000
            ])
            input.expectsMediaDataInRealTime = false
            guard writer.canAdd(input) else { throw EncodeError.writer("can't add the sound track") }
            writer.add(input)
            var description = AudioStreamBasicDescription(
                mSampleRate: Float64(sampleRate), mFormatID: kAudioFormatLinearPCM,
                mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked, mBytesPerPacket: 8, mFramesPerPacket: 1,
                mBytesPerFrame: 8, mChannelsPerFrame: 2, mBitsPerChannel: 32, mReserved: 0
            )
            var made: CMAudioFormatDescription?
            CMAudioFormatDescriptionCreate(allocator: kCFAllocatorDefault, asbd: &description, layoutSize: 0, layout: nil,
                                           magicCookieSize: 0, magicCookie: nil, extensions: nil, formatDescriptionOut: &made)
            guard let made else { throw EncodeError.writer("no sound format") }
            format = made
            self.audio = audio
            self.sampleRate = sampleRate
        }

        func append(upTo frameLimit: Int) async throws {
            let limit = min(frameLimit, audio.count / 2)
            while written < limit {
                var waited = 0
                while !input.isReadyForMoreMediaData {
                    try await Task.sleep(for: .milliseconds(4))
                    waited += 1
                    if waited > 5000 { throw EncodeError.stalled }
                }
                let count = min(limit - written, 4096)
                let bytes = count * 8
                var block: CMBlockBuffer?
                CMBlockBufferCreateWithMemoryBlock(allocator: kCFAllocatorDefault, memoryBlock: nil, blockLength: bytes,
                                                   blockAllocator: kCFAllocatorDefault, customBlockSource: nil, offsetToData: 0,
                                                   dataLength: bytes, flags: 0, blockBufferOut: &block)
                guard let block else { throw EncodeError.writer("no audio buffer") }
                let start = written * 2
                audio.withUnsafeBufferPointer { samples in
                    guard let base = samples.baseAddress else { return }
                    _ = CMBlockBufferReplaceDataBytes(with: base + start, blockBuffer: block, offsetIntoDestination: 0, dataLength: bytes)
                }
                var sample: CMSampleBuffer?
                CMAudioSampleBufferCreateReadyWithPacketDescriptions(
                    allocator: kCFAllocatorDefault, dataBuffer: block, formatDescription: format, sampleCount: count,
                    presentationTimeStamp: CMTime(value: CMTimeValue(written), timescale: CMTimeScale(sampleRate)),
                    packetDescriptions: nil, sampleBufferOut: &sample
                )
                guard let sample, input.append(sample) else { throw EncodeError.writer("couldn't append sound") }
                written += count
            }
        }

        func finish() async throws {
            try await append(upTo: audio.count / 2)
            input.markAsFinished()
        }
    }
#endif
