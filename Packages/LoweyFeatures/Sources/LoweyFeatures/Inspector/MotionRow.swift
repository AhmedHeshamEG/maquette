import HmmDesign
import LoweyCore
import SwiftUI

/// Make it move (CONTEXT §4.1): every motion once, in one strip. The loops come first (spin, float, bounce, wiggle,
/// swing, follow a path): one tap and the thing moves on the stage straight away, a second tap stops it, one slider
/// sets how fast and Make keyframes turns what's running into keys. Then the moves that happen once, at the playhead
/// (pop in, grow, shake, fade, slide in…). The four that used to be in both lists are loops now.
struct MakeItMove: View {
    let editor: EditorModel

    /// The moves that happen once; a loop of the same name is the loop.
    static let once: [AnimationPreset] = AnimationPreset.allCases.filter { ![.bounce, .wiggle, .float, .spin].contains($0) }

    var body: some View {
        VStack(alignment: .leading, spacing: HmmSpacing.xs) {
            HmmSectionHeader("Make it move").accessibilityIdentifier("section-Make it move")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: HmmSpacing.xs) {
                    ForEach(LoopMotion.allCases) { motion in
                        Group {
                            if motion == .followPath { followTile } else { tile(motion) }
                        }
                        .frame(width: 76)
                    }
                    Divider().frame(height: 44)
                    ForEach(Self.once) { preset in
                        TileButton(title: preset.title, systemName: MoreWaysToMove.icon(for: preset), identifier: "preset-\(preset.rawValue)") {
                            editor.applyPreset(preset)
                        }
                        .frame(width: 76)
                    }
                }
            }
            .scrollClipDisabled()
            if !editor.loopMotions.isEmpty {
                LabeledSlider(title: "Speed", value: editor.loopMotionSpeed, range: LoopMotion.speedRange,
                              format: { String(format: "%.2g×", $0) }, set: { editor.setLoopMotionSpeed($0) }, done: { editor.endGesture() })
                    .accessibilityIdentifier("motion-speed")
                HmmPillButton("Make keyframes", systemName: "diamond") { editor.makeLoopMotionKeyframes() }
                    .accessibilityIdentifier("motion-keyframes")
            }
        }
    }

    private func tile(_ motion: LoopMotion, path: ObjectID? = nil) -> some View {
        TileButton(title: motion.title, systemName: Self.icon(for: motion), identifier: "motion-\(motion.rawValue)",
                   isOn: editor.hasLoopMotion(motion)) {
            editor.toggleLoopMotion(motion, path: path)
        }
    }

    /// Follow a path: one drawn line is followed at a tap; with several, the tap asks which. With none, there's
    /// nothing to follow, so the tile isn't shown.
    @ViewBuilder private var followTile: some View {
        let paths = editor.followablePaths
        if paths.count > 1, !editor.hasLoopMotion(.followPath) {
            Menu {
                ForEach(paths, id: \.self) { id in
                    Button(editor.baseScene.objects[id]?.name ?? "Path") { editor.toggleLoopMotion(.followPath, path: id) }
                }
            } label: {
                TileLabel(title: LoopMotion.followPath.title, systemName: Self.icon(for: .followPath))
            }
            .accessibilityIdentifier("motion-followPath")
        } else if !paths.isEmpty || editor.hasLoopMotion(.followPath) {
            tile(.followPath, path: paths.first)
        }
    }

    static func icon(for motion: LoopMotion) -> String {
        switch motion {
        case .spin: "arrow.clockwise"
        case .float: "cloud"
        case .bounce: "arrow.up.and.down"
        case .wiggle: "water.waves"
        case .swing: "metronome"
        case .followPath: "point.topleft.down.to.point.bottomright.curvepath"
        }
    }
}

/// A row that opens one step deeper, in place (progressive disclosure). It remembers whether it was open.
struct DisclosureRow<Content: View>: View {
    let title: String
    let systemName: String
    let identifier: String
    @ViewBuilder let content: () -> Content
    @AppStorage private var open: Bool
    @Environment(\.hmmTheme) private var theme

    init(_ title: String, systemName: String, identifier: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.systemName = systemName
        self.identifier = identifier
        self.content = content
        _open = AppStorage(wrappedValue: false, "inspector.row.\(identifier)")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: HmmSpacing.s) {
            Button {
                HmmHaptics.play(.selection)
                withHmmAnimation(.snappy) { open.toggle() }
            } label: {
                HStack(spacing: HmmSpacing.s) {
                    Image(systemName: systemName).frame(width: 22).foregroundStyle(theme.text2)
                    Text(LocalizedStringKey(title)).font(.hmm(.body, weight: .semibold)).foregroundStyle(theme.text)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: HmmSpacing.xs)
                    Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundStyle(theme.text3)
                        .rotationEffect(.degrees(open ? 90 : 0))
                }
                .frame(minHeight: 40)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(open ? .isSelected : [])
            .accessibilityIdentifier(identifier)
            if open {
                content().transition(.opacity)
            }
        }
    }
}
