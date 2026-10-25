@preconcurrency import AVFoundation
import CoreImage
import HmmDesign
import os
import SwiftUI
import UIKit

/// One frame of the front camera, upright and mirrored like a mirror.
struct ReferenceCameraFrame: @unchecked Sendable {
    let image: CGImage
}

/// The Reference window's Face mode (Q1): the front camera, to draw expressions from. Frames arrive upright and mirrored
/// about 24 times a second; nothing is recorded or kept, and nothing leaves the iPad.
final class ReferenceCamera: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    enum Problem: Equatable {
        /// The person said no to the camera (Settings ▸ Maquette changes it).
        case denied
        /// No front camera here (a simulator), or it's busy.
        case noCamera
    }

    private let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "studio.h.maquette.reference-camera")
    private let context = CIContext(options: [.cacheIntermediates: false])
    private let logger = Logger(subsystem: "studio.h.maquette", category: "reference")
    private var lastFrame: CFTimeInterval = 0
    private var connection: AVCaptureConnection?
    private var rotation: AVCaptureDevice.RotationCoordinator?
    private var rotationObservation: NSKeyValueObservation?
    /// Called on the main actor for every frame shown.
    let onFrame: @MainActor @Sendable (ReferenceCameraFrame) -> Void

    init(onFrame: @escaping @MainActor @Sendable (ReferenceCameraFrame) -> Void) {
        self.onFrame = onFrame
        super.init()
    }

    /// Asks for the camera the first time (the line in the Info.plist says why), then starts it. Nil when it runs.
    @MainActor
    func start() async -> Problem? {
        // No camera, no question.
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) else { return .noCamera }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: break
        case .notDetermined:
            guard await AVCaptureDevice.requestAccess(for: .video) else { return .denied }
        default: return .denied
        }
        guard let input = try? AVCaptureDeviceInput(device: camera) else { return .noCamera }
        session.beginConfiguration()
        session.sessionPreset = .hd1280x720
        if session.canAddInput(input) { session.addInput(input) }
        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: queue)
        if session.canAddOutput(output) { session.addOutput(output) }
        if let connection = output.connection(with: .video) {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = true
            self.connection = connection
        }
        session.commitConfiguration()
        // Upright whichever way the iPad is turned.
        let coordinator = AVCaptureDevice.RotationCoordinator(device: camera, previewLayer: nil)
        rotation = coordinator
        applyRotation(coordinator.videoRotationAngleForHorizonLevelCapture)
        rotationObservation = coordinator.observe(\.videoRotationAngleForHorizonLevelCapture, options: [.new]) { [weak self] _, change in
            guard let angle = change.newValue, let self else { return }
            queue.async { [weak self] in self?.applyRotation(angle) }
        }
        queue.async { [session] in session.startRunning() }
        return nil
    }

    private func applyRotation(_ angle: CGFloat) {
        guard let connection, connection.isVideoRotationAngleSupported(angle), connection.videoRotationAngle != angle else { return }
        connection.videoRotationAngle = angle
    }

    func stop() {
        rotationObservation?.invalidate()
        rotationObservation = nil
        queue.async { [session] in session.stopRunning() }
    }

    func captureOutput(_: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from _: AVCaptureConnection) {
        let now = CACurrentMediaTime()
        guard now - lastFrame > 1.0 / 24, let pixels = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        lastFrame = now
        let picture = CIImage(cvPixelBuffer: pixels)
        guard let image = context.createCGImage(picture, from: picture.extent) else {
            logger.error("A camera frame couldn't be drawn")
            return
        }
        let frame = ReferenceCameraFrame(image: image)
        let onFrame = onFrame
        Task { @MainActor in onFrame(frame) }
    }
}

// MARK: Face

/// The camera's latest frame and what stopped it, for the view to show.
@Observable
@MainActor
private final class ReferenceFaceFeed {
    var frame: CGImage?
    var problem: ReferenceCamera.Problem?
    @ObservationIgnored var camera: ReferenceCamera?

    func start() async {
        let camera = ReferenceCamera { [weak self] frame in self?.frame = frame.image }
        self.camera = camera
        problem = await camera.start()
    }

    func stop() {
        camera?.stop()
        camera = nil
        frame = nil
    }
}

struct ReferenceFaceContent: View {
    @Bindable var editor: EditorModel
    let size: CGSize
    @State private var feed = ReferenceFaceFeed()
    @Environment(\.openURL) private var openURL
    @Environment(\.hmmTheme) private var theme

    var body: some View {
        ZStack {
            Color.black
            if let frame = feed.frame {
                Image(decorative: frame, scale: 1).resizable().scaledToFill()
                    .frame(width: size.width, height: size.height)
                    .clipped()
            } else if editor.faceActive {
                message(Text("The camera is reading your face for the performance"))
            } else if feed.problem == .denied {
                VStack(spacing: HmmSpacing.xs) {
                    message(Text("Maquette may use the front camera only to show you your face here"))
                    HmmPillButton("Settings", systemName: "gear") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    }
                }
            } else if feed.problem == .noCamera {
                message(Text("There's no front camera here"))
            } else {
                ProgressView()
            }
        }
        .frame(width: size.width, height: size.height)
        .contentShape(Rectangle())
        .onTapGesture(coordinateSpace: .local) { location in pick(at: location) }
        .task {
            guard !editor.faceActive else { return }
            await feed.start()
        }
        .onDisappear { feed.stop() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Your face, from the front camera"))
        .accessibilityIdentifier("reference-face")
    }

    private func message(_ text: Text) -> some View {
        text
            .font(.hmm(.footnote))
            .foregroundStyle(theme.text2)
            .multilineTextAlignment(.center)
            .padding(HmmSpacing.s)
    }

    /// The frame fills the window (cropped, never stretched): the tap's pixel in it.
    private func pick(at location: CGPoint) {
        guard editor.pickActive || editor.eyedropping, let frame = feed.frame, size.width > 0, size.height > 0 else { return }
        let width = Double(frame.width), height = Double(frame.height)
        let scale = max(size.width / width, size.height / height)
        let x = (location.x - (size.width - width * scale) / 2) / (width * scale)
        let y = (location.y - (size.height - height * scale) / 2) / (height * scale)
        editor.pickReferenceColour(EditorModel.colour(of: frame, at: CGPoint(x: x, y: y)))
    }
}
