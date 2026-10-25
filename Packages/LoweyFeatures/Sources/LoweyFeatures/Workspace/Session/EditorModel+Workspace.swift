import Foundation
import HmmDesign
import LoweyCore

/// How the open project shows (`workspace.json`): the timeline on call and its height, snapping, the grid, the
/// starter template's first panel. Written moments after it changes; it isn't the project, so it's never undone.
extension EditorModel {
    func loadWorkspace() {
        workspace = store.loadWorkspace(at: projectURL)
        timelinePresence = workspace.timeline
        timelineHeight = workspace.timelineHeight
        snap = workspace.snap
        showsGrid = workspace.showsGrid
        units = workspace.units
        precision.section = workspace.section
        precision.printBed = workspace.printBed
        precision.showsDimensions = workspace.showsDimensions
        frameGuide = workspace.frameGuide
        planeGuide = workspace.planeGuide
        references = workspace.references
        placing.window = workspace.referenceWindow
        rotoscope = workspace.rotoscope
        projectSetUp = workspace.setUp
        if workspace.firstPanel == ProjectWorkspace.boardPanel {
            // A Sketch project opens on its board, once.
            workspace.firstPanel = nil
            saveWorkspace()
            openBoard()
        } else if let first = workspace.firstPanel.flatMap(ClusterPanel.init(rawValue:)) {
            openPanel = first
            workspace.firstPanel = nil
            saveWorkspace()
        }
    }

    /// Something shown changed: write the workspace shortly (a resize or a run of toggles is one write).
    func workspaceChanged() {
        workspaceSaveTask?.cancel()
        workspaceSaveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(0.4))
            guard let self, !Task.isCancelled else { return }
            saveWorkspace()
        }
    }

    func saveWorkspace() {
        workspaceSaveTask?.cancel()
        workspace.timeline = timelinePresence
        workspace.timelineHeight = timelineHeight
        workspace.snap = snap
        workspace.showsGrid = showsGrid
        workspace.units = units
        workspace.section = precision.section
        workspace.printBed = precision.printBed
        workspace.showsDimensions = precision.showsDimensions
        workspace.frameGuide = frameGuide
        workspace.planeGuide = planeGuide
        workspace.references = references
        workspace.referenceWindow = placing.window
        workspace.rotoscope = rotoscope
        do {
            try store.saveWorkspace(workspace, at: projectURL)
        } catch {
            logger.error("Couldn't save the workspace: \(error.localizedDescription)")
        }
    }

    /// "Set up for", any time: the set-up's units, snapping, grid, printer and timeline come into reach; the project
    /// itself doesn't change (`ProjectWorkspace.settingUp`).
    func setUp(for kind: StarterTemplate.Kind) {
        guard kind != projectSetUp else { return }
        saveWorkspace()
        workspace = workspace.settingUp(for: kind)
        projectSetUp = workspace.setUp
        timelinePresence = workspace.timeline
        snap = workspace.snap
        showsGrid = workspace.showsGrid
        units = workspace.units
        precision.printBed = workspace.printBed
        saveWorkspace()
        HmmHaptics.play(.selection)
    }

    // MARK: The timeline on call

    /// The corner control: calls the slim transport, or sends the timeline away.
    func toggleTimeline() {
        HmmHaptics.play(.selection)
        timelinePresence = timelinePresence == .hidden ? .transport : .hidden
    }

    /// Animate: the whole timeline (again: it goes back to the transport).
    /// The divider was dragged to a new height (points).
    func setTimelineHeight(_ height: Double) {
        let range = ProjectWorkspace.timelineHeightRange
        timelineHeight = min(max(height, range.lowerBound), range.upperBound)
        workspaceChanged()
    }

    /// New shapes are this many metres (the starter template's size; 1 m otherwise).
    var newShapeScale: Double { workspace.shapeSize }
}
