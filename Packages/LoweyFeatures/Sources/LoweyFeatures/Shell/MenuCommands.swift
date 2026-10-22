import HmmBoardUI
import HmmCommands
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
    /// The board, while it covers the stage: the Edit menu acts on it then.
    private var board: BoardModel? { editor?.boardShown == true ? editor?.board : nil }

    public var body: some Commands {
        CommandGroup(replacing: .undoRedo) {
            Button(editor?.canUndo == true && board == nil ? editor?.undoTitle ?? "Undo" : "Undo") { undo() }
                .keyboardShortcut("z", modifiers: .command)
                .disabled(board.map { !$0.session.canUndo } ?? (editor?.canUndo != true))
            Button(editor?.canRedo == true && board == nil ? editor?.redoTitle ?? "Redo" : "Redo") { redo() }
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .disabled(board.map { !$0.session.canRedo } ?? (editor?.canRedo != true))
        }
        CommandGroup(replacing: .pasteboard) {
            Button("Copy") { copy() }.keyboardShortcut("c", modifiers: .command)
            Button("Paste") { paste() }.keyboardShortcut("v", modifiers: .command)
            Button("Duplicate") { duplicate() }.keyboardShortcut("d", modifiers: .command)
            Button("Delete") { delete() }.keyboardShortcut(.delete, modifiers: .command)
            Divider()
            Button("Select All") { selectAll() }.keyboardShortcut("a", modifiers: .command)
            Button("Select Similar") { editor?.selectSimilar() }.keyboardShortcut("a", modifiers: [.command, .shift]).disabled(board != nil)
            Button("Group") { editor?.groupSelection() }.keyboardShortcut("g", modifiers: .command).disabled(board != nil)
            Button("Ungroup") { editor?.ungroupSelection() }.keyboardShortcut("g", modifiers: [.command, .shift]).disabled(board != nil)
        }
        // The making tools in the order of the top-right cluster, then the document's panels.
        CommandMenu("Tools") {
            Button("Model") { panel(.model) }.keyboardShortcut("1", modifiers: .command)
            Button("Draw") { stageEditor?.toggleDraw() }.keyboardShortcut("2", modifiers: .command)
            Button("Rig") { panel(.rig) }.keyboardShortcut("3", modifiers: .command)
            Button("Animate") { editor?.toggleAnimate() }.keyboardShortcut("4", modifiers: .command)
            Divider()
            Button("Actions") { panel(.actions) }.keyboardShortcut("6", modifiers: .command)
            Button("Look") { panel(.look) }.keyboardShortcut("7", modifiers: .command)
            Button("Lasso") { tool(.lasso, panel: nil) }.keyboardShortcut("8", modifiers: .command)
            Button("Library") { panel(.library) }.keyboardShortcut("l", modifiers: .command)
            Divider()
            Button("Precision") { modelPage(.precision) }
            Button("Solid Shape") { stageEditor?.chooseDrawBrush(.solid(.tube)) }
            Button("Frames") { stageEditor?.setDrawFrames(true) }
            Button("Shadow Brush") { stageEditor?.chooseDrawBrush(.shadow(pushes: true)) }
            Button("Scatter") { tool(.scatter, panel: nil) }
            Divider()
            Button("Move") { gizmo(.move) }.keyboardShortcut("1", modifiers: [.command, .option])
            Button("Turn") { gizmo(.rotate) }.keyboardShortcut("2", modifiers: [.command, .option])
            Button("Size") { gizmo(.scale) }.keyboardShortcut("3", modifiers: [.command, .option])
        }
        CommandMenu("Shape") {
            Button("Shape by Touch") { stageEditor?.chooseModelVerb(.shape) }.keyboardShortcut("1", modifiers: [.command, .shift])
            Button("Brush the Surface") { stageEditor?.chooseModelVerb(.brush) }.keyboardShortcut("2", modifiers: [.command, .shift])
            Button("Cage") { stageEditor?.chooseModelVerb(.cage) }.keyboardShortcut("3", modifiers: [.command, .shift])
            Button("Bend") { stageEditor?.chooseModelVerb(.bend) }.keyboardShortcut("4", modifiers: [.command, .shift])
            Divider()
            Button("Smooth More") { smooth(by: 1) }
                .keyboardShortcut("]", modifiers: .command)
            Button("Smooth Less") { smooth(by: -1) }
                .keyboardShortcut("[", modifiers: .command)
            Button("Loop Cut") { stageEditor?.loopCutPickedEdge() }.keyboardShortcut("r", modifiers: [.command, .control])
            Button("Linked Copy") { stageEditor?.makeLinkedCopy() }.keyboardShortcut("d", modifiers: [.command, .shift])
            Divider()
            Button("Clone") { stageEditor?.cloneSelection() }.keyboardShortcut("c", modifiers: [.command, .control])
            Button("Morph Into…") { stageEditor?.beginMorph() }.keyboardShortcut("o", modifiers: [.command, .control])
            Button("Pivot to the Middle") { stageEditor?.movePivot(to: .middle) }
        }
        CommandMenu("Texture") {
            // U7: the surface's tools, for the keyboard.
            Button("Paint Flat") { stageEditor?.colourPaint.flatView = true }.keyboardShortcut("f", modifiers: [.command, .shift])
            Button("Add Dirt") { stageEditor?.addFill(.wear(PaintWear(kind: .dirt))) }.keyboardShortcut("w", modifiers: [.command, .option])
            Button("Add Worn Edges") { stageEditor?.addFill(.wear(PaintWear(kind: .edges))) }.keyboardShortcut("e", modifiers: [.command, .option])
            Button("Mirror Paint") { stageEditor?.togglePaintMirror() }.keyboardShortcut("m", modifiers: [.command, .control])
            Button("Fill Faces") { stageEditor?.toggleFacesBrush() }.keyboardShortcut("f", modifiers: [.command, .option, .shift])
        }
        CommandMenu("Look") {
            // L2: the Looks one after another, and the drawn set at the playhead (aimed at the selection).
            Button("Next Look") { stageEditor?.stepLook(by: 1) }.keyboardShortcut("k", modifiers: [.command, .option])
            Button("Previous Look") { stageEditor?.stepLook(by: -1) }.keyboardShortcut("k", modifiers: [.command, .option, .shift])
            Divider()
            Button("Impact Frame") { stageEditor?.addScreenEffect(.impact) }.keyboardShortcut("i", modifiers: [.command, .control])
            Button("Focus Lines") { stageEditor?.addScreenEffect(.focusLines) }.keyboardShortcut("u", modifiers: [.command, .control])
            Button("Kirby Dots") { stageEditor?.addScreenEffect(.kirbyDots) }.keyboardShortcut("k", modifiers: [.command, .control])
        }
        CommandMenu("Physics") {
            Button("Make Real") { stageEditor?.makeReal() }.keyboardShortcut("j", modifiers: [.command, .shift])
            Button("Not Real") { stageEditor?.makeUnreal() }.keyboardShortcut("j", modifiers: [.command, .option])
            Button("Settle") { stageEditor?.settleSelection() }.keyboardShortcut("j", modifiers: .command)
            Button("Does It Stand?") { stageEditor?.checkStands() }.keyboardShortcut("u", modifiers: [.command, .option])
            Button("Keep the Run as Keys") { stageEditor?.keepRun() }.keyboardShortcut("k", modifiers: [.command, .shift])
            Button("Show Speed and Forces") { stageEditor.map { $0.physicsRun.showsArrows.toggle(); $0.refreshPhysicsOverlay() } }
        }
        CommandMenu("Character") {
            Button("New Character…") {
                editor?.libraryPage = .characters
                editor?.openPanel = .library
            }
            .keyboardShortcut("c", modifiers: [.command, .shift])
            Button("New Person") { editor?.newCharacter(.person) }.keyboardShortcut("p", modifiers: [.command, .option])
            Button("New Four-Legged") { editor?.newCharacter(.fourLegs) }
            Button("New Creature from Nothing") { editor?.newCharacter(.nothing) }
            Divider()
            Button(editor?.maker.symmetric == false ? "Mirror Parts" : "Stop Mirroring Parts") { editor?.maker.symmetric.toggle() }
            Button("Rig It Again") { editor.map { editor in editor.makerCharacter.map { editor.rigAgain($0, gesture: nil) } } }
                .disabled(editor?.makerCharacter == nil)
            Button("Export for Games…") { editor?.sheet = .gameExport }.keyboardShortcut("e", modifiers: [.command, .shift])
        }
        CommandMenu("Kit") {
            Section("Room") {
                Button("Plans and Elevations") { editor?.sheet = .plans }.keyboardShortcut("a", modifiers: [.command, .control])
                Button("Walk Through") { editor.map { $0.guest.walkHeight == nil ? $0.startWalking() : $0.stopWalking() } }
                    .keyboardShortcut("w", modifiers: [.command, .control])
                Button("Match a Photo…") { editor?.sheet = .matchPhoto }
            }
            Section("Print") {
                Button("Best Way Up") { stageEditor?.orientForPrinting() }.keyboardShortcut("b", modifiers: [.command, .control])
                Button("Split for Printing") { stageEditor?.splitForPrinting() }.keyboardShortcut("s", modifiers: [.command, .control])
                Button("Hollow") { stageEditor?.hollowForPrinting() }.keyboardShortcut("h", modifiers: [.command, .control])
                Button("Show Overhangs") { stageEditor?.guest.overhangs.toggle() }.keyboardShortcut("v", modifiers: [.command, .control])
            }
            Section("Study") {
                Button("Explode") { stageEditor?.toggleExplode() }.keyboardShortcut("x", modifiers: [.command, .control])
            }
            Section("Game") {
                Button("Freeze Transforms") { stageEditor?.freezeTransforms() }.keyboardShortcut("t", modifiers: [.command, .control])
            }
        }
        CommandMenu("Scene") {
            Button("Frame Selection") { editor?.frameSelection() }.keyboardShortcut("f", modifiers: .command)
            Button("Director View") { editor.map { $0.setDirectorView(!$0.directorView) } }.keyboardShortcut("d", modifiers: [.command, .option])
            Button("Fly the Camera") { editor.map { $0.flying ? $0.stopFlying() : $0.startFlying() } }.keyboardShortcut("y", modifiers: [.command, .option])
            Button("Hide Interface") { editor?.chromeHidden.toggle() }.keyboardShortcut("f", modifiers: [.command, .control])
            Divider()
            Button("History and Steps") { editor?.openHistory() }.keyboardShortcut("y", modifiers: .command)
            Button("Export…") { editor?.sheet = .export }.keyboardShortcut("e", modifiers: .command)
            Button("Close the Loop") { stageEditor?.closeTheLoop() }.keyboardShortcut("e", modifiers: [.command, .control])
            Button("Paste a Scene Script") { editor?.importScriptFromClipboard() }.keyboardShortcut("v", modifiers: [.command, .option])
            Button("AI & Laptop Bridge…") { editor?.sheet = .bridge }.keyboardShortcut("b", modifiers: [.command, .shift])
            Button("Scripts…") { editor?.openScript(nil) }
            Divider()
            Button("New Monitor Window") { openWindow(id: LoweyWindow.monitor) }.keyboardShortcut("n", modifiers: [.command, .option])
        }
        CommandMenu("Timeline") {
            Button(editor?.timelinePresence == .hidden ? "Show Timeline" : "Hide Timeline") { editor?.toggleTimeline() }
                .keyboardShortcut("t", modifiers: .command)
            Button("Play / Pause") { editor?.togglePlay() }
            Button("Key the Selection") { editor?.keySelection() }.keyboardShortcut("k", modifiers: .command)
            Button("Record a Performance") { editor?.armPerform() }.keyboardShortcut("r", modifiers: [.command, .shift])
            Button("Add Marker") { editor?.addMarker() }.keyboardShortcut("m", modifiers: .command)
            Divider()
            Button("Audio & Words…") { editor?.sheet = .audio }.keyboardShortcut("u", modifiers: [.command, .shift])
            Button("Transcript") { editor?.sheet = .transcript }.keyboardShortcut("t", modifiers: [.command, .shift])
            Button("Record Voiceover") { editor?.toggleVoiceRecording() }.keyboardShortcut("r", modifiers: [.command, .option])
            Divider()
            Button("Select All Keys") { editor?.selectKeys(.all) }.keyboardShortcut("a", modifiers: [.command, .option])
            Button("Keys After the Playhead") { editor?.selectKeys(.afterPlayhead) }.keyboardShortcut(.rightArrow, modifiers: [.command, .shift])
            Button("Keys at the Playhead") { editor?.selectKeys(.atPlayhead) }
            Divider()
            // Animate's bar (A1).
            Button("Draw a Path") { animateVerb(.path) }.keyboardShortcut("4", modifiers: [.command, .option])
            Button("Look At…") { animateVerb(.lookAt) }.keyboardShortcut("l", modifiers: [.command, .control])
            Button("Pick Up or Hand Off…") { animateVerb(.pickUp) }.keyboardShortcut("p", modifiers: [.command, .control])
            Button("Even Speed") { stageEditor?.evenSpeed() }.disabled(stageEditor?.motionDuration == nil)
            Button(editor?.animate.ghosts == false ? "Show Ghosts While Scrubbing" : "Hide Ghosts While Scrubbing") { editor?.animate.ghosts.toggle() }
                .keyboardShortcut("g", modifiers: [.command, .control])
            Button(editor?.timelineStyle == .dopeSheet ? "Show Motion" : "Show the Dope Sheet") {
                guard let editor = stageEditor else { return }
                editor.timelineStyle = editor.timelineStyle == .dopeSheet ? .motion : .dopeSheet
                editor.timelinePresence = .full
            }
            .keyboardShortcut("d", modifiers: [.command, .control])
            Divider()
            // The lens and the frame (F1).
            Button("Lens and Frame…") { editor?.showsLensPanel = true }
                .keyboardShortcut("l", modifiers: [.command, .option])
                .disabled(editor?.editedCamera == nil)
            Button("Focus on the Selection") { editor?.focusOnSelection(pull: false) }.keyboardShortcut("f", modifiers: [.command, .option])
            Button("Pull Focus to the Selection") { editor?.focusOnSelection(pull: true) }.keyboardShortcut("f", modifiers: [.command, .control, .option])
        }
        // Live performance airs as 1.2 (held in App Store builds until then).
        if Held.isOn(.livePerformance) {
            CommandMenu("Perform") {
                Button(editor?.live.voiceOn == true ? "Stop the Microphone" : "Mouth from the Microphone") { editor?.toggleVoice() }
                    .keyboardShortcut("m", modifiers: [.command, .option])
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
