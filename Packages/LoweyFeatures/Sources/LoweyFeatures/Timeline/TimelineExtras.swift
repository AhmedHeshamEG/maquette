import HmmDesign
import LoweyCore
import SwiftUI

/// Frame rate, length, the project's stepping.
struct TimelineSettingsSheet: View {
    let editor: EditorModel
    @State private var length: Double = 10

    var body: some View {
        HmmSheet("Timeline") {
            HmmSectionHeader("Frame rate")
            Picker("Frame rate", selection: Binding(get: { editor.timeline.fps }, set: { editor.setFrameRate($0) })) {
                ForEach(Timeline.frameRates, id: \.self) { Text("\($0) fps").tag($0) }
            }
            .pickerStyle(.segmented)
            LabeledSlider(title: "Length", value: length, range: 1 ... 120, format: { "\(NumberFormat.short($0)) s" }, set: { length = $0 },
                          done: { editor.setDuration(length) })
            HmmPillButton("Fit to the animation") {
                editor.fitDurationToContent()
                length = editor.timeline.duration
            }
            HmmSectionHeader("Stepping (the whole project)")
            Picker("Stepping", selection: Binding(get: { editor.timeline.stepping }, set: { editor.setProjectStepping($0) })) {
                Text("On ones").tag(Stepping.onOnes)
                Text("On twos").tag(Stepping.onTwos)
                Text("On threes").tag(Stepping.onThrees)
                Text("On fours").tag(Stepping.onFours)
            }
            .pickerStyle(.segmented)
            Hint("On twos looks hand-animated. Cameras stay smooth; any object can choose its own in the inspector.")
        }
        .onAppear { length = editor.timeline.duration }
    }
}

/// What a touch performs while the timeline records: moving, sizing and turning, or one number (glow, light strength,
/// focal length, opacity…). Chosen in the timeline's menu; the number's slider then sits beside Record.
enum PerformValueOptions {
    struct Option: Identifiable {
        let key: PropertyKey
        let title: String
        let range: ClosedRange<Double>
        var id: String { key.rawValue }
    }

    @MainActor
    static func options(for editor: EditorModel) -> [Option] {
        guard let object = editor.singleSelection else { return [] }
        if object.kind == .camera {
            return [Option(key: .fieldOfView, title: "Zoom", range: 10 ... 100), Option(key: .focusDistance, title: "Focus", range: 0.2 ... 40)]
        }
        var result = [Option(key: .opacity, title: "Opacity", range: 0 ... 1)]
        if object.kind.hasSurface { result.append(Option(key: .emissiveIntensity, title: "Glow", range: 0 ... 8)) }
        if case .light = object.kind { result.append(Option(key: .lightIntensity, title: "Light", range: 0 ... 6)) }
        return result
    }
}

/// The menu's choice of what a touch performs.
struct PerformValueMenu: View {
    @Bindable var editor: EditorModel

    var body: some View {
        let options = PerformValueOptions.options(for: editor)
        if !options.isEmpty {
            Menu("A touch performs…", systemImage: "hand.draw") {
                Button("Move, size and turn") { editor.performSliderKey = nil }
                ForEach(options) { option in
                    Button(LocalizedStringKey(option.title)) { editor.performSliderKey = option.key }
                }
            }
        }
    }
}

/// The performed number's slider, beside Record while one is chosen.
struct PerformValueSlider: View {
    @Bindable var editor: EditorModel
    @State private var value: Double = 0

    var body: some View {
        if let key = editor.performSliderKey, let option = PerformValueOptions.options(for: editor).first(where: { $0.key == key }) {
            HStack(spacing: HmmSpacing.xs) {
                Text(LocalizedStringKey(option.title)).font(.hmm(.footnote, weight: .semibold))
                Slider(value: $value, in: option.range) { editing in
                    if !editing { editor.performValue(key, value, touching: false) }
                }
                .frame(width: 160)
                .onChange(of: value) { _, newValue in editor.performValue(key, newValue, touching: true) }
                .accessibilityLabel(option.title)
            }
            .onAppear { value = editor.singleSelection?[key]?.floatValue ?? option.range.lowerBound }
        }
    }
}

/// "Ready 3-2-1" and the recording badge.
struct PerformCountdown: View {
    let editor: EditorModel
    @Environment(\.hmmTheme) private var theme

    var body: some View {
        ZStack {
            switch editor.performPhase {
            case .ready:
                VStack(spacing: HmmSpacing.xs) {
                    Text("Ready").font(.hmm(.title2, weight: .semibold))
                    Text("Touch and move to perform. Time runs while you touch.").font(.hmm(.body)).foregroundStyle(theme.text2)
                }
                .padding(.horizontal, HmmSpacing.l)
                .padding(.vertical, HmmSpacing.m)
                .hmmPanelBackground(cornerRadius: 26)
                .frame(maxHeight: .infinity, alignment: .top)
                .padding(.top, 70)
                .transition(.opacity)
                .accessibilityIdentifier("perform-ready")
            case let .countdown(count):
                VStack(spacing: HmmSpacing.xs) {
                    Text("Ready").font(.hmm(.title3, weight: .semibold))
                    Text("\(count)").font(.system(size: 96, weight: .heavy, design: .rounded)).monospacedDigit()
                    Text(editor.virtualCameraActive ? "Move the iPad when it plays" : "Touch and move when it plays").font(.hmm(.body))
                        .foregroundStyle(theme.text2)
                }
                .padding(HmmSpacing.xl)
                .hmmPanelBackground(cornerRadius: 30)
                .transition(.scale.combined(with: .opacity))
                .accessibilityIdentifier("perform-countdown")
            case .recording:
                HStack(spacing: HmmSpacing.xs) {
                    Circle().fill(theme.record).frame(width: 12, height: 12)
                    Text("REC").font(.hmm(.body, weight: .semibold))
                    Text(editor.performTouching ? "recording" : "lift = paused").font(.hmm(.footnote)).foregroundStyle(theme.text2)
                }
                .padding(.horizontal, HmmSpacing.m)
                .padding(.vertical, HmmSpacing.xs)
                .hmmGlass(in: Capsule(), interactive: false)
                .frame(maxHeight: .infinity, alignment: .top)
                .padding(.top, 70)
                .accessibilityIdentifier("perform-recording")
            case .idle:
                EmptyView()
            }
        }
        .allowsHitTesting(false)
        .animation(.hmmStandard, value: editor.performPhase)
    }
}
