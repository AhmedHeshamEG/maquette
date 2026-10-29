import Foundation

/// Preferences kept on this device. Each default is the calm choice.
public enum AppSettings {
    /// Show where the Apple Pencil will land while it hovers (off: it would follow the Pencil everywhere).
    public static let pencilHoverPreview = "pencilHoverPreview"
    /// Diagnostics ▸ Apple Pencil (Q2): the hover mark sits where a stroke begun there would land, not at the tip, so
    /// any offset between the two shows on the device.
    public static let pencilLandingDot = "pencilLandingDot"
    /// The Pencil, hovering, lights what a tap would land on (U5: on by default, "it adds much to the feel").
    public static let pencilHoverLights = "pencilHoverLights"
    /// Settings ▸ Gestures: undo and redo buttons in the sidebar (off: the two- and three-finger taps, U5).
    public static let showsUndoButtons = "showsUndoButtons"
    /// Draw the stage at the screen's full pixel density and never lower the render scale (off: dynamic scale).
    public static let fullResolutionStage = "fullResolutionStage"
    /// Off: the inspector floats beside the selection (the default). On: it stays docked at the side.
    public static let inspectorDocked = "inspectorDocked"
    /// How fast the joystick moves, turns and sizes things (1 = normal).
    public static let joystickSpeed = "joystickSpeed"
    public static let joystickSpeedRange = 0.25 ... 3.0
    /// The on-screen joystick under a selection (on by default; its own × or Settings ▸ Stage hides it).
    public static let showsJoystick = "showsJoystick"
    /// The view cube in the view corner (on unless hidden in Settings ▸ Stage).
    public static let showsViewCube = "showsViewCube"
    /// How fast fingers move around the scene: orbit, pan, pinch zoom (1 = normal).
    public static let navigationSpeed = "navigationSpeed"
    public static let navigationSpeedRange = 0.25 ... 3.0
    /// The left sidebar on the right edge (left-handed use).
    public static let sidebarOnRight = "sidebarOnRight"
    /// Settings ▸ Stage: the sidebar never rests (off: with no tool that uses it, it rests as a thin rail).
    public static let alwaysShowsSidebar = "alwaysShowsSidebar"
    /// The Performance HUD over the stage.
    public static let showsPerformanceHUD = "showsPerformanceHUD"
    /// Projects in iCloud Drive (when the build is entitled and the user is signed in) or on this iPad.
    public static let storeInICloud = "storeInICloud"
    /// The 60-second tour was seen (it never comes back by itself; Settings replays it).
    public static let tourSeen = "tourSeen"
    /// The Schizzo board (on by default). Off: no board in Actions, no Sketch template, pinned cards put away.
    public static let boardEnabled = "boardEnabled"
    /// Settings ▸ Gestures: one finger draws around keys and clips on the timeline (off: the Pencil does; a finger pans).
    public static let timelineFingerSelects = "timelineFingerSelects"
    /// Settings ▸ Gestures: the Pencil hovering over the timeline moves the playhead (Procreate Dreams' way).
    public static let timelineHoverScrubs = "timelineHoverScrubs"

    /// The navigation speed, clamped (read when a gesture starts).
    public static var navigationFactor: Double {
        clamped(UserDefaults.standard.object(forKey: navigationSpeed) as? Double ?? 1, to: navigationSpeedRange)
    }

    /// Degrees the view turns per point a finger drags, wherever it turns (the stage, the Director view's camera, the view
    /// cube): half a turn across the screen's long side, times the navigation speed. The screen and not the stage's frame,
    /// so turning the iPad, a narrower window or the tool in the hand never changes it (one sensitivity everywhere).
    public static func orbitDegreesPerPoint(screenLongSide: Double) -> Double {
        180 / max(screenLongSide, 568) * navigationFactor
    }

    public static var joystickFactor: Double {
        clamped(UserDefaults.standard.object(forKey: joystickSpeed) as? Double ?? 1, to: joystickSpeedRange)
    }

    static func clamped(_ value: Double, to range: ClosedRange<Double>) -> Double {
        min(max(value, range.lowerBound), range.upperBound)
    }
}
