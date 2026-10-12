#if canImport(UIKit) && canImport(Metal) && canImport(SwiftUI) && !os(watchOS) && !os(tvOS)
    import HmmBoard
    import HmmDesign
    import SwiftUI

    /// The Pencil's own gestures on the board (CONTEXT §4.4): double-tap does what the iPad's Pencil setting says
    /// (the eraser, the last tool, the colours), squeeze opens the quick menu at the tip. Each has its switch in
    /// Settings ▸ Gestures.
    struct BoardPencilGestures: ViewModifier {
        let model: BoardModel
        @Binding var choosingColour: Bool
        @State private var previousTool: BoardTool = .draw
        @State private var quickMenuAt: CGPoint?
        @Environment(\.preferredPencilDoubleTapAction) private var doubleTapAction
        @Environment(\.preferredPencilSqueezeAction) private var squeezeAction

        func body(content: Content) -> some View {
            content
                .onPencilDoubleTap { _ in
                    guard HmmShortcut.pencilDoubleTap.isOn() else { return }
                    perform(doubleTapAction, at: nil)
                }
                .onPencilSqueeze { phase in
                    guard case let .ended(value) = phase, HmmShortcut.squeeze.isOn() else { return }
                    perform(squeezeAction, at: value.hoverPose?.location)
                }
                .onChange(of: model.session.tool) { old, _ in previousTool = old }
                .overlay {
                    if let point = quickMenuAt {
                        HmmQuickMenu(items: quickItems, at: point) { quickMenuAt = nil }
                    }
                }
        }

        private func perform(_ action: PencilPreferredAction, at point: CGPoint?) {
            switch action {
            case .switchEraser:
                model.setTool(model.session.tool == .erase ? (previousTool == .erase ? .draw : previousTool) : .erase)
                HmmHaptics.play(.selection)
            case .switchPrevious:
                model.setTool(previousTool)
                HmmHaptics.play(.selection)
            case .showColorPalette:
                choosingColour = true
            case .ignore:
                break
            default:
                // The tool palette, ink attributes, a system shortcut: our quick menu at the tip.
                quickMenuAt = point ?? CGPoint(x: 200, y: 200)
            }
        }

        private var quickItems: [HmmQuickMenuItem] {
            let tool = model.session.tool
            return [
                HmmQuickMenuItem(id: "draw", title: "Draw", systemName: "pencil.tip", isOn: tool == .draw) { model.setTool(.draw) },
                HmmQuickMenuItem(id: "erase", title: "Erase", systemName: "eraser", isOn: tool == .erase) { model.setTool(.erase) },
                HmmQuickMenuItem(id: "colour", title: "Colour", systemName: "paintpalette") { choosingColour = true },
                HmmQuickMenuItem(id: "select", title: "Select", systemName: "hand.point.up.left", isOn: tool == .select) { model.setTool(.select) },
                HmmQuickMenuItem(id: "undo", title: "Undo", systemName: "arrow.uturn.backward") { model.undo() },
                HmmQuickMenuItem(id: "redo", title: "Redo", systemName: "arrow.uturn.forward") { model.redo() }
            ]
        }
    }
#endif
