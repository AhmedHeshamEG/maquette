import HmmDesign
import LoweyCore
import SwiftUI

/// Whether the export loops seamlessly (D1): the moment after the last frame against the first. When it jumps, what jumps
/// is named and one button closes the loop.
struct LoopCheckRow: View {
    let editor: EditorModel
    @State private var seams: [LoopCheck.Seam]?
    @Environment(\.hmmTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: HmmSpacing.xs) {
            if let seams {
                if seams.isEmpty {
                    Label("Loops seamlessly", systemImage: "infinity").font(.hmm(.body, weight: .semibold))
                } else {
                    Label("Jumps when it loops", systemImage: "arrow.uturn.backward.circle").font(.hmm(.body, weight: .semibold))
                    Text(seams.prefix(4).map { "\($0.name) \(String(localized: String.LocalizationValue($0.what.title)))" }.joined(separator: " · "))
                        .font(.hmm(.footnote)).foregroundStyle(theme.text2)
                    HmmPillButton("Close the loop", systemName: "infinity") {
                        editor.closeTheLoop()
                        self.seams = editor.loopSeams
                    }
                    .accessibilityIdentifier("export-close-loop")
                }
            } else {
                ProgressView()
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("export-loop-check")
        .task { seams = editor.loopSeams }
    }
}
