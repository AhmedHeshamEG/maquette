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

    /// The eraser of the tool in the hand, and back (ink, flipbooks, paint); with anything else, ink's eraser.
    func toggleEraser() {
        HmmHaptics.play(.selection)
        switch tool {
        case .ink: ink.mode = ink.mode == .erase ? .draw : .erase
        case .flipbook: flipbook.mode = flipbook.mode == .erase ? .draw : .erase
        case .paint: colourPaint.mode = colourPaint.mode == .erase ? .paint : .erase
        default:
            tool = .ink
            ink.mode = .erase
        }
    }

    /// The tool in the hand before this one.
    func switchToLastTool() {
        HmmHaptics.play(.selection)
        let previous = lastTool
        tool = previous
    }

    /// The squeeze menu's buttons, as Settings filled its six slots.
    var quickMenuItems: [HmmQuickMenuItem] {
        QuickAction.slots().map { action in
            HmmQuickMenuItem(id: action.rawValue, title: action.title, systemName: action.systemImage, isOn: isOn(action)) { [weak self] in
                self?.run(action)
            }
        }
    }

    private func isOn(_ action: QuickAction) -> Bool {
        switch action {
        case .eraser: ink.mode == .erase && tool == .ink || flipbook.mode == .erase && tool == .flipbook || colourPaint.mode == .erase && tool == .paint
        case .snap: snap.magnet
        case .play: isPlaying
        default: false
        }
    }

    func run(_ action: QuickAction) {
        switch action {
        case .eraser: toggleEraser()
        case .lastTool: switchToLastTool()
        case .colour: hands.choosingColour = true
        case .snap: toggleSnapMagnet()
        case .undo: undo()
        case .redo: redo()
        case .play: togglePlay()
        case .hideChrome: chromeHidden.toggle()
        case .frame: frameSelection()
        case .newSheet: newSheet()
        }
    }

    /// The Snap magnet: everything that snaps, on or off (the details are its hold).
    func toggleSnapMagnet() {
        snap.magnet.toggle()
        HmmHaptics.play(.selection)
        if snap.magnet { app.show("Snapping on") } else { app.show("Snapping off") }
    }

    // MARK: Cut, copy, paste

    /// The three-finger swipe's bar.
    var editBarItems: [HmmEditBarItem] {
        [
            HmmEditBarItem("Cut", systemName: "scissors") { [weak self] in self?.cutSelection() },
            HmmEditBarItem("Copy", systemName: "doc.on.doc") { [weak self] in self?.copySelection() },
            HmmEditBarItem("Paste", systemName: "doc.on.clipboard") { [weak self] in self?.paste() },
            HmmEditBarItem("Duplicate", systemName: "plus.square.on.square") { [weak self] in self?.duplicateSelection() }
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
