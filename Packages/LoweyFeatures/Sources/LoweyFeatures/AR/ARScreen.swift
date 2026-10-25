import HmmDesign
import LoweyCore
import LoweyEngine
import SwiftUI

/// The scene in your room (M12, Actions ▸ View in AR): the camera fills the screen and the scene stands on a floor or
/// table you tap, drawn in its own Look. One finger moves it, two turn it, a pinch sizes it; On the table and Life size
/// set the size at once. Play runs the timeline in the room; Share hands over a USDZ for AR Quick Look.
struct ARScreen: View {
    @Bindable var editor: EditorModel
    @State private var guidance: String? = String(localized: "Move the iPad slowly to look around the room")
    @State private var placement: ARPlacement?
    @State private var lifeSize = false
    @State private var sharing: URL?
    @State private var view: ARStageView?

    var body: some View {
        ZStack {
            ARStageHost(editor: editor, view: $view, guidance: $guidance, placement: $placement)
                .ignoresSafeArea()
            VStack {
                HStack(alignment: .top) {
                    HmmPillButton("Done", systemName: "xmark") { editor.closeAR() }
                        .accessibilityIdentifier("ar-done")
                        .keyboardShortcut(.cancelAction)
                    Spacer()
                    if let guidance {
                        Text(guidance)
                            .font(.hmm(.body))
                            .padding(.horizontal, HmmSpacing.m)
                            .padding(.vertical, HmmSpacing.s)
                            .hmmGlass(in: Capsule(), interactive: false)
                            .accessibilityIdentifier("ar-guidance")
                    }
                    Spacer()
                }
                Spacer()
                if placement != nil { controls }
            }
            .padding(HmmSpacing.l)
        }
        .onChange(of: placement) { _, placed in lifeSize = placed?.isLifeSize ?? false }
        .sheet(item: Binding(get: { sharing.map(IdentifiedURL.init) }, set: { sharing = $0?.url })) { ShareSheet(items: [$0.url]) }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ar-view")
    }

    private var controls: some View {
        HStack(spacing: HmmSpacing.s) {
            HmmButton("cube", label: "On the table", isOn: !lifeSize) { view?.setSize(lifeSize: false) }
                .accessibilityIdentifier("ar-table")
            HmmButton("figure.stand", label: "Life size", isOn: lifeSize) { view?.setSize(lifeSize: true) }
                .accessibilityIdentifier("ar-life")
            Divider().frame(height: 28)
            HmmButton(editor.isPlaying ? "pause.fill" : "play.fill", label: editor.isPlaying ? "Pause" : "Play") { editor.togglePlay() }
                .accessibilityIdentifier("ar-play")
            HmmButton("square.and.arrow.up", label: "Share for AR") { sharing = editor.arShareFile() }
                .accessibilityIdentifier("ar-share")
        }
        .padding(HmmSpacing.xs)
        .environment(\.hmmInsideGlass, true)
        .hmmGlass(in: Capsule(), interactive: false)
    }
}

/// The AR stage in SwiftUI: it runs while the screen shows, and draws the editor's scene at the playhead.
private struct ARStageHost: UIViewRepresentable {
    let editor: EditorModel
    @Binding var view: ARStageView?
    @Binding var guidance: String?
    @Binding var placement: ARPlacement?

    func makeUIView(context _: Context) -> UIView {
        guard ARStageView.isSupported, let stage = try? ARStageView(device: RenderDevice.sharedDevice()) else {
            let label = UILabel()
            label.text = String(localized: "This iPad can't show the scene in the room. Share for AR opens it on an iPhone.")
            label.textAlignment = .center
            label.numberOfLines = 0
            label.textColor = .secondaryLabel
            label.accessibilityIdentifier = "ar-unsupported"
            DispatchQueue.main.async { guidance = nil }
            return label
        }
        stage.sceneBounds = editor.arSceneBounds
        stage.frameSource = { [weak editor] size in editor?.arFrame(size: size) }
        stage.onGuidance = { text in guidance = text }
        stage.onPlaced = { placed in placement = placed }
        stage.start()
        DispatchQueue.main.async { view = stage }
        return stage
    }

    func updateUIView(_: UIView, context _: Context) {}

    static func dismantleUIView(_ view: UIView, coordinator _: ()) {
        (view as? ARStageView)?.stop()
    }
}
