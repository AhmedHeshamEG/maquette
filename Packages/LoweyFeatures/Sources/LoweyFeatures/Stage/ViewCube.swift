import HmmDesign
import LoweyCore
import SwiftUI

/// The view cube (U6, on by default, Settings ▸ Stage hides it): a small cube that turns with the view. Tap a side to
/// look from there; drag it to turn the view; double-tap for perspective or flat; hold it for the views and Frame all.
struct ViewCube: View {
    let editor: EditorModel
    @State private var dragged = CGSize.zero
    @Environment(\.hmmTheme) private var theme
    static let size: CGFloat = 56

    var body: some View {
        let faces = Self.faces(yaw: editor.viewYaw, pitch: editor.viewPitch, size: Self.size)
        Canvas { context, _ in
            for face in faces {
                let path = Path { $0.addLines(face.corners); $0.closeSubpath() }
                context.fill(path, with: .color(theme.surface2.opacity(0.55 + 0.4 * face.facing)))
                context.stroke(path, with: .color(theme.text3), lineWidth: 1)
                if face.facing > 0.35 {
                    context.draw(Text(LocalizedStringKey(face.side.label)).font(.system(size: 8, weight: .semibold)).foregroundColor(theme.text2),
                                 at: face.centre)
                }
            }
        }
        .frame(width: Self.size, height: Self.size)
        .contentShape(Rectangle())
        .gesture(drag)
        .simultaneousGesture(TapGesture(count: 2).onEnded { editor.toggleProjection() })
        .simultaneousGesture(SpatialTapGesture().onEnded { value in
            if let face = faces.last(where: { Self.contains($0.corners, value.location) }) {
                let angles = face.side.angles(currentYaw: editor.viewYaw)
                editor.look(fromYaw: angles.yaw, pitch: angles.pitch)
            }
        })
        .contextMenu {
            ForEach(ViewAxis.allCases, id: \.self) { axis in
                Button(LocalizedStringKey(axis.displayName)) { editor.stage?.quickView(axis) }
            }
            Divider()
            Button(editor.projection == .orthographic ? "Perspective" : "Orthographic") { editor.toggleProjection() }
            Button("Frame all", systemImage: "viewfinder") {
                editor.setSelection([])
                editor.frameSelection()
            }
        }
        .accessibilityElement()
        .accessibilityLabel("View cube")
        .accessibilityHint("Tap a side to look from there, drag to turn the view")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("view-cube")
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                let delta = CGSize(width: value.translation.width - dragged.width, height: value.translation.height - dragged.height)
                dragged = value.translation
                editor.turnView(byYaw: -Double(delta.width) * 1.2, pitch: Double(delta.height) * 1.2)
            }
            .onEnded { _ in dragged = .zero }
    }

    // MARK: The cube

    enum Side: CaseIterable {
        case front, back, right, left, top, bottom

        var normal: Vec3 {
            switch self {
            case .front: .unitZ
            case .back: -Vec3.unitZ
            case .right: .unitX
            case .left: -Vec3.unitX
            case .top: .unitY
            case .bottom: -Vec3.unitY
            }
        }

        var label: String {
            switch self {
            case .front: "Front"
            case .back: "Back"
            case .right: "Right"
            case .left: "Left"
            case .top: "Top"
            case .bottom: "Under"
            }
        }

        /// The view that looks at this side (the top and the bottom keep the heading).
        func angles(currentYaw: Double) -> (yaw: Double, pitch: Double) {
            switch self {
            case .front: (0, 0)
            case .back: (180, 0)
            case .right: (90, 0)
            case .left: (-90, 0)
            case .top: (currentYaw, 89.9)
            case .bottom: (currentYaw, -89.9)
            }
        }
    }

    struct Face {
        var side: Side
        var corners: [CGPoint]
        var centre: CGPoint
        /// How squarely it faces the eye (0…1).
        var facing: Double
        var depth: Double
    }

    /// The sides that face the eye, far to near, drawn into a square `size` points wide.
    static func faces(yaw: Double, pitch: Double, size: CGFloat) -> [Face] {
        let y = yaw * .pi / 180, p = pitch * .pi / 180
        let back = Vec3(sin(y) * cos(p), sin(p), cos(y) * cos(p))
        let right = Vec3(cos(y), 0, -sin(y))
        let up = back.cross(right)
        let scale = Double(size) * 0.3, middle = Double(size) / 2
        func screen(_ v: Vec3) -> CGPoint { CGPoint(x: middle + v.dot(right) * scale, y: middle - v.dot(up) * scale) }
        return Side.allCases.compactMap { side -> Face? in
            let facing = side.normal.dot(back)
            guard facing > 0.02 else { return nil }
            let n = side.normal
            let a = abs(n.y) > 0.5 ? Vec3.unitX : Vec3.unitY
            let b = n.cross(a)
            let corners = [a + b, a - b, -a - b, -a + b].map { screen(n + $0) }
            return Face(side: side, corners: corners, centre: screen(n), facing: facing, depth: n.dot(back))
        }.sorted { $0.depth < $1.depth }
    }

    static func contains(_ polygon: [CGPoint], _ point: CGPoint) -> Bool {
        Outlines.contains(polygon.map { Vec2(Double($0.x), Double($0.y)) }, Vec2(Double(point.x), Double(point.y)))
    }
}
