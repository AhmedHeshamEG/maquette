import HmmDesign
import LoweyCore
import SwiftUI

/// Animate's bar under the stage (A1, six verbs): Path (draw where the thing goes), Look at, Pick up, Properties (key
/// any of them), Ghosts (where it was and will be, while scrubbing) and the Dope sheet. Above it, the chip of a drawn
/// path: its timing, even speed, facing the way it goes, leaning into turns, its front.
struct AnimateBar: View {
    @Bindable var editor: EditorModel
    @State private var properties = false
    @Environment(\.hmmTheme) private var theme

    var body: some View {
        VStack(spacing: HmmSpacing.xs) {
            if let verb = editor.animate.verb {
                hint(verb)
            }
            if editor.animate.verb == .path, editor.animateSubject != nil { MotionPathChip(editor: editor) }
            bar
        }
    }

    private var bar: some View {
        HStack(spacing: HmmSpacing.xxs) {
            ForEach(AnimateVerb.allCases) { verb in
                HmmButton(verb.systemImage, label: verb.title, isOn: editor.animate.verb == verb, accent: editor.animate.verb == verb) {
                    editor.chooseAnimateVerb(verb)
                }
                .accessibilityIdentifier("animate-\(verb.rawValue)")
            }
            HmmButton("slider.horizontal.3", label: "Properties", isOn: properties) { properties = true }
                .disabled(editor.animateSubject == nil)
                .accessibilityIdentifier("animate-properties")
                .popover(isPresented: $properties, arrowEdge: .bottom) {
                    AnimatePropertiesPopover(editor: editor)
                        .presentationCompactAdaptation(.popover)
                }
            HmmButton("square.stack.3d.forward.dottedline", label: "Ghosts", isOn: editor.animate.ghosts) {
                editor.animate.ghosts.toggle()
                HmmHaptics.play(.selection)
            }
            .accessibilityIdentifier("animate-ghosts")
            HmmButton("tablecells", label: "Dope sheet", isOn: editor.timelineStyle == .dopeSheet) {
                editor.timelineStyle = editor.timelineStyle == .dopeSheet ? .motion : .dopeSheet
                if editor.timelinePresence != .full { editor.timelinePresence = .full }
                HmmHaptics.play(.selection)
            }
            .accessibilityIdentifier("animate-dope-sheet")
        }
        .padding(HmmSpacing.xxs)
        .environment(\.hmmInsideGlass, true)
        .hmmGlass(in: Capsule(), interactive: false)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("animate-bar")
    }

    /// The verb's one line, and who holds the thing now while Pick up is in the hand.
    private func hint(_ verb: AnimateVerb) -> some View {
        let held = verb == .pickUp ? editor.heldBy.map { " \($0) holds it now." } ?? "" : ""
        return Text(LocalizedStringKey(verb.hint + held))
            .font(.hmm(.footnote))
            .foregroundStyle(theme.text2)
            .padding(.horizontal, HmmSpacing.s)
            .padding(.vertical, HmmSpacing.xxs)
            .hmmGlass(in: Capsule(), interactive: false)
            .accessibilityIdentifier("animate-hint")
    }
}

/// A drawn path's chip: how long it lasts (drag the number to stretch or squeeze it), even speed, facing the way it
/// goes, leaning into turns, and a quarter turn of its front for a model that faces another way.
struct MotionPathChip: View {
    @Bindable var editor: EditorModel
    @State private var gesture = UUID().uuidString

    var body: some View {
        HStack(spacing: HmmSpacing.xxs) {
            if let duration = editor.motionDuration {
                HmmNumberPill("Lasts", value: Binding(get: { duration }, set: { editor.retimeMotion(to: $0, gesture: gesture) }),
                              scrub: HmmScrub(fine: 0.02, range: 0.1 ... 120), format: { "\(NumberFormat.short($0)) s" },
                              onEditingChanged: { editing in
                                  if !editing {
                                      editor.endGesture()
                                      gesture = UUID().uuidString
                                  }
                              })
                              .accessibilityIdentifier("path-duration")
                HmmButton("speedometer", label: "Even speed") { editor.evenSpeed() }
                    .accessibilityIdentifier("path-even-speed")
                HmmButton("arrow.clockwise", label: "Turn its front") { editor.turnFront() }
                    .accessibilityIdentifier("path-front")
            }
            HmmButton("location.north.line", label: "Face the way it goes", isOn: editor.animate.facesTheWay) {
                editor.animate.facesTheWay.toggle()
            }
            .accessibilityIdentifier("path-faces")
            HmmButton("airplane", label: "Lean into turns", isOn: editor.animate.banks) { editor.animate.banks.toggle() }
                .disabled(!editor.animate.facesTheWay)
                .accessibilityIdentifier("path-banks")
        }
        .padding(HmmSpacing.xxs)
        .environment(\.hmmInsideGlass, true)
        .hmmGlass(in: Capsule(), interactive: false)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("path-chip")
    }
}

/// Animate ▸ Properties: everything the selection has that can move, each keyed at the playhead with one tap (a key
/// mark shows what moves already; after the first key, changing it keys itself).
struct AnimatePropertiesPopover: View {
    let editor: EditorModel
    @Environment(\.hmmTheme) private var theme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Key at the playhead").font(.hmm(.footnote, weight: .semibold)).foregroundStyle(theme.text2)
                    .padding(.horizontal, HmmSpacing.m).padding(.vertical, HmmSpacing.xs)
                ForEach(editor.animatableChoices) { choice in
                    Button {
                        editor.keyProperty(choice.key)
                    } label: {
                        HStack {
                            Text(LocalizedStringKey(choice.title)).font(.hmm(.body))
                            Spacer()
                            Image(systemName: editor.isAnimated(choice.key) ? "diamond.fill" : "diamond")
                                .foregroundStyle(editor.isAnimated(choice.key) ? theme.accent : theme.text3)
                        }
                        .padding(.horizontal, HmmSpacing.m)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Key \(choice.title)"))
                    .accessibilityValue(Text(editor.isAnimated(choice.key) ? "Animated" : "Not animated"))
                    .accessibilityIdentifier("animate-key-\(choice.key.rawValue)")
                }
            }
            .padding(.vertical, HmmSpacing.xs)
        }
        .frame(width: 280)
        .frame(maxHeight: 420)
    }
}
