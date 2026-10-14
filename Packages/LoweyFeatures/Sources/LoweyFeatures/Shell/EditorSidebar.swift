import HmmDesign
import LoweyCore
import SwiftUI

/// The left sidebar: two sliders that change with the context (drawing: width and opacity; Shadow Brush: size and
/// strength; Perform: filtering and sensitivity), Pick, and the colour well while something is made outside Draw
/// (Model ▸ Add: a colour is always in the hand before making; Draw has its own, U5). Undo and redo only when Settings ▸
/// Gestures shows them (U5: the finger taps are universal).
///
/// It rests rather than leaves: with no tool that uses the sliders, they and the well shrink to a faint rail in the
/// same place, and a touch on it brings back the sliders, which then mean size and opacity (of ink, the drawing tool
/// that comes first). Settings ▸ Stage ▸ Always show the sidebar keeps it awake.
struct EditorSidebar: View {
    @Bindable var editor: EditorModel
    @AppStorage(AppSettings.alwaysShowsSidebar) private var alwaysShows = false
    @AppStorage(AppSettings.showsUndoButtons) private var showsUndo = false
    @State private var woken = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let (top, bottom) = sliders
        HmmSidebar(top: top, bottom: bottom, pickActive: editor.pickActive, pick: {
            editor.pickActive.toggle()
        }, accessory: showsWell ? AnyView(SidebarColourWell(editor: editor)) : nil, resting: resting, wake: { woken = true },
        showsUndo: showsUndo, canUndo: editor.canUndo, canRedo: editor.canRedo, undo: editor.undo, redo: editor.redo)
            .animation(HmmMotion.standard.animation(reduceMotion: reduceMotion), value: resting)
            .onChange(of: editor.tool) { _, _ in woken = false }
            .onChange(of: editor.selection) { _, _ in woken = false }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("sidebar")
    }

    /// No tool in the hand wants the sliders.
    private var idle: Bool {
        !editor.flying && !(editor.timelineMode == .perform && (editor.performPhase != .idle || editor.tool == .select))
            && ([StageTool.select, .lasso, .scatter].contains(editor.tool) || (editor.tool == .model && editor.modeling.verb != .brush)
                || (editor.tool == .rig && editor.rigging.mode != .weights))
    }

    private var resting: Bool { idle && !alwaysShows && !woken && !makingFromModel }

    /// Model ▸ Add (or the Model tool) is open: what is made next takes the colour in the hand.
    private var makingFromModel: Bool { editor.openPanel == .model && editor.modelPage == .add }

    /// While drawing the colour is the Draw bar's (U5: no control twice).
    private var showsWell: Bool { !editor.isDrawing && (makingFromModel || (idle && (woken || alwaysShows))) }

    private var sliders: (HmmSidebarSlider, HmmSidebarSlider) {
        if editor.flying {
            return (HmmSidebarSlider("Fly speed", value: Binding(get: { editor.flyer.flight.speed }, set: { editor.flyer.flight.speed = $0 }),
                                     in: 0.3 ... 20, format: { String(format: "%.2g m/s", $0) }),
                    HmmSidebarSlider("Ease", value: Binding(get: { editor.flyer.flight.response }, set: { editor.flyer.flight.response = $0 }),
                                     in: 0.05 ... 1.2, format: { String(format: "%.2g s", $0) }))
        }
        if editor.timelineMode == .perform, editor.performPhase != .idle || editor.tool == .select {
            return (HmmSidebarSlider("Filtering", value: $editor.performSettings.smoothing, in: 0 ... 1),
                    HmmSidebarSlider("Sensitivity", value: $editor.performSettings.sensitivity, in: 0.25 ... 3,
                                     format: { String(format: "%.2g×", $0) }))
        }
        switch editor.tool {
        case .flipbook:
            return (HmmSidebarSlider("Width", value: $editor.flipbook.width, in: 0.5 ... 24, format: { "\(Int(($0 * 2).rounded())) pt" },
                                     onEditingChanged: editor.setBrushResizing),
                    HmmSidebarSlider("Opacity", value: $editor.flipbook.opacity, in: 0.05 ... 1, format: { "\(Int(($0 * 100).rounded())) %" }))
        case .ink:
            return (HmmSidebarSlider("Width", value: $editor.ink.width, in: 0.001 ... 0.05, format: { "\(Int(($0 * 2000).rounded())) mm" },
                                     onEditingChanged: editor.setBrushResizing),
                    HmmSidebarSlider("Opacity", value: inkOpacity, in: 0.05 ... 1, format: { "\(Int(($0 * 100).rounded())) %" },
                                     onEditingChanged: { if !$0 { editor.endGesture() } }))
        case .draw:
            return (HmmSidebarSlider("Width", value: $editor.draw.width, in: 0.005 ... 0.4, format: { "\(Int(($0 * 100).rounded())) cm" },
                                     onEditingChanged: editor.setBrushResizing),
                    HmmSidebarSlider("Smoothing", value: $editor.draw.smoothing, in: 0 ... 1))
        case .paint:
            return (HmmSidebarSlider("Size", value: $editor.colourPaint.size, in: 1 ... 120, format: { "\(Int($0.rounded())) pt" },
                                     onEditingChanged: editor.setBrushResizing),
                    HmmSidebarSlider("Opacity", value: $editor.colourPaint.opacity, in: 0.05 ... 1, format: { "\(Int(($0 * 100).rounded())) %" }))
        case .model where editor.modeling.verb == .brush:
            return (HmmSidebarSlider("Size", value: $editor.modeling.sculpt.size, in: 8 ... 200, format: { "\(Int($0.rounded())) pt" },
                                     onEditingChanged: editor.setBrushResizing),
                    HmmSidebarSlider("Strength", value: $editor.modeling.sculpt.strength, in: 0.05 ... 1, format: { "\(Int(($0 * 100).rounded())) %" }))
        case .rig where editor.rigging.mode == .weights:
            return (HmmSidebarSlider("Size", value: $editor.rigging.size, in: 4 ... 160, format: { "\(Int($0.rounded())) pt" },
                                     onEditingChanged: editor.setBrushResizing),
                    HmmSidebarSlider("Strength", value: $editor.rigging.strength, in: 0.05 ... 1, format: { "\(Int(($0 * 100).rounded())) %" }))
        case .shadowBrush:
            return (HmmSidebarSlider("Brush size", value: $editor.shadowBrush.radius, in: 0.02 ... 1, format: { "\(Int(($0 * 100).rounded())) cm" },
                                     onEditingChanged: editor.setBrushResizing),
                    HmmSidebarSlider("Strength", value: $editor.shadowBrush.strength, in: 0.05 ... 1))
        default:
            // Awake with nothing that uses them, the sliders still mean size and opacity: ink's.
            return (HmmSidebarSlider("Width", value: $editor.ink.width, in: 0.001 ... 0.05, format: { "\(Int(($0 * 2000).rounded())) mm" },
                                     onEditingChanged: editor.setBrushResizing),
                    HmmSidebarSlider("Opacity", value: inkOpacity, in: 0.05 ... 1, format: { "\(Int(($0 * 100).rounded())) %" },
                                     onEditingChanged: { if !$0 { editor.endGesture() } }))
        }
    }
}

extension EditorSidebar {
    /// New strokes' opacity, and the selected ink drawing's.
    var inkOpacity: Binding<Double> {
        Binding(get: { editor.activeInk?.opacity ?? editor.ink.opacity }, set: { value in
            editor.ink.opacity = value
            editor.setInkOpacity(value)
        })
    }
}

/// Bottom centre of the stage: the bar of the top-right tool in the hand (U5: one bar of at most six verbs each).
struct ToolOptionsBar: View {
    let editor: EditorModel

    var body: some View {
        if editor.isDrawing {
            VStack(spacing: HmmSpacing.xs) {
                if editor.tool == .flipbook { FrameStrip(editor: editor) }
                DrawBar(editor: editor)
            }
        } else {
            switch editor.tool {
            case .scatter: ScatterOptionsBar(editor: editor)
            case .model: ModelOptionsBar(editor: editor)
            case .rig: RigOptionsBar(editor: editor)
            case .select: TriggerDeckBar(editor: editor)
            case .lasso, .ink, .draw, .flipbook, .shadowBrush, .paint: EmptyView()
            }
        }
    }
}
