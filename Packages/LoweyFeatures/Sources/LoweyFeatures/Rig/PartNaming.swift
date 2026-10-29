import HmmDesign
import LoweyCore
import SwiftUI

/// Under the stage while a character's parts are named (Q2): what the tapped piece or circled area is, or, with nothing
/// waiting, the face parts it has none of yet (ours only fill gaps) and Done.
struct PartNamingBar: View {
    @Bindable var editor: EditorModel

    var body: some View {
        if editor.rigging.naming != nil {
            ForEach(editor.namingJobs) { job in
                HmmPillButton(job.label, systemName: job.systemImage, prominent: job == .eye || job == .mouth) { editor.nameWaitingPart(job) }
                    .accessibilityIdentifier("name-part-\(job.rawValue)")
            }
            HmmButton("xmark", label: "Cancel", size: 36) { editor.rigging.naming = nil }
        } else {
            if editor.missingFaceParts.contains(.eye) {
                HmmPillButton("No eyes yet: add them", systemName: CharacterPart.Job.eye.systemImage) { editor.addPart(.eye) }
                    .accessibilityIdentifier("add-missing-eye")
            }
            if editor.missingFaceParts.contains(.mouth) {
                HmmPillButton("No mouth yet: add one", systemName: CharacterPart.Job.mouth.systemImage) { editor.addPart(.mouth) }
                    .accessibilityIdentifier("add-missing-mouth")
            }
            HmmButton("checkmark", label: "Done", size: 36) { editor.tool = .select }
                .accessibilityIdentifier("parts-done")
        }
    }
}

extension CharacterPart.Job {
    /// One part's name (the jobs' titles are plural, for the maker's lists).
    var label: String {
        switch self {
        case .head: "Head"
        case .eye: "Eye"
        case .brow: "Brow"
        case .mouth: "Mouth"
        case .nose: "Nose"
        case .ear: "Ear"
        case .hair: "Hair"
        case .body: "Body"
        case .arm: "Arm"
        case .leg: "Leg"
        case .tail: "Tail"
        case .wing: "Wing"
        case .extra: "Extra"
        }
    }
}

/// The labels a character's named pieces and areas wear on the stage while its parts are named.
struct PartLabelsOverlay: View {
    let editor: EditorModel

    var body: some View {
        let revision = editor.displayRevision + Int(editor.viewYaw)
        let labels = revision >= 0 ? editor.partLabelsOnScreen() : []
        ZStack {
            ForEach(labels.indices, id: \.self) { index in
                let item = labels[index]
                HStack(spacing: 2) {
                    Text(LocalizedStringKey(item.label.job.label))
                    if item.label.side != .middle {
                        // The character's own left or right.
                        Text(verbatim: item.label.side == .left ? "L" : "R").opacity(0.7)
                    }
                }
                .font(.hmm(.caption, weight: .semibold))
                .padding(.horizontal, HmmSpacing.xs)
                .padding(.vertical, 2)
                .background(Capsule().fill(.ultraThinMaterial))
                .position(item.point)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("part-label-\(item.label.job.rawValue)")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
