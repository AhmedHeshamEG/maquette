import HmmDesign
import LoweyCore
import SwiftUI

/// The proportion handles on the stage (K1 step 4): drag the head up to make it bigger, a foot down for longer legs, a
/// hand down for longer arms, the waist's side out to widen it. One drag is one undo step; the rig follows when it ends.
struct ProportionHandles: View {
    let editor: EditorModel
    @State private var drag: (id: String, last: CGSize, gesture: String)?

    var body: some View {
        _ = editor.viewRevision
        _ = editor.displayRevision
        _ = editor.viewYaw
        _ = editor.viewPitch
        return ZStack {
            ForEach(editor.proportionHandles) { handle in
                Image(systemName: handle.measure == .waist ? "arrow.left.and.right" : "arrow.up.and.down")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.black)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(Color(red: 1, green: 0.722, blue: 0.278)))
                    .overlay(Circle().stroke(Color.black.opacity(0.5), lineWidth: 1.5))
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
                    .position(handle.point)
                    .gesture(dragging(handle))
                    .accessibilityLabel(Text(LocalizedStringKey(handle.measure.title)))
                    .accessibilityHint("Drag to change it")
                    .accessibilityIdentifier("proportion-handle-\(handle.id)")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func dragging(_ handle: ProportionHandle) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                if drag?.id != handle.id { drag = (handle.id, .zero, UUID().uuidString) }
                guard let current = drag else { return }
                let step = CGSize(width: value.translation.width - current.last.width, height: value.translation.height - current.last.height)
                drag?.last = value.translation
                editor.changeProportion(handle.measure, by: handle.factor(for: step), gesture: current.gesture, side: handle.side)
            }
            .onEnded { _ in
                if let gesture = drag?.gesture, let root = editor.makerCharacter { editor.rigAgain(root, gesture: gesture) }
                drag = nil
                editor.endGesture()
                HmmHaptics.play(.commit)
            }
    }
}
