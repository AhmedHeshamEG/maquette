#if canImport(SwiftUI)
    import SwiftUI

    public extension EnvironmentValues {
        /// The area panels may be moved in, in global coordinates (the canvas's chrome sets it; nil = anywhere).
        @Entry var hmmPanelBounds: CGRect?
        /// The drag on a movable panel's title row (set by `hmmMovable`, read by the title row).
        @Entry var hmmPanelMove: HmmPanelMoveHandle?
    }

    /// The title row's way to move its panel.
    public struct HmmPanelMoveHandle {
        let changed: (CGSize) -> Void
        let ended: () -> Void
        let reset: () -> Void
    }

    extension View {
        /// Makes this view (a panel's title row) the grip of the movable panel around it, if there is one.
        func hmmPanelGrip() -> some View {
            modifier(HmmPanelGrip())
        }
    }

    private struct HmmPanelGrip: ViewModifier {
        @Environment(\.hmmPanelMove) private var move

        func body(content: Content) -> some View {
            if let move {
                content
                    .gesture(
                        DragGesture(minimumDistance: 4, coordinateSpace: .global)
                            .onChanged { move.changed($0.translation) }
                            .onEnded { _ in move.ended() }
                    )
                    .onTapGesture(count: 2) { move.reset() }
                    .accessibilityAction(named: Text("Put the panel back")) { move.reset() }
            } else {
                content
            }
        }
    }

    public extension View {
        /// Moved by hand: the view can be dragged by the grip inside it (`hmmPanelGrip`, a panel's title row) and stays
        /// where it was left, remembered by `position`; kept inside `hmmPanelBounds`. Nil leaves the view where it is.
        func hmmMovable(_ position: HmmPanelPosition?, title: String) -> some View {
            modifier(HmmMovable(position: position, title: title))
        }
    }

    struct HmmMovable: ViewModifier {
        let position: HmmPanelPosition?
        let title: String
        @State private var offset: CGSize = .zero
        @State private var dragStart: CGSize?
        @State private var homeFrame: CGRect = .zero
        @Environment(\.hmmPanelBounds) private var bounds

        func body(content: Content) -> some View {
            if let position {
                content
                    .onGeometryChange(for: CGRect.self) { proxy in
                        proxy.frame(in: .global)
                    } action: { frame in
                        // Where the panel would be unmoved: the frame on screen less the offset it carries.
                        homeFrame = frame.offsetBy(dx: -offset.width, dy: -offset.height)
                    }
                    .offset(offset)
                    .environment(\.hmmPanelMove, HmmPanelMoveHandle(changed: { translation in
                        let start = dragStart ?? offset
                        if dragStart == nil { dragStart = start }
                        offset = clamp(position, CGSize(width: start.width + translation.width, height: start.height + translation.height))
                    }, ended: {
                        dragStart = nil
                        position.save(offset)
                    }, reset: {
                        position.reset()
                        withHmmAnimation(.standard) { offset = .zero }
                    }))
                    .onAppear { offset = position.load().map { clamp(position, $0) } ?? .zero }
            } else {
                content
            }
        }

        private func clamp(_ position: HmmPanelPosition, _ proposed: CGSize) -> CGSize {
            guard let bounds, homeFrame.width > 0 else { return proposed }
            return position.clamped(proposed, frame: homeFrame, in: bounds)
        }
    }
#endif
