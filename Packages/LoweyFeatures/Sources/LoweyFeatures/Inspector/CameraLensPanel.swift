import HmmDesign
import LoweyCore
import LoweyEngine
import SwiftUI

/// The lens and the frame (F1), on the camera's panel and the camera button's: the body and its millimetres, focus that
/// follows a thing and pulls to the next, the aperture, the frame's shape and its guides, and the rig the camera rides.
struct CameraLensPanel: View {
    @Bindable var editor: EditorModel
    let camera: ObjectID

    var body: some View {
        VStack(alignment: .leading, spacing: HmmSpacing.m) {
            lens
            frame
            rig
        }
        .font(.hmm(.body))
    }

    private var lens: some View {
        let lens = editor.lens(of: camera)
        let sensor = editor.sensor(of: camera)
        return PanelSection("Lens") {
            Picker("Camera body", selection: Binding(get: { sensor }, set: { editor.setSensor($0) })) {
                ForEach(CameraSensor.allCases) { Text(LocalizedStringKey($0.title)).tag($0) }
            }
            .accessibilityIdentifier("camera-body")
            LabeledSlider(title: "Focal length", value: lens?.focalLength(on: sensor) ?? 35, range: max(8 / sensor.cropFactor, 4) ... 300 / sensor.cropFactor,
                          format: { "\(Int($0.rounded())) mm" }, set: { editor.setBodyFocalLength($0, gesture: "focal") }, done: editor.endGesture)
            LabeledSlider(title: "Aperture", value: lens?.aperture ?? 0, range: 0 ... 22, format: { $0 < 0.9 ? "Off" : "f/\(NumberFormat.short($0))" },
                          set: { editor.setCameraProperty(.aperture, $0 < 0.9 ? 0 : $0, gesture: "aperture") }, done: editor.endGesture)
            if let target = editor.focusTarget(of: camera) {
                HStack {
                    Label(String(localized: "Sharp on \(target)"), systemImage: "scope").font(.hmm(.footnote, weight: .semibold))
                    Spacer()
                    HmmPillButton("By distance", systemName: "ruler") { editor.stopFocusFollowing() }
                }
            } else {
                LabeledSlider(title: "Focus", value: lens?.focusDistance ?? 5, range: 0.2 ... 60, format: { "\(NumberFormat.short($0)) m" },
                              set: { editor.setCameraProperty(.focusDistance, $0, gesture: "focus") }, done: editor.endGesture)
            }
            HStack(spacing: HmmSpacing.xs) {
                HmmPillButton("Focus on selection", systemName: "scope") { editor.focusOnSelection(pull: false) }
                    .accessibilityIdentifier("focus-on")
                HmmPillButton("Pull focus here", systemName: "camera.metering.center.weighted") { editor.focusOnSelection(pull: true) }
                    .accessibilityIdentifier("focus-pull")
            }
            .shown(editor.selection.contains { $0 != camera })
            Hint("Select a thing too: the lens follows it. Pull focus here hands the focus to it at the playhead.")
        }
    }

    private var frame: some View {
        PanelSection("Frame") {
            Picker("Frame", selection: $editor.deliveryFraming) {
                ForEach(Framing.allCases) { Text(LocalizedStringKey($0.title)).tag($0) }
            }
            .accessibilityIdentifier("frame-shape")
            Toggle("Thirds", isOn: $editor.showsThirds)
            Toggle("Safe areas", isOn: $editor.showsSafeAreas)
            Hint("The Director view, Frame shot and every video and picture come out in this shape.")
        }
    }

    private var rig: some View {
        let object = editor.displayed.scene.objects[camera]
        let rig = object.map(CameraRig.of) ?? .none
        return PanelSection("Rig") {
            Picker("Rig", selection: Binding(get: { rig }, set: { editor.setRig($0) })) {
                ForEach(CameraRig.allCases) { Text(LocalizedStringKey($0.title)).tag($0) }
            }
            .accessibilityIdentifier("camera-rig")
            ForEach(rig.controls, id: \.self) { key in
                HStack(alignment: .bottom, spacing: HmmSpacing.xs) {
                    LabeledSlider(title: key.spec?.label ?? key.rawValue, value: object?[key]?.floatValue ?? Self.fallback(key), range: Self.range(key),
                                  format: Self.format(key), set: { editor.setCameraProperty(key, $0, gesture: "rig-\(key.rawValue)") },
                                  done: editor.endGesture)
                    if key.spec?.animatable == true {
                        Button {
                            editor.keyRig(key)
                        } label: {
                            Image(systemName: editor.isKeyed(key, on: camera) ? "diamond.fill" : "diamond")
                        }
                        .buttonStyle(.plain)
                        .frame(width: 44, height: 44)
                        .accessibilityLabel(String(localized: "Key \(key.spec?.label ?? key.rawValue) at the playhead"))
                    }
                }
            }
            if rig != .none {
                Hint("Key a number at one moment, change the playhead and move it: the rig moves between them.")
            }
        }
    }

    static func fallback(_ key: PropertyKey) -> Double {
        switch key {
        case .rigArm: 3
        case .rigShake: 0.5
        default: 0
        }
    }

    static func range(_ key: PropertyKey) -> ClosedRange<Double> {
        switch key {
        case .rigTravel: -10 ... 10
        case .rigLift: -3 ... 8
        case .rigSwing: -180 ... 180
        case .rigArm: 0.5 ... 10
        default: 0 ... 1
        }
    }

    static func format(_ key: PropertyKey) -> (Double) -> String {
        switch key {
        case .rigSwing: { "\(Int($0.rounded()))°" }
        case .rigShake: NumberFormat.percent
        default: { "\(NumberFormat.short($0)) m" }
        }
    }
}
