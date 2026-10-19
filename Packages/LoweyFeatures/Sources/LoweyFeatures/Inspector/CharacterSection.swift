import HmmDesign
import LoweyCore
import SwiftUI

/// A made character's panel (K1): its parts first, the picked part's styles under them, and one step deeper its face,
/// its proportions, a line to say, acting it out and the game exports. On any other thing, "Give it parts" (a teapot
/// gets hands, a rock gets eyes); on a drawing or a modelled thing near a character, "Make it a part".
struct CharacterSection: View {
    @Bindable var editor: EditorModel
    let object: SceneObject
    @Environment(\.hmmTheme) private var theme

    var body: some View {
        if editor.makerCharacter != nil {
            parts
            if let part = editor.selectedPart?.part { styles(part) }
            VStack(alignment: .leading, spacing: 0) {
                DisclosureRow("Face", systemName: "face.smiling", identifier: "character-face") { CharacterFaceSection(editor: editor) }
                DisclosureRow("Proportions", systemName: "ruler", identifier: "character-proportions") { CharacterProportionsSection(editor: editor) }
                DisclosureRow("Say a line", systemName: "text.bubble", identifier: "character-say") { SayLineSection(editor: editor) }
                if editor.canActOut {
                    DisclosureRow("Act it out", systemName: "figure.dance", identifier: "character-act") { ActOutSection(editor: editor) }
                }
                DisclosureRow("For games", systemName: "gamecontroller", identifier: "character-games") {
                    HmmPillButton("Engines, sprite sheets, turnaround…", systemName: "square.and.arrow.up") { editor.sheet = .gameExport }
                        .accessibilityIdentifier("character-game-export")
                }
            }
        } else if object.kind.hasSurface || object.kind == .group {
            VStack(alignment: .leading, spacing: 0) {
                if object.kind.isDrawingKind || object.kind.isMeshKind, editor.nearestCharacter(to: object.id) != nil {
                    DisclosureRow("Make it a part", systemName: "puzzlepiece", identifier: "character-assign") { MakeItAPart(editor: editor, object: object) }
                }
                DisclosureRow("Give it parts", systemName: "eyes", identifier: "character-give") { parts }
            }
        }
    }

    /// Every job, a tap away: it adds that part (a mirrored pair when Mirrored is on).
    private var parts: some View {
        VStack(alignment: .leading, spacing: HmmSpacing.xs) {
            HStack {
                Text("Parts").font(.hmm(.footnote, weight: .semibold)).foregroundStyle(theme.text2)
                Spacer()
                ChoiceChip(title: "Mirrored", systemName: "arrow.left.and.right.righttriangle.left.righttriangle.right", isOn: editor.maker.symmetric) {
                    editor.maker.symmetric.toggle()
                }
                .accessibilityIdentifier("character-mirrored")
            }
            TileGrid(minimum: 64) {
                ForEach(CharacterPart.Job.allCases) { job in
                    TileButton(title: job.title, systemName: job.systemImage, identifier: "add-part-\(job.rawValue)") { editor.addPart(job) }
                        .hmmHoldMenu(HmmHoldMenu(extras: [HmmHoldMenu.Item(
                            "Add as…",
                            systemName: "square.grid.2x2",
                            children: PartSet.styles(for: job).map { style in
                                HmmHoldMenu.Item(style.title, id: style.id, systemName: job.systemImage) { editor.addPart(job, style: style.name) }
                            }
                        )]))
                }
            }
        }
    }

    /// The picked part's styles from the set, and taking it away.
    private func styles(_ part: CharacterPart) -> some View {
        VStack(alignment: .leading, spacing: HmmSpacing.xs) {
            Text(part.job.title).font(.hmm(.footnote, weight: .semibold)).foregroundStyle(theme.text2)
            if PartSet.styles(for: part.job).contains(where: { $0.name == part.style }) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: HmmSpacing.xs) {
                        ForEach(PartSet.styles(for: part.job)) { style in
                            ChoiceChip(title: style.title, isOn: style.name == part.style) { editor.restyleSelectedPart(style.name) }
                                .accessibilityIdentifier("part-style-\(style.name)")
                        }
                    }
                }
            }
            HStack(spacing: HmmSpacing.xs) {
                HmmPillButton("Take it away", systemName: "minus.circle") { editor.removeSelectedPart() }
                    .accessibilityIdentifier("remove-part")
                // Kept in Yours (L2): it goes onto any character from Library ▸ Yours ▸ Parts.
                if let id = editor.selectedPart?.id {
                    HmmPillButton("Save to Yours", systemName: "tray.and.arrow.down") { Task { await editor.savePartToYours(id) } }
                        .accessibilityIdentifier("part-save-yours")
                }
            }
        }
    }
}

/// A drawn or modelled thing becomes a part of the character nearest it: as the part, or as the drawing of one of its
/// face states (the mouth's Oh, a blink).
struct MakeItAPart: View {
    let editor: EditorModel
    let object: SceneObject
    @State private var job: CharacterPart.Job = .mouth

    var body: some View {
        VStack(alignment: .leading, spacing: HmmSpacing.s) {
            Picker("Part", selection: $job) {
                ForEach(CharacterPart.Job.allCases) { Text(LocalizedStringKey($0.title)).tag($0) }
            }
            .pickerStyle(.menu)
            HmmPillButton("Make it the \(job.title.lowercased())", systemName: "puzzlepiece", prominent: true) { editor.makeSelectionPart(job) }
                .accessibilityIdentifier("make-it-part")
            if !FaceStates.names(for: job).isEmpty {
                Text("Or the drawing of one face:").font(.hmm(.footnote))
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: HmmSpacing.xs) {
                        ForEach(FaceStates.names(for: job).dropFirst(), id: \.self) { state in
                            ChoiceChip(title: FaceStates.title(state), isOn: false) { editor.makeSelectionPart(job, shows: state) }
                                .accessibilityIdentifier("make-it-state-\(state)")
                        }
                    }
                }
            }
        }
    }
}

extension ObjectKind {
    var isDrawingKind: Bool {
        if case .drawing = self { return true }
        return false
    }

    var isMeshKind: Bool {
        switch self {
        case .mesh, .primitive: true
        default: false
        }
    }
}
