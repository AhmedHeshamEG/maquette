import HmmDesign
import LoweyCore
import LoweyEngine
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// The Reference window (Q1, Procreate's Reference is the bar): a slim bar to grab it by, the three modes and a close
/// button; under it the whole scene from its own camera, a picture, or the front camera. Dragged by its bar it glides
/// and settles with a spring off the clusters and the edges; its corner (or a pinch on the bar) sizes it, smoothly, its
/// content never stretched. Its touches stay its own: the stage under it keeps drawing but never feels them.
struct ReferenceWindowView: View {
    @Bindable var editor: EditorModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.hmmTheme) private var theme
    /// While the bar is dragged: how far it moved.
    @State private var moved = CGSize.zero
    /// While the corner is dragged or the bar pinched: the content's size.
    @State private var sizing: CGSize?

    var body: some View {
        GeometryReader { geometry in
            let stage = geometry.size
            let origin = geometry.frame(in: .global).origin
            let window = editor.referenceState
            let size = sizing ?? CGSize(width: window.width, height: window.height)
            let frame = window.frame(in: stage)
            VStack(spacing: 0) {
                ReferenceBar(editor: editor, window: window, onMove: { drag, ended in
                    move(drag, ended: ended, frame: frame, stage: stage, origin: origin)
                }, onPinch: { scale, ended in
                    pinch(scale, ended: ended, window: window, stage: stage, origin: origin)
                })
                ReferenceContent(editor: editor, window: window, size: size)
                    .frame(width: size.width, height: size.height)
                    .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: HmmRadius.card, bottomTrailingRadius: HmmRadius.card, style: .continuous))
                    .overlay(alignment: .bottomTrailing) { grip(window: window, stage: stage, origin: origin) }
            }
            .frame(width: size.width)
            .hmmPanelBackground(cornerRadius: HmmRadius.card)
            .shadow(color: .black.opacity(0.35), radius: 14, y: 6)
            .contentShape(RoundedRectangle(cornerRadius: HmmRadius.card, style: .continuous))
            // Two fingers tapped on it: it steps out of the way for a moment.
            .gesture(TwoFingerTap { editor.hideReferenceForAMoment() })
            .position(x: frame.minX + size.width / 2 + moved.width,
                      y: frame.minY + (size.height + ReferenceWindow.barHeight) / 2 + moved.height)
            .opacity(editor.placing.hidden ? 0 : 1)
            .allowsHitTesting(!editor.placing.hidden)
            .animation(HmmMotion.gentle.animation(reduceMotion: reduceMotion), value: editor.placing.hidden)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Text("Reference window"))
            .accessibilityIdentifier("reference-window")
            .onAppear { reconcile(stage: stage, origin: origin) }
            .onChange(of: stage) { _, _ in reconcile(stage: stage, origin: origin) }
        }
    }

    /// The bar dragged: the window follows the finger, then glides on a little and settles with a spring.
    private func move(_ drag: CGSize?, ended: CGSize?, frame: CGRect, stage: CGSize, origin: CGPoint) {
        if let drag {
            moved = drag
            return
        }
        guard let ended else {
            moved = .zero
            return
        }
        let center = CGPoint(x: frame.midX + ended.width, y: frame.midY + ended.height)
        withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.38, dampingFraction: 0.82)) {
            moved = .zero
            editor.moveReferenceWindow(to: center, in: stage, stageOrigin: origin)
        }
    }

    /// A pinch on the bar sizes the window about its top-left corner.
    private func pinch(_ scale: Double?, ended: Bool, window: ReferenceWindow, stage: CGSize, origin: CGPoint) {
        guard let scale else {
            sizing = nil
            return
        }
        let size = Self.clampedSize(CGSize(width: window.width * scale, height: window.height * scale))
        if ended {
            editor.resizeReferenceWindow(width: Double(size.width), height: Double(size.height), in: stage, stageOrigin: origin)
            sizing = nil
        } else {
            sizing = size
        }
    }

    /// The corner that sizes the window.
    private func grip(window: ReferenceWindow, stage: CGSize, origin: CGPoint) -> some View {
        Image(systemName: "arrow.up.left.and.arrow.down.right")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(theme.text)
            .frame(width: 28, height: 28)
            .background(theme.surface.opacity(0.85), in: Circle())
            .frame(width: HmmTarget.minimum, height: HmmTarget.minimum)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .global)
                .onChanged { value in
                    sizing = Self.clampedSize(CGSize(width: window.width + value.translation.width, height: window.height + value.translation.height))
                }
                .onEnded { value in
                    let size = Self.clampedSize(CGSize(width: window.width + value.translation.width,
                                                       height: window.height + value.translation.height))
                    editor.resizeReferenceWindow(width: Double(size.width), height: Double(size.height), in: stage, stageOrigin: origin)
                    sizing = nil
                })
            .accessibilityElement()
            .accessibilityLabel(Text("Resize"))
            .accessibilityAddTraits(.isButton)
            .accessibilityAdjustableAction { direction in
                let step = direction == .increment ? 1.2 : 1 / 1.2
                editor.resizeReferenceWindow(width: window.width * step, height: window.height * step, in: stage, stageOrigin: origin)
            }
            .accessibilityIdentifier("reference-resize")
    }

    private static func clampedSize(_ size: CGSize) -> CGSize {
        CGSize(width: min(max(size.width, ReferenceWindow.widthRange.lowerBound), ReferenceWindow.widthRange.upperBound),
               height: min(max(size.height, ReferenceWindow.heightRange.lowerBound), ReferenceWindow.heightRange.upperBound))
    }

    /// Shown, or the stage changed size (a rotation, Stage Manager): the window settles inside it again. Only the edges
    /// count here; the clusters are still finding their places, so they're avoided when it's let go.
    private func reconcile(stage: CGSize, origin: CGPoint) {
        guard stage.width > 1, stage.height > 1 else { return }
        let frame = editor.referenceState.frame(in: stage)
        editor.moveReferenceWindow(to: CGPoint(x: frame.midX, y: frame.midY), in: stage, stageOrigin: origin, avoidingClusters: false)
    }
}

/// The slim bar: grab it to move the window (a pinch on it sizes it), the modes, close.
private struct ReferenceBar: View {
    @Bindable var editor: EditorModel
    let window: ReferenceWindow
    let onMove: (_ drag: CGSize?, _ ended: CGSize?) -> Void
    let onPinch: (_ scale: Double?, _ ended: Bool) -> Void
    @Environment(\.hmmTheme) private var theme

    var body: some View {
        HStack(spacing: HmmSpacing.xxs) {
            Capsule()
                .fill(theme.text2.opacity(0.6))
                .frame(width: 22, height: 5)
                .frame(width: 30, height: ReferenceWindow.barHeight)
                .accessibilityElement()
                .accessibilityLabel(Text("Move the Reference window"))
                .accessibilityIdentifier("reference-grab")
            Picker("Show", selection: Binding(get: { window.mode }, set: { editor.setReferenceMode($0) })) {
                ForEach(ReferenceWindow.Mode.allCases) { mode in
                    Label(LocalizedStringKey(mode.title), systemImage: mode.systemImage).labelStyle(.iconOnly).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 150)
            .accessibilityIdentifier("reference-mode")
            Spacer(minLength: 0)
            Button {
                editor.closeReferenceWindow()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(theme.text)
                    .frame(width: 28, height: 28)
                    .background(theme.surface2, in: Circle())
                    .frame(width: HmmTarget.minimum, height: ReferenceWindow.barHeight)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Close the Reference window"))
            .accessibilityIdentifier("reference-close")
        }
        .padding(.leading, HmmSpacing.xxs)
        .frame(height: ReferenceWindow.barHeight)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 2, coordinateSpace: .global)
            .onChanged { value in onMove(value.translation, nil) }
            .onEnded { value in
                // It glides on a little in the direction it was thrown.
                let glide = CGSize(width: (value.predictedEndTranslation.width - value.translation.width) * 0.25,
                                   height: (value.predictedEndTranslation.height - value.translation.height) * 0.25)
                onMove(nil, CGSize(width: value.translation.width + glide.width, height: value.translation.height + glide.height))
            })
        .simultaneousGesture(MagnifyGesture(minimumScaleDelta: 0.01)
            .onChanged { value in onPinch(Double(value.magnification), false) }
            .onEnded { value in onPinch(Double(value.magnification), true) })
    }
}

/// What the window shows.
private struct ReferenceContent: View {
    @Bindable var editor: EditorModel
    let window: ReferenceWindow
    let size: CGSize

    var body: some View {
        switch window.mode {
        case .canvas: ReferenceCanvasContent(editor: editor)
        case .image: ReferenceImageContent(editor: editor, window: window, size: size)
        case .face: ReferenceFaceContent(editor: editor, size: size)
        }
    }
}

// MARK: Canvas

private struct ReferenceCanvasContent: View {
    @Bindable var editor: EditorModel
    @Environment(\.hmmTheme) private var theme

    var body: some View {
        ReferenceCanvasHost(editor: editor)
            .contentShape(Rectangle())
            .onTapGesture(coordinateSpace: .local) { location in
                guard editor.pickActive || editor.eyedropping else { return }
                editor.pickReferenceColour(editor.referenceCanvasColour(at: location))
            }
            .overlay(alignment: .topTrailing) {
                Button {
                    editor.reframeReferenceCanvas()
                } label: {
                    Image(systemName: "scope")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(theme.text)
                        .frame(width: 28, height: 28)
                        .background(theme.surface.opacity(0.85), in: Circle())
                        .frame(width: HmmTarget.minimum, height: HmmTarget.minimum)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("The whole scene, from where you look"))
                .accessibilityIdentifier("reference-reframe")
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Text("The whole scene"))
            .accessibilityIdentifier("reference-canvas")
    }
}

/// A second stage view drawing the scene through the window's camera, live (it never takes touches; SwiftUI does).
private struct ReferenceCanvasHost: UIViewRepresentable {
    let editor: EditorModel

    func makeUIView(context _: Context) -> UIView {
        guard let view = try? StageView(device: RenderDevice.sharedDevice()) else { return UIView() }
        view.isUserInteractionEnabled = false
        view.preferredFramesPerSecond = 30
        view.isContinuous = true
        view.frameSource = { [weak editor] view in editor?.referenceCanvasFrame(for: view) }
        editor.placing.canvas = view
        return view
    }

    func updateUIView(_: UIView, context _: Context) {}

    static func dismantleUIView(_ view: UIView, coordinator _: ()) {
        (view as? StageView)?.isPaused = true
    }
}

// MARK: Image

private struct ReferenceImageContent: View {
    @Bindable var editor: EditorModel
    let window: ReferenceWindow
    let size: CGSize
    @State private var picture: UIImage?
    @State private var panning = CGSize.zero
    @State private var zooming: (scale: Double, focus: CGPoint)?
    @State private var choosingPhoto = false
    @State private var photo: PhotosPickerItem?
    @State private var choosingFile = false
    @Environment(\.hmmTheme) private var theme

    /// The window as the fingers have it now (the live pan and zoom on top of what's kept).
    private var live: ReferenceWindow {
        var shown = window
        shown.width = size.width
        shown.height = size.height
        if let zooming { shown = shown.zoomed(by: zooming.scale, about: zooming.focus) }
        return shown.panned(by: panning)
    }

    var body: some View {
        ZStack {
            theme.surface2.opacity(0.6)
            if let picture, let rect = live.pictureRect() {
                Image(uiImage: picture)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)
                    .accessibilityHidden(true)
            } else {
                VStack(spacing: HmmSpacing.xs) {
                    Image(systemName: "photo").font(.system(size: 22)).foregroundStyle(theme.text2)
                    Text("A picture to work from").font(.hmm(.footnote)).foregroundStyle(theme.text2)
                }
            }
        }
        .frame(width: size.width, height: size.height)
        .contentShape(Rectangle())
        .gesture(pan)
        .simultaneousGesture(zoom)
        .onTapGesture(coordinateSpace: .local) { location in pick(at: location) }
        .overlay(alignment: .bottom) { buttons }
        .dropDestination(for: Data.self) { items, _ in
            guard let item = items.first(where: { UIImage(data: $0) != nil }) else { return false }
            editor.addReference(imageData: item)
            return true
        }
        .photosPicker(isPresented: $choosingPhoto, selection: $photo, matching: .images)
        .onChange(of: photo) { _, item in
            guard let item else { return }
            photo = nil
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) { editor.addReference(imageData: data) }
            }
        }
        .fileImporter(isPresented: $choosingFile, allowedContentTypes: [.image]) { result in
            guard case let .success(url) = result else { return }
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            if let data = try? Data(contentsOf: url) { editor.addReference(imageData: data) }
        }
        .task(id: window.image) {
            picture = window.image.flatMap { UIImage(contentsOfFile: editor.referenceImageURL($0).path) }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(window.image == nil ? "No picture yet" : "The picture"))
        .accessibilityIdentifier("reference-image")
    }

    /// Import (Photos or Files), Paste, Clear; and for a picture, its two uses.
    private var buttons: some View {
        HStack(spacing: HmmSpacing.xxs) {
            Menu {
                Button("From Photos", systemImage: "photo.on.rectangle") { choosingPhoto = true }
                Button("From Files", systemImage: "folder") { choosingFile = true }
            } label: {
                chip("square.and.arrow.down", Text("Import"))
            }
            .accessibilityIdentifier("reference-import")
            Button { editor.pasteReference() } label: { chip("doc.on.clipboard", Text("Paste")) }
                .buttonStyle(.plain)
                .accessibilityIdentifier("reference-paste")
            if window.image != nil {
                Button { editor.clearReferenceImage() } label: { chip("xmark.circle", Text("Clear")) }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("reference-clear")
                if let card = editor.referenceImageCard {
                    Menu {
                        Button("Trace it on the sheet", systemImage: "square.on.square.dashed") { editor.traceReference(card) }
                        Button("Stand it in the scene", systemImage: "photo.on.rectangle") { editor.standReferenceInScene(card) }
                    } label: {
                        chip("ellipsis", Text("More"))
                    }
                    .accessibilityIdentifier("reference-more")
                }
            }
        }
        .padding(HmmSpacing.xxs)
    }

    private func chip(_ systemName: String, _ title: Text) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(theme.text)
            .frame(width: 32, height: 32)
            .background(theme.surface.opacity(0.85), in: Circle())
            .frame(width: HmmTarget.minimum, height: HmmTarget.minimum)
            .contentShape(Rectangle())
            .accessibilityLabel(title)
    }

    /// One finger moves the picture inside the window.
    private var pan: some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                guard window.image != nil else { return }
                panning = value.translation
            }
            .onEnded { value in
                guard window.image != nil else { return }
                panning = .zero
                editor.panReferenceImage(by: value.translation)
            }
    }

    /// Two fingers zoom it, about the point between them.
    private var zoom: some Gesture {
        MagnifyGesture(minimumScaleDelta: 0.01)
            .onChanged { value in
                guard window.image != nil else { return }
                zooming = (Double(value.magnification), value.startLocation)
            }
            .onEnded { value in
                guard window.image != nil else { return }
                zooming = nil
                editor.zoomReferenceImage(by: Double(value.magnification), about: value.startLocation)
            }
    }

    /// Pick (or the quick menu's Eyedropper) takes the picture's colour under the tap.
    private func pick(at location: CGPoint) {
        guard editor.pickActive || editor.eyedropping, let picture else { return }
        guard let unit = live.picturePoint(at: location) else {
            editor.pickReferenceColour(nil)
            return
        }
        editor.pickColour(from: picture, at: unit)
    }
}

/// Two fingers tapping (fingers only).
private struct TwoFingerTap: UIGestureRecognizerRepresentable {
    let action: () -> Void

    func makeUIGestureRecognizer(context _: Context) -> UITapGestureRecognizer {
        let recognizer = UITapGestureRecognizer()
        recognizer.numberOfTouchesRequired = 2
        recognizer.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        return recognizer
    }

    func handleUIGestureRecognizerAction(_ recognizer: UITapGestureRecognizer, context _: Context) {
        if recognizer.state == .ended { action() }
    }
}
