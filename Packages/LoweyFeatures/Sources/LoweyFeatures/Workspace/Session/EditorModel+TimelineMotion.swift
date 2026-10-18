import HmmDesign
import LoweyCore
import SwiftUI

/// What the timeline's thick rows show of a thing (A1): its colour and how much it moves at each frame.
extension EditorModel {
    /// How much the thing moves frame by frame (0…1), kept until the document changes.
    func motionCurve(of id: ObjectID) -> [Double] {
        if motionCurves.revision != session.revision { motionCurves = (session.revision, [:]) }
        if let cached = motionCurves.curves[id] { return cached }
        let curve = MotionCurve.amounts(of: id, in: document)
        motionCurves.curves[id] = curve
        return curve
    }

    /// The thing's own colour (the accent for things without one, like lights and cameras).
    func rowColour(of id: ObjectID) -> Color {
        guard let colour = baseScene.objects[id]?.color?.resolved(in: look.palette) else { return HmmTheme.loweyDark.accent }
        return colour.color
    }
}
