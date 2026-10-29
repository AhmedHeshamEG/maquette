import HmmHeld

/// Maquette's held features (CONTEXT §5, §D.25): built, kept in the code, and hidden from the App Store build until each
/// passes on the device (its test task done without frustration, its checks closed, no P0 bug in it). One that passes
/// before L1 ships in 1.0 by deleting its name from `MAQUETTE_HELD` in `project.yml`; one that doesn't comes as a free
/// update. Debug and the sideloaded Release build hold nothing, so every part can be tested. Only entry points ask.
public enum MaquetteHeld: String, HmmHeldFeature {
    /// IFC out, plans and elevations, and underlays (G1's building files; the building tools themselves stay).
    case buildingFiles
    /// The technical sheet (Export ▸ Paper).
    case technicalSheets
    /// ISO screws and printed threads: the jar, bolt and nut, the screw and threaded holes.
    case threads
    /// Papercraft and the laser net (Export ▸ Paper).
    case papercraft
    /// RoomPlan's room scan, on the iPad or from the iPhone.
    case roomScan
    /// The Board (the planning sheet) and the cards pinned from it.
    case board
    /// Reviews over FaceTime (SharePlay).
    case faceTimeReview
    /// Web pieces added by hand: a page, a folder or a Lottie file on a screen or over the frame.
    case webPieces
    /// The iPhone companion: its screen on the iPhone and every "your iPhone" entry on the iPad.
    case companion
}

/// This build's held list, read once from the Info.plist.
public enum Held {
    public static let build = HmmHeld<MaquetteHeld>.main()

    /// Whether `feature` can be reached in this build.
    public static func isOn(_ feature: MaquetteHeld) -> Bool {
        build.isOn(feature)
    }
}
