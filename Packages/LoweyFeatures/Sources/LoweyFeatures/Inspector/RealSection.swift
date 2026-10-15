import HmmDesign
import LoweyCore
import SwiftUI

/// Real (P1), on a thing's panel: a switch, what it's made of in words, how it moves. Its mass comes from the
/// material and its real size; the exact numbers are one step deeper. Joints, Settle and "does it stand?" sit here
/// because they're about this thing.
struct RealSection: View {
    @Bindable var editor: EditorModel
    let object: SceneObject
    @State private var gesture = UUID().uuidString
    @Environment(\.hmmTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: HmmSpacing.s) {
            Toggle("Real", isOn: Binding(get: { object.physics != nil }, set: { $0 ? editor.makeReal() : editor.makeUnreal() }))
                .font(.hmm(.body))
                .accessibilityIdentifier("real-toggle")
            if let physics = object.physics {
                materials(physics)
                motion(physics)
                weight
                if physics.material == .cloth, physics.motion == .falls {
                    Toggle("Hangs from its top edge", isOn: Binding(get: { physics.hangs ?? false }, set: { value in
                        editor.changePhysics("Hangs") { $0.hangs = value }
                    }))
                    .font(.hmm(.body))
                    .accessibilityIdentifier("real-hangs")
                }
                JointRows(editor: editor)
                actions
                DisclosureRow("Exact numbers", systemName: "number", identifier: "real-numbers") {
                    RealNumbers(editor: editor, physics: physics)
                }
            } else {
                Hint("A real thing falls, collides and is pushed, with the weight of what it's made of.")
            }
        }
    }

    private func materials(_ physics: ObjectPhysics) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: HmmSpacing.xxs) {
                ForEach(PhysicsMaterial.allCases) { material in
                    Button {
                        editor.changePhysics("Real: \(material.title)") { $0.material = material }
                    } label: {
                        Label(material.title, systemImage: material.systemImage)
                            .font(.hmm(.footnote, weight: material == physics.material ? .semibold : .regular))
                            .padding(.horizontal, HmmSpacing.s)
                            .frame(minHeight: 36)
                            .background(material == physics.material ? theme.accent.opacity(0.25) : theme.surface2, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(material == physics.material ? .isSelected : [])
                    .accessibilityIdentifier("real-material-\(material.rawValue)")
                }
            }
        }
    }

    private func motion(_ physics: ObjectPhysics) -> some View {
        Picker("How it moves", selection: Binding(get: { physics.motion }, set: { value in
            editor.changePhysics(value.title) { $0.motion = value }
        })) {
            ForEach(ObjectPhysics.Motion.allCases, id: \.self) { motion in
                Text(motion.title).tag(motion)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("real-motion")
    }

    @ViewBuilder
    private var weight: some View {
        if let frames = editor.physicsRun.frames, let index = frames.bodies.firstIndex(of: object.id), frames.masses[index] > 0 {
            HStack {
                Text("Weighs").foregroundStyle(theme.text2)
                Spacer()
                Text(Self.mass(frames.masses[index])).monospacedDigit()
                    .accessibilityIdentifier("real-mass")
            }
            .font(.hmm(.body))
        }
    }

    static func mass(_ kilograms: Double) -> String {
        kilograms < 1 ? "\(Int((kilograms * 1000).rounded())) g" : kilograms < 100 ? String(format: "%.1f kg", kilograms) : "\(Int(kilograms.rounded())) kg"
    }

    private var actions: some View {
        HStack(spacing: HmmSpacing.xs) {
            HmmPillButton("Settle", systemName: "arrow.down.to.line") { editor.settleSelection() }
                .accessibilityIdentifier("real-settle")
            HmmPillButton("Does it stand?", systemName: "figure.stand") { editor.checkStands() }
                .accessibilityIdentifier("real-stands")
            if let frames = editor.physicsRun.frames, frames.isComplete {
                HmmPillButton("Keep it", systemName: "key") { editor.keepRun() }
                    .accessibilityIdentifier("real-keep")
            }
        }
    }
}

/// Several things at once: all real (in one material) or none, and joining two of them.
struct RealSeveral: View {
    @Bindable var editor: EditorModel

    var body: some View {
        VStack(alignment: .leading, spacing: HmmSpacing.s) {
            let real = editor.realSelection.count
            HStack(spacing: HmmSpacing.xs) {
                HmmPillButton(real == editor.selection.count ? "All real" : "Make them real", systemName: "atom", prominent: real < editor.selection.count) {
                    editor.makeReal()
                }
                .accessibilityIdentifier("real-several")
                if real > 0 {
                    HmmPillButton("Not real", systemName: "xmark") { editor.makeUnreal() }
                        .accessibilityIdentifier("real-several-off")
                }
            }
            Menu {
                ForEach(PhysicsMaterial.allCases) { material in
                    Button(material.title, systemImage: material.systemImage) { editor.makeReal(material) }
                }
            } label: {
                Label("Made of…", systemImage: "square.stack.3d.up").font(.hmm(.body)).frame(minHeight: 44)
            }
            .accessibilityIdentifier("real-several-material")
            if editor.selection.count == 2 { JointRows(editor: editor) }
        }
    }
}

/// The joints that hold the selected thing, and a way to add one.
struct JointRows: View {
    @Bindable var editor: EditorModel
    @Environment(\.hmmTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: HmmSpacing.xxs) {
            ForEach(editor.selectedJoints) { joint in
                JointRow(editor: editor, joint: joint)
            }
            Menu {
                ForEach(PhysicsJoint.Kind.allCases, id: \.self) { kind in
                    Button(kind.title, systemImage: kind.systemImage) { editor.join(kind) }
                }
            } label: {
                Label(editor.selection.count > 1 ? "Join them" : "Join to the world", systemImage: "link.badge.plus")
                    .font(.hmm(.body))
                    .frame(minHeight: 44)
            }
            .accessibilityIdentifier("real-join")
        }
    }
}

struct JointRow: View {
    @Bindable var editor: EditorModel
    let joint: PhysicsJoint
    @State private var gesture = UUID().uuidString
    @Environment(\.hmmTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: HmmSpacing.xxs) {
            HStack {
                Label(title, systemImage: joint.kind.systemImage).font(.hmm(.body))
                Spacer()
                HmmButton("xmark", label: "Remove the \(joint.kind.title.lowercased())", size: 32) { editor.removeJoint(joint.id) }
                    .accessibilityIdentifier("joint-remove-\(joint.id)")
            }
            if joint.kind == .hinge || joint.kind == .slider {
                HmmNumberPill(joint.kind == .hinge ? "Motor °/s" : "Motor m/s", value: Binding(get: { joint.motorSpeed ?? 0 }, set: { value in
                    editor.changeJoint(joint.id, coalesce: gesture) { $0.motorSpeed = abs(value) < 1e-6 ? nil : value }
                }), scrub: HmmScrub(fine: joint.kind == .hinge ? 1 : 0.01, range: -3600 ... 3600), format: { String(format: "%.2g", $0) },
                onEditingChanged: { editing in
                    if !editing {
                        editor.endGesture()
                        gesture = UUID().uuidString
                    }
                })
                .accessibilityIdentifier("joint-motor-\(joint.id)")
            }
            if joint.kind == .spring {
                HmmNumberPill("Bounces a second", value: Binding(get: { joint.springiness ?? 2 }, set: { value in
                    editor.changeJoint(joint.id, coalesce: gesture) { $0.springiness = max(value, 0.1) }
                }), scrub: HmmScrub(fine: 0.1, range: 0.1 ... 30), format: { String(format: "%.1f", $0) })
                    .accessibilityIdentifier("joint-spring-\(joint.id)")
            }
        }
    }

    private var title: String {
        let other = joint.second.flatMap { editor.baseScene.objects[$0]?.name }
        let mine = editor.baseScene.objects[joint.first]?.name ?? ""
        let partner = editor.singleSelection?.id == joint.first ? other : mine
        return partner.map { "\(joint.kind.title) to \($0)" } ?? "\(joint.kind.title) to the world"
    }
}

/// One step deeper: the numbers a material stands for, the speed it starts with, breaking, stiffness, the arrows.
struct RealNumbers: View {
    @Bindable var editor: EditorModel
    let physics: ObjectPhysics
    @State private var gesture = UUID().uuidString

    var body: some View {
        VStack(alignment: .leading, spacing: HmmSpacing.s) {
            HmmNumberPill("Mass kg", value: Binding(get: { physics.mass ?? 0 }, set: { value in
                editor.changePhysics("Mass", coalesce: gesture) { $0.mass = value > 0 ? value : nil }
            }), scrub: HmmScrub(fine: 0.1, range: 0 ... 1_000_000), format: { $0 > 0 ? String(format: "%.2f", $0) : String(localized: "From its size") },
            onEditingChanged: done)
                .accessibilityIdentifier("real-mass-number")
            LabeledSlider(title: "Grip", value: physics.effectiveFriction, range: 0 ... 1, format: { String(format: "%.2f", $0) }) { value in
                editor.changePhysics("Grip", coalesce: gesture) { $0.friction = value }
            } done: { done(false) }
                .accessibilityIdentifier("real-friction")
            LabeledSlider(title: "Bounce", value: physics.effectiveBounce, range: 0 ... 1, format: { String(format: "%.2f", $0) }) { value in
                editor.changePhysics("Bounce", coalesce: gesture) { $0.bounce = value }
            } done: { done(false) }
                .accessibilityIdentifier("real-bounce")
            if physics.material.body != .rigid {
                LabeledSlider(title: "Stiffness", value: physics.effectiveStiffness, range: 0 ... 1, format: { String(format: "%.2f", $0) }) { value in
                    editor.changePhysics("Stiffness", coalesce: gesture) { $0.stiffness = value }
                } done: { done(false) }
                    .accessibilityIdentifier("real-stiffness")
            } else {
                Toggle("Breaks when knocked hard", isOn: Binding(get: { physics.effectiveBreaks }, set: { value in
                    editor.changePhysics("Breaks") { $0.breaks = value }
                }))
                .font(.hmm(.body))
                .accessibilityIdentifier("real-breaks")
            }
            HStack(spacing: HmmSpacing.xxs) {
                ForEach(0 ..< 3, id: \.self) { axis in
                    HmmNumberPill(["Start x m/s", "y", "z"][axis], value: Binding(get: { component(physics.startSpeed, axis) }, set: { value in
                        editor.changePhysics("Start speed", coalesce: gesture) { $0.startSpeed = setting(physics.startSpeed, axis, value) }
                    }), scrub: HmmScrub(fine: 0.05, range: -100 ... 100), format: { String(format: "%.2f", $0) }, onEditingChanged: done)
                        .accessibilityIdentifier("real-speed-\(axis)")
                }
            }
            Toggle("Show speed and forces", isOn: Binding(get: { editor.physicsRun.showsArrows }, set: { value in
                editor.physicsRun.showsArrows = value
                editor.refreshPhysicsOverlay()
            }))
            .font(.hmm(.body))
            .accessibilityIdentifier("real-arrows")
        }
    }

    private func done(_ editing: Bool) {
        guard !editing else { return }
        editor.endGesture()
        gesture = UUID().uuidString
    }

    private func component(_ vector: Vec3?, _ axis: Int) -> Double {
        guard let vector else { return 0 }
        return [vector.x, vector.y, vector.z][axis]
    }

    private func setting(_ vector: Vec3?, _ axis: Int, _ value: Double) -> Vec3? {
        var parts = [vector?.x ?? 0, vector?.y ?? 0, vector?.z ?? 0]
        parts[axis] = value
        let result = Vec3(parts[0], parts[1], parts[2])
        return result.length < 1e-9 ? nil : result
    }
}
