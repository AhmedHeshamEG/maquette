import Foundation
import LoweyCore

/// The character maker's view state (K1): never undone, never saved.
struct MakerState: Equatable {
    /// Paired parts come as a mirrored pair, and a change to one side changes both.
    var symmetric = true
    /// The face state the person is looking at in the maker: shown on the stage (as a live value) until they leave it.
    var preview: FacePreview?
    /// Proportions are open: their handles stand on the stage.
    var proportions = false
    /// Act it out as in a mirror (raise your right hand, the character raises the hand on that side of the screen).
    var mirrored = true
    /// How far reading a video has gone (0…1), while it reads.
    var reading: Double?
    /// What the game export is doing, while it works ("Drawing the walk, east…").
    var working: String?
    /// The motions a sprite sheet holds, and how it's drawn.
    var sprites = SpriteSettings()

    struct FacePreview: Equatable {
        var character: ObjectID
        var job: CharacterPart.Job
        var state: String
    }
}

/// How a sprite sheet is made (K1 step 6).
struct SpriteSettings: Equatable {
    var eightDirections = false
    var size = 128
    var fps = 12.0
    var pixelArt = false
    var pixelHeight = 48
    /// The motions on the sheet, by name ("Timeline", "Idle", "Walk"…); empty: standing still.
    var motions: [String] = ["Idle", "Walk"]

    var directions: [SpriteSheet.Direction] { eightDirections ? SpriteSheet.Direction.eight : SpriteSheet.Direction.four }
}
