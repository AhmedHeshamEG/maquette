import AVFoundation
import CoreVideo
import Foundation
import HmmDesign
import HmmMedia
import LoweyCore
import LoweyEngine
import UIKit

/// G1, Room: a matched photo becomes the shot camera with the photo behind the stage; a scan becomes the building.
extension EditorModel {
    /// The camera that took the photo, made the shot camera and looked through; the photo stands behind the stage as a
    /// rotoscope that holds still (a reference: exports never show it).
    func applyPhotoMatch(_ match: PhotoMatch.Camera, photo: UIImage) async {
        var camera = SceneObject(id: .make(), name: ObjectFactory.uniqueName("Photo camera", in: scene), kind: .camera,
                                 transform: CoreTransform(position: match.position, rotation: match.rotation))
        camera[.fieldOfView] = .float(match.fieldOfView)
        guard perform(.batch("Match a photo", [operations.add(camera), .setActiveCamera(camera.id)])) else { return }
        do {
            let file = try await stillVideo(photo, seconds: max(timeline.duration, 60))
            setRotoscope(Rotoscope(video: file, opacity: 1, start: 0))
        } catch {
            app.show("Couldn't put the photo behind the stage: \(error.localizedDescription)", kind: .error)
        }
        setSelection([camera.id])
        setDirectorView(true)
        app.show("The camera stands where the photo was taken; what you build sits in it")
    }

    /// The photo as a video that holds it (one frame a second), in the project's assets: the rotoscope's backdrop.
    private func stillVideo(_ photo: UIImage, seconds: Double) async throws -> String {
        guard let image = photo.cgImage else { throw EncodeError.invalidSettings }
        let scale = min(1, 1920 / Double(max(image.width, image.height)))
        let width = Int(Double(image.width) * scale) / 2 * 2, height = Int(Double(image.height) * scale) / 2 * 2
        try FileManager.default.createDirectory(at: assetsFolder, withIntermediateDirectories: true)
        let file = uniqueMediaName("Matched photo.mp4")
        let encoder = try HmmMedia.VideoEncoder(url: assetsFolder.appendingPathComponent(file),
                                                settings: EncodeSettings(width: width, height: height, fps: 1, codec: .h264))
        for frame in 0 ..< Int(seconds.rounded(.up)) {
            let buffer = try encoder.makePixelBuffer()
            CVPixelBufferLockBaseAddress(buffer, [])
            if let context = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: width, height: height, bitsPerComponent: 8,
                                       bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: CGColorSpaceCreateDeviceRGB(),
                                       bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) {
                context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            }
            CVPixelBufferUnlockBaseAddress(buffer, [])
            try await encoder.append(buffer, frame: frame)
        }
        try await encoder.finish()
        return file
    }

    /// A finished room scan as the building: walls with their openings, the floor, furniture blocks, one undo step.
    func addScannedRoom(_ scan: RoomScan) {
        var ids = operations.ids
        guard let command = scan.command(ids: &ids) else {
            app.show("The scan found no walls", kind: .error)
            return
        }
        operations.ids = ids
        if perform(command) {
            HmmHaptics.play(.commit)
            app.show("The room is in: \(scan.surfaces.filter { $0.kind == .wall }.count) walls, \(scan.items.count) pieces of furniture")
        }
    }
}
