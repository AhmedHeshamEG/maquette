import HmmDesign
import LoweyCore
import SwiftUI

/// Settings ▸ Pencil and hands ▸ Your Pencil (CONTEXT §4.4): one page with a test pad, and every tool obeys it. A
/// guided calibration (your lightest line, then your heaviest) fits the pressure curve; presets for a light, normal or
/// heavy hand; the curve itself to drag; stabilisation; a Pencil without pressure thins with speed; the hover point;
/// what a double-tap does; the squeeze menu's six slots.
struct PencilPage: View {
    @State private var feel = HmmPencilFeel.load(from: .standard)
    @State private var calibration: Calibration?
    @State private var lightest: [Double] = []
    @State private var pressure = 0.0
    @State private var tilt = 90.0
    @State private var clears = 0
    @AppStorage(AppSettings.pencilHoverPreview) private var pencilHover = false
    @AppStorage(DoubleTapChoice.storageKey) private var doubleTap = DoubleTapChoice.system.rawValue
    @State private var slots = QuickAction.slots()
    @Environment(\.hmmTheme) private var theme

    /// The two calibration strokes, in order.
    enum Calibration {
        case lightest, heaviest
    }

    var body: some View {
        Form {
            Section {
                PencilTestPad(feel: feel, clearCount: clears, sample: { pressure = $0
                    tilt = $1
                }, stroke: heard)
                    .frame(height: 220)
                    .background(RoundedRectangle(cornerRadius: HmmRadius.card).fill(theme.surface2))
                    .accessibilityIdentifier("pencil-test-pad")
                HStack {
                    HStack(spacing: 4) {
                        Text("Pressure")
                        Text(verbatim: "\(Int((pressure * 100).rounded())) %").monospacedDigit()
                    }
                    Spacer()
                    HStack(spacing: 4) {
                        Text("Tilt")
                        Text(verbatim: "\(Int(tilt.rounded()))°").monospacedDigit()
                    }
                    Spacer()
                    Button("Clear") { clears += 1 }
                }
                .font(.hmm(.footnote))
                .foregroundStyle(theme.text2)
            } header: {
                Text("Test pad")
            } footer: {
                Text(calibrationText)
            }
            Section("Pressure") {
                Button(calibration == nil ? "Calibrate: two strokes" : "Start again") {
                    lightest = []
                    calibration = .lightest
                    clears += 1
                }
                .accessibilityIdentifier("pencil-calibrate")
                Picker("Hand", selection: Binding(get: { feel.hand }, set: { choose($0) })) {
                    ForEach(HmmPencilFeel.Hand.allCases) { hand in
                        Text(LocalizedStringKey(hand.title)).tag(hand)
                    }
                }
                .pickerStyle(.segmented)
                PressureCurveEditor(curve: $feel.curve) {
                    feel.hand = .calibrated
                    save()
                }
                LabeledSlider(title: "Stabilisation", value: feel.stabilisation, range: 0 ... 1, format: { "\(Int(($0 * 100).rounded())) %" }) {
                    feel.stabilisation = $0
                } done: { save() }
                Toggle("Thickness follows speed on a Pencil without pressure", isOn: Binding(get: { feel.speedForPressure }, set: {
                    feel.speedForPressure = $0
                    save()
                }))
            }
            Section {
                Toggle("Pencil hover preview", isOn: $pencilHover)
                Picker("Double-tap", selection: $doubleTap) {
                    ForEach(DoubleTapChoice.allCases) { Text(LocalizedStringKey($0.title)).tag($0.rawValue) }
                }
            } header: {
                Text("Hover and double-tap")
            } footer: {
                Text("The iPad's own setting is in Settings ▸ Apple Pencil: the eraser, the last tool or the colours.")
            }
            Section {
                ForEach(slots.indices, id: \.self) { index in
                    Picker(selection: Binding(get: { slots[index] }, set: { action in
                        slots[index] = action
                        QuickAction.save(slots)
                    })) {
                        ForEach(QuickAction.allCases) { Label(LocalizedStringKey($0.title), systemImage: $0.systemImage).tag($0) }
                    } label: {
                        Text("Slot \(index + 1)")
                    }
                }
            } header: {
                Text("Squeeze menu")
            } footer: {
                Text("Squeeze an Apple Pencil Pro and these six open around its tip. A Pencil that can't squeeze opens them with a double-tap.")
            }
        }
        .navigationTitle("Your Pencil")
    }

    private var calibrationText: String {
        switch calibration {
        case .lightest: String(localized: "Draw your lightest line.")
        case .heaviest: String(localized: "Now your heaviest.")
        case nil: String(localized: "Draw to try the curve: the line is as wide as the pressure it gets.")
        }
    }

    /// A stroke on the pad, while calibrating: the lightest, then the heaviest, then the curve that fits them.
    private func heard(_ raw: [Double]) {
        switch calibration {
        case .lightest:
            guard raw.count >= 4 else { return }
            lightest = raw
            calibration = .heaviest
            HmmHaptics.play(.selection)
        case .heaviest:
            guard let curve = HmmPencilFeel.calibrated(lightest: lightest, heaviest: raw) else {
                HmmHaptics.play(.error)
                calibration = .lightest
                return
            }
            feel.curve = curve
            feel.hand = .calibrated
            calibration = nil
            save()
            HmmHaptics.play(.commit)
        case nil:
            break
        }
    }

    private func choose(_ hand: HmmPencilFeel.Hand) {
        feel.hand = hand
        if hand != .calibrated { feel.curve = HmmPencilFeel.curve(for: hand) }
        save()
    }

    private func save() {
        feel.save(to: .standard)
    }
}
