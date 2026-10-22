import GameController
import HmmDesign
import LoweyCore
import SwiftUI

/// Present mode's only controls (U8): nothing at all while it plays; a tap brings back, for three seconds, what it
/// plays (the film, walking, the model), play and the shots for the film, and Done. Walking with no iPhone and no game
/// controller keeps two faint sticks in the bottom corners.
struct PresentOverlay: View {
    @Bindable var editor: EditorModel
    let state: PresentState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .bottom) {
            if state.kind == .walk, editor.together.phone == nil, GCController.controllers().isEmpty {
                WalkSticks(editor: editor)
            }
            if state.controls {
                controls
                    .padding(.bottom, HmmSpacing.l)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .animation(HmmMotion.standard.animation(reduceMotion: reduceMotion), value: state.controls)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("present")
    }

    private var controls: some View {
        HStack(spacing: HmmSpacing.s) {
            ForEach(PresentKind.allCases) { kind in
                HmmButton(kind.systemImage, label: kind.title, isOn: state.kind == kind) { editor.startPresenting(kind) }
                    .accessibilityIdentifier("present-\(kind.rawValue)")
            }
            if state.kind == .film {
                Divider().frame(height: 28)
                HmmButton("backward.end.fill", label: "Previous shot") { editor.presentRemote(.previousShot) }
                HmmButton(editor.isPlaying ? "pause.fill" : "play.fill", label: editor.isPlaying ? "Pause" : "Play") {
                    editor.togglePresentedPlay()
                    editor.showPresentControls()
                }
                HmmButton("forward.end.fill", label: "Next shot") { editor.presentRemote(.nextShot) }
            }
            if let phone = editor.together.phone {
                Image(systemName: "iphone.radiowaves.left.and.right")
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(Text("\(phone.name) is the remote"))
            }
            Divider().frame(height: 28)
            HmmPillButton("Done", systemName: "xmark") { editor.stopPresenting() }
                .accessibilityIdentifier("present-done")
        }
        .padding(HmmSpacing.xs)
        .environment(\.hmmInsideGlass, true)
        .hmmGlass(in: Capsule(), interactive: false)
    }
}

/// Two faint sticks for walking with fingers: the left one walks, the right one looks round.
private struct WalkSticks: View {
    let editor: EditorModel

    var body: some View {
        HStack {
            WalkStick(label: "Walk") { vector in
                editor.flyer.pad.strafe = vector.x
                editor.flyer.pad.forward = -vector.y
            }
            Spacer()
            WalkStick(label: "Look") { vector in
                editor.flyer.pad.pan = vector.x
                editor.flyer.pad.tilt = -vector.y
            }
        }
        .padding(HmmSpacing.xl)
        .opacity(0.55)
    }
}

/// A well and a knob; −1…1 on both axes (y down), back to the middle when let go.
private struct WalkStick: View {
    let label: String
    let changed: (SIMD2<Double>) -> Void
    @State private var offset = CGSize.zero
    @Environment(\.hmmTheme) private var theme
    private static let radius: CGFloat = 56

    var body: some View {
        ZStack {
            Circle().fill(theme.surface2.opacity(0.6))
            Circle().fill(theme.text.opacity(0.85)).frame(width: 40, height: 40).offset(offset)
        }
        .frame(width: Self.radius * 2, height: Self.radius * 2)
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    let length = max(1, hypot(value.translation.width, value.translation.height))
                    let scale = min(1, Self.radius / length)
                    offset = CGSize(width: value.translation.width * scale, height: value.translation.height * scale)
                    changed(SIMD2(Double(offset.width / Self.radius), Double(offset.height / Self.radius)))
                }
                .onEnded { _ in
                    offset = .zero
                    changed(.zero)
                }
        )
        .accessibilityLabel(Text(LocalizedStringKey(label)))
    }
}
