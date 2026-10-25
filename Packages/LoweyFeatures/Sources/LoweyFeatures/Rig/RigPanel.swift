import HmmDesign
import LoweyCore
import SwiftUI

/// Rig: give the selected thing a skeleton and pose it. Bones → Skin → Pose for anything with a surface; a character's
/// saved poses and its clips. Characters themselves (a Blob, Me, a Puppet) come from the Library; what a character
/// does live (expressions, the voice, the face, triggers) is performed in the timeline's Perform.
struct RigPanel: View {
    @Bindable var editor: EditorModel

    var body: some View {
        HmmPanel("Rig", width: 360, sizing: HmmPanelSizing(id: "rig"), movable: true, close: { editor.openPanel = nil }) {
            VStack(alignment: .leading, spacing: HmmSpacing.m) {
                if editor.selection.isEmpty {
                    nothingSelected
                } else {
                    RigSection(editor: editor)
                    if let character = currentCharacter { CharacterSections(editor: editor, character: character) }
                    PartSection(editor: editor)
                }
            }
        }
    }

    private var currentCharacter: ObjectID? {
        editor.selectedPuppet ?? editor.selectedCharacter?.object.id
            ?? editor.selection.first.flatMap { editor.isBlob($0) || editor.baseScene.objects[$0]?.rig != nil ? $0 : nil }
            ?? editor.rigSubject.flatMap { $0.rig != nil ? $0.id : nil }
    }

    private var nothingSelected: some View {
        VStack(alignment: .leading, spacing: HmmSpacing.s) {
            Hint("Select something to rig it: a drawing, a shape, a model. A ready-made character (a Blob, you, a Puppet) is in the Library.")
            HmmPillButton("Open the Library", systemName: "books.vertical") { editor.openPanel = .library }
                .accessibilityIdentifier("rig-open-library")
        }
    }
}

/// What a rigged character keeps: its poses and its clips.
struct CharacterSections: View {
    @Bindable var editor: EditorModel
    let character: ObjectID

    var body: some View {
        VStack(alignment: .leading, spacing: HmmSpacing.m) {
            if PoseLibrary.character(of: character, in: editor.baseScene, rigs: editor.libraryRigs()) == character {
                PoseSection(editor: editor, character: character)
            }
            ClipsSection(editor: editor, character: character)
            if editor.castType(of: character) == .puppet {
                HmmPillButton("Edit this puppet", systemName: "person.crop.circle") {
                    editor.characterBuilderTarget = character
                    editor.openPanel = nil
                    editor.sheet = .characterBuilder
                }
            }
        }
    }
}
