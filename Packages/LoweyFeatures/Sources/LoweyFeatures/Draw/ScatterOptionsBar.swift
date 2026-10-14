import HmmDesign
import LoweyCore
import SwiftUI

/// Scatter options while the Scatter tool is on.
struct ScatterOptionsBar: View {
    @Bindable var editor: EditorModel

    var body: some View {
        HStack(spacing: HmmSpacing.m) {
            LabeledSlider(title: "How many", value: Double(editor.scatter.count), range: 3 ... 150, format: { "\(Int($0))" }) {
                editor.scatter.count = Int($0)
            }
            .frame(width: 180)
            LabeledSlider(title: "Size variety", value: editor.scatter.scaleVariation, range: 0 ... 0.6, format: NumberFormat.percent) {
                editor.scatter.scaleVariation = $0
            }
            .frame(width: 150)
            LabeledSlider(title: "Spacing", value: editor.scatter.spacing, range: 0 ... 2) { editor.scatter.spacing = $0 }
                .frame(width: 150)
            HmmButton("xmark", label: "Done scattering", size: 36) { editor.tool = .select }
        }
        .padding(HmmSpacing.s)
        .hmmPanelBackground()
    }
}
