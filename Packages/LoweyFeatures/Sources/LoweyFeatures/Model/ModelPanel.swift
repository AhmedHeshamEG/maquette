import HmmDesign
import LoweyCore
import SwiftUI

/// Model: what goes into the world (shapes, lights, words and pictures, effects), shaping it (sketches, push/pull,
/// booleans, bevels, shells, symmetry, printing), and precision (snapping, units, measuring, the section view). Ready
/// models are in the Library.
struct ModelPanel: View {
    @Bindable var editor: EditorModel

    var body: some View {
        HmmPanel("Model", width: 380, sizing: HmmPanelSizing(id: "model"), movable: true, close: { editor.openPanel = nil }) {
            VStack(alignment: .leading, spacing: HmmSpacing.m) {
                pages
                switch editor.modelPage {
                case .add: ModelAddPage(editor: editor)
                case .shape: ModelShapePage(editor: editor)
                case .precision: PrecisionPage(editor: editor)
                }
            }
        }
    }

    private var pages: some View {
        HStack(spacing: HmmSpacing.xs) {
            ForEach(ModelPage.allCases) { page in
                ChoiceChip(title: page.title, systemName: page.systemImage, isOn: editor.modelPage == page) {
                    withHmmAnimation(.snappy) { editor.modelPage = page }
                }
                .accessibilityIdentifier("model-\(page.rawValue)")
            }
        }
    }
}
