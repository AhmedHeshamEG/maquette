#if canImport(SwiftUI)
    import SwiftUI

    /// One button of a corner cluster.
    public struct HmmClusterItem: Identifiable {
        public var id: String
        public var systemName: String
        public var label: String
        public var isOn: Bool
        /// The one active thing (the tool in the hand): the only button that keeps the accent with chrome restraint.
        public var accent: Bool
        public var isEnabled: Bool
        public var action: () -> Void

        public init(id: String, systemName: String, label: String, isOn: Bool = false, accent: Bool = false, isEnabled: Bool = true,
                    action: @escaping () -> Void) {
            self.id = id
            self.systemName = systemName
            self.label = label
            self.isOn = isOn
            self.accent = accent
            self.isEnabled = isEnabled
            self.action = action
        }
    }

    /// A row of icon buttons sharing one glass capsule, for a canvas corner. Top-left holds document and app-level
    /// actions; top-right holds the app's making tools.
    ///
    /// It rests while the hand works (Maquette U5): with `resting`, the buttons shrink to a faint rail in the same place,
    /// and a touch on it, or the Pencil hovering near it, calls `wake`.
    public struct HmmCornerCluster: View {
        private let items: [HmmClusterItem]
        private let resting: Bool
        private let wake: (() -> Void)?
        @Environment(\.hmmTheme) private var theme

        public init(_ items: [HmmClusterItem], resting: Bool = false, wake: (() -> Void)? = nil) {
            self.items = items
            self.resting = resting
            self.wake = wake
        }

        public var body: some View {
            if resting {
                rail
            } else {
                buttons
            }
        }

        private var buttons: some View {
            HStack(spacing: HmmSpacing.xxs) {
                ForEach(items) { item in
                    HmmButton(item.systemName, label: item.label, isOn: item.isOn, accent: item.accent, action: item.action)
                        .disabled(!item.isEnabled)
                }
            }
            .padding(HmmSpacing.xxs)
            .environment(\.hmmInsideGlass, true)
            .hmmGlass(in: Capsule(), interactive: false)
            .transition(.opacity.combined(with: .scale(scale: 0.92)))
        }

        /// Where the buttons sit, as one faint line; as wide as they are, as tall as a finger.
        private var rail: some View {
            Capsule()
                .fill(theme.text3.opacity(0.5))
                .frame(width: Double(items.count) * (HmmTarget.minimum + HmmSpacing.xxs) * 0.6, height: 4)
                .frame(width: Double(items.count) * (HmmTarget.minimum + HmmSpacing.xxs), height: HmmTarget.minimum)
                .contentShape(Rectangle())
                .onTapGesture { wake?() }
                .onContinuousHover { phase in
                    if case .active = phase { wake?() }
                }
                .transition(.opacity)
                .accessibilityElement()
                .accessibilityLabel(Text("Show the buttons"))
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { wake?() }
        }
    }
#endif
