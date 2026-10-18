import HmmDesign
import LoweyCore
import SwiftUI

/// A thing's motion drawn in its row (A1): how much it moves at each frame, as a filled curve in its own colour, with a
/// dot a frame once the frames are wide enough to tell apart.
struct MotionLane: View {
    let editor: EditorModel
    let layout: TimelineLayout
    let id: ObjectID
    let width: CGFloat

    var body: some View {
        let curve = editor.motionCurve(of: id)
        let colour = editor.rowColour(of: id)
        let fps = Double(max(editor.timeline.fps, 1))
        let start = layout.visibleStart
        let pps = layout.pps
        let frames = FrameCells.showsFrames(pps: pps, fps: fps)
        Canvas { context, size in
            guard curve.count > 1 else { return }
            let first = max(Int((start * fps).rounded(.down)) - 1, 0)
            let last = min(Int(((start + Double(size.width) / pps) * fps).rounded(.up)) + 1, curve.count - 1)
            guard last > first else { return }
            let top: CGFloat = 6
            let bottom = size.height - 8
            let x = { (frame: Int) in CGFloat((Double(frame) / fps - start) * pps) }
            let point = { (frame: Int) in CGPoint(x: x(frame), y: bottom - CGFloat(curve[frame]) * (bottom - top)) }
            var area = Path()
            area.move(to: CGPoint(x: x(first), y: bottom))
            for frame in first ... last {
                area.addLine(to: point(frame))
            }
            area.addLine(to: CGPoint(x: x(last), y: bottom))
            area.closeSubpath()
            context.fill(area, with: .color(colour.opacity(0.22)))
            var line = Path()
            line.move(to: point(first))
            for frame in first ... last {
                line.addLine(to: point(frame))
            }
            context.stroke(line, with: .color(colour.opacity(0.75)), lineWidth: 1.5)
            guard frames else { return }
            for frame in first ... last where curve[frame] > 0.001 {
                let dot = point(frame)
                context.fill(Path(ellipseIn: CGRect(x: dot.x - 2, y: dot.y - 2, width: 4, height: 4)), with: .color(colour))
            }
        }
        .frame(width: width)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Frames as cells once the timeline is zoomed in far enough to tell them apart (A1): a hairline between frames, every
/// other frame faintly shaded.
struct FrameCells: View {
    let editor: EditorModel
    let layout: TimelineLayout
    let width: CGFloat
    @Environment(\.hmmTheme) private var theme

    /// A frame at least this wide (points) shows as a cell.
    static func showsFrames(pps: Double, fps: Double) -> Bool { pps / fps >= 9 }

    var body: some View {
        let fps = Double(max(editor.timeline.fps, 1))
        let start = layout.visibleStart
        let pps = layout.pps
        let count = editor.timeline.frameCount
        let shade = theme.text
        if Self.showsFrames(pps: pps, fps: fps) {
            Canvas { context, size in
                let first = max(Int((start * fps).rounded(.down)), 0)
                let last = min(Int(((start + Double(size.width) / pps) * fps).rounded(.up)), count)
                guard last > first else { return }
                let cell = CGFloat(pps / fps)
                for frame in first ... last {
                    let x = CGFloat((Double(frame) / fps - start) * pps)
                    if frame % 2 == 0 { context.fill(Path(CGRect(x: x, y: 0, width: cell, height: size.height)), with: .color(shade.opacity(0.025))) }
                    context.fill(Path(CGRect(x: x, y: 0, width: 0.5, height: size.height)), with: .color(shade.opacity(0.07)))
                }
            }
            .frame(width: width)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}
