import AVFoundation
import CoreVideo
import Foundation
import ImageIO
import LoweyCore
import Vision

/// Reads a person's body from a video, frame by frame (K1, Act it out): Apple's on-device 3D body pose
/// (`VNDetectHumanBodyPose3DRequest`), nothing generated and nothing sent anywhere. Frames where no person is found are
/// left out; the character holds its last pose across them.
public enum BodyPoseReader {
    public enum Failure: Error, LocalizedError {
        case noVideo, unreadable, nobody

        public var errorDescription: String? {
            switch self {
            case .noVideo: "That file has no video in it."
            case .unreadable: "That video couldn't be read."
            case .nobody: "No one was found in the video. Film the whole body, head to feet, in good light."
            }
        }
    }

    /// The body's joints in every frame read, at most `fps` a second. `progress` gets 0…1 as it reads.
    public static func frames(of url: URL, fps: Double = 30, progress: @escaping @Sendable (Double) -> Void = { _ in }) async throws -> [ActOut.Frame] {
        try await Task.detached(priority: .userInitiated) {
            try await read(url, fps: fps, progress: progress)
        }.value
    }

    private static func read(_ url: URL, fps: Double, progress: @Sendable (Double) -> Void) async throws -> [ActOut.Frame] {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else { throw Failure.noVideo }
        let duration = try await asset.load(.duration).seconds
        let orientation = try await Self.orientation(track.load(.preferredTransform))
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { throw Failure.unreadable }
        reader.add(output)
        guard reader.startReading() else { throw Failure.unreadable }
        var frames: [ActOut.Frame] = []
        var next = 0.0
        while let sample = output.copyNextSampleBuffer() {
            try Task.checkCancellation()
            let time = CMSampleBufferGetPresentationTimeStamp(sample).seconds
            guard time + 1e-6 >= next, let pixels = CMSampleBufferGetImageBuffer(sample) else { continue }
            next = time + 1 / max(fps, 1)
            if let joints = try? joints(in: pixels, orientation: orientation) { frames.append(ActOut.Frame(time: time, joints: joints)) }
            if duration > 0 { progress(min(time / duration, 1)) }
        }
        guard !frames.isEmpty else { throw Failure.nobody }
        return frames
    }

    /// The joints of the one person in a picture (nil when there's nobody).
    static func joints(in pixels: CVPixelBuffer, orientation: CGImagePropertyOrientation) throws -> [ActOut.BodyJoint: Vec3]? {
        let request = VNDetectHumanBodyPose3DRequest()
        try VNImageRequestHandler(cvPixelBuffer: pixels, orientation: orientation).perform([request])
        guard let body = request.results?.first else { return nil }
        var joints: [ActOut.BodyJoint: Vec3] = [:]
        for (name, joint) in Self.names {
            guard let point = try? body.recognizedPoint(name) else { continue }
            let at = point.position.columns.3
            joints[joint] = Vec3(Double(at.x), Double(at.y), Double(at.z))
        }
        return joints.count >= 10 ? joints : nil
    }

    static var names: [(VNHumanBodyPose3DObservation.JointName, ActOut.BodyJoint)] {
        [
            (.root, .root), (.spine, .spine), (.centerShoulder, .centerShoulder), (.centerHead, .centerHead), (.topHead, .topHead),
            (.leftShoulder, .leftShoulder), (.leftElbow, .leftElbow), (.leftWrist, .leftWrist), (.leftHip, .leftHip), (.leftKnee, .leftKnee),
            (.leftAnkle, .leftAnkle), (.rightShoulder, .rightShoulder), (.rightElbow, .rightElbow), (.rightWrist, .rightWrist), (.rightHip, .rightHip),
            (.rightKnee, .rightKnee), (.rightAnkle, .rightAnkle)
        ]
    }

    /// Which way up the video's frames are (a phone filmed upright stores its frames turned).
    static func orientation(_ transform: CGAffineTransform) -> CGImagePropertyOrientation {
        switch (transform.a, transform.b, transform.c, transform.d) {
        case (0, 1, -1, 0): .right
        case (0, -1, 1, 0): .left
        case (-1, 0, 0, -1): .down
        default: .up
        }
    }
}
