import HmmDesign
import LoweyCore
import SwiftUI

/// A made character's face states (K1 step 3): pick the mouth, the brows or the eyes, tap a state to see it on the stage,
/// bend it with its dials (one step deeper), or put it back as it was. A drawing of a state is made with the Pencil, then
/// "Make it a part" on the drawing.
struct CharacterFaceSection: View {
    @Bindable var editor: EditorModel
    @State private var job: CharacterPart.Job = .mouth
    @State private var state: String?
    @State private var bending = false
    @Environment(\.hmmTheme) private var theme

    /// The face parts the character has (the selected one first).
    private var jobs: [CharacterPart.Job] {
        guard let root = editor.makerCharacter, let anatomy = CharacterAnatomy(root, in: editor.baseScene) else { return [] }
        return [CharacterPart.Job.mouth, .brow, .eye].filter { !anatomy.pieces($0).isEmpty }
    }

    /// The piece whose states are shown: the selected part when it's a face part, else the character's first of the job.
    private var piece: SceneObject? {
        if let selected = editor.selectedPart, selected.part?.job == job { return selected }
        guard let root = editor.makerCharacter, let id = CharacterAnatomy(root, in: editor.baseScene)?.pieces(job).first(where: { $0.part.shows == nil })?.id
        else { return nil }
        return editor.baseScene.objects[id]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: HmmSpacing.s) {
            if jobs.isEmpty {
                Text("Add a mouth, brows or eyes: they get their faces here.").font(.hmm(.footnote)).foregroundStyle(theme.text2)
            } else {
                Picker("Face part", selection: $job) {
                    ForEach(jobs) { Text(LocalizedStringKey($0.title)).tag($0) }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("face-part")
                states
                if let state, let part = piece?.part, state != FaceStates.names(for: job).first { dials(part, state) }
            }
        }
        .onAppear { if let first = jobs.first, !jobs.contains(job) { job = first } }
        .onChange(of: job) { _, _ in show(nil) }
        .onDisappear { editor.previewFaceState(job, nil) }
    }

    private var states: some View {
        TileGrid(minimum: 72) {
            ForEach(FaceStates.names(for: job), id: \.self) { name in
                ChoiceChip(title: FaceStates.title(name), isOn: state == name) { show(state == name ? nil : name) }
                    .accessibilityIdentifier("face-state-\(name)")
            }
        }
    }

    private func show(_ name: String?) {
        state = name
        editor.previewFaceState(job, name)
    }

    /// The bend's numbers, one step deeper (a state looks right as it comes; these make it the character's own).
    private func dials(_ part: CharacterPart, _ state: String) -> some View {
        let bend = FaceStates.bend(of: part, state)
        let dials: [(LocalizedStringKey, WritableKeyPath<FaceBend, Double>, ClosedRange<Double>)] = [
            ("Open", \.open, -1 ... 2), ("Wide", \.wide, -1 ... 1.5), ("Round", \.round, 0 ... 1.2), ("Smile", \.smile, -1 ... 1),
            ("Lift", \.lift, -1 ... 1), ("Tilt", \.tilt, -1 ... 1), ("Close", \.squash, 0 ... 1)
        ]
        return VStack(alignment: .leading, spacing: HmmSpacing.xs) {
            Button(bending ? "Hide its numbers" : "Bend it") { withHmmAnimation(.snappy) { bending.toggle() } }
                .font(.hmm(.footnote, weight: .semibold))
                .accessibilityIdentifier("face-bend")
            if bending {
                ForEach(dials.indices, id: \.self) { index in
                    let dial = dials[index]
                    HStack {
                        Text(dial.0).font(.hmm(.footnote)).frame(width: 52, alignment: .leading)
                        Slider(value: Binding(get: { bend[keyPath: dial.1] }, set: { value in
                            var changed = bend
                            changed[keyPath: dial.1] = value
                            editor.setFaceBend(state, changed, gesture: "face-\(state)")
                        }), in: dial.2) { editing in if !editing { editor.endGesture() } }
                    }
                }
                HmmPillButton("As it came", systemName: "arrow.uturn.backward") { editor.setFaceBend(state, nil) }
                    .accessibilityIdentifier("face-reset")
            }
        }
    }
}

/// Proportions by hand (K1 step 4): the measures in metres, each a number to drag or type; the handles on the stage do
/// the same by dragging the head, the feet, a hand or the waist.
struct CharacterProportionsSection: View {
    @Bindable var editor: EditorModel
    @State private var gesture = UUID().uuidString
    @Environment(\.hmmTheme) private var theme

    var body: some View {
        let measures = editor.proportions
        VStack(alignment: .leading, spacing: HmmSpacing.xs) {
            ForEach(CharacterProportions.Measure.allCases.filter { measures[$0] != nil }) { measure in
                HStack {
                    Text(LocalizedStringKey(measure.title)).font(.hmm(.body))
                    Spacer()
                    HmmNumberPill(measure.title, value: Binding(get: { (measures[measure] ?? 1) / editor.units.metres }, set: { typed in
                        let now = measures[measure] ?? 1
                        guard now > 1e-6 else { return }
                        editor.changeProportion(measure, by: typed * editor.units.metres / now, gesture: gesture)
                    }), scrub: HmmScrub(fine: 0.5, range: 0.01 ... 1_000), format: { editor.units.format($0 * editor.units.metres, symbol: false) },
                    parse: { editor.parseLength($0).map { $0 / editor.units.metres } }, onEditingChanged: { editing in
                        if !editing, let root = editor.makerCharacter {
                            editor.rigAgain(root, gesture: gesture)
                            editor.endGesture()
                            gesture = UUID().uuidString
                        }
                    })
                    .accessibilityIdentifier("proportion-\(measure.rawValue)")
                    Text(verbatim: editor.units.symbol).font(.hmm(.footnote)).foregroundStyle(theme.text3)
                }
            }
            Text(editor.maker.symmetric ? "Both sides change together." : "Mirrored is off: a limb's handle changes its own side.")
                .font(.hmm(.footnote)).foregroundStyle(theme.text2)
        }
        .onAppear { editor.maker.proportions = true }
        .onDisappear { editor.maker.proportions = false }
    }
}

/// A line without a voice: typed, then said from the playhead.
struct SayLineSection: View {
    let editor: EditorModel
    @State private var line = ""

    var body: some View {
        VStack(alignment: .leading, spacing: HmmSpacing.s) {
            TextField("What does it say?", text: $line, axis: .vertical)
                .lineLimit(1 ... 3)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("say-line-text")
                .onSubmit(say)
            HmmPillButton("Say it", systemName: "mouth", prominent: true, action: say)
                .disabled(line.trimmingCharacters(in: .whitespaces).isEmpty)
                .accessibilityIdentifier("say-line")
        }
    }

    private func say() {
        editor.sayLine(line)
        line = ""
    }
}
