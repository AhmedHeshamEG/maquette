import HmmDesign
import LoweyCore
import SwiftUI

/// Actions ▸ History, over the scrubber (H1): the selected thing's modelling steps in plain words ("Hole, 6 mm"). Tap a
/// step for its numbers; change one and the steps after it replay. Steps fixed by a change made by hand, by paint or by
/// a rig are listed dimmed, with one line saying why.
struct ModelStepsPanel: View {
    @Bindable var editor: EditorModel
    let object: SceneObject
    /// Steps change only from now, not from a moment the scrubber went back to.
    let isNow: Bool
    @State private var picked: Int?
    @State private var pending: [Int: Double] = [:]
    @State private var working = false
    @Environment(\.hmmTheme) private var theme

    private var history: ModelHistory? { object.modelHistory }
    private var lock: ModelingOperations.HistoryFailure? { ModelingOperations.historyLock(of: object) }

    var body: some View {
        if let history {
            VStack(alignment: .leading, spacing: HmmSpacing.xs) {
                HStack(spacing: HmmSpacing.xs) {
                    Image(systemName: "list.number").foregroundStyle(theme.accent)
                    Text("Steps").font(.hmm(.headline, weight: .semibold))
                    Text(verbatim: object.name).font(.hmm(.footnote)).foregroundStyle(theme.text2).lineLimit(1)
                    Spacer()
                    if working { ProgressView().controlSize(.small) }
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: HmmSpacing.xxs) {
                        ForEach(Array((history.earlier + history.steps).enumerated()), id: \.offset) { position, step in
                            chip(step, at: position, fixed: position < history.earlier.count)
                        }
                    }
                }
                if let line = note { Text(verbatim: line).font(.hmm(.footnote)).foregroundStyle(theme.text2).lineLimit(2) }
                if let picked, lock == nil, isNow, history.steps.indices.contains(picked) { numbers(of: history.steps[picked], at: picked) }
            }
            .padding(HmmSpacing.m)
            .frame(maxWidth: 560, alignment: .leading)
            .hmmGlass(in: RoundedRectangle(cornerRadius: HmmRadius.panel, style: .continuous), interactive: false)
            .padding(.horizontal, HmmSpacing.m)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("steps-panel")
            .onChange(of: object.id) { picked = nil }
        }
    }

    /// Why the steps can't change right now, in one line.
    private var note: String? {
        if let lock { return lock.description }
        if !isNow { return String(localized: "Come back to now to change a step.") }
        return picked == nil ? String(localized: "Tap a step to change its numbers. The steps after it follow.") : nil
    }

    private func chip(_ step: ModelStep, at position: Int, fixed: Bool) -> some View {
        let editable = !fixed && lock == nil && isNow
        let index = position - (history?.earlier.count ?? 0)
        let chosen = editable && picked == index
        return Button {
            guard editable else { return }
            HmmHaptics.play(.selection)
            pending = [:]
            picked = chosen ? nil : index
        } label: {
            HStack(spacing: HmmSpacing.xxs) {
                if fixed { Image(systemName: "lock.fill").font(.hmm(.caption)) }
                Text(verbatim: "\(position + 1). \(step.title { editor.units.format($0) })")
                    .font(.hmmNumbers(.footnote, weight: chosen ? .semibold : .regular))
            }
            .foregroundStyle(chosen ? theme.onAccent : (editable ? theme.text : theme.text3))
            .padding(.horizontal, HmmSpacing.s)
            .frame(minHeight: HmmTarget.minimum)
            .background(chosen ? theme.accent : theme.surface2.opacity(0.6), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: step.title { editor.units.format($0) }))
        .accessibilityHint(editable ? Text("Shows its numbers") : Text("Fixed"))
        .accessibilityIdentifier("step-\(position + 1)")
    }

    private func numbers(of step: ModelStep, at index: Int) -> some View {
        HStack(spacing: HmmSpacing.xs) {
            ForEach(Array(step.numbers.enumerated()), id: \.offset) { number, value in
                Text(LocalizedStringKey(value.name.title)).font(.hmm(.footnote)).foregroundStyle(theme.text2)
                HmmNumberPill(value.name.title, value: Binding(get: { (pending[number] ?? value.value) / editor.units.metres }, set: { typed in
                    pending[number] = typed * editor.units.metres
                }), scrub: HmmScrub(fine: 1, range: value.signed ? -1_000_000 ... 1_000_000 : 0.001 ... 1_000_000),
                format: { editor.units.format($0 * editor.units.metres, symbol: false) },
                parse: { text in editor.parseLength(text).map { $0 / editor.units.metres } }, onEditingChanged: { editing in
                    if !editing { commit(step: index, number: number) }
                })
                .accessibilityIdentifier("step-number-\(number + 1)")
            }
            Text(verbatim: editor.units.symbol).font(.hmm(.footnote)).foregroundStyle(theme.text3)
        }
        .disabled(working)
    }

    private func commit(step index: Int, number: Int) {
        guard let metres = pending[number], !working else { return }
        working = true
        Task {
            _ = await editor.changeStep(of: object.id, step: index, number: number, to: metres)
            pending = [:]
            working = false
        }
    }
}
