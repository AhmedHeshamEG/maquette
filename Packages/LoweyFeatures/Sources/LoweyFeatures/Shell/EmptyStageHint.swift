import HmmDesign
import SwiftUI

/// The first open (Q2): a new project's stage says, once, quietly, where things come from. It goes as soon as anything
/// is on the stage or a tool is in the hand, and never shows with Settings' instructions off.
struct EmptyStageHint: View {
    @AppStorage(HmmInstructions.storageKey) private var showsInstructions = true
    @Environment(\.hmmTheme) private var theme

    var body: some View {
        if showsInstructions {
            VStack(spacing: HmmSpacing.xs) {
                Text("An empty stage")
                    .font(.hmm(.headline, weight: .semibold))
                    .foregroundStyle(theme.text)
                Text("Model adds a shape, Draw sketches with the Pencil, the Library has ready-made things.")
                    .font(.hmm(.caption))
                    .foregroundStyle(theme.text2)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: 320)
            .padding(HmmSpacing.m)
            .background(RoundedRectangle(cornerRadius: 16).fill(.ultraThinMaterial).opacity(0.6))
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("empty-stage-hint")
        }
    }
}

extension EditorModel {
    /// Nothing on the stage yet and nothing in the hand: the first open.
    var stageIsEmpty: Bool {
        baseScene.objects.isEmpty && baseScene.sheets.isEmpty && tool == .select && openPanel == nil && !isDrawing
    }
}
