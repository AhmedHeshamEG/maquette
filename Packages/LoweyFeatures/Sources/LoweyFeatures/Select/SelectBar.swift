import HmmDesign
import LoweyCore
import SwiftUI

/// Select is a small bar: tap or lasso, everything, nothing, and (with something chosen) more like it. The scene's
/// objects are behind the scene's name.
struct SelectBar: View {
    @Bindable var editor: EditorModel

    var body: some View {
        HStack(spacing: HmmSpacing.xxs) {
            ChoiceChip(title: "Tap", systemName: "hand.point.up.left", isOn: editor.tool == .select) { editor.tool = .select }
            ChoiceChip(title: "Lasso", systemName: "lasso", isOn: editor.tool == .lasso) { editor.tool = .lasso }
                .accessibilityIdentifier("tool-lasso")
            Divider().frame(height: 24)
            ChoiceChip(title: "All", systemName: "checkmark.circle", isOn: false) { editor.selectAll() }
                .accessibilityIdentifier("select-all")
            if !editor.selection.isEmpty {
                ChoiceChip(title: "None", systemName: "xmark.circle", isOn: false) { editor.setSelection([]) }
                    .accessibilityIdentifier("select-none")
                ChoiceChip(title: "Similar", systemName: "square.on.square", isOn: false) { editor.selectSimilar() }
                    .accessibilityIdentifier("select-similar")
            }
        }
        .padding(HmmSpacing.xs)
        .hmmPanelBackground(cornerRadius: HmmRadius.card + 8)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("select-bar")
    }
}
