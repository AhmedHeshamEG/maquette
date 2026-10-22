#if canImport(SwiftUI)
    import SwiftUI

    /// The eyedropper's loupe (Procreate's): a ring under the held finger, the colour about to be taken in its top half
    /// and the colour in the hand in its bottom half, lifted above the finger so the finger never hides it.
    public struct HmmColourLoupe: View {
        private let current: Color
        private let picked: Color
        @Environment(\.hmmTheme) private var theme

        public static let diameter = 96.0
        /// How far above the finger the ring's centre sits.
        public static let lift = 70.0

        public init(current: Color, picked: Color) {
            self.current = current
            self.picked = picked
        }

        public var body: some View {
            ZStack {
                Circle().trim(from: 0.5, to: 1).stroke(picked, lineWidth: 22)
                Circle().trim(from: 0, to: 0.5).stroke(current, lineWidth: 22)
                Circle().stroke(theme.background.opacity(0.6), lineWidth: 1).padding(-11)
                Circle().stroke(theme.background.opacity(0.6), lineWidth: 1).padding(11)
            }
            .frame(width: Self.diameter - 22, height: Self.diameter - 22)
            .shadow(color: .black.opacity(0.35), radius: 6, y: 2)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
#endif
