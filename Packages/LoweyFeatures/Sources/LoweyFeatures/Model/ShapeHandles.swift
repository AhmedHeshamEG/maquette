import HmmDesign
import LoweyCore
import SwiftUI

/// The handles Model's verbs put on the stage (U6): the cage's points, each dragged by either hand, and the bend's
/// one handle past the end of the thing (drag it up or right for more).
struct ShapeHandles: View {
    let editor: EditorModel
    @State private var drag: HandleDrag?

    private struct HandleDrag {
        var index: Int
        var start: CGPoint
        var offset: Vec3
        var gesture: String
    }

    var body: some View {
        _ = editor.viewRevision
        _ = editor.displayRevision
        _ = editor.viewYaw
        return ZStack {
            if let points = editor.cagePoints {
                ForEach(points.indices, id: \.self) { index in
                    handle(size: 22)
                        .position(points[index])
                        .gesture(cageDrag(index, at: points[index]))
                        .accessibilityLabel("Cage point \(index + 1)")
                        .accessibilityIdentifier("cage-point-\(index)")
                }
            }
            if let point = editor.bendHandlePoint {
                BendHandle(editor: editor)
                    .position(point)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func handle(size: CGFloat) -> some View {
        Circle()
            .fill(Color(red: 1, green: 0.722, blue: 0.278))
            .overlay(Circle().stroke(Color.black.opacity(0.5), lineWidth: 1.5))
            .frame(width: size, height: size)
            .frame(width: 44, height: 44)
            .contentShape(Circle())
    }

    private func cageDrag(_ index: Int, at point: CGPoint) -> some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .global)
            .onChanged { value in
                if drag?.index != index {
                    let offset = editor.shapedSelection?.shaping?.cage?.offsets[safe: index] ?? .zero
                    drag = HandleDrag(index: index, start: point, offset: offset, gesture: UUID().uuidString)
                }
                guard let drag else { return }
                let now = CGPoint(x: drag.start.x + value.translation.width, y: drag.start.y + value.translation.height)
                editor.dragCagePoint(index, startOffset: drag.offset, from: drag.start, to: now, gesture: drag.gesture)
            }
            .onEnded { _ in
                drag = nil
                editor.endGesture()
                HmmHaptics.play(.commit)
            }
    }
}

/// The bend's one handle.
private struct BendHandle: View {
    let editor: EditorModel
    @State private var start: Double?
    @State private var gesture = UUID().uuidString

    var body: some View {
        Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(Color.black)
            .frame(width: 30, height: 30)
            .background(Circle().fill(Color(red: 1, green: 0.722, blue: 0.278)))
            .frame(width: 44, height: 44)
            .contentShape(Circle())
            .gesture(DragGesture(minimumDistance: 2)
                .onChanged { value in
                    if start == nil { start = editor.shapedSelection.flatMap { editor.bend(of: $0)?.amount } ?? 0 }
                    editor.dragBendHandle(from: start ?? 0, by: value.translation, gesture: gesture)
                }
                .onEnded { _ in
                    start = nil
                    editor.endGesture()
                    gesture = UUID().uuidString
                })
            .accessibilityLabel("Bend handle")
            .accessibilityIdentifier("bend-handle")
    }
}
