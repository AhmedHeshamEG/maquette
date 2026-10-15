#if canImport(SwiftUI)
    import SwiftUI

    /// The Disc: hue round the ring, saturation across the inner disc (at the brightness in hand), brightness on the
    /// slider under it. A finger or the Pencil drags either; a drag ends with the colour going on the history.
    struct HmmColourDiscView: View {
        @Binding var colour: HmmColour
        let commit: () -> Void
        @State private var hsb = HmmHSB(hue: 0, saturation: 0, brightness: 1)
        @State private var dragging: Part?
        @Environment(\.hmmTheme) private var theme

        enum Part { case ring, disc }

        var body: some View {
            VStack(spacing: HmmSpacing.s) {
                GeometryReader { proxy in
                    let side = min(proxy.size.width, proxy.size.height)
                    ZStack {
                        Circle()
                            .strokeBorder(AngularGradient(colors: hues(12, brightness: 1), center: .center, startAngle: .degrees(-90),
                                                          endAngle: .degrees(270)),
                                          lineWidth: side / 2 * (1 - HmmColourDisc.ringInner))
                        Circle()
                            .fill(AngularGradient(colors: (0 ... 12).map {
                                HmmHSB(hue: Double($0) / 12, saturation: 1, brightness: hsb.brightness).rgb.color
                            }, center: .center, startAngle: .degrees(-90), endAngle: .degrees(270)))
                            .overlay(Circle().fill(RadialGradient(colors: [HmmHSB(hue: 0, saturation: 0, brightness: hsb.brightness).rgb.color,
                                                                           .clear], center: .center, startRadius: 0,
                                endRadius: side / 2 * HmmColourDisc.ringInner * 0.94)))
                            .padding(side / 2 * (1 - HmmColourDisc.ringInner) + 2)
                        marks(side: side)
                    }
                    .frame(width: side, height: side)
                    .contentShape(Circle())
                    .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                        drag(value.location, side: side)
                    }.onEnded { _ in
                        dragging = nil
                        commit()
                    })
                    .frame(maxWidth: .infinity)
                }
                .frame(height: 230)
                HmmChannelSlider(title: "Brightness", value: hsb.brightness, colours: [.black, HmmHSB(hue: hsb.hue, saturation: hsb.saturation,
                                                                                                      brightness: 1).rgb.color]) { value in
                    hsb.brightness = value
                    colour = hsb.rgb
                } done: { commit() }
            }
            .onAppear { hsb = HmmHSB(colour) }
            .onChange(of: colour) { _, new in
                // From outside (a swatch, the values): follow it, keeping the hue when it went grey.
                guard new != hsb.rgb else { return }
                var next = HmmHSB(new)
                if next.saturation < 0.001 || next.brightness < 0.001 { next.hue = hsb.hue }
                hsb = next
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("colour-disc")
        }

        private func marks(side: Double) -> some View {
            let point = HmmColourDisc.point(hue: hsb.hue, saturation: hsb.saturation)
            let ring = HmmColourDisc.point(hue: hsb.hue, saturation: 1 / 0.94 * (1 + HmmColourDisc.ringInner) / 2 / HmmColourDisc.ringInner)
            return ZStack {
                Circle().strokeBorder(.white, lineWidth: 3).frame(width: 22, height: 22).shadow(radius: 2)
                    .offset(x: point.x * side / 2, y: point.y * side / 2)
                Circle().strokeBorder(.white, lineWidth: 3).frame(width: 18, height: 18).shadow(radius: 2)
                    .offset(x: ring.x * side / 2, y: ring.y * side / 2)
            }
            .allowsHitTesting(false)
        }

        private func drag(_ location: CGPoint, side: Double) {
            let x = (location.x - side / 2) / (side / 2), y = (location.y - side / 2) / (side / 2)
            if dragging == nil { dragging = HmmColourDisc.isOnRing(x: x, y: y) ? .ring : .disc }
            hsb.hue = HmmColourDisc.hue(atX: x, y: y)
            if dragging == .disc { hsb.saturation = HmmColourDisc.saturation(atX: x, y: y) }
            colour = hsb.rgb
        }
    }

    /// The hues round the circle, `steps` of them (and back to red), at a brightness.
    func hues(_ steps: Int, brightness: Double) -> [Color] {
        (0 ... steps).map { HmmHSB(hue: Double($0) / Double(steps), saturation: 1, brightness: brightness).rgb.color }
    }

    /// A colour with one of its hue, saturation or brightness changed.
    func changed(_ hsb: HmmHSB, _ change: (inout HmmHSB) -> Void) -> HmmColour {
        var copy = hsb
        change(&copy)
        return copy.rgb
    }

    /// A channel as a slider over its own gradient, with its number.
    struct HmmChannelSlider: View {
        let title: String
        let value: Double
        let colours: [Color]
        var scale: Double = 100
        let change: (Double) -> Void
        let done: () -> Void
        @Environment(\.hmmTheme) private var theme

        var body: some View {
            HStack(spacing: HmmSpacing.s) {
                Text(LocalizedStringKey(title)).font(.hmm(.caption)).foregroundStyle(theme.text2).frame(width: 74, alignment: .leading)
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(LinearGradient(colors: colours, startPoint: .leading, endPoint: .trailing))
                        Circle().strokeBorder(.white, lineWidth: 3).frame(width: 24, height: 24).shadow(radius: 2)
                            .offset(x: value * (proxy.size.width - 24))
                    }
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                        change(min(max((drag.location.x - 12) / max(proxy.size.width - 24, 1), 0), 1))
                    }.onEnded { _ in done() })
                }
                .frame(height: 28)
                Text("\(Int((value * scale).rounded()))").font(.hmm(.caption).monospacedDigit()).frame(width: 34, alignment: .trailing)
            }
            .frame(minHeight: HmmTarget.minimum)
            .accessibilityElement()
            .accessibilityLabel(Text(LocalizedStringKey(title)))
            .accessibilityValue(Text("\(Int((value * scale).rounded()))"))
            .accessibilityAdjustableAction { direction in
                change(min(max(value + (direction == .increment ? 0.05 : -0.05), 0), 1))
                done()
            }
        }
    }

    /// Values: hue, saturation and brightness, red, green and blue, and the hex code to type.
    struct HmmColourValues: View {
        @Binding var colour: HmmColour
        let commit: () -> Void
        @State private var hex = ""

        var body: some View {
            let hsb = HmmHSB(colour)
            VStack(spacing: HmmSpacing.xxs) {
                HmmChannelSlider(title: "Hue", value: hsb.hue, colours: hues(6, brightness: 1), scale: 360) { value in
                    colour = changed(hsb) { $0.hue = value }
                } done: { commit() }
                HmmChannelSlider(title: "Saturation", value: hsb.saturation,
                                 colours: [changed(hsb) { $0.saturation = 0 }.color, changed(hsb) { $0.saturation = 1 }.color]) { value in
                    colour = changed(hsb) { $0.saturation = value }
                } done: { commit() }
                HmmChannelSlider(title: "Brightness", value: hsb.brightness, colours: [.black, changed(hsb) { $0.brightness = 1 }.color]) { value in
                    colour = changed(hsb) { $0.brightness = value }
                } done: { commit() }
                HmmChannelSlider(title: "Red", value: colour.red, colours: [.black, .red], scale: 255) { value in
                    colour.red = value
                } done: { commit() }
                HmmChannelSlider(title: "Green", value: colour.green, colours: [.black, .green], scale: 255) { value in
                    colour.green = value
                } done: { commit() }
                HmmChannelSlider(title: "Blue", value: colour.blue, colours: [.black, .blue], scale: 255) { value in
                    colour.blue = value
                } done: { commit() }
                HStack {
                    Text("Hex").font(.hmm(.caption)).frame(width: 74, alignment: .leading)
                    TextField("#RRGGBB", text: $hex)
                        .font(.hmm(.body).monospaced())
                    #if os(iOS)
                        .textInputAutocapitalization(.characters)
                    #endif
                        .autocorrectionDisabled()
                        .onSubmit {
                            if let typed = HmmColour(hex: hex) {
                                colour = typed
                                commit()
                            }
                            hex = colour.hex
                        }
                        .accessibilityIdentifier("colour-hex")
                }
                .frame(minHeight: HmmTarget.minimum)
            }
            .onAppear { hex = colour.hex }
            .onChange(of: colour) { _, new in hex = new.hex }
        }
    }

    /// Palettes: the ones saved on this device, a swatch to choose a colour, + to keep the colour in hand in one, a new
    /// palette, and a palette's hold menu to rename or delete it.
    struct HmmPalettesPage: View {
        @Binding var memory: HmmColourMemory
        let colour: HmmColour
        let choose: (HmmColour) -> Void
        @State private var renaming: HmmPalette?
        @State private var name = ""
        @Environment(\.hmmTheme) private var theme

        var body: some View {
            VStack(alignment: .leading, spacing: HmmSpacing.s) {
                ForEach(memory.palettes) { palette in
                    VStack(alignment: .leading, spacing: HmmSpacing.xxs) {
                        Text(palette.name).font(.hmm(.caption, weight: .semibold)).foregroundStyle(theme.text2)
                        LazyVGrid(columns: Array(repeating: GridItem(.fixed(30), spacing: 6), count: 10), alignment: .leading, spacing: 6) {
                            ForEach(Array(palette.colours.enumerated()), id: \.offset) { _, swatch in
                                Button { choose(swatch) } label: { HmmSwatch(colour: swatch, size: 30, isOn: swatch == colour) }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel(Text(swatch.hex))
                                    .draggable(swatch.hex)
                            }
                            Button { add(to: palette.id) } label: {
                                Image(systemName: "plus").frame(width: 30, height: 30)
                                    .background(theme.surface2, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(Text("Keep this colour in \(palette.name)"))
                        }
                    }
                    .contextMenu {
                        Button("Rename", systemImage: "pencil") {
                            renaming = palette
                            name = palette.name
                        }
                        Button("Delete", systemImage: "trash", role: .destructive) { delete(palette.id) }
                    }
                }
                Button("New palette", systemImage: "plus.square.on.square") { newPalette() }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("palette-new")
            }
            .alert("Rename palette", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
                TextField("Name", text: $name)
                Button("Rename") {
                    if let id = renaming?.id, let index = memory.palettes.firstIndex(where: { $0.id == id }), !name.isEmpty {
                        memory.palettes[index].name = name
                        memory.save()
                    }
                    renaming = nil
                }
                Button("Cancel", role: .cancel) { renaming = nil }
            }
        }

        private func add(to id: String) {
            guard let index = memory.palettes.firstIndex(where: { $0.id == id }) else { return }
            memory.palettes[index].add(colour)
            memory.save()
        }

        /// A new palette starts from the colours used lately.
        private func newPalette() {
            memory.palettes.append(HmmPalette(
                name: "Palette \(memory.palettes.count + 1)",
                colours: memory.history.colours.isEmpty ? [colour] : memory.history.colours
            ))
            memory.save()
        }

        private func delete(_ id: String) {
            memory.palettes.removeAll { $0.id == id }
            memory.save()
        }
    }
#endif
