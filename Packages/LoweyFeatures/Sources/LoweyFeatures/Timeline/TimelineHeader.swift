import HmmDesign
import LoweyCore
import SwiftUI

/// The timeline's bar, seven controls (CONTEXT §10.10, Procreate Dreams' restraint; U5: + Overlay went, titles are 3D
/// text that sticks to the camera and screen finishes live in Look): play, the time, Perform | Keys, the mode's one
/// button (Record or Key), + Sound, the menu, collapse. Markers, the loop and what each mode
/// does one step deeper are in the menu; going to the start is a flick on the ruler, a frame is a tap beside the
/// playhead. A selected character adds its Perform button beside Record; a performed number, its slider.
struct TimelineHeader: View {
    @Bindable var editor: EditorModel
    let fit: () -> Void
    @Environment(\.hmmTheme) private var theme

    var body: some View {
        HStack(spacing: HmmSpacing.s) {
            HmmButton(editor.isPlaying ? "pause.fill" : "play.fill", label: editor.isPlaying ? "Pause" : "Play", isOn: editor.isPlaying,
                      size: HmmTarget.primary) { editor.togglePlay() }
            TimelineClock(editor: editor)
            ModePicker(mode: $editor.timelineMode)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: HmmSpacing.xs) {
                    switch editor.timelineMode {
                    case .perform: PerformControls(editor: editor)
                    case .keyframe: KeyButton(editor: editor)
                    }
                    soundButton
                }
            }
            menu
            HmmButton("chevron.down", label: "Collapse the timeline", size: 36) { editor.timelinePresence = .transport }
        }
        .environment(\.hmmInsideGlass, true)
    }

    private var soundButton: some View {
        Button {
            HmmHaptics.play(.selection)
            editor.sheet = .audio
        } label: {
            Label("Sound", systemImage: "waveform")
                .font(.hmm(.footnote, weight: .semibold))
                .foregroundStyle(theme.text)
                .padding(.horizontal, HmmSpacing.s)
                .frame(height: 40)
                .background(Capsule().fill(theme.surface2))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Sound and words")
        .accessibilityIdentifier("Sound and words")
    }

    private var menu: some View {
        Menu {
            Section {
                Button("Add marker", systemImage: "flag") { editor.addMarker() }
                Button("Loop starts here", systemImage: "arrow.right.to.line") { editor.setLoopStart() }
                Button("Loop ends here", systemImage: "arrow.left.to.line") { editor.setLoopEnd() }
                if editor.timeline.loop != nil { Button("No loop", systemImage: "xmark") { editor.clearLoop() } }
            }
            switch editor.timelineMode {
            case .keyframe: KeyMenuItems(editor: editor)
            case .perform: PerformMenuItems(editor: editor)
            }
            Section {
                Button("Show the whole timeline", systemImage: "arrow.left.and.right", action: fit)
                Toggle("Snap to spoken words", isOn: $editor.snapToWords)
                Button("Timeline settings…", systemImage: "slider.horizontal.3") { editor.sheet = .timelineSettings }
            }
        } label: {
            Image(systemName: editor.timeline.loop != nil ? "repeat" : "ellipsis")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(editor.timeline.loop != nil ? theme.accent : theme.text)
                .frame(width: 40, height: 40)
        }
        .accessibilityLabel("Timeline menu")
        .accessibilityIdentifier("timeline-menu")
    }
}

/// Perform | Keys, both shown as words.
private struct ModePicker: View {
    @Binding var mode: TimelineMode
    @Environment(\.hmmTheme) private var theme

    var body: some View {
        HStack(spacing: 2) {
            ForEach(TimelineMode.allCases) { item in
                Button {
                    HmmHaptics.play(.selection)
                    withHmmAnimation(.snappy) { mode = item }
                } label: {
                    Text(LocalizedStringKey(item.title))
                        .font(.hmm(.footnote, weight: .semibold))
                        .lineLimit(1)
                        .padding(.horizontal, 12)
                        .frame(height: 36)
                        .foregroundStyle(item == mode ? theme.onAccent : theme.text)
                        .background(Capsule().fill(item == mode ? theme.accent : .clear))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.title)
                .accessibilityAddTraits(item == mode ? .isSelected : [])
                .accessibilityIdentifier("timeline-mode-\(item.rawValue)")
            }
        }
        .padding(3)
        .background(Capsule().fill(theme.surface2))
    }
}

/// Keys: the mode's one button keys the selection at the playhead.
private struct KeyButton: View {
    @Bindable var editor: EditorModel

    var body: some View {
        if !editor.selection.isEmpty {
            HmmPillButton("Key", systemName: "diamond.fill", prominent: true) { editor.keySelection() }
                .accessibilityIdentifier("key-selection")
        }
    }
}

/// Keys, one step deeper (the timeline's menu): auto-key, picking keys, the picked keys' easing and timing, the graph.
private struct KeyMenuItems: View {
    @Bindable var editor: EditorModel

    var body: some View {
        Section("Keys") {
            Toggle("Pick several keys", isOn: $editor.keyBoxSelect)
                .accessibilityIdentifier("key-select-mode")
            Menu(editor.selection.isEmpty ? "Pick keys" : "Pick keys in the selection", systemImage: "checklist") {
                ForEach(KeyQuery.allCases) { query in
                    if query != .loop || editor.timeline.loop != nil {
                        Button(LocalizedStringKey(query.title), systemImage: query.systemImage) { editor.selectKeys(query) }
                    }
                }
            }
            .accessibilityIdentifier("key-select-menu")
            if !editor.selectedKeys.isEmpty {
                Menu("Easing", systemImage: "point.topleft.down.to.point.bottomright.curvepath") {
                    ForEach(EasingChoice.allCases) { choice in
                        Button(LocalizedStringKey(choice.title)) { editor.setEasing(choice.easing) }
                    }
                }
                Menu("Timing", systemImage: "timer") {
                    Button("Twice as fast", systemImage: "hare") { editor.retimeKeys(0.5) }
                    Button("Twice as slow", systemImage: "tortoise") { editor.retimeKeys(2) }
                    Button("One frame earlier", systemImage: "chevron.left") { editor.nudgeSelectedKeys(frames: -1) }
                    Button("One frame later", systemImage: "chevron.right") { editor.nudgeSelectedKeys(frames: 1) }
                }
            }
            if let key = editor.selectedKeys.min(by: { $0.time < $1.time }) ?? editor.firstGraphKey {
                Button("Graph editor…", systemImage: "point.topleft.down.to.point.bottomright.curvepath") { editor.graphKey = key }
                    .accessibilityIdentifier("graph-editor")
            }
            if editor.hasKeyClipboard {
                Button("Paste keys at the playhead", systemImage: "doc.on.clipboard") { editor.pasteKeys() }
            }
            if !editor.selection.isEmpty, editor.selectionHasAnimation {
                Button("Clear the selection's animation", systemImage: "xmark.bin", role: .destructive) { editor.clearAnimation() }
            }
        }
    }
}

/// Perform, one step deeper (the timeline's menu): what a touch performs, and the Pencil's roll.
private struct PerformMenuItems: View {
    @Bindable var editor: EditorModel

    var body: some View {
        Section("Perform") {
            PerformValueMenu(editor: editor)
            Toggle("Pencil roll turns it", isOn: $editor.performSettings.barrelRoll)
        }
    }
}

/// Perform: Record (Ready, then time runs while you touch), the selected character's button, a performed number.
private struct PerformControls: View {
    @Bindable var editor: EditorModel
    @Environment(\.hmmTheme) private var theme

    var body: some View {
        Button {
            if editor.performPhase == .recording || editor.performPhase == .ready {
                editor.stopPerform()
            } else {
                editor.armPerform()
            }
        } label: {
            HStack(spacing: 6) {
                Circle().fill(theme.record).frame(width: 14, height: 14)
                Text(recordTitle).font(.hmm(.body, weight: .semibold))
            }
            .padding(.horizontal, HmmSpacing.s)
            .frame(height: 40)
            .background(Capsule().fill(editor.performPhase == .idle ? theme.surface2 : theme.record.opacity(0.35)))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("perform-record")
        PerformCharacterButton(editor: editor)
        PerformValueSlider(editor: editor)
    }

    private var recordTitle: String {
        switch editor.performPhase {
        case .idle: "Record"
        case .ready: "Ready"
        case let .countdown(count): "Ready… \(count)"
        case .recording: "Stop"
        }
    }
}
