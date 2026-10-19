#if canImport(ImageIO) && canImport(CoreGraphics)
    import CoreGraphics
    import Foundation
    import ImageIO
    import UniformTypeIdentifiers

    public enum ImageWriteError: Error, Equatable, CustomStringConvertible {
        case cannotCreate
        case cannotFinish

        public var description: String {
            switch self {
            case .cannotCreate: "Couldn't create the image file."
            case .cannotFinish: "Couldn't finish writing the image file."
            }
        }
    }

    /// PNG stills and GIF loops.
    public enum ImageWriters {
        public static func png(_ image: CGImage) throws -> Data {
            let data = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
                throw ImageWriteError.cannotCreate
            }
            CGImageDestinationAddImage(destination, image, nil)
            guard CGImageDestinationFinalize(destination) else { throw ImageWriteError.cannotFinish }
            return data as Data
        }

        public static func writePNG(_ image: CGImage, to url: URL) throws {
            try png(image).write(to: url, options: .atomic)
        }

        /// A spatial photo (HEIC): the two eyes as a stereo pair, each with its camera (where it is, how wide it sees), so
        /// Vision Pro and the iPhone's Photos show it in depth. `baseline` is the eyes' distance in metres,
        /// `horizontalFieldOfView` each eye's in degrees, `disparityAdjustment` where the screen sits (−1 … 1).
        public static func spatialPhoto(left: CGImage, right: CGImage, baseline: Double = 0.063, horizontalFieldOfView: Double,
                                        disparityAdjustment: Double = 0.02) throws -> Data {
            let data = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(data, UTType.heic.identifier as CFString, 2, nil) else {
                throw ImageWriteError.cannotCreate
            }
            let width = Double(left.width)
            let height = Double(left.height)
            let focal = width / 2 / tan(horizontalFieldOfView * .pi / 360)
            let intrinsics: [Double] = [focal, 0, width / 2, 0, focal, height / 2, 0, 0, 1]
            for (index, image) in [left, right].enumerated() {
                let isLeft = index == 0
                let camera: [String: Any] = [
                    kIIOMetadata_CameraModelKey as String: [kIIOCameraModel_Intrinsics as String: intrinsics,
                                                            kIIOCameraModel_ModelType as String: kIIOCameraModelType_SimplifiedPinhole],
                    kIIOMetadata_CameraExtrinsicsKey as String: [
                        kIIOCameraExtrinsics_Position as String: [isLeft ? 0 : baseline, 0, 0],
                        kIIOCameraExtrinsics_Rotation as String: [1.0, 0, 0, 0, 1, 0, 0, 0, 1]
                    ]
                ]
                let eye: CFString = isLeft ? kCGImagePropertyGroupImageIsLeftImage : kCGImagePropertyGroupImageIsRightImage
                let properties: [String: Any] = [
                    kCGImagePropertyGroups as String: [
                        kCGImagePropertyGroupIndex as String: 0,
                        kCGImagePropertyGroupType as String: kCGImagePropertyGroupTypeStereoPair,
                        eye as String: true,
                        kCGImagePropertyGroupImageDisparityAdjustment as String: Int((min(max(disparityAdjustment, -1), 1) * 10000).rounded())
                    ],
                    kCGImagePropertyHEIFDictionary as String: camera,
                    kCGImageDestinationLossyCompressionQuality as String: 0.92
                ]
                CGImageDestinationAddImage(destination, image, properties as CFDictionary)
            }
            guard CGImageDestinationFinalize(destination) else { throw ImageWriteError.cannotFinish }
            return data as Data
        }

        /// A 360° panorama (JPEG): an equirectangular picture marked with Google's Photo Sphere tags (GPano), which
        /// Facebook, Google Photos and every 360 viewer read.
        public static func panorama(_ image: CGImage, software: String = "studio h.") throws -> Data {
            let data = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else {
                throw ImageWriteError.cannotCreate
            }
            let metadata = CGImageMetadataCreateMutable()
            let namespace = "http://ns.google.com/photos/1.0/panorama/" as CFString
            CGImageMetadataRegisterNamespaceForPrefix(metadata, namespace, "GPano" as CFString, nil)
            let tags: [(String, Any)] = [
                ("ProjectionType", "equirectangular"), ("UsePanoramaViewer", "True"),
                ("CroppedAreaImageWidthPixels", image.width), ("CroppedAreaImageHeightPixels", image.height),
                ("FullPanoWidthPixels", image.width), ("FullPanoHeightPixels", image.height),
                ("CroppedAreaLeftPixels", 0), ("CroppedAreaTopPixels", 0), ("StitchingSoftware", software)
            ]
            for (name, value) in tags {
                CGImageMetadataSetValueWithPath(metadata, nil, "GPano:\(name)" as CFString, "\(value)" as CFString)
            }
            let options = [kCGImageDestinationLossyCompressionQuality as String: 0.92] as CFDictionary
            CGImageDestinationAddImageAndMetadata(destination, image, metadata, options)
            guard CGImageDestinationFinalize(destination) else { throw ImageWriteError.cannotFinish }
            return data as Data
        }
    }

    /// Writes an animated GIF frame by frame (loops forever). GIF has 256 colours per frame and 1/100 s timing, so it's
    /// for short loops, not long videos.
    public final class GIFWriter {
        private let destination: CGImageDestination
        private let frameProperties: CFDictionary

        public init(url: URL, frameCount: Int, fps: Int) throws {
            guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString, frameCount, nil) else {
                throw ImageWriteError.cannotCreate
            }
            self.destination = destination
            let delay = 1 / Double(max(fps, 1))
            frameProperties = [kCGImagePropertyGIFDictionary as String: [kCGImagePropertyGIFUnclampedDelayTime as String: delay,
                                                                         kCGImagePropertyGIFDelayTime as String: delay]] as CFDictionary
            let fileProperties = [kCGImagePropertyGIFDictionary as String: [kCGImagePropertyGIFLoopCount as String: 0]] as CFDictionary
            CGImageDestinationSetProperties(destination, fileProperties)
        }

        public func append(_ image: CGImage) {
            CGImageDestinationAddImage(destination, image, frameProperties)
        }

        public func finish() throws {
            guard CGImageDestinationFinalize(destination) else { throw ImageWriteError.cannotFinish }
        }
    }
#endif
