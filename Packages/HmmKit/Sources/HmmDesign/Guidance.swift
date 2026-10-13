#if canImport(SwiftUI)
    import SwiftUI

    /// The instructions switch: the short explanations inside panels are on by default (a beginner needs them) and one
    /// switch in Settings hides them in every studio app. `HmmHint` obeys it.
    public enum HmmInstructions {
        public static let storageKey = "hmm.showInstructions"
    }

    /// A short explanation inside a panel; gone while the instructions switch is off.
    public struct HmmHint: View {
        private let text: Text
        @AppStorage(HmmInstructions.storageKey) private var showsInstructions = true
        @Environment(\.hmmTheme) private var theme

        public init(_ key: LocalizedStringKey) {
            text = Text(key)
        }

        public init(verbatim: String) {
            text = Text(verbatim: verbatim)
        }

        public var body: some View {
            if showsInstructions {
                text
                    .font(.hmm(.caption))
                    .foregroundStyle(theme.text2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// What an undo or a redo changed, said for about a second at the top centre, then gone.
    public struct HmmUndoLineMessage: Equatable, Identifiable, Sendable {
        public var id = UUID()
        public var text: String

        public init(_ text: String) {
            self.text = text
        }
    }

    private struct HmmUndoLinePresenter: ViewModifier {
        @Binding var message: HmmUndoLineMessage?
        let duration: Duration
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @Environment(\.hmmTheme) private var theme

        func body(content: Content) -> some View {
            content.overlay(alignment: .top) {
                if let current = message {
                    Text(LocalizedStringKey(current.text))
                        .font(.hmm(.caption, weight: .semibold))
                        .foregroundStyle(theme.text)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, HmmSpacing.s)
                        .padding(.vertical, HmmSpacing.xs)
                        .hmmGlass(in: Capsule(), interactive: false)
                        .padding(.top, HmmSpacing.s)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                        .accessibilityIdentifier("undo-line")
                        .task(id: current.id) {
                            try? await Task.sleep(for: duration)
                            guard !Task.isCancelled, message?.id == current.id else { return }
                            withAnimation(HmmMotion.snappy.animation(reduceMotion: reduceMotion)) { message = nil }
                        }
                }
            }
            .animation(HmmMotion.snappy.animation(reduceMotion: reduceMotion), value: message)
        }
    }

    /// One line at the bottom when a guided step starts or changes what it asks; like every message it leaves after a
    /// moment or on any touch (Maquette U5), and the moment the step ends (`text` back to nil). A new line shows again.
    private struct HmmGuideLinePresenter: ViewModifier {
        let text: String?
        let duration: Duration
        /// The line already read (its time ran out, or a touch came after it showed).
        @State private var read: String?
        @State private var shownAt = 0
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @Environment(\.hmmTheme) private var theme

        func body(content: Content) -> some View {
            content.overlay(alignment: .bottom) {
                if let text, text != read {
                    Text(LocalizedStringKey(text))
                        .font(.hmm(.body, weight: .semibold))
                        .foregroundStyle(theme.text)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, HmmSpacing.m)
                        .padding(.vertical, HmmSpacing.xs)
                        .hmmGlass(in: Capsule(), interactive: false)
                        .padding(.bottom, HmmSpacing.xl * 2)
                        .padding(.horizontal, HmmSpacing.xl)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                        .accessibilityIdentifier("guide-line")
                        .task(id: text) {
                            shownAt = HmmTouchCount.now
                            try? await Task.sleep(for: duration)
                            guard !Task.isCancelled else { return }
                            read = text
                        }
                }
            }
            .onChange(of: HmmTouchCount.now) { _, touches in
                if let text, touches > shownAt { read = text }
            }
            .onChange(of: text) { _, new in
                if new != read { read = nil }
            }
            .animation(HmmMotion.standard.animation(reduceMotion: reduceMotion), value: text)
            .animation(HmmMotion.standard.animation(reduceMotion: reduceMotion), value: read)
        }
    }

    public extension View {
        /// The undo line: `message` at the top centre for `duration`, then cleared.
        func hmmUndoLine(_ message: Binding<HmmUndoLineMessage?>, duration: Duration = .seconds(1.1)) -> some View {
            modifier(HmmUndoLinePresenter(message: message, duration: duration))
        }

        /// The guide line: one line at the bottom when `text` starts or changes, for `duration` or until any touch.
        func hmmGuideLine(_ text: String?, duration: Duration = .seconds(2.5)) -> some View {
            modifier(HmmGuideLinePresenter(text: text, duration: duration))
        }
    }
#endif
