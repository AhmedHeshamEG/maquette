import Foundation

/// Sprite sheets for 2D games (K1 step 6): a character's clips rendered from 4 or 8 directions, packed into one picture
/// with a JSON that says where each frame is (Aseprite's hash form, which most 2D engines and packers read) and a Godot
/// SpriteFrames resource, so it drops into an AnimatedSprite2D. The frames come from the renderer; this packs them.
public enum SpriteSheet {
    /// The way the character faces in a frame, as seen by the camera (south faces the camera).
    public enum Direction: String, CaseIterable, Sendable {
        case south = "S", southEast = "SE", east = "E", northEast = "NE", north = "N", northWest = "NW", west = "W", southWest = "SW"

        /// The camera's turn around the character for this direction, in degrees (0: looking at its face).
        public var yaw: Double {
            switch self {
            case .south: 0
            case .southEast: 45
            case .east: 90
            case .northEast: 135
            case .north: 180
            case .northWest: 225
            case .west: 270
            case .southWest: 315
            }
        }

        public static let four: [Direction] = [.south, .east, .north, .west]
        public static let eight: [Direction] = allCases
    }

    /// One clip seen from one direction.
    public struct Strip: Sendable {
        public var clip: String
        public var direction: Direction
        public var frames: [RGBAImage]
        public var fps: Double

        public init(clip: String, direction: Direction, frames: [RGBAImage], fps: Double) {
            self.clip = clip
            self.direction = direction
            self.frames = frames
            self.fps = fps
        }

        /// The animation's name in the sheet ("walk_S").
        public var name: String {
            let base = clip.lowercased().replacingOccurrences(of: " ", with: "_")
            return "\(base)_\(direction.rawValue)"
        }
    }

    public struct Packed: Sendable {
        public var image: RGBAImage
        public var json: Data
        public var spriteFrames: String
        public var cell: (width: Int, height: Int)
    }

    /// Packs the strips into one sheet: a row per strip, a cell per frame, every cell the size of the largest frame.
    public static func pack(_ strips: [Strip], imageName: String) -> Packed? {
        let frames = strips.flatMap(\.frames)
        guard let cellWidth = frames.map(\.width).max(), let cellHeight = frames.map(\.height).max(), cellWidth > 0, cellHeight > 0 else { return nil }
        let columns = strips.map(\.frames.count).max() ?? 1
        var sheet = RGBAImage(width: cellWidth * columns, height: cellHeight * strips.count, color: RGBA(0, 0, 0, 0))
        var entries: [(key: String, x: Int, y: Int, duration: Int)] = []
        var tags: [[String: Any]] = []
        var index = 0
        for (row, strip) in strips.enumerated() {
            let from = index
            for (column, frame) in strip.frames.enumerated() {
                // Each frame sits at the bottom middle of its cell (the character's feet stay put across directions).
                let x = column * cellWidth + (cellWidth - frame.width) / 2
                let y = row * cellHeight + (cellHeight - frame.height)
                sheet.blit(frame, x: x, y: y)
                entries.append(("\(strip.name)_\(column)", column * cellWidth, row * cellHeight, Int((1000 / max(strip.fps, 1)).rounded())))
                index += 1
            }
            tags.append(["name": strip.name, "from": from, "to": index - 1, "direction": "forward"])
        }
        var hash: [String: Any] = [:]
        for entry in entries {
            hash[entry.key] = ["frame": ["x": entry.x, "y": entry.y, "w": cellWidth, "h": cellHeight], "rotated": false, "trimmed": false,
                               "spriteSourceSize": ["x": 0, "y": 0, "w": cellWidth, "h": cellHeight],
                               "sourceSize": ["w": cellWidth, "h": cellHeight], "duration": entry.duration]
        }
        let meta: [String: Any] = ["app": "Maquette", "version": "1.0", "image": imageName, "format": "RGBA8888",
                                   "size": ["w": sheet.width, "h": sheet.height], "scale": "1", "frameTags": tags]
        let json = (try? JSONSerialization.data(withJSONObject: ["frames": hash, "meta": meta], options: [.prettyPrinted, .sortedKeys])) ?? Data()
        return Packed(image: sheet, json: json, spriteFrames: spriteFrames(strips, imageName: imageName, cell: (cellWidth, cellHeight)),
                      cell: (cellWidth, cellHeight))
    }

    /// A Godot 4 SpriteFrames resource (`.tres`) over the sheet: an animation per strip, a region per frame.
    static func spriteFrames(_ strips: [Strip], imageName: String, cell: (Int, Int)) -> String {
        var lines = ["[gd_resource type=\"SpriteFrames\" load_steps=\(strips.reduce(0) { $0 + $1.frames.count } + 2) format=3]", "",
                     "[ext_resource type=\"Texture2D\" path=\"res://\(imageName)\" id=\"1\"]", ""]
        var sub = 0
        var animations: [String] = []
        for (row, strip) in strips.enumerated() {
            var frames: [String] = []
            for column in strip.frames.indices {
                sub += 1
                lines += ["[sub_resource type=\"AtlasTexture\" id=\"a\(sub)\"]", "atlas = ExtResource(\"1\")",
                          "region = Rect2(\(column * cell.0), \(row * cell.1), \(cell.0), \(cell.1))", ""]
                frames.append("{\n\"duration\": 1.0,\n\"texture\": SubResource(\"a\(sub)\")\n}")
            }
            animations.append("{\n\"frames\": [\(frames.joined(separator: ", "))],\n\"loop\": true,\n\"name\": &\"\(strip.name)\",\n\"speed\": \(strip.fps)\n}")
        }
        lines += ["[resource]", "animations = [\(animations.joined(separator: ", "))]", ""]
        return lines.joined(separator: "\n")
    }

    /// A turnaround: the views side by side on one picture (front, three-quarter, side, back), bottoms lined up.
    public static func turnaround(_ views: [RGBAImage], gap: Int = 16, background: RGBA = RGBA(1, 1, 1, 1)) -> RGBAImage? {
        guard let height = views.map(\.height).max(), !views.isEmpty else { return nil }
        let width = views.reduce(0) { $0 + $1.width } + gap * (views.count + 1)
        var sheet = RGBAImage(width: width, height: height + gap * 2, color: background)
        var x = gap
        for view in views {
            sheet.blit(view, x: x, y: gap + height - view.height)
            x += view.width + gap
        }
        return sheet
    }
}

public extension RGBAImage {
    /// Another picture laid over this one at (x, y), over its pixels by its alpha.
    mutating func blit(_ image: RGBAImage, x: Int, y: Int) {
        for row in 0 ..< image.height {
            let ty = y + row
            guard ty >= 0, ty < height else { continue }
            for column in 0 ..< image.width {
                let tx = x + column
                guard tx >= 0, tx < width else { continue }
                let source = (row * image.width + column) * 4
                let target = (ty * width + tx) * 4
                let alpha = Int(image.pixels[source + 3])
                guard alpha > 0 else { continue }
                for channel in 0 ..< 4 {
                    let over = Int(image.pixels[source + channel])
                    let under = Int(pixels[target + channel])
                    pixels[target + channel] =
                        UInt8(channel == 3 ? min(255, alpha + under * (255 - alpha) / 255) : (over * alpha + under * (255 - alpha)) / 255)
                }
            }
        }
    }
}
