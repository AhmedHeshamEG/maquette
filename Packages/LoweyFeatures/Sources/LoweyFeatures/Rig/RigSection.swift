import HmmDesign
import LoweyCore
import SwiftUI

/// Rig: give anything a skeleton, fast, and change it afterwards (CONTEXT §10.10, ToonSquid the bar). With nothing on
/// it yet: the four body shortcuts, or pins and dots by hand. Rigged: change the rig (it relaxes to its rest shape
/// and shows its marks), put the pose back, and one step deeper, how it bends.
struct RigSection: View {
    @Bindable var editor: EditorModel

    var body: some View {
        if editor.selection.count > 1 {
            PanelSection("Rig") {
                HmmPillButton("Rig these together", systemName: "square.on.square", prominent: true) { editor.rigTogether() }
                    .accessibilityIdentifier("rig-together")
                Hint("They become one thing: each part rides the bone nearest it, and a dot between two parts hinges them.")
            }
        } else if let object = editor.rigSubject, editor.castType(of: object.id) == nil || object.rig != nil {
            PanelSection("Rig") {
                if let blocker = editor.rigBlocker(object) {
                    Hint(blocker)
                } else if object.rig == nil, editor.rigging.weighing[object.id] == nil {
                    start(object)
                } else {
                    rigged(object)
                }
                if editor.canMakeCharacter(object) {
                    HmmPillButton("Make it a character", systemName: "face.smiling") { editor.makeCharacter(from: object.id) }
                        .accessibilityIdentifier("rig-make-character")
                }
            }
        }
    }

    @ViewBuilder private func start(_ object: SceneObject) -> some View {
        TileGrid {
            ForEach(shortcuts(for: object)) { body in
                TileButton(title: body.title, systemName: body.systemImage, identifier: "rig-body-\(body.rawValue)") {
                    editor.startBody(body, on: object.id)
                }
            }
        }
        HmmPillButton("Pins and dots", systemName: RigSettings.Mode.marks.systemImage) { editor.startMarking(object.id) }
            .accessibilityIdentifier("rig-marks")
        Hint("Tap a dot on each joint (a shoulder, an elbow, a wrist), or pins where a soft thing holds and bends. Drag them to pose it.")
    }

    /// A drawing lies on a plane: a person, four legs or wings can't be read from it; a chain and marks can.
    private func shortcuts(for object: SceneObject) -> [BodyShortcut] {
        if case .drawing = object.kind { return [.chain] }
        return BodyShortcut.allCases
    }

    @ViewBuilder private func rigged(_ object: SceneObject) -> some View {
        HmmPillButton("Change the rig", systemName: "slider.horizontal.3", prominent: true) { editor.startMarking(object.id) }
            .accessibilityIdentifier("rig-change")
        Hint(object.kind == .group ? "Each part rides the bone nearest it. Drag a hand or a foot on the stage to pose it."
            : "Drag its joints on the stage to pose it. Change the rig any time: the pose and the keys stay.")
        HmmPillButton("Reset the pose", systemName: "arrow.uturn.backward") { editor.resetPose(object.id) }
            .accessibilityIdentifier("rig-reset-pose")
        if object.kind != .group {
            DisclosureRow("How it bends", systemName: "point.3.connected.trianglepath.dotted", identifier: "rig-bending") { bending(object) }
        }
        DangleControl(editor: editor, character: object.id)
        HmmPillButton("Remove the rig", systemName: "trash", role: .destructive) { editor.removeRig(object.id) }
            .accessibilityIdentifier("rig-remove")
    }

    @ViewBuilder private func bending(_ object: SceneObject) -> some View {
        if editor.rigFits(object) {
            Hint("The skin follows the bones by itself. Paint a bone's weight only where a bend looks wrong.")
            HmmPillButton("Paint weights", systemName: RigSettings.Mode.weights.systemImage) { editor.startPaintingWeights(object.id) }
                .accessibilityIdentifier("rig-weights")
        } else {
            Hint("The shape changed since it was rigged.")
            HmmPillButton("Fit the weights to the new shape", systemName: "arrow.triangle.2.circlepath", prominent: true) {
                editor.refitRig(object.id)
            }
            .accessibilityIdentifier("rig-refit")
        }
    }
}

/// Under the stage while Rig is on: pins or dots for the Pencil, a person's Rig button, the weight brush's bone, Done.
struct RigOptionsBar: View {
    @Bindable var editor: EditorModel
    @Environment(\.hmmTheme) private var theme

    var body: some View {
        HStack(spacing: HmmSpacing.xs) {
            if editor.rigging.person != nil {
                Text("Drag a dot that's wrong, then Rig").font(.hmm(.body, weight: .semibold))
                HmmPillButton("Rig", systemName: "checkmark", prominent: true) { editor.finishPersonRig() }
                    .accessibilityIdentifier("rig-person-done")
                HmmButton("xmark", label: "Cancel", size: 36) {
                    editor.cancelPersonRig()
                    editor.tool = .select
                }
            } else if editor.rigging.mode == .weights, let rig = editor.rigTarget?.rig {
                jointMenu(rig)
                ChoiceChip(title: "Erase", systemName: "eraser", isOn: editor.rigging.erase) { editor.rigging.erase.toggle() }
                HmmButton("checkmark", label: "Done", size: 36) {
                    if let id = editor.rigTarget?.id { editor.startMarking(id) }
                }
            } else {
                ForEach(RigMark.Kind.allCases, id: \.self) { kind in
                    ChoiceChip(title: kind == .dot ? "Dots" : "Pins", systemName: kind == .dot ? "smallcircle.filled.circle" : "pin.fill",
                               isOn: editor.rigging.markKind == kind) { editor.rigging.markKind = kind }
                        .accessibilityIdentifier("rig-kind-\(kind.rawValue)")
                }
                HmmButton("checkmark", label: "Done rigging", size: 36) { editor.tool = .select }
                    .accessibilityIdentifier("rig-done")
            }
        }
        .padding(HmmSpacing.xs)
        .hmmPanelBackground()
    }

    private func jointMenu(_ rig: ObjectRig) -> some View {
        Menu {
            ForEach(rig.skeleton.joints.indices.filter { !RigMarks.isBetween(rig.skeleton.joints[$0].name) }, id: \.self) { index in
                Button(rig.skeleton.joints[index].name) { editor.rigging.joint = index }
            }
        } label: {
            Group {
                if let name = editor.rigging.joint.flatMap({ rig.skeleton.joints[safe: $0]?.name }) {
                    Label(name, systemImage: "point.3.connected.trianglepath.dotted")
                } else {
                    Label("Choose a bone", systemImage: "point.3.connected.trianglepath.dotted")
                }
            }
            .font(.hmm(.body, weight: .semibold))
            .foregroundStyle(theme.accent)
        }
        .accessibilityIdentifier("rig-joint")
    }
}

/// The person rig's dots over the stage: drag any of them.
struct PersonDotMarks: View {
    let editor: EditorModel
    @Environment(\.hmmTheme) private var theme

    var body: some View {
        let revision = editor.displayRevision + Int(editor.viewYaw)
        let dots = revision >= 0 ? editor.personDotsOnScreen() : []
        ZStack {
            ForEach(dots, id: \.dot) { item in
                Circle()
                    .fill(theme.accent)
                    .overlay(Circle().stroke(Color.white.opacity(0.85), lineWidth: 1.5))
                    .frame(width: 22, height: 22)
                    .contentShape(Circle().inset(by: -10))
                    .position(item.point)
                    .gesture(DragGesture(coordinateSpace: .named("person-dots")).onChanged { editor.movePersonDot(item.dot, to: $0.location) })
                    .accessibilityLabel(item.dot.title)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .coordinateSpace(.named("person-dots"))
    }
}

/// Pins and dots over the stage, where they can be touched: drag one to move it, hold one to take it away, tap one so
/// the next hangs from it (it glows). A dot is a joint; a pin, a soft bend.
struct RigMarksOverlay: View {
    let editor: EditorModel
    @Environment(\.hmmTheme) private var theme

    var body: some View {
        let revision = editor.displayRevision + Int(editor.viewYaw)
        let marks = revision >= 0 ? editor.marksOnScreen() : []
        ZStack {
            ForEach(marks, id: \.mark.name) { item in
                mark(item.mark)
                    .position(item.point)
                    .gesture(DragGesture(minimumDistance: 4, coordinateSpace: .named("rig-marks"))
                        .onChanged { editor.dragMark(item.mark.name, to: $0.location, ended: false) }
                        .onEnded { editor.dragMark(item.mark.name, to: $0.location, ended: true) })
                    .simultaneousGesture(LongPressGesture(minimumDuration: 0.5).onEnded { _ in editor.removeMark(item.mark.name) })
                    .onTapGesture(count: 2) { editor.toggleMarkKind(item.mark.name) }
                    .onTapGesture {
                        editor.rigging.current = item.mark.name
                        HmmHaptics.play(.selection)
                    }
                    .accessibilityLabel(item.mark.kind == .dot ? "Dot" : "Pin")
                    .accessibilityHint("Drag to move it; touch and hold to take it away")
                    .accessibilityIdentifier("rig-mark-\(item.mark.name)")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .coordinateSpace(.named("rig-marks"))
    }

    @ViewBuilder private func mark(_ mark: RigMark) -> some View {
        let current = editor.rigging.current == mark.name
        Group {
            if mark.kind == .dot {
                Circle().fill(current ? theme.accent : Color.white)
                    .overlay(Circle().stroke(Color.black.opacity(0.35), lineWidth: 1))
                    .frame(width: current ? 20 : 16, height: current ? 20 : 16)
            } else {
                Image(systemName: "pin.fill")
                    .font(.system(size: current ? 22 : 18, weight: .semibold))
                    .foregroundStyle(current ? theme.accent : Color.white)
                    .shadow(color: .black.opacity(0.4), radius: 1)
            }
        }
        .frame(width: 44, height: 44)
        .contentShape(Rectangle())
    }
}
