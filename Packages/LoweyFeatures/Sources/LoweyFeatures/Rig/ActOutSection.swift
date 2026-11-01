import CoreTransferable
import HmmDesign
import LoweyCore
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Act it out (K1 step 5): film yourself, or pick a video, and the character copies the body from the playhead. Apple's
/// on-device body pose reads it; nothing leaves the iPad and nothing is generated.
struct ActOutSection: View {
    @Bindable var editor: EditorModel
    @State private var picked: PhotosPickerItem?
    @State private var filming = false
    @Environment(\.hmmTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: HmmSpacing.s) {
            Text("Stand back so your whole body shows, head to feet.").font(.hmm(.footnote)).foregroundStyle(theme.text2)
            Toggle("As in a mirror", isOn: $editor.maker.mirrored)
                .accessibilityIdentifier("act-mirrored")
            HStack(spacing: HmmSpacing.s) {
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    HmmPillButton("Film yourself", systemName: "video", prominent: true) { filming = true }
                        .accessibilityIdentifier("act-film")
                }
                PhotosPicker(selection: $picked, matching: .videos) {
                    Label("From a video", systemImage: "film")
                }
                .accessibilityIdentifier("act-video")
            }
            if let reading = editor.maker.reading {
                ProgressView(value: reading) { Text("Reading your moves…").font(.hmm(.footnote)) }
            }
        }
        .disabled(editor.maker.reading != nil)
        .onChange(of: picked) { _, item in
            guard let item else { return }
            picked = nil
            Task {
                if let movie = try? await item.loadTransferable(type: PickedMovie.self) { editor.actOut(from: movie.url) }
            }
        }
        .fullScreenCover(isPresented: $filming) {
            CameraRecorder { url in
                filming = false
                if let url { editor.actOut(from: url) }
            }
            .ignoresSafeArea()
        }
    }
}

/// The system camera, filming video (the front camera first: you're acting to the iPad).
struct CameraRecorder: UIViewControllerRepresentable {
    let done: (URL?) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.mediaTypes = [UTType.movie.identifier]
        picker.cameraCaptureMode = .video
        if UIImagePickerController.isCameraDeviceAvailable(.front) { picker.cameraDevice = .front }
        picker.videoQuality = .typeHigh
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_: UIImagePickerController, context _: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(done: done) }

    @MainActor
    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let done: (URL?) -> Void

        init(done: @escaping (URL?) -> Void) {
            self.done = done
        }

        func imagePickerController(_: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            done(info[.mediaURL] as? URL)
        }

        func imagePickerControllerDidCancel(_: UIImagePickerController) {
            done(nil)
        }
    }
}
