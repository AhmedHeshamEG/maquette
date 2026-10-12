import CoreGraphics
import Foundation
import HmmDesign
import LoweyCore
import LoweyEngine
import UIKit

/// Where the selection sits on the stage, so the inspector can float beside it without covering it. Measured at once
/// when the selection changes, and once edits or the camera pause (not every frame of a drag or an orbit: the
/// inspector glides over when things come to rest).
extension EditorModel {
    /// One big thing open at a time (CONTEXT §10.10): while a panel, the whole timeline, a sheet or the board is open,
    /// or after the fold button, the object panel is a chip (its name and Move · Turn · Size).
    var inspectorAsChip: Bool {
        inspectorFolded || (openPanel != nil && openPanel != .select) || timelinePresence == .full || sheet != nil
    }

    /// One line at the bottom while a guided step runs (CONTEXT §10.10), gone the moment the step ends.
    var guideLine: String? {
        if pickActive { return "Tap something to take its colour into palette slot \(pickSlot + 1)" }
        if tool == .scatter { return selection.isEmpty ? "Select what to scatter first" : "Drag on the ground to fill an area with copies" }
        if tool == .rig { return rigGuide }
        switch modeling.mode.buildTool {
        case .walls?: return modeling.build.isEmpty ? "Tap where the first wall starts" : "Tap each corner, then Done"
        case .floor?: return modeling.build.isEmpty ? "Tap the floor's first corner" : "Tap each corner, then Done"
        case .door?, .window?: return "Tap a wall where it goes"
        case .stairs?: return "Tap where the stairs start"
        case nil: return nil
        }
    }

    /// Rig's one line: what the Pencil does next (nothing while a guess is placing the dots: they appear by themselves).
    private var rigGuide: String? {
        guard rigging.guessing == nil else { return nil }
        if rigging.person != nil { return "Drag a dot that's wrong, then Rig" }
        if rigging.mode == .weights { return "Paint where the chosen bone should pull" }
        guard let object = rigTarget else { return "Choose what to rig" }
        if shownMarks(of: object).isEmpty {
            return rigging.markKind == .pin ? "Drag along it with the Pencil, from where it holds to its end" : "Tap a dot on each joint with the Pencil"
        }
        return "Tap to add · drag to move · hold to take one away · double-tap to switch pin and dot"
    }

    /// Fold the object panel to its chip, or unfold it. Unfolding is choosing it as the one big thing: an open panel
    /// closes and the whole timeline folds to its transport.
    func foldInspector(_ fold: Bool) {
        inspectorFolded = fold
        guard !fold else { return }
        if openPanel != nil, openPanel != .select { openPanel = nil }
        if timelinePresence == .full { timelinePresence = .transport }
    }

    /// With no delay given: at once for a new selection, after a short pause for the same one being edited.
    func refreshSelectionScreenRect(after delay: Double? = nil) {
        selectionRectTask?.cancel()
        guard !selection.isEmpty else {
            if selectionScreenRect != nil { selectionScreenRect = nil }
            measuredSelection = []
            return
        }
        let delay = delay ?? (selection == measuredSelection ? 0.12 : 0)
        measuredSelection = selection
        selectionRectTask = Task { [weak self] in
            if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
            guard let self, !Task.isCancelled else { return }
            let rect = projectedSelectionRect()
            if rect != selectionScreenRect { selectionScreenRect = rect }
        }
    }

    /// The selection's box projected onto the stage (view points), clipped to the stage; nil when it's off screen.
    func projectedSelectionRect() -> CGRect? {
        guard let stage, let bounds = selectionBounds else { return nil }
        let corners = [bounds.min.x, bounds.max.x].flatMap { x in
            [bounds.min.y, bounds.max.y].flatMap { y in [bounds.min.z, bounds.max.z].map { z in Vec3(x, y, z) } }
        }
        guard let box = HmmFloatingPlacement.bounds(of: corners.compactMap { stage.screenPoint(of: $0) }) else { return nil }
        let visible = box.intersection(stage.bounds)
        return visible.isNull || visible.isEmpty ? nil : visible
    }
}

/// The open project is presented over Home by identity (one editor per opened project).
extension EditorModel: Identifiable {}
