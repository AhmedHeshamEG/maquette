import HmmDesign
import LoweyCore
import LoweyEngine
import SwiftUI

/// The flat view (U7): the painted thing's surface laid out as its texture is, the unwrap's lines over it, painted in 2D
/// with the brush, map and colour in hand. Strokes land on the layer through the same GPU stroke as on the stage (the
/// stage keeps drawing under the sheet), one undo step each; the picture refreshes after each.
struct FlatPaintView: View {
    @Bindable var editor: EditorModel
    @State private var picture: CGImage?
    @State private var lines: [[CGPoint]] = []
    @State private var live: [BrushInput<Vec2>] = []
    @State private var stroke: (object: ObjectID, layer: String, number: Int)?
    @State private var seed: UInt64 = 1
    @Environment(\.dismiss) private var dismiss
    @Environment(\.hmmTheme) private var theme

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                let side = min(proxy.size.width, proxy.size.height) - HmmSpacing.l * 2
                ZStack {
                    Rectangle().fill(theme.surface2)
                    if let picture { Image(decorative: picture, scale: 1).resizable().interpolation(.medium) }
                    Canvas { context, size in
                        var path = Path()
                        for triangle in lines {
                            guard let first = triangle.first else { continue }
                            path.move(to: CGPoint(x: first.x * size.width, y: first.y * size.height))
                            for point in triangle.dropFirst() {
                                path.addLine(to: CGPoint(x: point.x * size.width, y: point.y * size.height))
                            }
                            path.closeSubpath()
                        }
                        context.stroke(path, with: .color(theme.text.opacity(0.18)), lineWidth: 0.5)
                    }
                    .allowsHitTesting(false)
                    BrushPadSurface { samples, finished in paint(samples, finished: finished, side: side) }
                }
                .frame(width: side, height: side)
                .clipShape(RoundedRectangle(cornerRadius: HmmRadius.card, style: .continuous))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityElement(children: .contain)
                .accessibilityLabel(Text("The surface laid flat"))
                .accessibilityIdentifier("flat-paint")
            }
            .navigationTitle(Text(editor.paintTarget?.name ?? "Flat view"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .principal) {
                    Text(LocalizedStringKey(editor.colourPaint.map.title)).font(.hmm(.footnote)).foregroundStyle(theme.text2)
                }
            }
            .task(id: editor.paintTarget?.paint) { await refresh() }
        }
    }

    /// The colour composite over the thing's own colour, and the unwrap's triangles, made off the main thread.
    private func refresh() async {
        guard let object = editor.paintTarget, let paint = object.paint else { return }
        let file = editor.paintFiles
        let base = object.color?.resolved(in: editor.look.palette) ?? .blockout
        let made = await Task.detached(priority: .userInitiated) { () -> (CGImage?, [[CGPoint]]) in
            let pictures = PaintPictures(paint) { file($0) }
            let composite = PaintComposer.composite(paint) { layer, map in pictures.image(layer, map) }
            let shown = PaintComposer.flattened(composite, over: RGBA(base.r, base.g, base.b, 1)).resampled(to: min(paint.surface.size, 1024))
            let unwrap = file(paint.surface.unwrap).flatMap { try? PaintUnwrap(data: $0) }
            let triangles = (0 ..< min(unwrap?.triangleCount ?? 0, 20000)).map { face in
                (0 ..< 3).map { corner -> CGPoint in
                    let uv = unwrap?.uvs[Int(unwrap?.indices[face * 3 + corner] ?? 0)] ?? .zero
                    return CGPoint(x: CGFloat(uv.x), y: CGFloat(uv.y))
                }
            }
            return (MaterialModel.cgImage(shown), triangles)
        }.value
        picture = made.0
        lines = made.1
    }

    /// The pad's points (the view's points) become the texture's pixels, then the live stroke on the layer.
    private func paint(_ samples: [BrushInput<Vec2>], finished: Bool, side: Double) {
        guard let stage = editor.stage, let object = editor.paintTarget, let paint = object.paint, let layer = editor.paintLayer(of: object) else { return }
        let scale = Double(paint.surface.size) / max(side, 1)
        if stroke == nil {
            let map = editor.paintedMap(of: layer)
            guard layer.fill == nil || map == .mask else {
                editor.app.show("\(layer.name) is a fill: give it a mask and paint the mask")
                return
            }
            editor.paintStrokes += 1
            stroke = (object.id, PaintPictures.key(layer.id, map), editor.paintStrokes)
            seed = EditorModel.strokeSeed()
        }
        guard let stroke else { return }
        let pixels = samples.map { BrushInput(point: $0.point * scale, pressure: $0.pressure, altitude: $0.altitude, time: $0.time) }
        let brush = editor.currentBrush(for: .paint)
        let path = BrushStroker.path(pixels, brush: brush, size: editor.colourPaint.size / 2 * scale, opacity: editor.colourPaint.opacity,
                                     minimumSpacing: 1.5)
        let dabs = BrushStroker.dabs(path, brush: brush, seed: seed)
        let erases = editor.colourPaint.mode == .erase
        stage.showLivePaint(LivePaint(object: stroke.object, layer: stroke.layer, stroke: stroke.number, source: .flat(dabs, brush: brush),
                                      color: erases ? RGBA(0, 0, 0, 1) : editor.strokeColor, erases: erases, pixelsPerPoint: 1))
        stage.draw()
        guard finished else { return }
        stage.showLivePaint(nil)
        if let pending = stage.finishPaintStroke() { editor.commitPaintStroke(pending) }
        self.stroke = nil
        Task {
            try? await Task.sleep(for: .milliseconds(300))
            await refresh()
        }
    }
}
