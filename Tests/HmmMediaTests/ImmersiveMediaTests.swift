#if canImport(AVFoundation) && canImport(ImageIO)
    import AVFoundation
    @testable import HmmMedia
    import ImageIO
    import XCTest

    /// HDR video, spatial photos and video, and 360° panoramas, read back the way the Photos app reads them.
    final class ImmersiveMediaTests: XCTestCase {
        func testHDRVideoIsTenBitHLG() async throws {
            guard await VideoEncoder.canEncode(.hevcHDR) else { throw XCTSkip("this simulator doesn't write 10-bit HEVC") }
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("hmm-hdr-\(UUID().uuidString).mov")
            defer { try? FileManager.default.removeItem(at: url) }
            let encoder = try VideoEncoder(url: url, settings: EncodeSettings(width: 64, height: 64, fps: 24, codec: .hevcHDR))
            for frame in 0 ..< 4 {
                let buffer = try encoder.makePixelBuffer()
                XCTAssertEqual(CVPixelBufferGetPixelFormatType(buffer), kCVPixelFormatType_64RGBAHalf)
                try await encoder.append(buffer, frame: frame)
            }
            try await encoder.finish()
            let tracks = try await AVURLAsset(url: url).loadTracks(withMediaType: .video)
            let track = try XCTUnwrap(tracks.first)
            let descriptions = try await track.load(.formatDescriptions)
            let description = try XCTUnwrap(descriptions.first)
            let transfer = CMFormatDescriptionGetExtension(description, extensionKey: kCMFormatDescriptionExtension_TransferFunction) as? String
            XCTAssertEqual(transfer, kCMFormatDescriptionTransferFunction_ITU_R_2100_HLG as String)
        }

        func testASpatialPhotoIsAStereoPair() throws {
            let left = try XCTUnwrap(EncoderTests.solid(width: 32, height: 16))
            let right = try XCTUnwrap(EncoderTests.solid(width: 32, height: 16))
            let data: Data
            do {
                data = try ImageWriters.spatialPhoto(left: left, right: right, horizontalFieldOfView: 60)
            } catch {
                throw XCTSkip("no HEIC encoder here")
            }
            let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
            XCTAssertEqual(CGImageSourceGetCount(source), 2)
            let properties = try XCTUnwrap(CGImageSourceCopyProperties(source, nil) as? [String: Any])
            let groups = try XCTUnwrap(properties[kCGImagePropertyGroups as String] as? [[String: Any]])
            XCTAssertEqual(groups.first?[kCGImagePropertyGroupType as String] as? String, kCGImagePropertyGroupTypeStereoPair as String)
        }

        func testAPanoramaCarriesItsPhotoSphereTags() throws {
            let image = try XCTUnwrap(EncoderTests.solid(width: 64, height: 32))
            let data = try ImageWriters.panorama(image)
            let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
            let metadata = try XCTUnwrap(CGImageSourceCopyMetadataAtIndex(source, 0, nil))
            let projection = CGImageMetadataCopyStringValueWithPath(metadata, nil, "GPano:ProjectionType" as CFString) as String?
            XCTAssertEqual(projection, "equirectangular")
        }

        func testSpatialVideoWhereTheDeviceEncodesIt() async throws {
            guard SpatialVideoEncoder.isSupported else { throw XCTSkip("no MV-HEVC encoder here") }
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("hmm-spatial-\(UUID().uuidString).mov")
            defer { try? FileManager.default.removeItem(at: url) }
            let encoder = try SpatialVideoEncoder(url: url, settings: EncodeSettings(width: 64, height: 64, fps: 24, codec: .hevc),
                                                  stereo: .init(horizontalFieldOfView: 60))
            for frame in 0 ..< 4 {
                try await encoder.append(left: encoder.makePixelBuffer(), right: encoder.makePixelBuffer(), frame: frame)
            }
            try await encoder.finish()
            let tracks = try await AVURLAsset(url: url).loadTracks(withMediaType: .video)
            let track = try XCTUnwrap(tracks.first)
            let characteristics = try await track.load(.mediaCharacteristics)
            XCTAssertTrue(characteristics.contains(.containsStereoMultiviewVideo))
        }
    }
#endif
