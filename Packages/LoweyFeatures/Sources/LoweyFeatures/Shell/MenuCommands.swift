import HmmBoardUI
import HmmCommands
import HmmDesign
import LoweyCore
import LoweyEngine
import SwiftUI

/// The menu bar (iPadOS 26) with every keyboard shortcut. It acts on the open project.
public struct LoweyMenuCommands: Commands {
    let app: AppModel
    @Environment(\.openWindow) private var openWindow

    public init(app: AppModel) {
        self.app = app
    }

    private var editor: EditorModel? { app.editor }
    /// The keys, as Settings ▸ Keyboard set them (U8).
    private var keyboard: HmmKeyboard { app.keyboard }
    /// The board, while it covers the stage: the Edit menu acts on it then.
    private var board: BoardModel? { editor?.boardShown == true ? editor?.board : nil }

    public var body: some Commands {
        CommandGroup(replacing: .undoRedo) {
            Button(editor?.canUndo == true && board == nil ? editor?.undoTitle ?? "Undo" : "Undo") { undo() }
                .hmmKeyboardShortcut(KeyCommands.editUndo, in: keyboard)
                .disabled(board.map { !$0.session.canUndo } ?? (editor?.canUndo != true))
            Button(editor?.canRedo == true && board == nil ? editor?.redoTitle ?? "Redo" : "Redo") { redo() }
                .hmmKeyboardShortcut(KeyCommands.editRedo, in: keyboard)
                .disabled(board.map { !$0.session.canRedo } ?? (editor?.canRedo != true))
        }
        CommandGroup(replacing: .pasteboard) {
            Button("Copy") { copy() }.hmmKeyboardShortcut(KeyCommands.editCopy, in: keyboard)
            Button("Paste") { paste() }.hmmKeyboardShortcut(KeyCommands.editPaste, in: keyboard)
            Button("Duplicate") { duplicate() }.hmmKeyboardShortcut(KeyCommands.editDuplicate, in: keyboard)
            Button("Delete") { delete() }.hmmKeyboardShortcut(KeyCommands.editDelete, in: keyboard)
            Divider()
            Button("Select All") { selectAll() }.hmmKeyboardShortcut(KeyCommands.editSelectAll, in: keyboard)
            Button("Select Similar") { editor?.selectSimilar() }
                .hmmKeyboardShortcut(KeyCommands.editSelectSimilar, in: keyboard).disabled(board != nil)
            Button("Group") { editor?.groupSelection() }.hmmKeyboardShortcut(KeyCommands.editGroup, in: keyboard).disabled(board != nil)
            Button("Ungroup") { editor?.ungroupSelection() }.hmmKeyboardShortcut(KeyCommands.editUngroup, in: keyboard).disabled(board != nil)
        }
        // The making tools in the order of the top-right cluster, then the document's panels.
        CommandMenu("Tools") {
            Button("Model") { panel(.model) }.hmmKeyboardShortcut(KeyCommands.toolsModel, in: keyboard)
            Button("Draw") { stageEditor?.toggleDraw() }.hmmKeyboardShortcut(KeyCommands.toolsDraw, in: keyboard)
            Button("Rig") { panel(.rig) }.hmmKeyboardShortcut(KeyCommands.toolsRig, in: keyboard)
            Button("Animate") { editor?.toggleAnimate() }.hmmKeyboardShortcut(KeyCommands.toolsAnimate, in: keyboard)
            Divider()
            Button("Actions") { panel(.actions) }.hmmKeyboardShortcut(KeyCommands.toolsActions, in: keyboard)
            Button("Look") { panel(.look) }.hmmKeyboardShortcut(KeyCommands.toolsLook, in: keyboard)
            Button("Lasso") { tool(.lasso, panel: nil) }.hmmKeyboardShortcut(KeyCommands.toolsLasso, in: keyboard)
            Button("Library") { panel(.library) }.hmmKeyboardShortcut(KeyCommands.toolsLibrary, in: keyboard)
            Divider()
            Button("Precision") { modelPage(.precision) }.hmmKeyboardShortcut(KeyCommands.toolsPrecision, in: keyboard)
            Button("Solid Shape") { stageEditor?.chooseDrawBrush(.solid(.tube)) }.hmmKeyboardShortcut(KeyCommands.toolsSolidShape, in: keyboard)
            Button("Frames") { stageEditor?.setDrawFrames(true) }.hmmKeyboardShortcut(KeyCommands.toolsFrames, in: keyboard)
            Button("Shadow Brush") { stageEditor?.chooseDrawBrush(.shadow(pushes: true)) }
                .hmmKeyboardShortcut(KeyCommands.toolsShadowBrush, in: keyboard)
            Button("Scatter") { tool(.scatter, panel: nil) }.hmmKeyboardShortcut(KeyCommands.toolsScatter, in: keyboard)
            Divider()
            Button("Move") { gizmo(.move) }.hmmKeyboardShortcut(KeyCommands.toolsMove, in: keyboard)
            Button("Turn") { gizmo(.rotate) }.hmmKeyboardShortcut(KeyCommands.toolsTurn, in: keyboard)
            Button("Size") { gizmo(.scale) }.hmmKeyboardShortcut(KeyCommands.toolsSize, in: keyboard)
        }
        CommandMenu("Shape") {
            Button("Shape by Touch") { stageEditor?.chooseModelVerb(.shape) }.hmmKeyboardShortcut(KeyCommands.shapeShapeByTouch, in: keyboard)
            Button("Brush the Surface") { stageEditor?.chooseModelVerb(.brush) }.hmmKeyboardShortcut(KeyCommands.shapeBrushTheSurface, in: keyboard)
            Button("Cage") { stageEditor?.chooseModelVerb(.cage) }.hmmKeyboardShortcut(KeyCommands.shapeCage, in: keyboard)
            Button("Bend") { stageEditor?.chooseModelVerb(.bend) }.hmmKeyboardShortcut(KeyCommands.shapeBend, in: keyboard)
            Divider()
            Button("Smooth More") { smooth(by: 1) }
                .hmmKeyboardShortcut(KeyCommands.shapeSmoothMore, in: keyboard)
            Button("Smooth Less") { smooth(by: -1) }
                .hmmKeyboardShortcut(KeyCommands.shapeSmoothLess, in: keyboard)
            Button("Loop Cut") { stageEditor?.loopCutPickedEdge() }.hmmKeyboardShortcut(KeyCommands.shapeLoopCut, in: keyboard)
            Button("Linked Copy") { stageEditor?.makeLinkedCopy() }.hmmKeyboardShortcut(KeyCommands.shapeLinkedCopy, in: keyboard)
            Divider()
            Button("Clone") { stageEditor?.cloneSelection() }.hmmKeyboardShortcut(KeyCommands.shapeClone, in: keyboard)
            Button("Morph Into…") { stageEditor?.beginMorph() }.hmmKeyboardShortcut(KeyCommands.shapeMorphInto, in: keyboard)
            Button("Pivot to the Middle") { stageEditor?.movePivot(to: .middle) }.hmmKeyboardShortcut(KeyCommands.shapePivotToTheMiddle, in: keyboard)
        }
        CommandMenu("Texture") {
            // U7: the surface's tools, for the keyboard.
            Button("Paint Flat") { stageEditor?.colourPaint.flatView = true }.hmmKeyboardShortcut(KeyCommands.texturePaintFlat, in: keyboard)
            Button("Add Dirt") { stageEditor?.addFill(.wear(PaintWear(kind: .dirt))) }.hmmKeyboardShortcut(KeyCommands.textureAddDirt, in: keyboard)
            Button("Add Worn Edges") { stageEditor?.addFill(.wear(PaintWear(kind: .edges))) }
                .hmmKeyboardShortcut(KeyCommands.textureAddWornEdges, in: keyboard)
            Button("Mirror Paint") { stageEditor?.togglePaintMirror() }.hmmKeyboardShortcut(KeyCommands.textureMirrorPaint, in: keyboard)
            Button("Fill Faces") { stageEditor?.toggleFacesBrush() }.hmmKeyboardShortcut(KeyCommands.textureFillFaces, in: keyboard)
        }
        CommandMenu("Look") {
            // L2: the Looks one after another, and the drawn set at the playhead (aimed at the selection).
            Button("Next Look") { stageEditor?.stepLook(by: 1) }.hmmKeyboardShortcut(KeyCommands.lookNextLook, in: keyboard)
            Button("Previous Look") { stageEditor?.stepLook(by: -1) }.hmmKeyboardShortcut(KeyCommands.lookPreviousLook, in: keyboard)
            Divider()
            Button("Impact Frame") { stageEditor?.addScreenEffect(.impact) }.hmmKeyboardShortcut(KeyCommands.lookImpactFrame, in: keyboard)
            Button("Focus Lines") { stageEditor?.addScreenEffect(.focusLines) }.hmmKeyboardShortcut(KeyCommands.lookFocusLines, in: keyboard)
            Button("Kirby Dots") { stageEditor?.addScreenEffect(.kirbyDots) }.hmmKeyboardShortcut(KeyCommands.lookKirbyDots, in: keyboard)
        }
        CommandMenu("Physics") {
            Button("Make Real") { stageEditor?.makeReal() }.hmmKeyboardShortcut(KeyCommands.physicsMakeReal, in: keyboard)
            Button("Not Real") { stageEditor?.makeUnreal() }.hmmKeyboardShortcut(KeyCommands.physicsNotReal, in: keyboard)
            Button("Settle") { stageEditor?.settleSelection() }.hmmKeyboardShortcut(KeyCommands.physicsSettle, in: keyboard)
            Button("Does It Stand?") { stageEditor?.checkStands() }.hmmKeyboardShortcut(KeyCommands.physicsDoesItStand, in: keyboard)
            Button("Keep the Run as Keys") { stageEditor?.keepRun() }.hmmKeyboardShortcut(KeyCommands.physicsKeepTheRunAsKeys, in: keyboard)
            Button("Show Speed and Forces") { stageEditor.map { $0.physicsRun.showsArrows.toggle(); $0.refreshPhysicsOverlay() } }
                .hmmKeyboardShortcut(KeyCommands.physicsShowSpeedAndForces, in: keyboard)
        }
        CommandMenu("Character") {
            Button("New Character…") {
                editor?.libraryPage = .characters
                editor?.openPanel = .library
            }
            .hmmKeyboardShortcut(KeyCommands.characterNewCharacter, in: keyboard)
            Button("New Person") { editor?.newCharacter(.person) }.hmmKeyboardShortcut(KeyCommands.characterNewPerson, in: keyboard)
            Button("New Four-Legged") { editor?.newCharacter(.fourLegs) }.hmmKeyboardShortcut(KeyCommands.characterNewFourLegged, in: keyboard)
            Button("New Creature from Nothing") { editor?.newCharacter(.nothing) }
                .hmmKeyboardShortcut(KeyCommands.characterNewCreatureFromNothing, in: keyboard)
            Divider()
            Button(editor?.maker.symmetric == false ? "Mirror Parts" : "Stop Mirroring Parts") { editor?.maker.symmetric.toggle() }
                .hmmKeyboardShortcut(KeyCommands.characterMirrorParts, in: keyboard)
            Button("Rig It Again") { editor.map { editor in editor.makerCharacter.map { editor.rigAgain($0, gesture: nil) } } }
                .disabled(editor?.makerCharacter == nil).hmmKeyboardShortcut(KeyCommands.characterRigItAgain, in: keyboard)
            Button("Export for Games…") { editor?.sheet = .gameExport }.hmmKeyboardShortcut(KeyCommands.characterExportForGames, in: keyboard)
        }
        CommandMenu("Kit") {
            Section("Room") {
                Button("Plans and Elevations") { editor?.sheet = .plans }.hmmKeyboardShortcut(KeyCommands.kitPlansAndElevations, in: keyboard)
                Button("Walk Through") { editor.map { $0.guest.walkHeight == nil ? $0.startWalking() : $0.stopWalking() } }
                    .hmmKeyboardShortcut(KeyCommands.kitWalkThrough, in: keyboard)
                Button("Match a Photo…") { editor?.sheet = .matchPhoto }.hmmKeyboardShortcut(KeyCommands.kitMatchAPhoto, in: keyboard)
            }
            Section("Print") {
                Button("Best Way Up") { stageEditor?.orientForPrinting() }.hmmKeyboardShortcut(KeyCommands.kitBestWayUp, in: keyboard)
                Button("Split for Printing") { stageEditor?.splitForPrinting() }.hmmKeyboardShortcut(KeyCommands.kitSplitForPrinting, in: keyboard)
                Button("Hollow") { stageEditor?.hollowForPrinting() }.hmmKeyboardShortcut(KeyCommands.kitHollow, in: keyboard)
                Button("Show Overhangs") { stageEditor?.guest.overhangs.toggle() }.hmmKeyboardShortcut(KeyCommands.kitShowOverhangs, in: keyboard)
            }
            Section("Study") {
                Button("Explode") { stageEditor?.toggleExplode() }.hmmKeyboardShortcut(KeyCommands.kitExplode, in: keyboard)
            }
            Section("Game") {
                Button("Freeze Transforms") { stageEditor?.freezeTransforms() }.hmmKeyboardShortcut(KeyCommands.kitFreezeTransforms, in: keyboard)
            }
        }
        CommandMenu("Scene") {
            Button("Frame Selection") { editor?.frameSelection() }.hmmKeyboardShortcut(KeyCommands.sceneFrameSelection, in: keyboard)
            Button("Director View") { editor.map { $0.setDirectorView(!$0.directorView) } }
                .hmmKeyboardShortcut(KeyCommands.sceneDirectorView, in: keyboard)
            Button("Fly the Camera") { editor.map { $0.flying ? $0.stopFlying() : $0.startFlying() } }
                .hmmKeyboardShortcut(KeyCommands.sceneFlyTheCamera, in: keyboard)
            Button("Hide Interface") { editor?.chromeHidden.toggle() }.hmmKeyboardShortcut(KeyCommands.sceneHideInterface, in: keyboard)
            Divider()
            Button("History and Steps") { editor?.openHistory() }.hmmKeyboardShortcut(KeyCommands.sceneHistoryAndSteps, in: keyboard)
            Button("Export…") { editor?.sheet = .export }.hmmKeyboardShortcut(KeyCommands.sceneExport, in: keyboard)
            Button("Close the Loop") { stageEditor?.closeTheLoop() }.hmmKeyboardShortcut(KeyCommands.sceneCloseTheLoop, in: keyboard)
            Button("Paste a Scene Script") { editor?.importScriptFromClipboard() }
                .hmmKeyboardShortcut(KeyCommands.scenePasteASceneScript, in: keyboard)
            Button("AI & Laptop Bridge…") { editor?.sheet = .bridge }.hmmKeyboardShortcut(KeyCommands.sceneAiLaptopBridge, in: keyboard)
            Button("Scripts…") { editor?.openScript(nil) }.hmmKeyboardShortcut(KeyCommands.sceneScripts, in: keyboard)
            Divider()
            // U8: show it, write on it, hand it to the iPhone.
            Button("Present") { stageEditor.map { $0.together.presenting == nil ? $0.startPresenting() : $0.stopPresenting() } }
                .hmmKeyboardShortcut(KeyCommands.scenePresent, in: keyboard)
            Button("Notes") { stageEditor.map { $0.setNotesShown(!$0.together.notesShown) } }
                .hmmKeyboardShortcut(KeyCommands.sceneNotes, in: keyboard)
            Button("Your iPhone…") { editor?.sheet = .phone }
                .hmmKeyboardShortcut(KeyCommands.sceneYourIPhone, in: keyboard)
            Divider()
            Button("New Monitor Window") { openWindow(id: LoweyWindow.monitor) }.hmmKeyboardShortcut(KeyCommands.sceneNewMonitorWindow, in: keyboard)
        }
        CommandMenu("Timeline") {
            Button(editor?.timelinePresence == .hidden ? "Show Timeline" : "Hide Timeline") { editor?.toggleTimeline() }
                .hmmKeyboardShortcut(KeyCommands.timelineShowTimeline, in: keyboard)
            Button("Play / Pause") { editor?.togglePlay() }.hmmKeyboardShortcut(KeyCommands.timelinePlayPause, in: keyboard)
            Button("Key the Selection") { editor?.keySelection() }.hmmKeyboardShortcut(KeyCommands.timelineKeyTheSelection, in: keyboard)
            Button("Record a Performance") { editor?.armPerform() }.hmmKeyboardShortcut(KeyCommands.timelineRecordAPerformance, in: keyboard)
            Button("Add Marker") { editor?.addMarker() }.hmmKeyboardShortcut(KeyCommands.timelineAddMarker, in: keyboard)
            Divider()
            Button("Audio & Words…") { editor?.sheet = .audio }.hmmKeyboardShortcut(KeyCommands.timelineAudioWords, in: keyboard)
            Button("Transcript") { editor?.sheet = .transcript }.hmmKeyboardShortcut(KeyCommands.timelineTranscript, in: keyboard)
            Button("Record Voiceover") { editor?.toggleVoiceRecording() }.hmmKeyboardShortcut(KeyCommands.timelineRecordVoiceover, in: keyboard)
            Divider()
            Button("Select All Keys") { editor?.selectKeys(.all) }.hmmKeyboardShortcut(KeyCommands.timelineSelectAllKeys, in: keyboard)
            Button("Keys After the Playhead") { editor?.selectKeys(.afterPlayhead) }
                .hmmKeyboardShortcut(KeyCommands.timelineKeysAfterThePlayhead, in: keyboard)
            Button("Keys at the Playhead") { editor?.selectKeys(.atPlayhead) }
                .hmmKeyboardShortcut(KeyCommands.timelineKeysAtThePlayhead, in: keyboard)
            Divider()
            // Animate's bar (A1).
            Button("Draw a Path") { animateVerb(.path) }.hmmKeyboardShortcut(KeyCommands.timelineDrawAPath, in: keyboard)
            Button("Look At…") { animateVerb(.lookAt) }.hmmKeyboardShortcut(KeyCommands.timelineLookAt, in: keyboard)
            Button("Pick Up or Hand Off…") { animateVerb(.pickUp) }.hmmKeyboardShortcut(KeyCommands.timelinePickUpOrHandOff, in: keyboard)
            Button("Even Speed") { stageEditor?.evenSpeed() }
                .disabled(stageEditor?.motionDuration == nil)
                .hmmKeyboardShortcut(KeyCommands.timelineEvenSpeed, in: keyboard)
            Button(editor?.animate.ghosts == false ? "Show Ghosts While Scrubbing" : "Hide Ghosts While Scrubbing") { editor?.animate.ghosts.toggle() }
                .hmmKeyboardShortcut(KeyCommands.timelineGhosts, in: keyboard)
            Button(editor?.timelineStyle == .dopeSheet ? "Show Motion" : "Show the Dope Sheet") {
                guard let editor = stageEditor else { return }
                editor.timelineStyle = editor.timelineStyle == .dopeSheet ? .motion : .dopeSheet
                editor.timelinePresence = .full
            }
            .hmmKeyboardShortcut(KeyCommands.timelineDopeSheet, in: keyboard)
            Divider()
            // The lens and the frame (F1).
            Button("Lens and Frame…") { editor?.showsLensPanel = true }
                .hmmKeyboardShortcut(KeyCommands.timelineLensAndFrame, in: keyboard)
                .disabled(editor?.editedCamera == nil)
            Button("Focus on the Selection") { editor?.focusOnSelection(pull: false) }
                .hmmKeyboardShortcut(KeyCommands.timelineFocusOnTheSelection, in: keyboard)
            Button("Pull Focus to the Selection") { editor?.focusOnSelection(pull: true) }
                .hmmKeyboardShortcut(KeyCommands.timelinePullFocusToTheSelection, in: keyboard)
        }
        // Live performance airs as 1.2 (held in App Store builds until then).
        if Held.isOn(.livePerformance) {
            CommandMenu("Perform") {
                Button(editor?.live.voiceOn == true ? "Stop the Microphone" : "Mouth from the Microphone") { editor?.toggleVoice() }
                    .hmmKeyboardShortcut(KeyCommands.performMicrophone, in: keyboard)
                Divider()
                ForEach(TriggerDeck.keys, id: \.self) { key in
                    Button("Trigger \(key)") { editor?.fireTriggerKey(key) }
                        .keyboardShortcut(KeyEquivalent(Character(key)), modifiers: [])
                        .disabled(board != nil || editor?.hasTrigger(key: key) != true)
                }
            }
        }
    }

    private func undo() {
        if let board { board.undo() } else { editor?.undo() }
    }

    private func redo() {
        if let board { board.redo() } else { editor?.redo() }
    }

    private func copy() {
        if let board { board.copySelection() } else { editor?.copySelection() }
    }

    private func paste() {
        if let board { board.paste() } else { editor?.paste() }
    }

    private func duplicate() {
        if let board { board.duplicateSelection() } else { editor?.duplicateSelection() }
    }

    private func delete() {
        if let board { board.deleteSelection() } else { editor?.deleteSelection() }
    }

    private func selectAll() {
        if let board {
            board.mutate { session in
                session.tool = .select
                session.selectAll()
            }
        } else {
            editor?.selectAll()
        }
    }

    /// The stage under an open board, for the menus that only make sense on the stage.
    private var stageEditor: EditorModel? { editor?.boardShown == true ? nil : editor }

    private func smooth(by step: Int) {
        guard let editor = stageEditor, let object = editor.shapedSelection else { return }
        editor.setSmooth(editor.smoothLevels(of: object) + step)
    }

    private func panel(_ panel: ClusterPanel) {
        guard let editor = stageEditor else { return }
        editor.openPanel = editor.openPanel == panel ? nil : panel
    }

    private func tool(_ tool: StageTool, panel: ClusterPanel?) {
        guard let editor = stageEditor else { return }
        editor.tool = tool
        if let panel { editor.openPanel = panel }
    }

    /// An Animate verb, opening Animate first.
    private func animateVerb(_ verb: AnimateVerb) {
        guard let editor = stageEditor else { return }
        if !editor.animatesNow { editor.toggleAnimate() }
        editor.chooseAnimateVerb(verb)
    }

    private func modelPage(_ page: ModelPage) {
        guard let editor = stageEditor else { return }
        editor.modelPage = page
        editor.openPanel = .model
    }

    private func gizmo(_ mode: GizmoMode) {
        guard let editor = stageEditor else { return }
        editor.tool = .select
        editor.gizmoMode = mode
    }
}
