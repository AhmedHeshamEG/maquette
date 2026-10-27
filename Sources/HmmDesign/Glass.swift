#if canImport(SwiftUI)
    import SwiftUI

    public extension EnvironmentValues {
        /// Inside a glass panel, controls draw no glass of their own (glass on glass is muddy, and every glass layer
        /// over a live canvas is re-blurred every frame).
        @Entry var hmmInsideGlass = false
        /// Chrome restraint (a trial): floating chrome is neutral dark glass that takes no colour from the canvas under
        /// it, and the accent marks one active thing at a time (`HmmButton`'s `accent`).
        @Entry var hmmRestrainedChrome = false
    }

    /// The `UserDefaults` key an app keeps the chrome-restraint trial under (Diagnostics flips it).
    public enum HmmChromeRestraint {
        public static let storageKey = "hmm.restrainedChrome"
    }

    /// Floating chrome material: Liquid Glass with a dark tint so text stays legible over any content, or a solid
    /// surface at 96 % with Reduce Transparency (opaque, with a stronger outline, with Increase Contrast).
    private struct HmmGlassModifier<S: Shape>: ViewModifier {
        @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
        @Environment(\.colorSchemeContrast) private var contrast
        @Environment(\.hmmTheme) private var theme
        @Environment(\.hmmRestrainedChrome) private var restrained
        let shape: S
        let interactive: Bool
        let tint: Color?

        func body(content: Content) -> some View {
            if reduceTransparency || contrast == .increased {
                content
                    .background(theme.surface.opacity(contrast == .increased ? 1 : 0.96), in: shape)
                    .overlay(shape.stroke(contrast == .increased ? theme.text2 : theme.line, lineWidth: contrast == .increased ? 1.5 : 1))
            } else {
                let glassTint = tint ?? defaultTint
                content.glassEffect(interactive ? .regular.tint(glassTint).interactive() : .regular.tint(glassTint), in: shape)
            }
        }

        /// Restrained, the glass is nearly opaque graphite (or paper in light mode), so the canvas's colours don't
        /// bleed into the chrome; otherwise a light tint keeps text legible over anything.
        private var defaultTint: Color {
            switch (theme.appearance == .dark, restrained) {
            case (true, true): theme.surface.opacity(0.78)
            case (true, false): Color.black.opacity(0.32)
            case (false, true): theme.surface.opacity(0.74)
            case (false, false): Color.white.opacity(0.28)
            }
        }
    }

    public extension View {
        /// A floating control on glass (round buttons, pills over the canvas).
        func hmmGlass(in shape: some Shape = Capsule(), interactive: Bool = true, tint: Color? = nil) -> some View {
            modifier(HmmGlassModifier(shape: shape, interactive: interactive, tint: tint))
        }

        /// A floating panel: glass in the panel radius; controls inside draw no glass of their own.
        func hmmPanelBackground(cornerRadius: Double = HmmRadius.panel) -> some View {
            environment(\.hmmInsideGlass, true)
                .modifier(HmmGlassModifier(shape: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous),
                                           interactive: false, tint: nil))
        }
    }
#endif
