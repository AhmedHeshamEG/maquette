import HmmDesign
import LoweyCore
import SwiftUI

/// The chip of a sheet laid on a face (Q1): exact when asked. How far above the face it sits, its turn (snapping to
/// 15°) and its size, each a slider (drag it) with the number pad behind it (tap it). Docked above the tool's bar.
struct SheetChip: View {
    @Bindable var editor: EditorModel
    @State private var gesture = UUID().uuidString

    var body: some View {
        if let state = editor.placing.fit, state.chipShown, let sheet = editor.currentSheet, sheet.id == state.sheetID {
            VStack {
                Spacer(minLength: 0)
                chip(state, sheet).fixedSize()
            }
            .padding(.bottom, 92)
            .frame(maxWidth: .infinity)
        }
    }

    private func chip(_ state: SheetFitState, _ sheet: DrawingSheet) -> some View {
        let units = editor.units
        return HStack(spacing: HmmSpacing.xxs) {
            ChipNumber(title: "Offset", identifier: "sheet-offset", text: units.format(state.offset), value: state.offset,
                       fine: 0.001, units: LengthUnit.allCases.map(\.symbol)) { value, ended in
                editor.adjustFittedSheet(offset: value, gesture: gesture)
                if ended { finish() }
            } typed: { text in
                if let metres = editor.parseLength(text) { editor.adjustFittedSheet(offset: metres, gesture: nil) }
            }
            ChipNumber(title: "Turn", identifier: "sheet-turn", text: "\(NumberFormat.short(state.turn))°", value: state.turn,
                       fine: 0.25, units: []) { value, ended in
                editor.scrubFittedSheetTurn(value, gesture: gesture)
                if ended { finish() }
            } typed: { text in
                if let degrees = HmmArithmetic.evaluate(text) { editor.adjustFittedSheet(turn: degrees, gesture: nil) }
            }
            ChipNumber(title: "Size", identifier: "sheet-size", text: units.format(sheet.width), value: sheet.width,
                       fine: 0.002, units: LengthUnit.allCases.map(\.symbol)) { value, ended in
                editor.adjustFittedSheet(width: max(value, 0.01), gesture: gesture)
                if ended { finish() }
            } typed: { text in
                if let metres = editor.parseLength(text), metres > 0 { editor.adjustFittedSheet(width: metres, gesture: nil) }
            }
            HmmButton("xmark", label: "Done", size: 40) { editor.placing.fit?.chipShown = false }
                .accessibilityIdentifier("sheet-chip-done")
        }
        .padding(HmmSpacing.xxs)
        .environment(\.hmmInsideGlass, true)
        .hmmGlass(in: Capsule(), interactive: false)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("The sheet"))
        .accessibilityIdentifier("sheet-chip")
    }

    /// One drag is one undo step for a kept sheet; the next starts a new one.
    private func finish() {
        editor.endGesture()
        gesture = UUID().uuidString
    }
}

/// One of the chip's numbers: drag it (slowly for fine, fast for coarse) or tap it for the number pad.
private struct ChipNumber: View {
    let title: LocalizedStringKey
    let identifier: String
    let text: String
    let value: Double
    let fine: Double
    let units: [String]
    let scrub: (_ value: Double, _ ended: Bool) -> Void
    let typed: (String) -> Void
    @State private var typing = false
    @State private var start: Double?
    @State private var last: CGSize?
    @Environment(\.hmmTheme) private var theme

    var body: some View {
        Button {
            HmmHaptics.play(.selection)
            typing = true
        } label: {
            VStack(spacing: 0) {
                Text(title).font(.hmm(.caption)).foregroundStyle(theme.text2)
                Text(verbatim: text).font(.hmmNumbers(.footnote)).foregroundStyle(theme.text)
            }
            .frame(minWidth: 64, minHeight: 40)
            .padding(.horizontal, HmmSpacing.xxs)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .simultaneousGesture(drag)
        .hmmNumberPad(isPresented: $typing, placeholder: text, units: units) { typed($0) }
        .accessibilityLabel(Text(title))
        .accessibilityValue(Text(verbatim: text))
        .accessibilityAdjustableAction { direction in
            scrub(value + (direction == .increment ? 1 : -1) * fine * 20, true)
        }
        .accessibilityIdentifier(identifier)
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { drag in
                let previous = last ?? .zero
                last = drag.translation
                let delta = HmmScrub.delta(dx: drag.translation.width - previous.width, dy: drag.translation.height - previous.height)
                let speed = HmmScrub.delta(dx: drag.velocity.width, dy: drag.velocity.height)
                let next = HmmScrub(fine: fine).value(from: start ?? value, delta: delta, speed: speed)
                start = next
                scrub(next, false)
            }
            .onEnded { _ in
                if let start { scrub(start, true) }
                start = nil
                last = nil
            }
    }
}
