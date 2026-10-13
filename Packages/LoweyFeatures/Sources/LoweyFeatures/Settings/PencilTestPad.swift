import HmmDesign
import LoweyCore
import SwiftUI
import UIKit

/// The Pencil page's test pad: draw on it and see the pressure (the line's width, through the curve being tried) and
/// the tilt. Each finished stroke's raw pressures go to `stroke`, which is how calibration hears the lightest and the
/// heaviest line.
struct PencilTestPad: UIViewRepresentable {
    let feel: HmmPencilFeel
    let clearCount: Int
    let sample: (_ pressure: Double, _ tilt: Double) -> Void
    let stroke: (_ rawPressures: [Double]) -> Void

    func makeUIView(context _: Context) -> PencilPadView {
        let view = PencilPadView()
        view.backgroundColor = .clear
        view.isMultipleTouchEnabled = false
        return view
    }

    func updateUIView(_ view: PencilPadView, context _: Context) {
        view.feel = feel
        view.onSample = sample
        view.onStroke = stroke
        if view.clearCount != clearCount {
            view.clearCount = clearCount
            view.clear()
        }
    }
}

/// Draws what the Pencil does on the pad: each point as wide as its pressure through the curve, and a crosshair where
/// the app thinks the tip is (U5: touching or hovering), so a line that leaves the tip shows at once.
final class PencilPadView: UIView {
    var feel = HmmPencilFeel.default
    var onSample: ((Double, Double) -> Void)?
    var onStroke: (([Double]) -> Void)?
    var clearCount = 0
    private var strokes: [[(point: CGPoint, width: CGFloat)]] = []
    private var raw: [Double] = []
    /// Where the app reads the tip: the last touch, or the hovering Pencil.
    private var tip: CGPoint?

    override init(frame: CGRect) {
        super.init(frame: frame)
        addGestureRecognizer(UIHoverGestureRecognizer(target: self, action: #selector(hovered(_:))))
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        addGestureRecognizer(UIHoverGestureRecognizer(target: self, action: #selector(hovered(_:))))
    }

    @objc private func hovered(_ recognizer: UIHoverGestureRecognizer) {
        tip = recognizer.state == .ended || recognizer.state == .cancelled ? nil : recognizer.location(in: self)
        setNeedsDisplay()
    }

    func clear() {
        strokes = []
        setNeedsDisplay()
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        raw = []
        strokes.append([])
        add(touch, event: event)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        add(touch, event: event)
    }

    override func touchesEnded(_: Set<UITouch>, with _: UIEvent?) {
        onStroke?(raw)
        raw = []
    }

    override func touchesCancelled(_: Set<UITouch>, with _: UIEvent?) {
        raw = []
    }

    private func add(_ touch: UITouch, event: UIEvent?) {
        for item in event?.coalescedTouches(for: touch) ?? [touch] {
            let pressure = item.maximumPossibleForce > 0 ? Double(item.force / item.maximumPossibleForce) : 0.6
            raw.append(pressure)
            let width = CGFloat(1 + 13 * feel.pressure(pressure))
            if strokes.isEmpty { strokes.append([]) }
            strokes[strokes.count - 1].append((item.preciseLocation(in: self), width))
            tip = item.preciseLocation(in: self)
            onSample?(feel.pressure(pressure), item.type == .pencil ? Double(item.altitudeAngle) * 180 / .pi : 90)
        }
        setNeedsDisplay()
    }

    override func draw(_: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        context.setStrokeColor(UIColor.label.cgColor)
        context.setLineCap(.round)
        for stroke in strokes {
            for (from, to) in zip(stroke, stroke.dropFirst()) {
                context.setLineWidth((from.width + to.width) / 2)
                context.move(to: from.point)
                context.addLine(to: to.point)
                context.strokePath()
            }
        }
        guard let tip else { return }
        context.setStrokeColor(UIColor(red: 1, green: 0.72, blue: 0.28, alpha: 1).cgColor)
        context.setLineWidth(1)
        for (from, to) in [(CGPoint(x: tip.x - 14, y: tip.y), CGPoint(x: tip.x + 14, y: tip.y)),
                           (CGPoint(x: tip.x, y: tip.y - 14), CGPoint(x: tip.x, y: tip.y + 14))] {
            context.move(to: from)
            context.addLine(to: to)
        }
        context.strokePath()
    }
}

/// The pressure curve, editable by hand (Procreate's way): drag its middle points; the ends stay at the corners.
struct PressureCurveEditor: View {
    @Binding var curve: BrushCurve
    let changed: () -> Void
    @Environment(\.hmmTheme) private var theme

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            ZStack {
                Path { path in
                    for step in 0 ... 40 {
                        let x = Double(step) / 40
                        let point = CGPoint(x: x * size.width, y: (1 - curve.value(at: x)) * size.height)
                        if step == 0 { path.move(to: point) } else { path.addLine(to: point) }
                    }
                }
                .stroke(theme.accent, lineWidth: 2)
                ForEach(Array(curve.points.enumerated()), id: \.offset) { index, point in
                    if index > 0, index < curve.points.count - 1 {
                        Circle()
                            .fill(theme.accent)
                            .frame(width: 16, height: 16)
                            .position(x: point.x * size.width, y: (1 - point.y) * size.height)
                            .gesture(DragGesture().onChanged { value in move(index, to: value.location, in: size) }.onEnded { _ in changed() })
                    }
                }
            }
        }
        .background(RoundedRectangle(cornerRadius: HmmRadius.control).fill(theme.surface2))
        .frame(height: 140)
        .accessibilityElement()
        .accessibilityLabel(Text("Pressure curve"))
    }

    private func move(_ index: Int, to location: CGPoint, in size: CGSize) {
        var points = curve.points
        let lower = points[index - 1].x + 0.01, upper = points[index + 1].x - 0.01
        let x = Double(location.x / max(size.width, 1)), y = Double(1 - location.y / max(size.height, 1))
        points[index] = Vec2(min(max(x, lower), upper), min(max(y, 0), 1))
        curve = BrushCurve(points)
    }
}
