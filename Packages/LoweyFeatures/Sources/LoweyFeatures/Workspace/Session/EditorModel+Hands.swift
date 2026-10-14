import CoreGraphics
import Foundation
import HmmDesign
import LoweyCore
import LoweyEngine

/// The hand shortcuts (CONTEXT §10.10): the Pencil's squeeze and double-tap, the squeeze menu's six slots, the
/// three-finger edit bar, and a finger's double-tap that frames a thing or looks straight at the face it touched.
extension EditorModel {
    /// The Pencil was squeezed or double-tapped (`point`: where it hovered, in screen points).
    func pencilShortcut(_ shortcut: PencilShortcut, at point: CGPoint?) {
        switch shortcut {
        case .eraser: toggleEraser()
        case .lastTool: switchToLastTool()
        case .colour: hands.choosingColour = true
        case .quickMenu:
            HmmHaptics.play(.selection)
            hands.quickMenuAt = point ?? CGPoint(x: 320, y: 320)
        case .none: break
        }
    }

    /// The eraser of the tool in the hand, and back to the last brush (Draw's Erase ↔ Brush); with anything else, Draw
    /// with its eraser.
    func toggleEraser() {
        HmmHaptics.play(.selection)
        if isDrawing {
            chooseDrawVerb(drawVerbInUse == .erase ? .brush : .erase)
        } else {
            drawVerb = .erase
            applyDraw()
        }
    }

    /// The tool in the hand before this one.
    func switchToLastTool() {
        HmmHaptics.play(.selection)
        let previous = lastTool
        tool = previous
    }

    /// The squeeze menu's buttons: Rig's own six while rigging, else the six slots Settings filled (U5).
    var quickMenuItems: [HmmQuickMenuItem] {
        if tool == .rig {
            return RigQuickAction.allCases.map { action in
                HmmQuickMenuItem(id: action.rawValue, title: action.title, systemName: action.systemImage, isOn: isOn(action)) { [weak self] in
                    self?.run(action)
                }
            }
        }
        return QuickAction.slots().map { action in
            HmmQuickMenuItem(id: action.rawValue, title: action.title, systemName: action.systemImage, isOn: isOn(action)) { [weak self] in
                self?.run(action)
            }
        }
    }

    private func isOn(_ action: QuickAction) -> Bool {
        switch action {
        case .lasso: tool == .lasso || tool == .ink && ink.mode == .select
        case .eyedropper: eyedropping
        case .eraser: isDrawing && drawVerbInUse == .erase
        case .snap: snap.magnet
        case .hideSheet: sheetHidden
        case .play: isPlaying
        default: false
        }
    }

    private func isOn(_ action: RigQuickAction) -> Bool {
        switch action {
        case .pins: rigging.markKind == .pin
        case .dots: rigging.markKind == .dot
        case .showBones: !rigging.hidesBones
        default: false
        }
    }

    func run(_ action: QuickAction) {
        switch action {
        case .lasso: startLasso()
        case .eyedropper: eyedropping = true
        case .eraser: toggleEraser()
        case .snap: toggleSnapMagnet()
        case .hideSheet: sheetHidden.toggle()
        case .frame: frameSelection()
        case .lastTool: switchToLastTool()
        case .colour: hands.choosingColour = true
        case .undo: undo()
        case .redo: redo()
        case .play: togglePlay()
        case .hideChrome: chromeHidden.toggle()
        case .newSheet: newSheet()
        }
    }

    func run(_ action: RigQuickAction) {
        HmmHaptics.play(.selection)
        switch action {
        case .pins: rigging.markKind = .pin
        case .dots: rigging.markKind = .dot
        case .mirrorPose: if let character = poseCharacter ?? rigTarget?.id { mirrorPose(of: character) }
        case .resetPose: if let id = rigTarget?.id ?? poseCharacter { resetPose(id) }
        case .savePose: if let character = poseCharacter ?? rigTarget?.id { savePose(of: character) }
        case .showBones:
            rigging.hidesBones.toggle()
            refreshModelOverlay()
        }
    }

    /// The lasso (U5: the Select button left): while drawing it picks strokes, else things. One loop, then back.
    func startLasso() {
        if isDrawing, drawsLines {
            ink.mode = .select
            tool = .ink
        } else {
            tool = .lasso
        }
        HmmHaptics.play(.selection)
    }

    /// The Snap magnet: everything that snaps, on or off (the details are its hold).
    func toggleSnapMagnet() {
        snap.magnet.toggle()
        HmmHaptics.play(.selection)
        if snap.magnet { app.show("Snapping on") } else { app.show("Snapping off") }
    }

    // MARK: Cut, copy, paste

    /// The three-finger swipe's bar (U5: with the lasso and Select all, where the Select button was).
    var editBarItems: [HmmEditBarItem] {
        [
            HmmEditBarItem("Cut", systemName: "scissors") { [weak self] in self?.cutSelection() },
            HmmEditBarItem("Copy", systemName: "doc.on.doc") { [weak self] in self?.copySelection() },
            HmmEditBarItem("Paste", systemName: "doc.on.clipboard") { [weak self] in self?.paste() },
            HmmEditBarItem("Duplicate", systemName: "plus.square.on.square") { [weak self] in self?.duplicateSelection() },
            HmmEditBarItem("Lasso", systemName: "lasso") { [weak self] in self?.startLasso() },
            HmmEditBarItem("Select all", systemName: "checkmark.circle") { [weak self] in self?.selectAll() }
        ]
    }

    func cutSelection() {
        guard !selection.isEmpty else { return }
        copySelection()
        deleteSelection()
    }

    // MARK: A finger's double-tap

    /// Frames the thing under the finger (everything, on empty space).
    func frame(_ id: ObjectID?) {
        guard let stage else { return }
        guard let id else {
            frameSelection()
            return
        }
        stage.frame(operations.bounds.worldBounds(of: [id], in: scene) ?? selectionBounds)
    }

    /// Turns the view to look straight at a face: from along its normal, at the point touched, as far as it was.
    func lookStraight(at point: Vec3, normal: Vec3) {
        guard let stage, normal.length > 1e-9 else { return }
        let direction = normal.normalized
        var viewpoint = stage.viewpoint
        viewpoint.target = point
        viewpoint.yaw = atan2(direction.x, direction.z) * 180 / .pi
        viewpoint.pitch = min(max(asin(min(max(direction.y, -1), 1)) * 180 / .pi, -89.9), 89.9)
        stage.animate(to: viewpoint)
        HmmHaptics.play(.selection)
    }
}
