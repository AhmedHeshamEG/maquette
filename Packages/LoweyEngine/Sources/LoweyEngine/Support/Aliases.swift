import LoweyCore

// SwiftUI also defines `Scene` and Foundation-adjacent frameworks define `Transform` and `Axis`. These aliases keep
// call sites readable without module-qualifying every use.
public typealias CoreScene = LoweyCore.Scene
public typealias CoreTransform = LoweyCore.Transform
public typealias CoreAxis = LoweyCore.Axis
/// Output shapes of snapshots and videos (Core's `FrameShape` since F1, where the timeline keeps the scene's).
public typealias Framing = LoweyCore.FrameShape
