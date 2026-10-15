#if canImport(SwiftUI)
    import SwiftUI

    /// The colour picker (Procreate's, CONTEXT §10.11 U7): the colour in the hand and the one before it, the scene's
    /// palette and the colours used lately, then a Disc, Values and saved Palettes, and an app's own extra page (Maquette's
    /// Materials). Every colour chosen goes on the history when the drag or the tap ends.
    public struct HmmColourPicker<Extra: View>: View {
        @Binding private var colour: HmmColour
        private let scene: [HmmColour]
        private let extraTitle: String?
        private let extraImage: String
        private let extra: () -> Extra
        @State private var page: Page = .disc
        @State private var memory = HmmColourMemory.load()
        @State private var previous: HmmColour?
        @Environment(\.hmmTheme) private var theme

        enum Page: Hashable {
            case disc, values, palettes, extra
        }

        /// `scene` is the scene's own palette (shown first); `extra` is an app's page beside the three.
        public init(colour: Binding<HmmColour>, scene: [HmmColour] = [], extraTitle: String? = nil, extraImage: String = "square.grid.2x2",
                    @ViewBuilder extra: @escaping () -> Extra) {
            _colour = colour
            self.scene = scene
            self.extraTitle = extraTitle
            self.extraImage = extraImage
            self.extra = extra
        }

        public var body: some View {
            VStack(alignment: .leading, spacing: HmmSpacing.s) {
                header
                if !scene.isEmpty { HmmSwatchRow(colours: scene, selected: colour, label: "The scene's colours") { choose($0) } }
                if !memory.history.colours.isEmpty {
                    HmmSwatchRow(colours: memory.history.colours, selected: colour, label: "Recent colours") { choose($0) }
                }
                pages
                switch page {
                case .disc: HmmColourDiscView(colour: $colour) { commit() }
                case .values: HmmColourValues(colour: $colour) { commit() }
                case .palettes: HmmPalettesPage(memory: $memory, colour: colour) { choose($0) }
                case .extra: extra()
                }
            }
            .onAppear { previous = previous ?? colour }
            .accessibilityIdentifier("colour-picker")
        }

        private var header: some View {
            HStack(spacing: HmmSpacing.xs) {
                HmmSwatch(colour: colour, size: 36, isOn: true)
                    .accessibilityLabel(Text("The colour in the hand, \(colour.hex)"))
                if let previous, previous != colour {
                    Button { choose(previous) } label: { HmmSwatch(colour: previous, size: 28, isOn: false) }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text("Back to the colour before, \(previous.hex)"))
                }
                Spacer(minLength: 0)
                Text(colour.hex).font(.hmm(.caption).monospaced()).foregroundStyle(theme.text2)
            }
        }

        private var pages: some View {
            Picker("Page", selection: $page) {
                Label("Disc", systemImage: "circle.circle").tag(Page.disc)
                Label("Values", systemImage: "slider.horizontal.3").tag(Page.values)
                Label("Palettes", systemImage: "square.grid.3x3").tag(Page.palettes)
                if let extraTitle { Label(extraTitle, systemImage: extraImage).tag(Page.extra) }
            }
            .pickerStyle(.segmented)
            .labelStyle(.titleOnly)
        }

        private func choose(_ chosen: HmmColour) {
            if chosen != colour { previous = colour }
            colour = chosen
            commit()
        }

        private func commit() {
            memory.history.use(colour)
            memory.save()
            HmmHaptics.play(.selection)
        }
    }

    public extension HmmColourPicker where Extra == EmptyView {
        init(colour: Binding<HmmColour>, scene: [HmmColour] = []) {
            self.init(colour: colour, scene: scene, extraTitle: nil, extra: { EmptyView() })
        }
    }

    public extension HmmColour {
        var color: Color { Color(red: red, green: green, blue: blue) }
    }

    /// One swatch: a rounded square, ringed when it's the one chosen.
    struct HmmSwatch: View {
        let colour: HmmColour
        var size: Double = 28
        var isOn = false
        @Environment(\.hmmTheme) private var theme

        var body: some View {
            RoundedRectangle(cornerRadius: size / 4, style: .continuous)
                .fill(colour.color)
                .frame(width: size, height: size)
                .overlay(RoundedRectangle(cornerRadius: size / 4, style: .continuous).strokeBorder(theme.line, lineWidth: 1))
                .overlay(RoundedRectangle(cornerRadius: size / 4 + 3, style: .continuous).strokeBorder(theme.accent, lineWidth: isOn ? 2 : 0)
                    .padding(-3))
        }
    }

    /// A row of swatches to tap.
    public struct HmmSwatchRow: View {
        let colours: [HmmColour]
        let selected: HmmColour?
        let label: String
        let choose: (HmmColour) -> Void

        public init(colours: [HmmColour], selected: HmmColour?, label: String, choose: @escaping (HmmColour) -> Void) {
            self.colours = colours
            self.selected = selected
            self.label = label
            self.choose = choose
        }

        public var body: some View {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: HmmSpacing.xs) {
                    ForEach(Array(colours.enumerated()), id: \.offset) { _, colour in
                        Button { choose(colour) } label: {
                            HmmSwatch(colour: colour, isOn: colour == selected).frame(width: HmmTarget.minimum, height: HmmTarget.minimum)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text(colour.hex))
                        .draggable(colour.hex)
                    }
                }
                .padding(.horizontal, 3)
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Text(LocalizedStringKey(label)))
        }
    }
#endif
