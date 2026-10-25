#if canImport(SwiftUI)
    import SwiftUI

    /// Something that lives on a canvas edge and can be dragged along it (Procreate's sidebar): a short grip under it
    /// moves it up or down, the place is kept under `key` as a fraction of the room there is, and a double-tap on the
    /// grip sends it back to the middle. Give it the full height; it takes only its content's width.
    public struct HmmEdgeSlide<Content: View>: View {
        private let content: Content
        private let grip: Bool
        @AppStorage private var fraction: Double
        @State private var start: Double?
        @State private var contentHeight = 0.0
        @State private var container = 0.0
        @Environment(\.hmmTheme) private var theme
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        /// `grip` false hides the grip (while the content rests to a rail: the rail is enough).
        public init(key: String, grip: Bool = true, @ViewBuilder content: () -> Content) {
            self.content = content()
            self.grip = grip
            _fraction = AppStorage(wrappedValue: 0, key)
        }

        public var body: some View {
            VStack(spacing: HmmSpacing.xxs) {
                content
                if grip { handle }
            }
            .onGeometryChange(for: Double.self) { $0.size.height } action: { contentHeight = $0 }
            .offset(y: HmmEdgePlace.offset(fraction, content: contentHeight, container: container))
            .frame(maxHeight: .infinity)
            .onGeometryChange(for: Double.self) { $0.size.height } action: { container = $0 }
        }

        private var handle: some View {
            Capsule()
                .fill(theme.text3.opacity(0.6))
                .frame(width: 24, height: 4)
                .frame(width: HmmTarget.minimum, height: 24)
                .contentShape(Rectangle())
                .gesture(drag)
                .onTapGesture(count: 2) { set(0) }
                .accessibilityElement()
                .accessibilityLabel(Text("Move along the edge"))
                .accessibilityAdjustableAction { direction in
                    switch direction {
                    case .increment: set(fraction + 0.25)
                    case .decrement: set(fraction - 0.25)
                    @unknown default: break
                    }
                }
                .accessibilityIdentifier("edge-grip")
        }

        private var drag: some Gesture {
            DragGesture(minimumDistance: 2, coordinateSpace: .global)
                .onChanged { value in
                    let from = start ?? fraction
                    start = from
                    fraction = HmmEdgePlace.fraction(from: from, dragged: value.translation.height, content: contentHeight, container: container)
                }
                .onEnded { _ in start = nil }
        }

        private func set(_ value: Double) {
            withAnimation(HmmMotion.standard.animation(reduceMotion: reduceMotion)) { fraction = max(-1, min(1, value)) }
        }
    }
#endif
