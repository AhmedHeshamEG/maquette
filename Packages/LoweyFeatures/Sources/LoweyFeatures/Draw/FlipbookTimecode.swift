import HmmDesign
import LoweyCore
import SwiftUI

/// The time and the drawing at the bottom left while frames are drawn (Dreams' way, U5); tap it for the onion skins:
/// how many drawings show before and after this one (up to eight) and their colours.
struct FlipbookTimecode: View {
    @Bindable var editor: EditorModel
    @State private var open = false
    @Environment(\.hmmTheme) private var theme

    var body: some View {
        Button {
            HmmHaptics.play(.selection)
            open = true
        } label: {
            HStack(spacing: HmmSpacing.xs) {
                Text(verbatim: TimeFormat.clock(editor.time)).font(.hmmNumbers(.body, weight: .semibold))
                if let frame = editor.activeFlipbookFrame {
                    Text("Drawing \(frame + 1)").font(.hmm(.caption)).foregroundStyle(theme.text2)
                }
                Image(systemName: "circle.dotted.circle").foregroundStyle(editor.flipbook.onionSkin ? theme.accent : theme.text3)
            }
            .padding(.horizontal, HmmSpacing.s)
            .frame(minHeight: HmmTarget.minimum)
            .hmmGlass(in: Capsule(), interactive: false)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Onion skins"))
        .accessibilityValue(Text(verbatim: TimeFormat.clock(editor.time)))
        .accessibilityIdentifier("flipbook-timecode")
        .popover(isPresented: $open, arrowEdge: .bottom) {
            onionSkins
                .padding(HmmSpacing.m)
                .frame(width: 300)
                .presentationCompactAdaptation(.popover)
        }
    }

    private var onionSkins: some View {
        VStack(alignment: .leading, spacing: HmmSpacing.s) {
            HmmSectionHeader("Onion skins")
            Toggle("Show the drawings around this one", isOn: $editor.flipbook.onionSkin)
                .accessibilityIdentifier("onion-skin")
            if editor.flipbook.onionSkin {
                Stepper("Before: \(editor.flipbook.onionBefore)", value: $editor.flipbook.onionBefore, in: 0 ... 8)
                    .accessibilityIdentifier("onion-before")
                ColorPicker("Before", selection: colour(\.onionBeforeColour), supportsOpacity: false)
                Stepper("After: \(editor.flipbook.onionAfter)", value: $editor.flipbook.onionAfter, in: 0 ... 8)
                    .accessibilityIdentifier("onion-after")
                ColorPicker("After", selection: colour(\.onionAfterColour), supportsOpacity: false)
            }
        }
        .font(.hmm(.body))
    }

    private func colour(_ key: WritableKeyPath<FlipbookSettings, RGBA>) -> Binding<Color> {
        Binding(get: { editor.flipbook[keyPath: key].color }, set: { value in
            let resolved = UIColor(value).resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
            var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
            resolved.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
            editor.flipbook[keyPath: key] = RGBA(Double(red), Double(green), Double(blue))
        })
    }
}
