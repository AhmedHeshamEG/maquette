import HmmDesign
import LoweyCore
import SwiftUI
import UIKit

/// The timeline as Procreate Dreams has it (CONTEXT §10.10): what a loop drawn over the lanes picks (keys and clips),
/// holding a clip's edge to retime it, two fingers that pan when a finger selects, and the Pencil's hover scrubbing.
extension TimelineLanes {
    /// The keys and clips inside a loop drawn over the lanes (added to the pick in Select mode).
    func pickInside(_ loop: [CGPoint]) {
        editor.selectKeys(layout.keys(inside: loop), additive: editor.keyBoxSelect)
        let clips = layout.clips(inside: loop)
        guard !clips.isEmpty else { return }
        editor.selectedClips = editor.keyBoxSelect ? editor.selectedClips.union(clips) : clips
        HmmHaptics.play(.selection)
    }

    /// A hold that began on a clip's edge, dragged: the clip plays faster or slower to end (or start) there. True when
    /// the hold is one.
    func holdEdge(_ drag: DragGesture.Value) -> Bool {
        if layout.retiming == nil {
            guard !layout.marqueeArmed, layout.laneDrag == nil, let edge = layout.clipEdge(at: layout.toContent(drag.startLocation)) else {
                return false
            }
            layout.retiming = (edge.clip.id, edge.end, UUID().uuidString)
            HmmHaptics.play(.selection)
        }
        guard let retiming = layout.retiming else { return false }
        let time = layout.time(at: max(layout.toContent(drag.location).x - TimelineLayout.labelWidth, 0))
        editor.retimeClip(retiming.clip, end: retiming.end, to: time, gesture: retiming.gesture)
        return true
    }
}

/// Two fingers pan the lanes while a finger draws around keys (Settings ▸ Gestures), and the Pencil hovering over
/// them moves the playhead (unless playing; Settings can switch it off).
struct DreamsLanes: ViewModifier {
    let editor: EditorModel
    let layout: TimelineLayout
    @AppStorage(AppSettings.timelineFingerSelects) private var fingerSelects = false
    @AppStorage(AppSettings.timelineHoverScrubs) private var hoverScrubs = true
    @State private var panStart: (time: Double, rows: CGFloat)?

    func body(content: Content) -> some View {
        content
            .simultaneousGesture(TwoFingerPan(enabled: fingerSelects) { translation, state in pan(translation, state: state) })
            .onContinuousHover(coordinateSpace: .named(TimelineLayout.lanesSpace)) { phase in
                guard hoverScrubs, !editor.isPlaying, case let .active(point) = phase, point.x >= TimelineLayout.labelWidth else { return }
                editor.setTime(max(0, layout.time(at: point.x - TimelineLayout.labelWidth)))
            }
    }

    private func pan(_ translation: CGPoint, state: UIGestureRecognizer.State) {
        switch state {
        case .began:
            layout.momentum.stop()
            panStart = (editor.timelineStart, layout.rowScroll)
        case .changed:
            guard let start = panStart else { return }
            editor.timelineStart = max(0, start.time - Double(translation.x) / layout.pps)
            layout.rowScroll = min(max(start.rows - translation.y, 0), layout.maxScroll)
        default:
            panStart = nil
        }
    }
}

/// Two fingers dragging (fingers only).
struct TwoFingerPan: UIGestureRecognizerRepresentable {
    let enabled: Bool
    let update: (CGPoint, UIGestureRecognizer.State) -> Void

    func makeUIGestureRecognizer(context _: Context) -> UIPanGestureRecognizer {
        let recognizer = UIPanGestureRecognizer()
        recognizer.minimumNumberOfTouches = 2
        recognizer.maximumNumberOfTouches = 2
        recognizer.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        return recognizer
    }

    func updateUIGestureRecognizer(_ recognizer: UIPanGestureRecognizer, context _: Context) {
        recognizer.isEnabled = enabled
    }

    func handleUIGestureRecognizerAction(_ recognizer: UIPanGestureRecognizer, context _: Context) {
        update(recognizer.translation(in: recognizer.view), recognizer.state)
    }
}
