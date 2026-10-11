import HmmDesign
import LoweyCore
import SwiftUI

/// The frame strip (CONTEXT §10.10), along the bottom while a flipbook is drawn: its drawings as real pictures, each as
/// wide as it is held. Tap one to draw on it; + adds the next and goes to it; the arrows step; hold a picture and drag
/// it to reorder; drag a picture's right edge to hold it longer or shorter; the onion skin shows the neighbours, and
/// the loop plays the drawings round while you draw. The timeline is only for timing them.
struct FrameStrip: View {
    @Bindable var editor: EditorModel
    @State private var moving: (index: Int, offset: CGFloat)?
    @State private var holding: (index: Int, start: Int, gesture: String)?
    @Environment(\.hmmTheme) private var theme

    static let tile: CGFloat = 46
    static let holdStep: CGFloat = 9

    var body: some View {
        HStack(spacing: HmmSpacing.xxs) {
            HmmButton("eraser", label: "Erase", isOn: editor.flipbook.mode == .erase, size: 36) { editor.toggleEraser() }
                .accessibilityIdentifier("flipbook-erase")
            if let track = editor.activeFlipbook, !track.frames.isEmpty {
                HmmButton("chevron.left", label: "Previous drawing", size: 36) { editor.stepFlipbookDrawing(by: -1) }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(Array(track.frames.enumerated()), id: \.element.id) { index, frame in
                            tile(frame, index: index, in: track)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .frame(maxWidth: 300)
                .fixedSize(horizontal: true, vertical: false)
                HmmButton("chevron.right", label: "Next drawing", size: 36) { editor.stepFlipbookDrawing(by: 1) }
                HmmButton("plus", label: "New drawing", size: 36) { editor.addFlipbookDrawing() }
                    .accessibilityIdentifier("frame-add")
                HmmButton("circle.dotted.circle", label: "Onion skin", isOn: editor.flipbook.onionSkin, size: 36) {
                    editor.flipbook.onionSkin.toggle()
                }
                HmmButton(editor.flipbook.looping ? "pause" : "repeat", label: editor.flipbook.looping ? "Stop the loop" : "Loop the drawings",
                          isOn: editor.flipbook.looping, size: 36) { editor.toggleFlipbookLoop() }
                    .accessibilityIdentifier("frame-loop")
            } else {
                Text("Draw the first drawing")
                    .font(.hmm(.caption, weight: .semibold))
                    .foregroundStyle(theme.text2)
                    .padding(.horizontal, HmmSpacing.xs)
            }
            HmmButton("xmark", label: "Done drawing", size: 36) { editor.tool = .select }
        }
        .padding(HmmSpacing.xs)
        .hmmPanelBackground()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("frame-strip")
    }

    private func tile(_ frame: FlipbookFrame, index: Int, in track: FlipbookTrack) -> some View {
        let current = editor.activeFlipbookFrame == index
        return FrameThumbnail(frame: frame, bounds: FrameThumbnail.bounds(of: track), palette: editor.look.palette)
            .frame(width: Self.tile + CGFloat(max(frame.hold - 1, 0)) * Self.holdStep, height: 36)
            .background(RoundedRectangle(cornerRadius: HmmRadius.control).fill(theme.surface2))
            .overlay(RoundedRectangle(cornerRadius: HmmRadius.control).stroke(current ? theme.accent : theme.line, lineWidth: current ? 2 : 1))
            .overlay(alignment: .trailing) { holdHandle(index: index, hold: frame.hold) }
            .overlay(alignment: .bottomLeading) {
                Text(verbatim: "\(index + 1)").font(.system(size: 9, weight: .semibold).monospacedDigit()).foregroundStyle(theme.text3).padding(3)
            }
            .offset(x: moving?.index == index ? moving?.offset ?? 0 : 0)
            .zIndex(moving?.index == index ? 1 : 0)
            .contentShape(Rectangle())
            .onTapGesture { editor.showFlipbookDrawing(index, of: track.id) }
            .gesture(reorder(index: index))
            .accessibilityElement()
            .accessibilityLabel(Text("Drawing \(index + 1), held \(frame.hold) frames"))
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("frame-\(index)")
    }

    /// Hold a picture, then drag it along the strip.
    private func reorder(index: Int) -> some Gesture {
        LongPressGesture(minimumDuration: 0.3)
            .sequenced(before: DragGesture(minimumDistance: 0))
            .onChanged { value in
                guard case let .second(true, drag) = value else { return }
                if moving == nil { HmmHaptics.play(.selection) }
                moving = (index, drag?.translation.width ?? 0)
            }
            .onEnded { _ in
                guard let moving else { return }
                let steps = Int((moving.offset / (Self.tile + 4)).rounded())
                self.moving = nil
                editor.moveFlipbookDrawing(index, to: index + steps)
            }
    }

    /// The right edge: drag it to hold the drawing longer or shorter.
    private func holdHandle(index: Int, hold: Int) -> some View {
        Capsule()
            .fill(theme.text2.opacity(0.6))
            .frame(width: 3, height: 18)
            .frame(width: 14, height: 36)
            .contentShape(Rectangle())
            .highPriorityGesture(
                DragGesture(minimumDistance: 2)
                    .onChanged { value in
                        let drag = holding ?? (index, hold, UUID().uuidString)
                        holding = drag
                        let wanted = max(drag.start + Int((value.translation.width / Self.holdStep).rounded()), 1)
                        editor.setFlipbookHold(wanted, ofDrawing: index, gesture: drag.gesture)
                    }
                    .onEnded { _ in
                        holding = nil
                        editor.endGesture()
                    }
            )
            .accessibilityHidden(true)
    }
}

/// A drawing of a flipbook as it is: its strokes, scaled the same for every drawing of the track so the motion shows.
struct FrameThumbnail: View {
    let frame: FlipbookFrame
    let bounds: (min: Vec2, max: Vec2)
    let palette: Palette

    var body: some View {
        Canvas { context, size in
            let width = max(bounds.max.x - bounds.min.x, 1e-6), height = max(bounds.max.y - bounds.min.y, 1e-6)
            let scale = min(Double(size.width - 6) / width, Double(size.height - 6) / height)
            let offset = CGPoint(x: (Double(size.width) - width * scale) / 2, y: (Double(size.height) - height * scale) / 2)
            func place(_ point: Vec2) -> CGPoint {
                CGPoint(x: offset.x + (point.x - bounds.min.x) * scale, y: offset.y + (bounds.max.y - point.y) * scale)
            }
            for stroke in frame.strokes {
                var path = Path()
                path.addLines(stroke.points.map(place))
                let colour = stroke.color.resolved(in: palette).color
                if stroke.filled {
                    path.closeSubpath()
                    context.fill(path, with: .color(colour))
                } else {
                    let average = stroke.widths.reduce(0, +) / Double(max(stroke.widths.count, 1))
                    context.stroke(path, with: .color(colour), style: StrokeStyle(lineWidth: max(average * 2 * scale, 1), lineCap: .round,
                                                                                  lineJoin: .round))
                }
            }
        }
        .allowsHitTesting(false)
    }

    /// Every drawing of the track inside one box.
    static func bounds(of track: FlipbookTrack) -> (min: Vec2, max: Vec2) {
        let points = track.frames.flatMap { $0.strokes.flatMap(\.points) }
        guard let first = points.first else { return (Vec2(-1, -1), Vec2(1, 1)) }
        var low = first, high = first
        for point in points {
            low = Vec2(min(low.x, point.x), min(low.y, point.y))
            high = Vec2(max(high.x, point.x), max(high.y, point.y))
        }
        return (low, high)
    }
}
