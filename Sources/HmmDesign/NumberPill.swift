#if canImport(UIKit) && canImport(SwiftUI)
    import SwiftUI

    /// A number as a 44 pt pill (Maquette U5): drag it to change it (slowly for fine, fast for coarse; `HmmScrub`), tap
    /// it to type it on our number pad. The Pencil Pro buzzes once when a drag reaches an end of the range.
    public struct HmmNumberPill: View {
        private let title: String
        @Binding private var value: Double
        private let scrub: HmmScrub
        private let format: (Double) -> String
        private let parse: (String) -> Double?
        private let units: [String]
        private let onEditingChanged: (Bool) -> Void
        @State private var last: CGSize?
        @State private var typing = false
        @Environment(\.hmmTheme) private var theme

        /// `parse` reads what was typed (nil: leave the number as it was); by default plain sums (`HmmArithmetic`).
        public init(_ title: String, value: Binding<Double>, scrub: HmmScrub, units: [String] = [],
                    format: @escaping (Double) -> String = { String(format: "%.3g", $0) },
                    parse: @escaping (String) -> Double? = { HmmArithmetic.evaluate($0) },
                    onEditingChanged: @escaping (Bool) -> Void = { _ in }) {
            self.title = title
            _value = value
            self.scrub = scrub
            self.format = format
            self.parse = parse
            self.units = units
            self.onEditingChanged = onEditingChanged
        }

        public var body: some View {
            Text(verbatim: format(value))
                .font(.hmmNumbers(.body, weight: .semibold))
                .foregroundStyle(theme.text)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, HmmSpacing.s)
                .frame(minWidth: HmmTarget.minimum, minHeight: HmmTarget.minimum)
                .background(last == nil ? Color.clear : theme.accent.opacity(0.22), in: Capsule())
                .hmmGlass(in: Capsule(), interactive: false)
                .contentShape(Capsule())
                .gesture(drag)
                .onTapGesture {
                    HmmHaptics.play(.selection)
                    typing = true
                }
                .hmmNumberPad(isPresented: $typing, title: title, placeholder: format(value), units: units) { text in
                    guard let typed = parse(text) else { return }
                    onEditingChanged(true)
                    value = scrub.clamped(typed)
                    onEditingChanged(false)
                }
                .accessibilityElement()
                .accessibilityLabel(Text(LocalizedStringKey(title)))
                .accessibilityValue(Text(verbatim: format(value)))
                .accessibilityHint(Text("Drag to change it, tap to type it"))
                .accessibilityAdjustableAction { direction in
                    let step = scrub.fine * 10
                    value = scrub.clamped(direction == .increment ? value + step : value - step)
                }
        }

        private var drag: some Gesture {
            DragGesture(minimumDistance: 6)
                .onChanged { drag in
                    if last == nil {
                        last = .zero
                        onEditingChanged(true)
                    }
                    let previous = last ?? .zero
                    let delta = HmmScrub.delta(dx: drag.translation.width - previous.width, dy: drag.translation.height - previous.height)
                    let speed = HmmScrub.delta(dx: drag.velocity.width, dy: drag.velocity.height)
                    last = drag.translation
                    let before = value
                    let next = scrub.value(from: value, delta: delta, speed: speed)
                    guard next != before else { return }
                    value = next
                    if scrub.isAtEnd(next), !scrub.isAtEnd(before) { HmmPencilHaptics.buzz() }
                }
                .onEnded { _ in
                    last = nil
                    onEditingChanged(false)
                    HmmHaptics.play(.commit)
                }
        }
    }
#endif
