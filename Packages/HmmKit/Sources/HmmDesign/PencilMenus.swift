#if canImport(UIKit) && canImport(SwiftUI)
    import SwiftUI
    import UIKit

    /// Haptics felt in the Pencil itself (Apple Pencil Pro): the soft click of a snap where it happened. On other
    /// Pencils and fingers the iPad plays its own light tick instead. Obeys the haptics switch.
    @MainActor
    public enum HmmPencilHaptics {
        private static var generator: (view: UIView, feedback: UICanvasFeedbackGenerator)?

        /// Something snapped (an angle, a corner, a grid line) under the tip at `point` in `view`.
        public static func snapped(at point: CGPoint, in view: UIView) {
            guard HmmHaptics.isEnabled else { return }
            feedback(for: view).alignmentOccurred(at: point)
        }

        /// A stroke became a clean shape, or a step finished.
        public static func completed(at point: CGPoint, in view: UIView) {
            guard HmmHaptics.isEnabled else { return }
            feedback(for: view).pathCompleted(at: point)
        }

        private static func feedback(for view: UIView) -> UICanvasFeedbackGenerator {
            if let generator, generator.view === view { return generator.feedback }
            let feedback = UICanvasFeedbackGenerator(view: view)
            generator = (view, feedback)
            return feedback
        }
    }

    /// One button of the squeeze menu.
    public struct HmmQuickMenuItem: Identifiable {
        public let id: String
        public let title: String
        public let systemName: String
        public let isOn: Bool
        public let action: () -> Void

        public init(id: String, title: String, systemName: String, isOn: Bool = false, action: @escaping () -> Void) {
            self.id = id
            self.title = title
            self.systemName = systemName
            self.isOn = isOn
            self.action = action
        }
    }

    /// The squeeze menu (CONTEXT §4.4): up to six buttons in a ring around the Pencil's tip, so the hand barely moves.
    /// A button acts and the ring leaves; a touch anywhere else just closes it.
    public struct HmmQuickMenu: View {
        private let items: [HmmQuickMenuItem]
        private let center: CGPoint
        private let dismiss: () -> Void
        @State private var shown = false
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        static let radius: CGFloat = 66
        static let button: Double = 50

        public init(items: [HmmQuickMenuItem], at center: CGPoint, dismiss: @escaping () -> Void) {
            self.items = Array(items.prefix(6))
            self.center = center
            self.dismiss = dismiss
        }

        public var body: some View {
            GeometryReader { geometry in
                let middle = Self.clamped(center, in: geometry.size)
                ZStack {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture(perform: dismiss)
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        HmmButton(item.systemName, label: item.title, isOn: item.isOn, accent: item.isOn, size: Self.button) {
                            dismiss()
                            item.action()
                        }
                        .accessibilityIdentifier("quick-\(item.id)")
                        .position(Self.place(index, of: items.count, around: middle, shown: shown))
                    }
                }
            }
            .onAppear {
                withAnimation(HmmMotion.snappy.animation(reduceMotion: reduceMotion)) { shown = true }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("quick-menu")
        }

        /// Clockwise from the top, a ring that opens out from the tip.
        static func place(_ index: Int, of count: Int, around middle: CGPoint, shown: Bool) -> CGPoint {
            let angle = -Double.pi / 2 + 2 * Double.pi * Double(index) / Double(max(count, 1))
            let distance = shown ? radius : radius * 0.3
            return CGPoint(x: middle.x + distance * CGFloat(cos(angle)), y: middle.y + distance * CGFloat(sin(angle)))
        }

        /// The ring stays whole on screen.
        static func clamped(_ point: CGPoint, in size: CGSize) -> CGPoint {
            let margin = radius + CGFloat(button) / 2 + 8
            return CGPoint(x: min(max(point.x, margin), max(size.width - margin, margin)),
                           y: min(max(point.y, margin), max(size.height - margin, margin)))
        }
    }

    /// One action of the edit bar.
    public struct HmmEditBarItem: Identifiable {
        public let title: String
        public let systemName: String
        public let action: () -> Void
        public var id: String { title }

        public init(_ title: String, systemName: String, action: @escaping () -> Void) {
            self.title = title
            self.systemName = systemName
            self.action = action
        }
    }

    /// Three fingers swiped down: cut, copy, paste (and whatever else the screen offers), at the top centre, until a
    /// choice or a few seconds pass.
    private struct HmmEditBarPresenter: ViewModifier {
        @Binding var isPresented: Bool
        let items: [HmmEditBarItem]
        @Environment(\.hmmTheme) private var theme
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        func body(content: Content) -> some View {
            content.overlay(alignment: .top) {
                if isPresented {
                    HStack(spacing: HmmSpacing.xxs) {
                        ForEach(items) { item in
                            Button {
                                HmmHaptics.play(.commit)
                                isPresented = false
                                item.action()
                            } label: {
                                Label(LocalizedStringKey(item.title), systemImage: item.systemName)
                                    .font(.hmm(.footnote, weight: .semibold))
                                    .padding(.horizontal, HmmSpacing.s)
                                    .frame(minHeight: HmmTarget.minimum)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(theme.text)
                            .accessibilityIdentifier("edit-\(item.title)")
                        }
                    }
                    .padding(.horizontal, HmmSpacing.xs)
                    .hmmPanelBackground(cornerRadius: HmmRadius.card)
                    .padding(.top, HmmSpacing.xl)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .task(id: isPresented) {
                        try? await Task.sleep(for: .seconds(4))
                        isPresented = false
                    }
                    .accessibilityIdentifier("edit-bar")
                }
            }
            .animation(HmmMotion.snappy.animation(reduceMotion: reduceMotion), value: isPresented)
        }
    }

    public extension View {
        /// The edit bar the three-finger swipe opens.
        func hmmEditBar(isPresented: Binding<Bool>, items: [HmmEditBarItem]) -> some View {
            modifier(HmmEditBarPresenter(isPresented: isPresented, items: items))
        }
    }
#endif
