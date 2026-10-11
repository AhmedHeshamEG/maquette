import HmmDesign
import LoweyCore
import SwiftUI

/// Perform's character button: with a character selected, the timeline's Perform holds what it does live. Its
/// expressions, lip sync, the face and (as they air) the microphone, triggers and life open from here, beside Record,
/// so performing never leaves the timeline.
struct PerformCharacterButton: View {
    @Bindable var editor: EditorModel
    @State private var open = false
    @Environment(\.hmmTheme) private var theme

    var body: some View {
        if let character = editor.faceTarget {
            Button {
                HmmHaptics.play(.selection)
                open.toggle()
            } label: {
                Label(editor.baseScene.objects[character]?.name ?? "Character", systemImage: "face.smiling")
                    .font(.hmm(.footnote, weight: .semibold))
                    .lineLimit(1)
                    .padding(.horizontal, HmmSpacing.s)
                    .frame(height: 40)
                    .background(Capsule().fill(open ? theme.text.opacity(0.16) : theme.surface2))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("perform-character")
            .popover(isPresented: $open, arrowEdge: .bottom) {
                ScrollView {
                    PerformCharacterSections(editor: editor, character: character)
                        .padding(HmmSpacing.m)
                }
                .frame(width: 360)
                .frame(maxHeight: 520)
                .presentationCompactAdaptation(.popover)
            }
        }
    }
}

/// What the selected character can do live.
struct PerformCharacterSections: View {
    @Bindable var editor: EditorModel
    let character: ObjectID

    var body: some View {
        VStack(alignment: .leading, spacing: HmmSpacing.m) {
            if editor.isBlob(character) { ExpressionTriggers(editor: editor, character: character) }
            FaceSection(editor: editor, character: character)
            if Held.isOn(.livePerformance) {
                TriggersSection(editor: editor, character: character)
                LifeSection(editor: editor, character: character)
            }
        }
    }
}

/// One tap poses the whole face at the playhead; the springs overshoot into it and settle.
struct ExpressionTriggers: View {
    let editor: EditorModel
    let character: ObjectID

    var body: some View {
        PanelSection("Expressions at the playhead") {
            TileGrid(minimum: 80) {
                ForEach(FaceExpression.allCases) { expression in
                    TileButton(title: expression.title, systemName: expression.symbol, identifier: "expression-\(expression.rawValue)") {
                        editor.keyExpression(expression, on: character)
                    }
                }
            }
            LabeledSlider(title: "Cartoon", value: editor.baseScene.objects[character]?[.cartoon]?.floatValue ?? 0.8, range: 0 ... 1,
                          format: NumberFormat.percent, set: { editor.setCartoon($0, on: character) }, done: editor.endGesture)
        }
    }
}

/// Lip sync and face performance.
struct FaceSection: View {
    @Bindable var editor: EditorModel
    let character: ObjectID

    var body: some View {
        PanelSection("Voice & face") {
            HmmPillButton(editor.wordSelection == nil ? "Lip sync to the voiceover" : "Lip sync these words", systemName: "mouth",
                          prominent: !editor.words.isEmpty) { editor.lipSync(character) }
                .accessibilityIdentifier("lip-sync")
            if Held.isOn(.livePerformance) {
                HStack(spacing: HmmSpacing.xs) {
                    HmmPillButton(editor.live.voiceOn ? "Stop the microphone" : "Mouth from the microphone",
                                  systemName: editor.live.voiceOn ? "mic.slash.fill" : "mic.fill") { editor.toggleVoice() }
                        .accessibilityIdentifier("voice-live")
                    if editor.live.voiceOn { VoiceLevel(meter: editor.live.meter) }
                }
            }
            if editor.faceActive {
                Text(editor.faceStatus ?? "Face on").font(.hmm(.body, weight: .semibold))
                HStack(spacing: HmmSpacing.xs) {
                    HmmPillButton("Set rest pose", systemName: "scope") { editor.setRestPose() }
                    HmmPillButton("Stop", systemName: "stop.fill") { editor.stopFaceCapture() }
                }
                Toggle("Mirror", isOn: Binding(get: { editor.facePerformer.mirror }, set: { editor.facePerformer.mirror = $0 }))
                Hint("Your face and hands drive the character live. Record to capture a take; every take is kept.")
            } else {
                HStack(spacing: HmmSpacing.xs) {
                    HmmPillButton("Front camera", systemName: "camera.fill") { editor.startFaceCapture(useIPhone: false) }
                        .accessibilityIdentifier("face-camera")
                    HmmPillButton("My iPhone", systemName: "iphone") { editor.startFaceCapture(useIPhone: true) }
                }
            }
        }
    }
}
