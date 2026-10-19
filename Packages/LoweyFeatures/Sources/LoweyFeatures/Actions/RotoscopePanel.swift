import CoreTransferable
import HmmDesign
import LoweyCore
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// Actions ▸ Rotoscope (F1): a video behind the stage, its frame always the one under the playhead, to pose or draw over
/// a real movement. It's a reference: the stage shows it, exports never do.
struct RotoscopeTile: View {
    @Bindable var editor: EditorModel
    @State private var picking = false
    @State private var item: PhotosPickerItem?
    @State private var showsPanel = false

    var body: some View {
        TileButton(title: "Rotoscope", systemName: "film.stack", identifier: "open-rotoscope", isOn: editor.rotoscope?.shown == true) {
            if editor.rotoscope == nil { picking = true } else { showsPanel = true }
        }
        .photosPicker(isPresented: $picking, selection: $item, matching: .videos)
        .onChange(of: item) { _, picked in
            guard let picked else { return }
            item = nil
            Task {
                guard let movie = try? await picked.loadTransferable(type: PickedMovie.self) else {
                    editor.app.show("That video can't be read", kind: .error)
                    return
                }
                editor.importRotoscope(movie.url)
                try? FileManager.default.removeItem(at: movie.url)
            }
        }
        .popover(isPresented: $showsPanel) {
            RotoscopeControls(editor: editor, choose: {
                showsPanel = false
                picking = true
            })
            .padding(HmmSpacing.m)
            .frame(width: 320)
            .presentationCompactAdaptation(.popover)
        }
    }
}

private struct RotoscopeControls: View {
    @Bindable var editor: EditorModel
    let choose: () -> Void

    var body: some View {
        if let rotoscope = editor.rotoscope {
            VStack(alignment: .leading, spacing: HmmSpacing.m) {
                PanelSection("Rotoscope") {
                    Toggle("Show it", isOn: Binding(get: { rotoscope.shown }, set: { shown in editor.updateRotoscope { $0.shown = shown } }))
                    LabeledSlider(title: "Opacity", value: rotoscope.opacity, range: 0.05 ... 1, format: NumberFormat.percent) { value in
                        editor.updateRotoscope { $0.opacity = value }
                    }
                    Toggle("Over the scene", isOn: Binding(get: { rotoscope.inFront }, set: { front in editor.updateRotoscope { $0.inFront = front } }))
                    Text("Starts at \(TimeFormat.clock(rotoscope.start))").font(.hmm(.footnote)).foregroundStyle(.secondary)
                    HStack(spacing: HmmSpacing.xs) {
                        HmmPillButton("Start at the playhead", systemName: "arrow.right.to.line") {
                            let now = editor.time
                            editor.updateRotoscope { $0.start = now }
                        }
                        HmmPillButton("Another video", systemName: "film") { choose() }
                    }
                    HmmPillButton("Remove", systemName: "trash", role: .destructive) { editor.setRotoscope(nil) }
                }
                Hint("Its frame follows the playhead. Look through the camera to line it up with the shot.")
            }
            .font(.hmm(.body))
        }
    }
}
