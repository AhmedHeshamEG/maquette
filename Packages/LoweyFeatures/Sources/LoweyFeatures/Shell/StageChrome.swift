import HmmDesign
import LoweyCore
import SwiftUI

/// Everything floating over the stage (docs/LAYOUT.md): the two corner clusters and the panel each opens, the sidebar,
/// the inspector beside the selection, and the bottom row (joystick, tool options, the timeline control and views).
struct StageChrome: View {
    @Bindable var editor: EditorModel
    @Environment(AppModel.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(AppSettings.sidebarOnRight) private var sidebarOnRight = false
    @AppStorage(AppSettings.showsJoystick) private var showsJoystick = true
    /// The open panel's frame on screen (the object panel, or its chip, keeps clear of it).
    @State private var panelFrame: CGRect?
    /// The stage's frame on screen: panels moved by hand stay inside it.
    @State private var bounds: CGRect?

    var body: some View {
        ZStack {
            if editor.tool == .model || editor.precision.showsDimensions { ModelDimensions(editor: editor) }
            // The sheet's edge: its grip, shapes and kept sheets, under it on the stage.
            if editor.drawsOnSheet, editor.currentSheet != nil { SheetEdgeControl(editor: editor) }
            HStack {
                if !sidebarOnRight { EditorSidebar(editor: editor) }
                Spacer()
                if sidebarOnRight { EditorSidebar(editor: editor) }
            }
            .padding(.horizontal, HmmSpacing.xs)
            .frame(maxHeight: .infinity, alignment: .center)
            bottomRow
            // Last, so above everything: a panel opened from a cluster covers the sidebar and the bottom row, never
            // the other way round.
            VStack(spacing: HmmSpacing.s) {
                HStack(alignment: .top) {
                    leadingCluster
                    Spacer(minLength: HmmSpacing.m)
                    trailingCluster
                }
                HStack(alignment: .top, spacing: HmmSpacing.s) {
                    if let panel = editor.openPanel, panel.isLeading {
                        ClusterPanelView(editor: editor, panel: panel)
                            .hmmPanelTransition(from: .topLeading)
                            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { panelFrame = $0 }
                            .onDisappear { panelFrame = nil }
                    }
                    Spacer(minLength: 0)
                    if let panel = editor.openPanel, !panel.isLeading {
                        ClusterPanelView(editor: editor, panel: panel)
                            .hmmPanelTransition(from: .topTrailing)
                            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { panelFrame = $0 }
                            .onDisappear { panelFrame = nil }
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(HmmSpacing.m)
        }
        .overlay {
            if showsInspector {
                FloatingInspector(editor: editor, avoiding: panelFrame, sidebarOnRight: sidebarOnRight)
                    .transition(.opacity)
            }
        }
        .environment(\.hmmPanelBounds, bounds)
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { bounds = $0 }
        .animation(HmmMotion.standard.animation(reduceMotion: reduceMotion), value: editor.openPanel)
        .animation(HmmMotion.standard.animation(reduceMotion: reduceMotion), value: showsInspector)
    }

    /// The object panel floats while something is selected (a chip while something bigger is open). While sketching it
    /// steps aside: the numbers on the stage are what you're working with then (D-124).
    private var showsInspector: Bool {
        !editor.selection.isEmpty && !editor.isSketching
    }

    // MARK: Clusters

    private var leadingCluster: some View {
        HmmCornerCluster([
            HmmClusterItem(id: "home", systemName: "square.grid.2x2", label: "Home") { app.closeEditor() },
            item(.actions, "ellipsis.circle", "Actions"),
            item(.look, "paintpalette", "Look"),
            item(.select, editor.tool == .lasso ? "lasso" : "hand.point.up.left", "Select", on: editor.tool == .lasso),
            item(.library, "books.vertical", "Library")
        ])
        .overlay(alignment: .bottomLeading) { SceneNameDoor(editor: editor).offset(x: HmmSpacing.xs, y: 30) }
    }

    /// The making tools, in the order a thing gets made: Model, Draw, Paint, Rig, and Animate (it calls the timeline).
    private var trailingCluster: some View {
        HmmCornerCluster([
            item(.model, "cube", "Model", on: editor.tool == .model && !editor.isSketching),
            item(.draw, drawIcon, "Draw", on: editor.tool.draws || editor.isSketching),
            item(.paint, editor.tool == .scatter ? "circle.hexagongrid" : "paintbrush.pointed", "Paint", on: editor.tool.paintsSurfaces),
            item(.rig, "figure.arms.open", "Rig", on: editor.tool == .rig),
            HmmClusterItem(id: "animate", systemName: "figure.walk.motion", label: "Animate", isOn: editor.timelinePresence == .full) {
                editor.toggleAnimate()
            }
        ])
    }

    private var drawIcon: String {
        switch editor.tool {
        case .draw: "scribble.variable"
        case .flipbook: "book.pages"
        case .model where editor.isSketching: "pencil.and.ruler"
        default: "pencil.tip"
        }
    }

    /// A cluster button. `on` is the tool in the hand: with chrome restraint, the one thing that wears the accent.
    private func item(_ panel: ClusterPanel, _ systemName: String, _ label: String, on: Bool = false) -> HmmClusterItem {
        HmmClusterItem(id: panel.rawValue, systemName: systemName, label: label, isOn: editor.openPanel == panel || on, accent: on) {
            editor.openPanel = editor.openPanel == panel ? nil : panel
            if panel == .library, editor.openPanel == nil { editor.libraryPurpose = .place }
        }
    }

    // MARK: Bottom of the stage

    private var bottomRow: some View {
        HStack(alignment: .bottom, spacing: HmmSpacing.s) {
            if editor.flying {
                FlyPad(editor: editor).transition(.scale.combined(with: .opacity))
            } else if showsJoystick, !editor.selection.isEmpty, editor.tool == .select, editor.performPhase == .idle, !editor.directorView {
                JoystickPad(editor: editor)
                    .overlay(alignment: .topTrailing) { JoystickHideButton { showsJoystick = false } }
                    .transition(.scale.combined(with: .opacity))
            }
            Spacer()
            ToolOptionsBar(editor: editor)
            Spacer()
            ViewControls(editor: editor)
        }
        .padding(HmmSpacing.m)
        .padding(.leading, sidebarOnRight ? 0 : 56)
        .padding(.trailing, sidebarOnRight ? 56 : 0)
        .frame(maxHeight: .infinity, alignment: .bottom)
    }
}

/// The panel a cluster button opened.
private struct ClusterPanelView: View {
    let editor: EditorModel
    let panel: ClusterPanel

    var body: some View {
        switch panel {
        case .actions: ActionsPanel(editor: editor)
        case .look: LookPanel(editor: editor)
        case .select: SelectBar(editor: editor)
        case .library: LibraryPanel(editor: editor)
        case .scene: ScenePanel(editor: editor)
        case .model: ModelPanel(editor: editor)
        case .draw: DrawToolsPanel(editor: editor)
        case .paint: PaintPanel(editor: editor)
        case .rig: RigPanel(editor: editor)
        }
    }
}

/// The scene's name under the top-left cluster, a door: tap it for the set-up, the scenes and the objects.
private struct SceneNameDoor: View {
    let editor: EditorModel
    @Environment(\.hmmTheme) private var theme

    var body: some View {
        Button {
            HmmHaptics.play(.selection)
            editor.openPanel = editor.openPanel == .scene ? nil : .scene
        } label: {
            HStack(spacing: 4) {
                Text(editor.baseScene.name).lineLimit(1)
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold))
            }
            .font(.hmm(.caption, weight: .semibold))
            .foregroundStyle(editor.openPanel == .scene ? theme.text : theme.text2)
            .padding(.horizontal, HmmSpacing.xs)
            .frame(minHeight: 28)
            .frame(maxWidth: 220, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Scene: \(editor.baseScene.name)"))
        .accessibilityHint(Text("The set-up, the scenes and the objects"))
        .accessibilityIdentifier("scene-name")
    }
}

/// The joystick's own way out (Settings ▸ Stage brings it back).
private struct JoystickHideButton: View {
    let hide: () -> Void
    @Environment(AppModel.self) private var app

    var body: some View {
        HmmButton("xmark", label: "Hide the joystick", size: 28) {
            hide()
            app.show("The joystick is in Settings ▸ Stage when you want it back")
        }
        .offset(x: HmmSpacing.xs, y: -HmmSpacing.xs)
        .accessibilityIdentifier("hide-joystick")
    }
}

/// Bottom-right of the stage: the timeline on call, the views, framing the selection, the camera button.
private struct ViewControls: View {
    let editor: EditorModel

    var body: some View {
        HStack(spacing: HmmSpacing.xxs) {
            HmmButton("timeline.selection", label: "Timeline", isOn: editor.timelinePresence != .hidden) { editor.toggleTimeline() }
                .accessibilityIdentifier("timeline-toggle")
            Menu {
                ForEach(ViewAxis.allCases, id: \.self) { axis in
                    Button(LocalizedStringKey(axis.displayName)) { editor.stage?.quickView(axis) }
                }
                Divider()
                Button(editor.projection == .orthographic ? "Perspective" : "Orthographic") { editor.toggleProjection() }
            } label: {
                Image(systemName: "cube.transparent").font(.system(size: 17, weight: .medium)).frame(width: 44, height: 44)
            }
            .accessibilityLabel("Views")
            .accessibilityIdentifier("views-menu")
            SnapMagnet(editor: editor)
            HmmButton("viewfinder", label: "Frame the selection") { editor.frameSelection() }
            CameraButton(editor: editor)
        }
        .padding(HmmSpacing.xxs)
        .environment(\.hmmInsideGlass, true)
        .hmmGlass(in: Capsule(), interactive: false)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("view-controls")
    }
}

/// The Snap magnet (CONTEXT §10.10): one switch for everything that snaps. Tap it on or off; hold it for the details
/// (the grid and its size, corners and middles, edges, faces, objects, the ground, turning in steps, how near). A finger
/// held down on the stage while the Pencil works flips it for that one move.
private struct SnapMagnet: View {
    @Bindable var editor: EditorModel

    var body: some View {
        HmmButton("magnet", label: "Snapping", isOn: editor.snap.magnet) { editor.toggleSnapMagnet() }
            .contextMenu {
                Toggle("Snap to grid", isOn: $editor.snap.grid)
                Picker("Grid size", selection: $editor.snap.gridSize) {
                    ForEach(PrecisionPage.gridSizes(for: editor.units), id: \.self) { size in
                        Text(editor.units.format(size)).tag(size)
                    }
                }
                Toggle("Snap to corners and middles", isOn: $editor.snap.corners)
                Toggle("Snap to edges", isOn: $editor.snap.edges)
                Toggle("Snap to faces", isOn: $editor.snap.faces)
                Toggle("Snap to objects", isOn: $editor.snap.objects)
                Toggle("Snap to the ground", isOn: $editor.snap.ground)
                Toggle("Turn in steps", isOn: $editor.snap.rotation)
                Picker("Step", selection: $editor.snap.rotationStep) {
                    Text(verbatim: "15°").tag(15.0)
                    Text(verbatim: "45°").tag(45.0)
                    Text(verbatim: "90°").tag(90.0)
                }
                Picker("How near", selection: $editor.snap.objectThreshold) {
                    ForEach([0.02, 0.05, 0.12, 0.25, 0.5], id: \.self) { distance in
                        Text(editor.units.format(distance)).tag(distance)
                    }
                }
            }
            .accessibilityIdentifier("snap-magnet")
    }
}

/// The camera button: tap to look through the camera (again for the next one, then back to the free view); hold for
/// a new camera from this view, or to pick one.
private struct CameraButton: View {
    let editor: EditorModel

    var body: some View {
        HmmButton("video", label: "Camera", isOn: editor.directorView) { editor.tapCameraButton() }
            .contextMenu {
                Button("New camera from this view", systemImage: "plus") { editor.newCameraFromThisView() }
                if !editor.cameras.isEmpty {
                    Section("Look through") {
                        ForEach(editor.cameras, id: \.self) { id in
                            Button {
                                editor.lookThrough(id)
                            } label: {
                                Text(verbatim: editor.baseScene.objects[id]?.name ?? "Camera")
                            }
                        }
                    }
                }
                if editor.directorView {
                    Button("Back to the free view", systemImage: "arrow.uturn.backward") { editor.setDirectorView(false) }
                }
            }
            .accessibilityIdentifier("camera-button")
    }
}
