import HmmDesign
import LoweyCore
import SwiftUI

/// The timeline's + Overlay: what sits on the video rather than in the world. Words on the frame (a title, a label),
/// marks (an arrow, a circle, a star…) and screen effects (a flash, a shake…), each landing at the playhead.
struct OverlayMenu: View {
    let editor: EditorModel
    @Environment(\.hmmTheme) private var theme

    private static let marks: [OverlayRecipe.Shape] = [.arrow, .circle, .highlight, .cross, .check, .question, .exclamation, .star]

    var body: some View {
        Menu {
            Section("Words on the frame") {
                Button("Title", systemImage: "textformat.size") { editor.addOverlay(.title) }
                Button("Label", systemImage: "tag") { editor.addOverlay(.label) }
            }
            Section("Marks") {
                ForEach(Self.marks, id: \.self) { shape in
                    Button(LocalizedStringKey(shape.title), systemImage: shape.systemImage) { editor.addOverlay(shape) }
                }
            }
            Section("Screen effects at the playhead") {
                ForEach(ScreenEffect.Kind.allCases) { kind in
                    Button(LocalizedStringKey(kind.title), systemImage: kind.systemImage) { editor.addScreenEffect(kind) }
                }
            }
        } label: {
            Label("Overlay", systemImage: "plus.rectangle.on.rectangle")
                .font(.hmm(.footnote, weight: .semibold))
                .foregroundStyle(theme.text)
                .padding(.horizontal, HmmSpacing.s)
                .frame(height: 40)
                .background(Capsule().fill(theme.surface2))
        }
        .accessibilityLabel("Add an overlay")
        .accessibilityIdentifier("add-overlay")
    }
}
