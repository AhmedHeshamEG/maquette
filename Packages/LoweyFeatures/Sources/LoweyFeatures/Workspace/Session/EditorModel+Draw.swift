import CoreGraphics
import Foundation
import HmmDesign
import LoweyCore
import LoweyEngine

/// One Draw (U5, CONTEXT §10.11): Draw and Paint are one tool with Procreate's five buttons, Brush · Smudge · Erase ·
/// Sheets (Layers while a paint brush is in the hand) · Colour. What the Brush holds decides which stage tool the Pencil
/// uses: lines and frames (ink, flipbooks), colour on a model, solids, shapes, the shadow brush. No panel opens.
extension EditorModel {
    /// Draw is in the hand (any of its brushes, or a shape being sketched).
    var isDrawing: Bool {
        tool.draws || tool == .paint || tool == .shadowBrush || isSketching
    }

    /// The Pencil's stroke becomes a line: ink, or a paint brush that started in the air.
    var drawsLines: Bool { tool == .ink || tool == .paint }

    /// Lines going into the selected drawing (Q2): its object panel stays away, so nothing pops up beside a stroke
    /// where the next one starts (it took that stroke's touch).
    var drawingIntoSelection: Bool { drawsLines && activeInk != nil }

    /// The top-right Draw: picks up the brush and verb last used, or puts Draw down.
    func toggleDraw() {
        openPanel = nil
        if isDrawing {
            if isSketching { stopModeling() } else { tool = .select }
        } else {
            applyDraw()
        }
    }

    /// One of the bar's first three buttons. Tapping the Brush when it is already in the hand opens the library (the
    /// bar does that); here the verb becomes the one in use.
    func chooseDrawVerb(_ verb: DrawVerb) {
        drawVerb = verb
        applyDraw()
        HmmHaptics.play(.selection)
    }

    /// A brush from the library (lines or paint, by its set) or a making set's brush.
    func chooseDrawBrush(_ kind: DrawBrushKind) {
        drawBrush = kind
        drawVerb = .brush
        applyDraw()
    }

    /// Frames on the sheet (the flipbook): lines go into the drawing at the playhead.
    func setDrawFrames(_ on: Bool) {
        drawFrames = on
        if on, drawBrush != .lines { drawBrush = .lines }
        applyDraw()
    }

    /// The stage tool for the bar's verb and brush.
    func applyDraw() {
        openPanel = nil
        switch drawVerb {
        case .brush:
            applyBrush()
        case .erase:
            if drawBrush == .paint {
                colourPaint.mode = .erase
                tool = .paint
            } else if drawFrames {
                flipbook.mode = .erase
                tool = .flipbook
            } else {
                ink.mode = .erase
                tool = .ink
            }
        case .smudge:
            if drawBrush == .paint {
                // U7: smudge drags paint along the surface of a painted thing.
                colourPaint.mode = .smudge
                tool = .paint
            } else {
                ink.mode = .reshape
                tool = .ink
            }
        }
    }

    private func applyBrush() {
        switch drawBrush {
        case .lines:
            if drawFrames {
                flipbook.mode = .draw
                tool = .flipbook
            } else {
                ink.mode = .draw
                tool = .ink
            }
        case .paint:
            if colourPaint.mode != .faces { colourPaint.mode = .paint }
            tool = .paint
        case let .solid(style):
            draw.style = style
            tool = .draw
        case let .shape(kind):
            startSketching(kind)
        case let .shadow(pushes):
            shadowBrush.pushesShadow = pushes
            tool = .shadowBrush
        }
    }

    /// The verb the bar shows as in use.
    var drawVerbInUse: DrawVerb {
        switch tool {
        case .ink: ink.mode == .erase ? .erase : ink.mode == .reshape ? .smudge : .brush
        case .flipbook: flipbook.mode == .erase ? .erase : .brush
        case .paint: colourPaint.mode == .erase ? .erase : colourPaint.mode == .smudge ? .smudge : .brush
        default: .brush
        }
    }

    /// Sheets becomes Layers while a paint brush is in the hand and there is a thing to paint.
    var drawShowsLayers: Bool { tool == .paint && paintTarget != nil }

    /// Where a paint brush's stroke would put colour: a thing that can be painted under the point.
    func paintsSurface(at point: CGPoint) -> Bool {
        guard let stage, let (id, _) = stage.pickObject(at: point), let object = displayed.scene.objects[id] else { return false }
        return object.isPaintable && !object.isInk
    }

    // MARK: The chrome rests while the hand works

    /// The clusters fold to faint rails while a stroke is drawn (U5); a finger or the hovering Pencil near them, a tool
    /// change or a panel brings them back.
    func restClusters() {
        guard isDrawing || tool == .model, !clustersResting else { return }
        clustersResting = true
    }

    func wakeClusters() {
        if clustersResting { clustersResting = false }
    }

    // MARK: A tapped line

    /// The Pencil tapped a line (U5: strokes stay editable): its drawing is chosen and the stroke picked, so its chip
    /// opens beside it. False when nothing drawn is there.
    func tapLine(at point: CGPoint) -> Bool {
        let before = inkStrokes
        selectInkStrokes(path: [point])
        guard !inkStrokes.isEmpty else {
            if !before.isEmpty { inkStrokes = [] }
            return false
        }
        HmmPencilHaptics.buzz(at: point)
        return true
    }
}
