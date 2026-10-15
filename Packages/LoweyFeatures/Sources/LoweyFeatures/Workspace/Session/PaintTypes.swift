import CoreGraphics
import Foundation
import LoweyCore

/// Paint ▸ Colour (CONTEXT §10.4, U7): what the Pencil does on a model, the brush's size and opacity, the map it paints
/// (colour, roughness, metal, glow, bumps, fur, or the layer's mask) and the value it lays on a value map, the layer each
/// object paints on, and a picture being placed to project.
public struct ColourPaintSettings: Equatable {
    public enum Mode: String, CaseIterable, Identifiable, Sendable {
        case paint, erase, fill, pick, smudge, faces, seams

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .paint: "Paint"
            case .erase: "Erase"
            case .fill: "Fill"
            case .pick: "Eyedropper"
            case .smudge: "Smudge"
            case .faces: "Faces"
            case .seams: "Seams"
            }
        }

        public var systemImage: String {
            switch self {
            case .paint: "paintbrush.pointed"
            case .erase: "eraser"
            case .fill: "drop.fill"
            case .pick: "eyedropper"
            case .smudge: "hand.point.up.left.and.text"
            case .faces: "square.on.square.squareshape.controlhandles"
            case .seams: "scissors"
            }
        }

        /// The Pencil's stroke paints into a layer (the GPU's live stroke).
        public var strokes: Bool { self == .paint || self == .erase }
    }

    public var mode: Mode = .paint
    /// The map a stroke paints: colour and glow take the colour in hand, the others `value` (D-338).
    public var map: PaintMap = .color
    /// The number a stroke lays on a value map (roughness, metal, bumps, fur; a mask is painted white, erased clear).
    public var value: Double = 0.5
    /// Seams marked so far in Seams mode, before they're kept (the object's own space).
    public var pendingSeams: [PaintSeam] = []
    /// A decal picture waits for a tap on the thing (the picture itself is `TextureWork.decal`), and its width (m).
    public var decalWaiting = false
    public var decalSize: Double = 0.3
    /// The flat view (the surface laid out as its texture) is open.
    public var flatView = false
    /// The brush's size in points at full pressure.
    public var size: Double = 16
    public var opacity: Double = 1
    /// The object being painted (the last one touched or chosen).
    public var target: ObjectID?
    /// The layer each object paints on (its top layer until another is chosen).
    public var layers: [ObjectID: String] = [:]
    /// Objects being made ready to paint (laid flat in the background).
    public var preparing: Set<ObjectID> = []
    /// A picture placed over the stage, to project onto the target.
    public var picture: PaintPicture?

    public init() {}
}

/// A picture over the stage, placed with the fingers, then projected from the camera onto what it covers.
public struct PaintPicture: Equatable {
    public let id = UUID()
    public let image: CGImage
    /// Where it sits on the stage (points).
    public var rect: CGRect

    public init(image: CGImage, rect: CGRect) {
        self.image = image
        self.rect = rect
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id && lhs.rect == rhs.rect
    }
}
